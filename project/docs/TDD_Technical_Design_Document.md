# Technical Design Document (TDD)

## 1. Document Identification & Architecture

| Item | Information |
| :--- | :--- |
| **Project title** | Event Registration and Attendee Management System |
| **Document type** | Technical Design Document (TDD) |
| **Prepared by** | Yashvin Jasani |
| **Course** | CS 437 Database Implementation |

**Architecture Summary:** Implemented on MySQL 8.0+ (InnoDB) to ensure ACID transactions, referential integrity, and crash recovery. Enforces `REPEATABLE READ` isolation with pessimistic row-level locking where required.

*(Note: Complete table schemas, constraints, triggers, and stored procedures are located in the dedicated Schema Build File, as per project requirements. The schema is normalized to 3NF.)*

---

## 2. Requirements Traceability Matrix

| FR / Rule ID | Requirement Summary | Schema Objects | Enforcement Method | Test Case |
| :--- | :--- | :--- | :--- | :--- |
| **FR-01** | Unique user accounts with role | `USER` | `PK`, `UNIQUE (Email)`, `ENUM RoleType` | `AC-02` |
| **FR-02** | Role + ownership permissions | `USER`, `EVENT`, `SESSION`, `REGISTRATION` | Role-based validation in procedures | `AC-12` |
| **FR-03** | Venue capacity > 0 | `VENUE` | `CHECK (MaxCapacity > 0)` | `TC-02` |
| **FR-04** | Valid event date range | `EVENT` | `CHECK (StartDate <= EndDate)` | `AC-11` |
| **FR-05** | Tier capacity <= venue capacity | `TICKET_TIER`, `VENUE` | Trigger validation | `TC-03` |
| **FR-06, BR-10** | Atomic registration + 1:1 payment | `REGISTRATION`, `PAYMENT` | `START TRANSACTION` / `ROLLBACK` | `AC-01`, `AC-09` |
| **FR-09, BR-03** | Cross-event ticket mismatch | `REGISTRATION`, `TICKET_TIER` | Composite `FK (EventID, TicketID)` | `AC-03` |
| **FR-10, BR-05** | Concurrency-safe capacity | `TICKET_TIER`, `REGISTRATION` | `FOR UPDATE` lock in registration procedure | `AC-08` |
| **FR-11** | Cancel releases capacity | `REGISTRATION`, `SESSION_ROSTER` | cancellation procedure | `AC-05` |
| **FR-14, BR-09** | No speaker overlap | `SESSION` | overlap validation trigger | `AC-10` |
| **FR-15, BR-04** | Same-event roster rule | `SESSION_ROSTER` | roster validation procedure | `AC-04` |
| **FR-18, BR-12** | Immutable audit logging | `AUDIT_LOG` | `AFTER` triggers and blocked `UPDATE`/`DELETE` | `AC-16` |

---

## 3. Roles, Entitlements, and Data Access

**Enforcement Mechanism:** Access is governed via MySQL database roles (`role_admin`, `role_organizer`, `role_speaker`, `role_attendee`) and row-filtered security views where appropriate.

| Protected Data Area | Admin | Organizer | Speaker | Attendee | Row-Level Ownership Rules |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`EVENT` / `SESSION` / `TICKET_TIER`** | View All | Create, Update own events | View All | View All | Writes strictly require ownership checks |
| **`REGISTRATION` / `PAYMENT`** | View All, Override Cancel | View/Cancel for own events | Register | Create, View, Cancel own | Attendees isolated to their own records |
| **`SESSION_ROSTER` (Enroll)** | View All | View for own events | View assigned | Join/Leave own | Requires confirmed registration and matching event |
| **`SESSION_ROSTER` (Check-In)** | Update | Update own events | Read-Only | Read-Only | Only organizer or admin can transition attendance status |
| **`AUDIT_LOG`** | Read-Only | No Access | No Access | No Access | Immutable: `UPDATE`/`DELETE` blocked |

