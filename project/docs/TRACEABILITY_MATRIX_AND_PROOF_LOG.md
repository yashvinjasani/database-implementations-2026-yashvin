# End-to-End Requirements Traceability Matrix & Release Proof Log
**Project:** Event Registration and Attendee Management System  
**Course:** 01:198:437 Database Systems Implementation  
**Release Tag:** `v2.0-release`  
**Governing Standard:** Principle 10 of 10 — Traceability: Requirements → Build → Evidence  

---

## 1. Traceability Chain Architecture

Every functional claim in this project follows an unbroken, verifiable chain of custody:
$$\text{Requirement (FR/BR/SEC)} \longrightarrow \text{Implemented Database Object} \longrightarrow \text{Deterministic Test Case} \longrightarrow \text{Committed Execution Log}$$

---

## 2. Complete End-to-End Requirements Traceability Matrix

| Requirement ID | Business Rule / Requirement Summary | Implemented Database Object(s) | Verification Test Case | Executed Result / Captured Proof (`build_execution.log`) | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **FR-01 / BR-01** | Unique user accounts with validated email format, active status, and coded role | `USER`, `uq_user_email`, `chk_user_email_fmt`, `fk_user_role_indicator` | `AC-02` | `Duplicate entry 'dave@test.com' for key 'USER.uq_user_email'` | **PASS** |
| **FR-02 / SEC-01–09** | Zero-trust session actor resolution & row-level record ownership | `fn_current_user_id()`, `APP_LOGIN_MAP`, `v_attendee_own_registrations`, `v_organizer_event_registrations` | `AC-14`, `08_concurrency` | `forbidden: SEC-03/SEC-04 Violation: Only the owning Event Organizer or Admin may update session check-in status.` | **PASS** |
| **FR-03 / BR-04** | Venue capacity positive integer & protected against under-allocation | `VENUE`, `chk_venue_cap`, `trg_venue_bu_cap` | `AC-03` | `conflict: BR-04 Violation: Combined ticket tier capacities exceed Venue MaxCapacity.` | **PASS** |
| **FR-04 / BR-02** | Event EndDate must be on or after StartDate | `EVENT`, `chk_event_dates` (`StartDate <= EndDate`) | `TC-02` | `Check constraint 'chk_event_dates' is violated.` | **PASS** |
| **FR-05 / BR-04** | Cumulative ticket tier capacities per event cannot exceed Venue MaxCapacity | `TICKET_TIER`, `trg_tickettier_bi_cap`, `trg_tickettier_bu_cap` | `AC-03` | `conflict: BR-04 Violation: Combined ticket tier capacities exceed Venue MaxCapacity.` | **PASS** |
| **FR-06 / BR-07** | Atomic registration & 1:1 payment processing with full rollback on error | `sp_register_and_pay`, `REGISTRATION`, `PAYMENT`, `trg_payment_bi_validate` | `AC-01`, `AC-09` | `invalid: BR-10 Violation: Payment AmountPaid must exactly equal REGISTRATION.AcceptedPrice.` (0 orphan rows) | **PASS** |
| **FR-07** | Unique external invoice tracking per registration | `PAYMENT`, `uq_payment_invoice`, `uq_payment_registration` | `AC-01` | `INV-1001`, `INV-1002`, `INV-1004` recorded 1:1 with `RegistrationID` | **PASS** |
| **FR-08 / BR-10** | Historical contract price preservation (`AcceptedPrice`) across catalog updates | `REGISTRATION.AcceptedPrice`, `trg_tickettier_au_audit` | `AC-13` | Tier 10 updated `$50.00 -> $75.00`; Reg 1 & 2 preserve `AcceptedPrice = 50.00` | **PASS** |
| **FR-09 / BR-03** | Prevent cross-event ticket tier assignment | `fk_reg_event_ticket` composite FK `(EventID, TicketID)` | `AC-03` / `sp_register_and_pay` | `invalid: BR-03 Violation: Ticket tier does not belong to the specified event.` | **PASS** |
| **FR-10 / BR-05** | Concurrency-safe tier capacity enforcement under parallel load | `sp_register_and_pay` (`SELECT ... FOR UPDATE`), `idx_reg_ticket_status` | `AC-06`, `AC-08` | `conflict: FR-10/BR-05 Violation: Ticket tier has reached maximum capacity.` | **PASS** |
| **FR-11 / BR-06** | Soft cancellation releasing capacity & allowing re-registration | `sp_cancel_registration`, generated column `ActiveAttendeeEventKey` | `AC-04`, `AC-05` | Reg 2 (`Cancelled`, `ActiveAttendeeEventKey = NULL`); Reg 4 (`Confirmed` at `$75.00`) | **PASS** |
| **FR-12 / BR-05 / BR-08** | Block capacity reductions below active confirmed headcount | `trg_tickettier_bu_cap`, `trg_session_bu_cap`, `trg_venue_bu_cap` | `AC-03`, `AC-11` | `conflict: BR-05 Violation: Cannot reduce tier capacity below current confirmed registrations.` | **PASS** |
| **FR-13 / BR-02** | Session timestamps must fall strictly within parent Event dates | `SESSION`, `chk_sess_time`, `trg_session_bi_validate`, `sp_schedule_session` | `TC-03` | `invalid: BR-02 Violation: Session timestamps must fall within parent Event StartDate and EndDate.` | **PASS** |
| **FR-14 / BR-09** | Prevent speaker double-booking across overlapping time intervals | `idx_session_speaker_interval`, `trg_session_bi_validate`, `trg_session_bu_cap` | `AC-10` | `conflict: BR-09 Violation: Speaker has an overlapping session schedule.` | **PASS** |
| **FR-15 / BR-08** | Session enrollment requires Confirmed registration for same Event & available capacity | `SESSION_ROSTER`, `trg_roster_bi_validate`, `sp_enroll_session_roster` | `AC-11` | `conflict: BR-08 Violation: Session has reached maximum capacity.` | **PASS** |
| **FR-16 / Principle 4** | Metadata-driven check-in state machine governed by role | `WORKFLOW_TRANSITION`, `sp_record_session_checkin` | `AC-14` | `invalid: Principle 4 Workflow Violation: Disallowed state transition or insufficient role.` | **PASS** |
| **FR-17 / RQ-01–04** | Analytical reporting views & covering index performance at 50k+ scale | `v_rq01_event_revenue` .. `v_rq04_speaker_schedule`, `idx_reg_ticket_status` | `06_performance_study` | Table scan `24.81 ms` (50,000 rows) reduced to `0.05 ms` (48 rows) via covering index | **PASS** |
| **FR-18 / BR-12** | Append-only immutable audit ledger blocking `UPDATE` and `DELETE` | `AUDIT_LOG`, `trg_audit_log_bu_immutable`, `trg_audit_log_bd_immutable` | `AC-16A`, `AC-16B` | `forbidden: BR-12/SEC-08 Violation: AUDIT_LOG is append-only and immutable.` | **PASS** |
