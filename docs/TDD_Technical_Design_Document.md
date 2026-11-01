# Technical Design Document (TDD)

## 1. Document Identification & Architecture

| Item | Information |
| :--- | :--- |
| **Project title** | Event Registration and Attendee Management System |
| **Document type** | Technical Design Document (TDD) |
| **Prepared by** | Yashvin Jasani |
| **Course** | CS 437 Database Implementation |

**Architecture Summary:** Implemented on MySQL 8.0+ (InnoDB) to ensure ACID transactions, referential integrity, and crash recovery. Enforces `REPEATABLE READ` isolation with pessimistic row-level locking (`SELECT ... FOR UPDATE`) to serialize concurrent capacity allocation. 

*(Note: Complete table schemas, constraints, triggers, and stored procedures are located in the dedicated **Schema Build File**, as per project requirements. The schema is normalized to 3NF.)*

---

## 2. Requirements Traceability Matrix

| FR / Rule ID | Requirement Summary | Schema Objects | Enforcement Method | Test Case | Demo Evidence |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **FR-01** | Unique user accounts with role | `USER` | `PK`, `UNIQUE (Email)`, `ENUM RoleType` | `AC-02` | `SHOW CREATE TABLE`; duplicate email rejected |
| **FR-02** | Role + ownership permissions | `USER`, `EVENT`, `SESSION`, `REGISTRATION` | Roles (`role_*`), Row-level validation in procedures | `AC-12` | Entitlement script showing allowed vs. denied |
| **FR-03** | Venue capacity > 0 | `VENUE` | `CHECK (MaxCapacity > 0)` | `TC-02` | Insert with capacity 0 rejected |
| **FR-04** | Valid event date range | `EVENT` | `CHECK (StartDate <= EndDate)` | `AC-11` | Out-of-bounds dates rejected |
| **FR-05** | Tier capacity <= Venue cap | `TICKET_TIER`, `VENUE` | `trg_tickettier_bi_cap` | `TC-03` | Trigger error on excess capacity |
| **FR-06, BR-10** | Atomic reg + 1:1 payment | `REGISTRATION`, `PAYMENT` | `sp_register_and_pay` (`START TRANSACTION` / `ROLLBACK`) | `AC-01`, `AC-09` | Commit output (`AC-01`); payment failure rollback (`AC-09`) |
| **FR-09, BR-03** | Cross-event ticket mismatch | `REGISTRATION`, `TICKET_TIER` | Composite `FK (EventID, TicketID)` | `AC-03` | Cross-event ticket insert rejected |
| **FR-10, BR-05** | Concurrency-safe capacity | `TICKET_TIER`, `REGISTRATION` | `FOR UPDATE` lock in `sp_register_and_pay` | `AC-08` | Dual-session last-seat contention resolution |
| **FR-11** | Cancel releases capacity | `REGISTRATION`, `SESSION_ROSTER` | `sp_cancel_registration` | `AC-05` | Before/after available capacity count |
| **FR-14, BR-09** | No speaker overlap | `SESSION` | `trg_session_bi_validate` | `AC-10` | Overlapping session insert rejected |
| **FR-15, BR-04** | Same-event roster rule | `SESSION_ROSTER` | `sp_enroll_session_roster` | `AC-04` | Cross-event session enrollment rejected |
| **FR-18, BR-12** | Immutable audit logging | `AUDIT_LOG` | `AFTER` triggers, `BEFORE UPDATE/DELETE` block triggers | `AC-16` | Lifecycle query; blocked `UPDATE`/`DELETE` |

---

## 3. Roles, Entitlements, and Data Access

**Enforcement Mechanism:** Access is governed via MySQL database roles (`role_admin`, `role_organizer`, `role_speaker`, `role_attendee`), row-filtered security views (`v_organizer_event_registrations`, etc.), and `SQL SECURITY DEFINER` stored procedures that dynamically evaluate `@current_user_id` against record ownership fields (`EVENT.OrganizerID`, `REGISTRATION.AttendeeID`).

| Protected Data Area | Admin | Organizer | Speaker | Attendee | Row-Level Ownership Rules |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`EVENT` / `SESSION` / `TICKET_TIER`** | View All | Create, Update **own events** | View All | View All | Writes strictly require `EVENT.OrganizerID = @current_user_id`. |
| **`REGISTRATION` / `PAYMENT`** | View All, Override Cancel | View/Cancel for **own events** | Register | Create, View, Cancel **own** | Attendees isolated to `AttendeeID = @current_user_id`. Organizers cannot register for own events. |
| **`SESSION_ROSTER` (Enroll)** | View All | View for own events | View assigned | Join/Leave own | Requires `Status = 'Confirmed'` and matching `EventID`. |
| **`SESSION_ROSTER` (Check-In)** | Update | Update **own events** | Read-Only | Read-Only | Only Organizer or Admin can transition status to `CheckedIn`. |
| **`AUDIT_LOG`** | Read-Only | No Access | No Access | No Access | **Immutable**: `UPDATE`/`DELETE` blocked by triggers for all roles. |

---

## 4. Performance and Index Design