---

## 4. Performance and Index Design

| Index Name | Indexed Columns | Query Pattern / Rule Supported | Expected Benefit |
| :--- | :--- | :--- | :--- |
| `idx_event_startdate_org` | `(StartDate, OrganizerID)` | Date filtering and reporting | Range scan, reduced sort cost |
| `uq_event_ticket` | `(EventID, TicketID)` | Composite FK checks | Efficient lookups |
| `idx_session_speaker_interval` | `(SpeakerID, StartDateTime, EndDateTime)` | Speaker double-booking check | Efficient overlap validation |
| `idx_reg_ticket_status` | `(TicketID, Status)` | Capacity counting | Reduced locking scope |
| `uq_reg_active_attendee_event` | `(AttendeeID, EventID, Status)` | Single active registration rule | Prevents duplicate active rows |
| `idx_roster_session_status` | `(SessionID, CheckInStatus, RegistrationID)` | Session roster reporting | Efficient roster retrieval |

**EXPLAIN Analysis Summary:** Core reporting views utilize indexed lookups and aggregate scans to minimize full table scans.

---

## 5. Resiliency, Recovery, and Data Integrity

* **Atomic Transactions & Rollback:** Registration flows use `START TRANSACTION` and an error handler to rollback on invalid conditions.
* **Concurrency & Phantom Protection:** To prevent two users from claiming the final seat, registration procedures lock the target `TICKET_TIER` row with `SELECT ... FOR UPDATE`.
* **Soft Deletion & History Preservation:** Records are never hard-deleted; cancellations update status to `'Cancelled'` or mark the corresponding roster as withdrawn.

---

## 6. Audit and Traceability Design

* **Events Audited:** Insertions, status changes, administrative overrides, and price/capacity modifications.
* **Audit Content:** `AUDIT_LOG` captures `ActorUserID`, `ActorRole`, `ActionTimestamp`, `ActionType`, `EntityName`, `RecordID`, `OldValue`, `NewValue`, and `Reason`.
* **Immutability Protection:** Triggers intercept and reject any `UPDATE` or `DELETE` statement targeting `AUDIT_LOG`.
* **History Reconstruction:** The system traces an attendee's lifecycle by querying `AUDIT_LOG` for matching `RecordID` values across registration, payment, and roster activity.

---

## 7. Testing and Test Evidence

| Test ID | Category | Rule Tested | Test Execution Summary | Expected Result |
| :--- | :--- | :--- | :--- | :--- |
| **AC-01** | Positive | Atomic Transaction | Call registration procedure with valid data. | `REGISTRATION`, `PAYMENT`, and `AUDIT_LOG` rows created; capacity reduced by 1. |
| **AC-03** | Negative | Cross-Event FK | Register with `TicketID` belonging to a different `EventID`. | Rejected by composite FK; 0 rows inserted. |
| **AC-05** | Lifecycle | Re-Registration | Attempt duplicate active reg, cancel it, register again. | Duplicate active rejected; success after cancel. |
| **AC-08** | Concurrency | Last-Seat Contention | Execute registration twice simultaneously for the final seat. | `FOR UPDATE` lock forces one commit and one rollback. |
| **AC-09** | Resiliency | Atomic Rollback | Trigger payment failure during registration. | Full rollback leaves no partial registration. |
| **AC-10** | Negative | Speaker Overlap | Schedule a session overlapping an existing speaker assignment. | Rejected by overlap validation. |
| **AC-12** | Security | Entitlement | Attendee attempts to cancel another attendee's registration. | Rejected by ownership validation. |
| **AC-13** | Integrity | Historical Price | Organizer raises price; new user registers. | Old registration keeps original price; new one captures new value. |
| **AC-16** | Governance | Audit Immutability | Admin attempts `UPDATE` and `DELETE` on `AUDIT_LOG`. | Both blocked by triggers. |