| Index Name | Indexed Columns | Query Pattern / Rule Supported | Expected Execution Plan Benefit |
| :--- | :--- | :--- | :--- |
| `idx_event_startdate_org` | `(StartDate, OrganizerID)` | `RQ-01` date filtering & sorting | Index range scan; avoids `filesort`. |
| `uq_event_ticket` | `(EventID, TicketID)` | Composite FK target (`BR-03`) | Covering index lookup for referential checks. |
| `idx_session_speaker_interval`| `(SpeakerID, StartDateTime, EndDateTime)` | Speaker double-booking check (`FR-14`) | Covering range scan; avoids scanning all events. |
| `idx_reg_ticket_status` | `(TicketID, Status)` | Locked capacity count (`FR-10`) | Covering index-only scan (`Using index`); minimizes `FOR UPDATE` lock duration. |
| `uq_reg_active_attendee_event`| `(ActiveAttendeeEventKey, EventID)` | Single active reg limit (`BR-02`) | Declarative uniqueness without scanning history. |
| `idx_roster_session_status` | `(SessionID, CheckInStatus, RegistrationID)`| `RQ-02` Session Roster Report | Reverses PK to allow index `ref` scan by `SessionID`. |

**EXPLAIN Analysis Summary:** Core reporting views (`v_rq01_event_revenue`, `v_rq02_session_roster`) utilize `eq_ref` for primary key joins (e.g., `PAYMENT`, `USER`) and `ref` for indexed aggregations. `idx_reg_ticket_status` is critical for concurrency, shifting the capacity calculation from a table scan to an index-only scan, thereby keeping the `X` lock on `TICKET_TIER` under 1 ms.

---

## 5. Resiliency, Recovery, and Data Integrity

* **Atomic Transactions & Rollback:** The `UC-01` registration flow is handled via `sp_register_and_pay`. It uses `START TRANSACTION` and an `EXIT HANDLER FOR SQLEXCEPTION`. If step 1 (Registration) succeeds but step 2 (Payment) fails due to a duplicate invoice or invalid amount, the handler executes `ROLLBACK`, guaranteeing no orphaned registrations remain.
* **Concurrency & Phantom Protection:** To prevent two users from claiming the final seat, `sp_register_and_pay` applies a pessimistic `SELECT ... FOR UPDATE` lock on the target `TICKET_TIER` row. This serializes validation: the first transaction commits, modifying the confirmed count, while the second transaction reads the updated count, hits the capacity threshold, and rolls back gracefully.
* **Soft Deletion & History Preservation:** Records are never hard-deleted (`ON DELETE RESTRICT`). Cancellations (`sp_cancel_registration`) transition `REGISTRATION.Status` to `'Cancelled'`. This releases the ticket capacity and enrolled session seats, updates the generated active uniqueness column to `NULL` (allowing future re-registration), and preserves financial references.

---

## 6. Audit and Traceability Design

* **Events Audited:** Insertions, status changes, administrative overrides, and price/capacity modifications.
* **Audit Content:** `AUDIT_LOG` captures `ActorUserID`, `ActorRole`, `ActionTimestamp`, `ActionType`, `EntityName`, `RecordID`, `OldValue`, `NewValue`, and `Reason`.
* **Immutability Protection:** Two triggers (`trg_audit_log_bu_immutable` and `trg_audit_log_bd_immutable`) intercept and reject any `UPDATE` or `DELETE` statement targeting `AUDIT_LOG`, preventing tampering even by database administrators.
* **History Reconstruction:** The system traces an attendee's lifecycle by querying `AUDIT_LOG` where `RecordID` matches the `RegistrationID` across the `REGISTRATION`, `PAYMENT`, and `SESSION_ROSTER` entity tags.

---

## 7. Testing and Test Evidence

| Test ID | Category | Rule Tested | Test Execution Summary | Expected Result / Evidence |
| :--- | :--- | :--- | :--- | :--- |
| **AC-01** | Positive | Atomic Transaction | Call `sp_register_and_pay` with valid data. | `REGISTRATION`, `PAYMENT`, `AUDIT_LOG` rows created; capacity reduced by 1. |
| **AC-03** | Negative | Cross-Event FK | Register with `TicketID` belonging to a different `EventID`. | Rejected by Composite FK; 0 rows inserted. |
| **AC-05** | Lifecycle | Re-Registration | Attempt duplicate active reg, cancel it, register again. | Duplicate active rejected; success after cancel. |
| **AC-08** | Concurrency| Last-Seat Contention| Execute `sp_register_and_pay` twice simultaneously for 1 seat. | `FOR UPDATE` lock forces 1 commit, 1 rollback. |
| **AC-09** | Resiliency | Atomic Rollback | Trigger payment failure during registration. | `EXIT HANDLER` rolls back uncommitted registration. |
| **AC-10** | Negative | Speaker Overlap | Schedule a session overlapping speaker's existing interval. | Rejected by `trg_session_bi_validate` overlap check. |
| **AC-12** | Security | Entitlement | Attendee attempts to cancel another attendee's registration. | Rejected by row-level ownership check. |
| **AC-13** | Integrity | Historical Price | Organizer raises price; new user registers. | Old reg retains original price; new reg captures new price. |
| **AC-16** | Governance | Audit Immutability | Admin attempts `UPDATE` and `DELETE` on `AUDIT_LOG`. | Both blocked by `BEFORE` triggers; data remains intact. |
