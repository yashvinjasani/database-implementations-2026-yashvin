# Technical Design Document (TDD)

## 1. Document Identification & Architecture Overview

| Item | Information |
| :--- | :--- |
| **Project title** | Event Registration and Attendee Management System |
| **Document type** | Technical Design Document (TDD) |
| **Prepared by** | Yashvin Jasani |
| **Course / Section** | CS 437 (01:198:437) Database Implementation |
| **Instructor** | Prof. Arnold Lau |
| **Date** | October 17, 2026 |
| **Version** | 2.0 (Aligned with FRD v2.0 & Smart 3D ERD v4.0) |
| **Repository location** | `https://github.com/yashvinjasani/database-implementations-2026-yashvin` |

### 1.1 System Architecture & Technology Stack

The Event Registration and Attendee Management System is engineered on MySQL 8.0+ using the InnoDB transactional storage engine. The relational database serves as the single authoritative enforcement boundary for Third Normal Form (3NF) data integrity, concurrency-safe seat capacity allocation, hybrid role and row-level ownership security, and append-only forensic auditing.

* **RDBMS Platform & Storage Engine:** MySQL 8.0+ (`ENGINE=InnoDB`, `CHARSET=utf8mb4`, `COLLATE=utf8mb4_0900_ai_ci`). InnoDB is required to support ACID transactions, row-level locking (`SELECT ... FOR UPDATE` and `FOR SHARE`), declarative foreign key constraints (`ON UPDATE CASCADE ON DELETE RESTRICT`), and write-ahead logging (redo/undo logs) for crash recovery.
* **Transaction Isolation & Concurrency Model:** `REPEATABLE READ` (InnoDB default) augmented with pessimistic row-level locking (`SELECT ... FOR UPDATE`) on parent `TICKET_TIER` and `SESSION` rows inside stored procedures (`sp_register_and_pay`, `sp_enroll_session_roster`). This serializes concurrent requests competing for the final seat (FR-10, BR-05, AC-08) and prevents lost updates or phantom overbookings.
* **Security & Access Control Layer:** Defense-in-depth enforcement combining:
  * **MySQL Database Roles:** `role_admin`, `role_organizer`, `role_speaker`, and `role_attendee`.
  * **Controlled Stored Procedures (`SQL SECURITY DEFINER`):** All write operations validate the acting user's `UserID`, `RoleType`, `IsActive` status, and row-level ownership (`EVENT.OrganizerID`, `SESSION.SpeakerID`, `REGISTRATION.AttendeeID`) before mutating data.
  * **Row-Filtered Security Views:** `v_public_event_catalog`, `v_organizer_event_registrations`, `v_speaker_session_roster`, and `v_attendee_own_registrations` restrict read visibility to authorized rows using session context (`@current_user_id`).
* **Memory & Caching Architecture (InnoDB Buffer Pool vs. Result Cache):**
  * During active registration windows, operational tables (`REGISTRATION`, `PAYMENT`, `SESSION_ROSTER`, `AUDIT_LOG`) experience high OLTP write churn. Because table-level result caches invalidate on every write touching a dependency (collapsing result cache hit rates toward zero on churning tables), the system relies on the **InnoDB Buffer Pool (Data/Page Cache)**.
  * **Midpoint Insertion LRU Policy:** InnoDB divides the buffer pool LRU list into a young/new sub-list (head/MRU region, ~5/8 of frames) and an old sub-list (tail/LRU region, ~3/8 of frames). Newly read pages enter at the midpoint boundary so ad-hoc analytical or reporting scans (RQ-01–RQ-04) do not evict hot index and data pages for active events (`EVENT`, `TICKET_TIER`, `SESSION`).
  * **Buffer Pool Telemetry Watch List:** Capacity planning monitors five core InnoDB/OS signals before resizing online in chunks: (1) Buffer pool hit rate (target > 98%; falling hit rate indicates read misses), (2) Free buffers (`Free_buffers = 0` indicates full pool), (3) Sustained physical page reads/sec (`Innodb_buffer_pool_reads`), (4) Dirty pages & pending writes (`Innodb_buffer_pool_pages_dirty`—if low/stable, bottleneck is read capacity; if high, bottleneck is disk flush I/O), and (5) OS free RAM and zero swap usage.

### 1.2 Data Flow & Transaction Boundary Diagram

```text
+-----------------------------------------------------------------------------------+
| CLIENT / APPLICATION / CLI SESSION                                                |
| Sets Context: SET @current_user_id = ?, @current_reason = ?                       |
+-----------------------------------------+-----------------------------------------+
                                          |
                        Calls Controlled Stored Procedures / Views
                                          v
+-----------------------------------------------------------------------------------+
| SECURITY & ENTITLEMENT ENFORCEMENT LAYER                                          |
| - MySQL Roles: role_admin, role_organizer, role_speaker, role_attendee            |
| - Row-Level Ownership Checks:                                                     |
|   * Organizer -> EVENT.OrganizerID = @current_user_id                             |
|   * Speaker   -> SESSION.SpeakerID = @current_user_id                             |
|   * Attendee  -> REGISTRATION.AttendeeID = @current_user_id                       |
+-----------------------------------------+-----------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| TRANSACTIONAL & BUSINESS RULE LAYER (InnoDB)                                      |
| - sp_register_and_pay (UC-01): Atomic START TRANSACTION -> Lock TICKET_TIER       |
|   row (FOR UPDATE) -> Verify Cross-Event FK & Remaining Capacity -> Capture       |
|   AcceptedPrice -> Insert REGISTRATION -> Insert 1:1 PAYMENT -> COMMIT/ROLLBACK   |
| - sp_schedule_session (UC-02): Verify Event Date Bounds, Venue Capacity, and      |
|   Speaker Non-Overlap ([StartDateTime, EndDateTime])                              |
| - sp_enroll_session_roster & sp_record_session_checkin (UC-03)                    |
+-----------------------------------------+-----------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| RELATIONAL STORAGE (9 Normalized 3NF Tables) & TRIGGERS                           |
| - Core Master Tier: USER, VENUE                                                   |
| - Event Configuration Tier: EVENT, TICKET_TIER, SESSION (Weak Entity)             |
| - Transactional Tier: REGISTRATION, PAYMENT (1:1), SESSION_ROSTER (M:N Bridge)    |
| - Governance Tier: AUDIT_LOG (Protected by BEFORE UPDATE/DELETE triggers)         |
+-----------------------------------------------------------------------------------+
```

---

## 2. Data Model (ERD Alignment) & Normalized 3NF Schema Design

### 2.1 Entity-Relationship Summary & Relationship Cardinalities

The database schema implements the exact 9-entity architecture and 12 relationships defined in the updated ER Diagram (`CS437_Event_Registration_3D_ERD_v4.html` and `docs/erd/`):

| Parent Entity | Child Entity | Relationship Label | Cardinality | Participation | Foreign Key / Bridge Implementation |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `USER` | `EVENT` | `organizes` | 1 : 0..N | Partial (User) / Total (Event) | `EVENT.OrganizerID` references `USER.UserID` (`NOT NULL`) |
| `VENUE` | `EVENT` | `hosts` | 1 : 0..N | Partial (Venue) / Total (Event) | `EVENT.VenueID` references `VENUE.VenueID` (`NOT NULL`) |
| `USER` | `SESSION` | `speaks_at` | 1 : 0..N | Partial (User) / Total (Session) | `SESSION.SpeakerID` references `USER.UserID` (`NOT NULL`) |
| `EVENT` | `TICKET_TIER` | `offers` | 1 : 1..N | Total | `TICKET_TIER.EventID` references `EVENT.EventID` (`NOT NULL`) |
| `EVENT` | `SESSION` | `contains` | 1 : 0..N | Partial (Event) / Total (Session - Weak/Dependent) | `SESSION.EventID` references `EVENT.EventID` (`NOT NULL`) |
| `USER` | `REGISTRATION` | `registers` | 1 : 0..N | Partial (User) / Total (Registration) | `REGISTRATION.AttendeeID` references `USER.UserID` (`NOT NULL`) |
| `EVENT` | `REGISTRATION` | `receives` | 1 : 0..N | Partial (Event) / Total (Registration) | `REGISTRATION.EventID` references `EVENT.EventID` (`NOT NULL`) |
| `TICKET_TIER` | `REGISTRATION` | `selected_for` | 1 : 0..N | Partial (Tier) / Total (Registration) | Composite `REGISTRATION(EventID, TicketID)` references `TICKET_TIER(EventID, TicketID)` |
| `REGISTRATION` | `PAYMENT` | `paid_by` | 1 : 1 | Total (Confirmed Reg <-> Payment) | `PAYMENT.RegistrationID` (`UNIQUE NOT NULL`) references `REGISTRATION.RegistrationID` |
| `REGISTRATION` | `SESSION_ROSTER` | `enrolls` | 1 : 0..N | Partial (Reg) / Total (Roster) | `SESSION_ROSTER.RegistrationID` (PK, FK) references `REGISTRATION.RegistrationID` |
| `SESSION` | `SESSION_ROSTER` | `has_roster` | 1 : 0..N | Partial (Session) / Total (Roster) | `SESSION_ROSTER.SessionID` (PK, FK) references `SESSION.SessionID` |
| `USER` | `AUDIT_LOG` | `logs_action` | 1 : 0..N | Partial (User) / Total (AuditLog) | `AUDIT_LOG.ActorUserID` references `USER.UserID` (`NOT NULL`) |

### 2.2 Complete 9-Table DDL Specification

#### 1. `USER` (Core Master Tier)

```sql
CREATE TABLE USER (
    UserID INT AUTO_INCREMENT PRIMARY KEY,
    FirstName VARCHAR(60) NOT NULL,
    LastName VARCHAR(60) NOT NULL,
    Email VARCHAR(120) NOT NULL,
    RoleType ENUM('Admin', 'Organizer', 'Speaker', 'Attendee') NOT NULL,
    IsActive BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_user_email UNIQUE (Email),
    CONSTRAINT chk_user_email_fmt CHECK (Email LIKE '%_@_%._%')
) ENGINE=InnoDB;
```

#### 2. `VENUE` (Core Master Tier)

```sql
CREATE TABLE VENUE (
    VenueID INT AUTO_INCREMENT PRIMARY KEY,
    VenueName VARCHAR(120) NOT NULL,
    Address VARCHAR(255) NOT NULL,
    MaxCapacity INT NOT NULL,
    CONSTRAINT uq_venue_name_addr UNIQUE (VenueName, Address),
    CONSTRAINT chk_venue_cap CHECK (MaxCapacity > 0)
) ENGINE=InnoDB;
```

#### 3. `EVENT` (Event Configuration Tier)

```sql
CREATE TABLE EVENT (
    EventID INT AUTO_INCREMENT PRIMARY KEY,
    OrganizerID INT NOT NULL,
    VenueID INT NOT NULL,
    EventName VARCHAR(150) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    CONSTRAINT chk_event_dates CHECK (StartDate <= EndDate),
    CONSTRAINT fk_event_organizer FOREIGN KEY (OrganizerID)
        REFERENCES USER(UserID) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_event_venue FOREIGN KEY (VenueID)
        REFERENCES VENUE(VenueID) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;
```

#### 4. `TICKET_TIER` (Event Configuration Tier)

```sql
CREATE TABLE TICKET_TIER (
    TicketID INT AUTO_INCREMENT PRIMARY KEY,
    EventID INT NOT NULL,
    TierName VARCHAR(60) NOT NULL,
    Price DECIMAL(10, 2) NOT NULL,
    Capacity INT NOT NULL,
    CONSTRAINT uq_event_ticket UNIQUE (EventID, TicketID),
    CONSTRAINT uq_event_tiername UNIQUE (EventID, TierName),
    CONSTRAINT chk_tier_price CHECK (Price >= 0.00),
    CONSTRAINT chk_tier_cap CHECK (Capacity > 0),
    CONSTRAINT fk_tickettier_event FOREIGN KEY (EventID)
        REFERENCES EVENT(EventID) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;
```

#### 5. `SESSION` (Event Configuration Tier — Dependent Entity on EVENT)

```sql
CREATE TABLE SESSION (
    SessionID INT AUTO_INCREMENT PRIMARY KEY,
    EventID INT NOT NULL,
    SpeakerID INT NOT NULL,
    SessionTitle VARCHAR(150) NOT NULL,
    StartDateTime DATETIME NOT NULL,
    EndDateTime DATETIME NOT NULL,
    SessionCapacity INT NOT NULL,
    RoomNumber VARCHAR(40) NOT NULL,
    CONSTRAINT uq_event_session UNIQUE (EventID, SessionID),
    CONSTRAINT chk_sess_time CHECK (StartDateTime < EndDateTime),
    CONSTRAINT chk_sess_cap CHECK (SessionCapacity > 0),
    CONSTRAINT fk_session_event FOREIGN KEY (EventID)
        REFERENCES EVENT(EventID) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_session_speaker FOREIGN KEY (SpeakerID)
        REFERENCES USER(UserID) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;
```

#### 6. `REGISTRATION` (Transactional Tier)

```sql
CREATE TABLE REGISTRATION (
    RegistrationID INT AUTO_INCREMENT PRIMARY KEY,
    AttendeeID INT NOT NULL,
    EventID INT NOT NULL,
    TicketID INT NOT NULL,
    RegistrationDate DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Status ENUM('Confirmed', 'Cancelled') NOT NULL DEFAULT 'Confirmed',
    AcceptedPrice DECIMAL(10, 2) NOT NULL,
    ActiveAttendeeEventKey INT GENERATED ALWAYS AS (
        CASE WHEN Status = 'Confirmed' THEN AttendeeID ELSE NULL END
    ) STORED,
    CONSTRAINT uq_reg_active_attendee_event UNIQUE (ActiveAttendeeEventKey, EventID),
    CONSTRAINT chk_reg_price CHECK (AcceptedPrice >= 0.00),
    CONSTRAINT fk_reg_attendee FOREIGN KEY (AttendeeID)
        REFERENCES USER(UserID) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_reg_event FOREIGN KEY (EventID)
        REFERENCES EVENT(EventID) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_reg_event_ticket FOREIGN KEY (EventID, TicketID)
        REFERENCES TICKET_TIER(EventID, TicketID) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;
```

#### 7. `PAYMENT` (Transactional Tier — Strict 1:1 with REGISTRATION)

```sql
CREATE TABLE PAYMENT (
    PaymentID INT AUTO_INCREMENT PRIMARY KEY,
    RegistrationID INT NOT NULL,
    AmountPaid DECIMAL(10, 2) NOT NULL,
    PaymentDate DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    InvoiceNumber VARCHAR(60) NOT NULL,
    CONSTRAINT uq_payment_registration UNIQUE (RegistrationID),
    CONSTRAINT uq_payment_invoice UNIQUE (InvoiceNumber),
    CONSTRAINT chk_pay_amt CHECK (AmountPaid >= 0.00),
    CONSTRAINT fk_payment_registration FOREIGN KEY (RegistrationID)
        REFERENCES REGISTRATION(RegistrationID) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;
```

#### 8. `SESSION_ROSTER` (Transactional Tier — Associative M:N Entity)

```sql
CREATE TABLE SESSION_ROSTER (
    RegistrationID INT NOT NULL,
    SessionID INT NOT NULL,
    CheckInStatus ENUM('Enrolled', 'CheckedIn', 'NoShow') NOT NULL DEFAULT 'Enrolled',
    EnrolledAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (RegistrationID, SessionID),
    CONSTRAINT fk_roster_registration FOREIGN KEY (RegistrationID)
        REFERENCES REGISTRATION(RegistrationID) ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_roster_session FOREIGN KEY (SessionID)
        REFERENCES SESSION(SessionID) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;
```

#### 9. `AUDIT_LOG` (Governance & Security Tier — Append-Only)

```sql
CREATE TABLE AUDIT_LOG (
    LogID BIGINT AUTO_INCREMENT PRIMARY KEY,
    ActorUserID INT NOT NULL,
    ActorRole VARCHAR(30) NOT NULL,
    ActionTimestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ActionType ENUM('INSERT', 'UPDATE', 'DELETE', 'STATUS_CHANGE', 'ADMIN_OVERRIDE') NOT NULL,
    EntityName VARCHAR(60) NOT NULL,
    RecordID VARCHAR(60) NOT NULL,
    OldValue TEXT NULL,
    NewValue TEXT NULL,
    Reason VARCHAR(255) NULL,
    CONSTRAINT fk_audit_actor FOREIGN KEY (ActorUserID)
        REFERENCES USER(UserID) ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;
```

### 2.3 Third Normal Form (3NF) Verification

* **First Normal Form (1NF):** Every column in all 9 tables stores a single atomic value. Repeating groups (such as multiple sessions attended by a registrant) are decomposed into the associative entity `SESSION_ROSTER`.
* **Second Normal Form (2NF):** Every non-key attribute is fully functionally dependent on the entire primary key. In `SESSION_ROSTER (RegistrationID, SessionID)`, both `CheckInStatus` and `EnrolledAt` depend on the composite key `(RegistrationID, SessionID)` as a whole.
* **Third Normal Form (3NF):** No non-key attribute is transitively dependent on another non-key attribute:
  * Venue attributes (`VenueName`, `Address`, `MaxCapacity`) depend solely on `VenueID` in `VENUE`.
  * User attributes (`FirstName`, `LastName`, `Email`, `RoleType`, `IsActive`) depend solely on `UserID` in `USER`.
  * **Historical Price Preservation (`REGISTRATION.AcceptedPrice`, FR-08, BR-10):** Storing `AcceptedPrice` in `REGISTRATION` does not violate 3NF. `TICKET_TIER.Price` stores the current catalog price at time `t_now`, whereas `REGISTRATION.AcceptedPrice` records the immutable historical price accepted by the attendee at registration time `t_reg`. When an organizer later updates `TICKET_TIER.Price` (AC-13), `REGISTRATION.AcceptedPrice` remains a functional fact of that specific `RegistrationID`.
  * **Cross-Event Composite Foreign Key (`REGISTRATION(EventID, TicketID)`, BR-03):** Referencing `TICKET_TIER(EventID, TicketID)` declaratively prevents a registration for Event A from referencing a ticket tier belonging to Event B (AC-03).

---

## 3. Requirements Traceability Matrix

Every Functional Requirement (FR-01–FR-18), Business Rule (BR-01–BR-12), Security Rule (SEC-01–SEC-09), and Report (RQ-01–RQ-04) from `Event_Registration_FRD_v2.md` is mapped below to its schema objects, enforcement method, test case, and demonstration evidence.

| FR / Rule ID | Requirement Summary | Schema Objects | Enforcement Method | Test Case | Demo Evidence |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **FR-01** | Store unique user accounts with contact details, active status, and base role | `USER` | PK (`UserID`), UNIQUE (`Email`), ENUM `RoleType`, `IsActive BOOLEAN` | AC-02, TC-01 | `SHOW CREATE TABLE USER;` duplicate email insert error |
| **FR-02, SEC-01–SEC-09** | Permissions determined by base role and event/session ownership | `USER`, `EVENT`, `SESSION`, `REGISTRATION`, Roles & Views | MySQL Roles (`role_*`), `SQL SECURITY DEFINER` procedures validating `@current_user_id`, row-filtered views | AC-12, AC-14 | Entitlement script proving allowed vs. denied actions by role/ownership |
| **FR-03, BR-01** | Store venue records with positive `MaxCapacity` | `VENUE` | PK (`VenueID`), `CHECK (MaxCapacity > 0)`, `UNIQUE (VenueName, Address)` | AC-02, TC-02 | Insert with `MaxCapacity <= 0` rejected by `chk_venue_cap` |
| **FR-04, BR-01, BR-08** | Organizer creates/updates events mapped to a venue and valid date range | `EVENT`, `VENUE`, `USER` | FK (`OrganizerID`), FK (`VenueID`), `CHECK (StartDate <= EndDate)`, `trg_event_bi_validate`, `sp_create_event` | AC-02, AC-11, AC-12 | Valid event creation vs. non-owner update rejection (AC-12) |
| **FR-05, BR-06** | Ticket tiers (`Price >= 0`, `Capacity > 0`, tier sum <= `Venue.MaxCapacity`) | `TICKET_TIER`, `EVENT`, `VENUE` | `CHECK (Price >= 0.00)`, `CHECK (Capacity > 0)`, `trg_tickettier_bi_cap`, `trg_tickettier_bu_cap` | TC-03, TC-04 | Trigger error when adding a tier whose capacity sum exceeds `Venue.MaxCapacity` |
| **FR-06, FR-07, BR-10, UC-01** | Atomic single-seat registration and 1:1 payment with unique external invoice | `REGISTRATION`, `PAYMENT`, `TICKET_TIER`, `EVENT` | `sp_register_and_pay` (`START TRANSACTION ... COMMIT/ROLLBACK`), `UNIQUE (RegistrationID)`, `UNIQUE (InvoiceNumber)` | AC-01, AC-09 | Commit output (AC-01) and forced payment failure rollback (AC-09) |
| **FR-08, BR-10** | Preserve historical `AcceptedPrice` and enforce `AmountPaid == AcceptedPrice` | `REGISTRATION`, `PAYMENT`, `TICKET_TIER` | `REGISTRATION.AcceptedPrice`, `trg_payment_bi_validate`, `sp_register_and_pay` | AC-13, AC-09 | Query showing User 5 keeps $50.00 after tier price rises to $75.00 (AC-13) |
| **FR-09, BR-02, BR-03** | Reject cross-event ticket mismatch and duplicate `Confirmed` registration; allow re-reg after cancel | `REGISTRATION`, `TICKET_TIER` | Composite FK `(EventID, TicketID)`, generated `UNIQUE (ActiveAttendeeEventKey, EventID)`, `trg_registration_bi_validate` | AC-03, AC-05 | Cross-event ticket rejected (AC-03); duplicate active rejected, re-reg after cancel succeeds (AC-05) |
| **FR-10, BR-05, UC-01** | Concurrency-safe ticket-tier capacity enforcement (`Confirmed` only) | `TICKET_TIER`, `REGISTRATION` | `SELECT ... FROM TICKET_TIER WHERE TicketID = ? FOR UPDATE` in `sp_register_and_pay` + `trg_registration_bi_validate` | AC-07, AC-08 | Full tier rejection (AC-07) & dual-session last-seat contention (AC-08) |
| **FR-11, BR-05** | Cancellation updates status to `'Cancelled'` and releases ticket & session seats | `REGISTRATION`, `SESSION_ROSTER`, `AUDIT_LOG` | `sp_cancel_registration` sets `Status = 'Cancelled'`, deletes `'Enrolled'` roster rows, logs audit entry | AC-05, TC-05 | Before/after available capacity count and `SESSION_ROSTER` rows |
| **FR-12, BR-07** | Prohibit reducing venue, ticket-tier, or session capacity below active allocations | `VENUE`, `TICKET_TIER`, `SESSION`, `REGISTRATION`, `SESSION_ROSTER` | `trg_venue_bu_cap`, `trg_tickettier_bu_cap`, `trg_session_bu_cap` | TC-06 | Trigger error when reducing `TicketTier.Capacity` below active `Confirmed` count |
| **FR-13, FR-14, BR-08, BR-09, UC-02** | Schedule sessions within event dates, `Start < End`, `SessionCapacity`, no speaker overlap | `SESSION`, `EVENT`, `VENUE`, `USER` | `CHECK (StartDateTime < EndDateTime)`, `trg_session_bi_validate`, `trg_session_bu_validate`, `sp_schedule_session` | AC-10, AC-11 | Speaker overlap rejected (AC-10); out-of-range session date rejected (AC-11) |
| **FR-15, BR-04, BR-11, UC-03A** | Attendee roster enrollment: same-event rule, active reg, session capacity, no time overlap | `SESSION_ROSTER`, `REGISTRATION`, `SESSION` | PK `(RegistrationID, SessionID)`, `sp_enroll_session_roster` (`FOR UPDATE` lock on `SESSION`), `trg_roster_bi_validate` | AC-04, AC-06, TC-07 | Cross-event session rejected (AC-04); duplicate roster rejected (AC-06) |
| **FR-16, BR-11, SEC-06, UC-03B** | Only owning Organizer or Admin updates `CheckInStatus` to `'CheckedIn'` or `'NoShow'` | `SESSION_ROSTER`, `SESSION`, `EVENT`, `AUDIT_LOG` | `sp_record_session_checkin` + `trg_roster_bu_checkin` verifying `EVENT.OrganizerID = @current_user_id` or Admin | AC-14 | Attendee/Speaker update rejected; owning Organizer update succeeds (AC-14) |
| **FR-17, RQ-01–RQ-04, SEC-07** | Generate Revenue, Session Roster, Capacity Exception, and Speaker Schedule reports | Views `v_rq01_event_revenue`, `v_rq02_session_roster`, `v_rq03_capacity_utilization`, `v_rq04_speaker_schedule` | SQL views, reporting procedures, covering indexes, and `EXPLAIN` execution plans | AC-15 | Report outputs ($125.00 for Event 1, $0.00 for Event 2) + `EXPLAIN` plans |
| **FR-18, BR-12, SEC-08, SEC-09** | Immutable audit logging of sensitive changes and defined Admin overrides | `AUDIT_LOG`, operational tables | `AFTER` audit triggers, `sp_admin_override_*`, `trg_audit_log_bu_immutable`, `trg_audit_log_bd_immutable` | AC-16 | Lifecycle audit query + blocked `UPDATE`/`DELETE` on `AUDIT_LOG` (AC-16) |

---

## 4. Roles, Entitlements, and Data Access Design

### 4.1 Role and Row-Level Ownership Entitlement Matrix

| Protected Data Area / Action | Admin (`role_admin`) | Organizer (`role_organizer`) | Speaker (`role_speaker`) | Attendee (`role_attendee`) | Row-Level Ownership / Business Condition |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **USER Account Management** | Create, View All, Update (`RoleType`, `IsActive`) | View own profile; View attendee contact info for own events (SEC-04) | View own profile | View/Update own profile | Attendees cannot view other attendees' profiles (SEC-02); Organizers see only registrants for their own events |
| **VENUE Records** | Create, View All, Update | Create, View All, Update | View All | View All | Capacity cannot be reduced below hosted event tier totals (BR-07) |
| **EVENT Records** | View All; Reassign `OrganizerID` when owner deactivated (SEC-09c) | Create; View All; Update own events only (SEC-01) | View All | View All | `EVENT.OrganizerID = @current_user_id` required for Organizer updates |
| **TICKET_TIER Records** | View All | Create/Update for own events only (SEC-01) | View All | View All | `EVENT.OrganizerID = @current_user_id`; tier capacity sum <= `Venue.MaxCapacity` |
| **SESSION Scheduling** | View All | Create/Update for own events only (SEC-01, UC-02) | View All; View own speaker schedule (RQ-04) | View All | `EVENT.OrganizerID = @current_user_id`; speaker non-overlap enforced (FR-14) |
| **REGISTRATION Lifecycle** | View All; Admin Override Cancel with mandatory reason (SEC-09a) | View/Cancel for own events; Register as attendee for other organizers' events (SEC-03) | Register as attendee for events (FR-06) | Create, View, Cancel own registrations only (SEC-02) | Owning Organizer (`EVENT.OrganizerID`) is strictly blocked from registering for their own event (SEC-03) |
| **PAYMENT Records** | View All; Admin Override Correction with mandatory reason (SEC-09b) | View payment totals/summaries for own events (SEC-04, RQ-01) | View own payments only | Created atomically via UC-01; View own payments only (SEC-02) | `REGISTRATION.AttendeeID = @current_user_id` for attendee visibility |
| **SESSION_ROSTER Enrollment** | View All | View rosters for own events | View rosters for assigned sessions (`SESSION.SpeakerID = @current_user_id`) | Join (`INSERT 'Enrolled'`) or Leave (`DELETE`) for own registration (SEC-06) | Requires `Registration.Status = 'Confirmed'` and `Registration.EventID = Session.EventID` (BR-04) |
| **SESSION_ROSTER Check-In** | Update to `'CheckedIn'` or `'NoShow'` | Update to `'CheckedIn'` or `'NoShow'` for own events only (FR-16, SEC-06) | Read-Only (Cannot modify check-in status) (SEC-05) | Read-Only (View own status; cannot self-check-in) (SEC-06) | Only owning Event Organizer or Admin can transition `'Enrolled'` -> `'CheckedIn'` / `'NoShow'` |
| **AUDIT_LOG History** | Read-Only (`SELECT`); Append via system triggers (SEC-08) | No Access | No Access | No Access | Immutable for all roles: `UPDATE` and `DELETE` are blocked by triggers even for Admin (BR-12, AC-16) |

### 4.2 Database Roles, Grants, and Row-Filtered Views

```sql
-- 1. Create Database Roles
CREATE ROLE IF NOT EXISTS 'role_admin', 'role_organizer', 'role_speaker', 'role_attendee';

-- 2. Row-Filtered Security Views
CREATE OR REPLACE VIEW v_public_event_catalog AS
SELECT e.EventID, e.EventName, e.StartDate, e.EndDate,
       v.VenueName, v.Address, v.MaxCapacity,
       tt.TicketID, tt.TierName, tt.Price, tt.Capacity
FROM EVENT e
INNER JOIN VENUE v ON e.VenueID = v.VenueID
INNER JOIN TICKET_TIER tt ON e.EventID = tt.EventID;

CREATE OR REPLACE VIEW v_attendee_own_registrations AS
SELECT r.RegistrationID, r.AttendeeID, r.EventID, e.EventName,
       r.TicketID, tt.TierName, r.RegistrationDate, r.Status,
       r.AcceptedPrice, p.PaymentID, p.AmountPaid, p.PaymentDate, p.InvoiceNumber
FROM REGISTRATION r
INNER JOIN EVENT e ON r.EventID = e.EventID
INNER JOIN TICKET_TIER tt ON r.EventID = tt.EventID AND r.TicketID = tt.TicketID
LEFT JOIN PAYMENT p ON r.RegistrationID = p.RegistrationID
WHERE r.AttendeeID = @current_user_id;

CREATE OR REPLACE VIEW v_organizer_event_registrations AS
SELECT e.EventID, e.EventName, e.OrganizerID,
       r.RegistrationID, r.Status, r.AcceptedPrice, r.RegistrationDate,
       u.UserID AS AttendeeID, u.FirstName, u.LastName, u.Email,
       p.PaymentID, p.AmountPaid, p.InvoiceNumber
FROM EVENT e
INNER JOIN REGISTRATION r ON e.EventID = r.EventID
INNER JOIN USER u ON r.AttendeeID = u.UserID
LEFT JOIN PAYMENT p ON r.RegistrationID = p.RegistrationID
WHERE e.OrganizerID = @current_user_id;

CREATE OR REPLACE VIEW v_speaker_session_roster AS
SELECT s.SessionID, s.SessionTitle, s.StartDateTime, s.EndDateTime, s.RoomNumber,
       sr.RegistrationID, u.FirstName, u.LastName, sr.CheckInStatus
FROM SESSION s
INNER JOIN SESSION_ROSTER sr ON s.SessionID = sr.SessionID
INNER JOIN REGISTRATION r ON sr.RegistrationID = r.RegistrationID
INNER JOIN USER u ON r.AttendeeID = u.UserID
WHERE s.SpeakerID = @current_user_id
  AND r.Status = 'Confirmed';

-- 3. Role Privilege Grants
GRANT SELECT ON v_public_event_catalog TO 'role_attendee', 'role_speaker', 'role_organizer', 'role_admin';
GRANT SELECT ON v_attendee_own_registrations TO 'role_attendee', 'role_speaker', 'role_organizer';
GRANT SELECT ON v_organizer_event_registrations TO 'role_organizer';
GRANT SELECT ON v_speaker_session_roster TO 'role_speaker';
GRANT SELECT ON AUDIT_LOG TO 'role_admin';

GRANT EXECUTE ON PROCEDURE sp_register_and_pay TO 'role_attendee', 'role_speaker', 'role_organizer';
GRANT EXECUTE ON PROCEDURE sp_cancel_registration TO 'role_attendee', 'role_organizer', 'role_admin';
GRANT EXECUTE ON PROCEDURE sp_enroll_session_roster TO 'role_attendee', 'role_speaker', 'role_organizer';
GRANT EXECUTE ON PROCEDURE sp_schedule_session TO 'role_organizer';
GRANT EXECUTE ON PROCEDURE sp_record_session_checkin TO 'role_organizer', 'role_admin';
GRANT EXECUTE ON PROCEDURE sp_admin_override_payment_correction TO 'role_admin';
GRANT EXECUTE ON PROCEDURE sp_admin_override_reassign_organizer TO 'role_admin';
```

---

## 5. Resiliency, Concurrency Control, Recovery, and Data Integrity

### 5.1 Atomic Registration & 1:1 Payment Stored Procedure (UC-01)

`sp_register_and_pay` executes the entire UC-01 registration and payment workflow as a single atomic unit of work. If any constraint or business rule fails (including payment amount mismatch or duplicate invoice number after the `REGISTRATION` insert), the `EXIT HANDLER FOR SQLEXCEPTION` immediately executes `ROLLBACK`, leaving zero partial or orphaned records (BR-10, AC-09):

```sql
DELIMITER $$
CREATE PROCEDURE sp_register_and_pay(
    IN p_attendee_id INT,
    IN p_event_id INT,
    IN p_ticket_id INT,
    IN p_amount_paid DECIMAL(10,2),
    IN p_invoice_number VARCHAR(60)
)
BEGIN
    DECLARE v_organizer_id INT;
    DECLARE v_tier_event_id INT;
    DECLARE v_tier_price DECIMAL(10,2);
    DECLARE v_tier_capacity INT;
    DECLARE v_confirmed_count INT;
    DECLARE v_new_reg_id INT;
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_is_active BOOLEAN;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- 1. Verify active user account and retrieve base role (FR-01)
    SELECT RoleType, IsActive INTO v_actor_role, v_is_active
    FROM USER WHERE UserID = p_attendee_id FOR SHARE;

    IF v_is_active IS NULL OR v_is_active = FALSE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'FR-01/UC-01 Error: Attendee account does not exist or is inactive.';
    END IF;

    -- 2. Verify Event exists and block self-registration by owning Organizer (SEC-03 / UC-01 E6)
    SELECT OrganizerID INTO v_organizer_id
    FROM EVENT WHERE EventID = p_event_id FOR SHARE;

    IF v_organizer_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'FR-04 Error: Target Event does not exist.';
    END IF;

    IF v_organizer_id = p_attendee_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'SEC-03 Violation: Event Organizer cannot register as an attendee for their own event.';
    END IF;

    -- 3. Acquire exclusive row lock on TICKET_TIER to serialize concurrent requests (FR-10 / BR-05 / AC-08)
    SELECT EventID, Price, Capacity
    INTO v_tier_event_id, v_tier_price, v_tier_capacity
    FROM TICKET_TIER
    WHERE TicketID = p_ticket_id
    FOR UPDATE;

    IF v_tier_event_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'FR-05 Error: Target Ticket Tier does not exist.';
    END IF;

    -- 4. Enforce Cross-Event Consistency (FR-09 / BR-03 / AC-03)
    IF v_tier_event_id != p_event_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'BR-03 Violation: Selected TicketID does not belong to the specified EventID.';
    END IF;

    -- 5. Calculate dynamic remaining availability under exclusive lock (FR-10 / BR-05 / AC-07 / AC-08)
    SELECT COUNT(*) INTO v_confirmed_count
    FROM REGISTRATION
    WHERE TicketID = p_ticket_id AND Status = 'Confirmed';

    IF v_confirmed_count >= v_tier_capacity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'FR-10/BR-05 Violation: Ticket tier has reached maximum capacity (0 seats remaining).';
    END IF;

    -- 6. Validate Payment Amount equals AcceptedPrice at registration time (FR-08 / BR-10 / AC-09)
    IF p_amount_paid != v_tier_price THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'BR-10 Violation: AmountPaid must equal the TicketTier Price accepted at registration time.';
    END IF;

    -- 7. Insert Confirmed REGISTRATION (captures historical AcceptedPrice; uq_reg_active_attendee_event blocks duplicate active)
    INSERT INTO REGISTRATION (AttendeeID, EventID, TicketID, RegistrationDate, Status, AcceptedPrice)
    VALUES (p_attendee_id, p_event_id, p_ticket_id, NOW(), 'Confirmed', v_tier_price);

    SET v_new_reg_id = LAST_INSERT_ID();

    -- 8. Insert 1:1 PAYMENT (if InvoiceNumber is duplicate or invalid, EXIT HANDLER rolls back Step 7 REGISTRATION)
    INSERT INTO PAYMENT (RegistrationID, AmountPaid, PaymentDate, InvoiceNumber)
    VALUES (v_new_reg_id, p_amount_paid, NOW(), p_invoice_number);

    -- 9. Append immutable creation entry to AUDIT_LOG (FR-18)
    INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionTimestamp, ActionType, EntityName, RecordID, OldValue, NewValue, Reason)
    VALUES (
        p_attendee_id, v_actor_role, NOW(), 'INSERT', 'REGISTRATION_PAYMENT', CAST(v_new_reg_id AS CHAR),
        NULL,
        CONCAT('EventID=', p_event_id, ', TicketID=', p_ticket_id, ', Status=Confirmed, AcceptedPrice=', v_tier_price, ', Invoice=', p_invoice_number),
        'Atomic UC-01 Registration and Payment'
    );

    COMMIT;
END$$
DELIMITER ;
```

### 5.2 Session Scheduling, Roster Enrollment, Check-In & Cancellation Procedures (UC-02, UC-03, FR-11)

```sql
DELIMITER $$

-- UC-02: Schedule Session with Organizer Ownership, Venue Capacity, Event Dates, and Speaker Conflict Checks
CREATE PROCEDURE sp_schedule_session(
    IN p_actor_user_id INT,
    IN p_event_id INT,
    IN p_speaker_id INT,
    IN p_session_title VARCHAR(150),
    IN p_start_dt DATETIME,
    IN p_end_dt DATETIME,
    IN p_session_cap INT,
    IN p_room_number VARCHAR(40)
)
BEGIN
    DECLARE v_owner_id INT;
    DECLARE v_event_start DATE;
    DECLARE v_event_end DATE;
    DECLARE v_venue_cap INT;
    DECLARE v_speaker_role VARCHAR(30);
    DECLARE v_speaker_active BOOLEAN;
    DECLARE v_overlap_count INT;
    DECLARE v_new_session_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT e.OrganizerID, e.StartDate, e.EndDate, v.MaxCapacity
    INTO v_owner_id, v_event_start, v_event_end, v_venue_cap
    FROM EVENT e
    INNER JOIN VENUE v ON e.VenueID = v.VenueID
    WHERE e.EventID = p_event_id
    FOR SHARE;

    IF v_owner_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'UC-02 Error: Target Event does not exist.';
    END IF;

    IF v_owner_id != p_actor_user_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEC-01 Violation: Only the owning Event Organizer can schedule sessions for this event.';
    END IF;

    SELECT RoleType, IsActive INTO v_speaker_role, v_speaker_active
    FROM USER WHERE UserID = p_speaker_id FOR SHARE;

    IF v_speaker_active IS NULL OR v_speaker_active = FALSE OR v_speaker_role != 'Speaker' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'UC-02 Error: Assigned SpeakerID does not exist, is inactive, or does not hold Speaker role.';
    END IF;

    IF p_start_dt >= p_end_dt OR DATE(p_start_dt) < v_event_start OR DATE(p_end_dt) > v_event_end THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-08 Violation: Session timestamps must have Start < End and fall within parent Event dates.';
    END IF;

    IF p_session_cap <= 0 OR p_session_cap > v_venue_cap THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-06 Violation: SessionCapacity must be > 0 and <= Venue.MaxCapacity.';
    END IF;

    SELECT COUNT(*) INTO v_overlap_count
    FROM SESSION
    WHERE SpeakerID = p_speaker_id
      AND StartDateTime < p_end_dt
      AND EndDateTime > p_start_dt;

    IF v_overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FR-14/BR-09 Violation: Assigned Speaker has an overlapping session during this time interval.';
    END IF;

    INSERT INTO SESSION (EventID, SpeakerID, SessionTitle, StartDateTime, EndDateTime, SessionCapacity, RoomNumber)
    VALUES (p_event_id, p_speaker_id, p_session_title, p_start_dt, p_end_dt, p_session_cap, p_room_number);

    SET v_new_session_id = LAST_INSERT_ID();

    INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionTimestamp, ActionType, EntityName, RecordID, OldValue, NewValue, Reason)
    VALUES (
        p_actor_user_id, 'Organizer', NOW(), 'INSERT', 'SESSION', CAST(v_new_session_id AS CHAR),
        NULL,
        CONCAT('EventID=', p_event_id, ', SpeakerID=', p_speaker_id, ', Start=', p_start_dt, ', End=', p_end_dt, ', Cap=', p_session_cap),
        'UC-02 Session Scheduled'
    );

    COMMIT;
END$$

-- UC-03 Part A: Attendee Session Roster Enrollment (Enforces Same-Event, Capacity, and Non-Overlap)
CREATE PROCEDURE sp_enroll_session_roster(
    IN p_actor_user_id INT,
    IN p_registration_id INT,
    IN p_session_id INT
)
BEGIN
    DECLARE v_reg_attendee INT;
    DECLARE v_reg_event INT;
    DECLARE v_reg_status VARCHAR(20);
    DECLARE v_sess_event INT;
    DECLARE v_sess_cap INT;
    DECLARE v_sess_start DATETIME;
    DECLARE v_sess_end DATETIME;
    DECLARE v_enrolled_count INT;
    DECLARE v_attendee_overlap INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT AttendeeID, EventID, Status
    INTO v_reg_attendee, v_reg_event, v_reg_status
    FROM REGISTRATION
    WHERE RegistrationID = p_registration_id
    FOR SHARE;

    IF v_reg_attendee IS NULL OR v_reg_attendee != p_actor_user_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'SEC-02 Violation: Attendee may only enroll using their own RegistrationID.';
    END IF;

    IF v_reg_status != 'Confirmed' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-04 Violation: Only Confirmed registrations can join a session roster.';
    END IF;

    -- Lock target SESSION row exclusively to prevent concurrent session overbooking
    SELECT EventID, SessionCapacity, StartDateTime, EndDateTime
    INTO v_sess_event, v_sess_cap, v_sess_start, v_sess_end
    FROM SESSION
    WHERE SessionID = p_session_id
    FOR UPDATE;

    IF v_sess_event IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'UC-03 Error: Target Session does not exist.';
    END IF;

    IF v_reg_event != v_sess_event THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'BR-04 Violation: Registration and Session must belong to the same EventID.';
    END IF;

    -- Check attendee schedule overlap across already enrolled sessions
    SELECT COUNT(*) INTO v_attendee_overlap
    FROM SESSION_ROSTER sr
    INNER JOIN SESSION s ON sr.SessionID = s.SessionID
    WHERE sr.RegistrationID = p_registration_id
      AND s.StartDateTime < v_sess_end
      AND s.EndDateTime > v_sess_start;

    IF v_attendee_overlap > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FR-15/BR-11 Violation: Attendee is already enrolled in an overlapping session.';
    END IF;

    -- Check session capacity across Confirmed registrations
    SELECT COUNT(*) INTO v_enrolled_count
    FROM SESSION_ROSTER sr
    INNER JOIN REGISTRATION r ON sr.RegistrationID = r.RegistrationID
    WHERE sr.SessionID = p_session_id
      AND r.Status = 'Confirmed';

    IF v_enrolled_count >= v_sess_cap THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FR-15/BR-06 Violation: Session has reached its maximum SessionCapacity.';
    END IF;

    INSERT INTO SESSION_ROSTER (RegistrationID, SessionID, CheckInStatus, EnrolledAt)
    VALUES (p_registration_id, p_session_id, 'Enrolled', NOW());

    COMMIT;
END$$

-- UC-03 Part B: Owning Organizer / Admin Attendance Check-In Recording (FR-16 / SEC-06 / AC-14)
CREATE PROCEDURE sp_record_session_checkin(
    IN p_actor_user_id INT,
    IN p_registration_id INT,
    IN p_session_id INT,
    IN p_new_status ENUM('CheckedIn', 'NoShow')
)
BEGIN
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_owner_id INT;
    DECLARE v_old_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT RoleType INTO v_actor_role FROM USER WHERE UserID = p_actor_user_id AND IsActive = TRUE;
    SELECT e.OrganizerID INTO v_owner_id
    FROM SESSION s
    INNER JOIN EVENT e ON s.EventID = e.EventID
    WHERE s.SessionID = p_session_id;

    IF v_actor_role IS NULL OR (v_actor_role != 'Admin' AND v_owner_id != p_actor_user_id) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'SEC-06 Violation: Only the owning Event Organizer or an Administrator may record session check-in status.';
    END IF;

    SELECT CheckInStatus INTO v_old_status
    FROM SESSION_ROSTER
    WHERE RegistrationID = p_registration_id AND SessionID = p_session_id
    FOR UPDATE;

    IF v_old_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'UC-03 Error: Roster entry does not exist.';
    END IF;

    UPDATE SESSION_ROSTER
    SET CheckInStatus = p_new_status
    WHERE RegistrationID = p_registration_id AND SessionID = p_session_id;

    INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionTimestamp, ActionType, EntityName, RecordID, OldValue, NewValue, Reason)
    VALUES (
        p_actor_user_id, v_actor_role, NOW(), 'STATUS_CHANGE', 'SESSION_ROSTER',
        CONCAT(p_registration_id, ':', p_session_id),
        CONCAT('CheckInStatus=', v_old_status),
        CONCAT('CheckInStatus=', p_new_status),
        'UC-03 Organizer Attendance Verification'
    );

    COMMIT;
END$$

-- FR-11: Controlled Soft-Cancellation Releasing Ticket & Session Roster Capacity
CREATE PROCEDURE sp_cancel_registration(
    IN p_actor_user_id INT,
    IN p_registration_id INT,
    IN p_reason VARCHAR(255)
)
BEGIN
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_attendee_id INT;
    DECLARE v_event_id INT;
    DECLARE v_owner_id INT;
    DECLARE v_old_status VARCHAR(20);
    DECLARE v_action_type VARCHAR(30);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT RoleType INTO v_actor_role FROM USER WHERE UserID = p_actor_user_id AND IsActive = TRUE;
    SELECT r.AttendeeID, r.EventID, r.Status, e.OrganizerID
    INTO v_attendee_id, v_event_id, v_old_status, v_owner_id
    FROM REGISTRATION r
    INNER JOIN EVENT e ON r.EventID = e.EventID
    WHERE r.RegistrationID = p_registration_id
    FOR UPDATE;

    IF v_attendee_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FR-11 Error: Registration does not exist.';
    END IF;

    IF v_old_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FR-11 Error: Registration is already Cancelled.';
    END IF;

    IF p_actor_user_id != v_attendee_id AND p_actor_user_id != v_owner_id AND v_actor_role != 'Admin' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'SEC-02 Violation: Only the owning Attendee, owning Event Organizer, or Admin may cancel a registration.';
    END IF;

    IF p_reason IS NULL OR TRIM(p_reason) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FR-18 Error: A cancellation reason is required.';
    END IF;

    UPDATE REGISTRATION SET Status = 'Cancelled' WHERE RegistrationID = p_registration_id;
    DELETE FROM SESSION_ROSTER WHERE RegistrationID = p_registration_id;

    SET v_action_type = IF(v_actor_role = 'Admin' AND p_actor_user_id != v_attendee_id, 'ADMIN_OVERRIDE', 'STATUS_CHANGE');

    INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionTimestamp, ActionType, EntityName, RecordID, OldValue, NewValue, Reason)
    VALUES (
        p_actor_user_id, v_actor_role, NOW(), v_action_type, 'REGISTRATION',
        CAST(p_registration_id AS CHAR),
        'Status=Confirmed', 'Status=Cancelled (Session Roster seats released)', p_reason
    );

    COMMIT;
END$$
DELIMITER ;
```

### 5.3 Capacity Non-Reduction & Integrity Triggers (BR-06, BR-07, BR-08, BR-09)

In addition to stored procedures, defensive `BEFORE INSERT` and `BEFORE UPDATE` triggers prevent any direct SQL statement from violating venue capacity sums, retroactive capacity reductions, or speaker schedule conflicts:

```sql
DELIMITER $$

-- BR-06 & BR-07: Prevent Ticket Tier capacity sum from exceeding Venue.MaxCapacity or dropping below Confirmed count
CREATE TRIGGER trg_tickettier_bi_cap
BEFORE INSERT ON TICKET_TIER
FOR EACH ROW
BEGIN
    DECLARE v_venue_cap INT;
    DECLARE v_current_tier_sum INT;

    SELECT v.MaxCapacity INTO v_venue_cap
    FROM EVENT e INNER JOIN VENUE v ON e.VenueID = v.VenueID
    WHERE e.EventID = NEW.EventID;

    SELECT COALESCE(SUM(Capacity), 0) INTO v_current_tier_sum
    FROM TICKET_TIER WHERE EventID = NEW.EventID;

    IF (v_current_tier_sum + NEW.Capacity) > v_venue_cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'BR-06 Violation: Sum of TicketTier capacities for this event exceeds Venue.MaxCapacity.';
    END IF;
END$$

CREATE TRIGGER trg_tickettier_bu_cap
BEFORE UPDATE ON TICKET_TIER
FOR EACH ROW
BEGIN
    DECLARE v_venue_cap INT;
    DECLARE v_other_tier_sum INT;
    DECLARE v_confirmed_regs INT;

    SELECT COUNT(*) INTO v_confirmed_regs
    FROM REGISTRATION
    WHERE TicketID = NEW.TicketID AND Status = 'Confirmed';

    IF NEW.Capacity < v_confirmed_regs THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'BR-07 Violation: Cannot reduce TicketTier.Capacity below current Confirmed registration count.';
    END IF;

    SELECT v.MaxCapacity INTO v_venue_cap
    FROM EVENT e INNER JOIN VENUE v ON e.VenueID = v.VenueID
    WHERE e.EventID = NEW.EventID;

    SELECT COALESCE(SUM(Capacity), 0) INTO v_other_tier_sum
    FROM TICKET_TIER WHERE EventID = NEW.EventID AND TicketID != NEW.TicketID;

    IF (v_other_tier_sum + NEW.Capacity) > v_venue_cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'BR-06 Violation: Updated TicketTier capacity sum exceeds Venue.MaxCapacity.';
    END IF;
END$$

-- BR-07: Prevent reducing Venue.MaxCapacity below any hosted event's tier sum or session capacity
CREATE TRIGGER trg_venue_bu_cap
BEFORE UPDATE ON VENUE
FOR EACH ROW
BEGIN
    DECLARE v_max_event_tier_sum INT;
    DECLARE v_max_session_cap INT;

    SELECT COALESCE(MAX(tier_sum), 0) INTO v_max_event_tier_sum
    FROM (
        SELECT SUM(tt.Capacity) AS tier_sum
        FROM EVENT e INNER JOIN TICKET_TIER tt ON e.EventID = tt.EventID
        WHERE e.VenueID = NEW.VenueID
        GROUP BY e.EventID
    ) t;

    SELECT COALESCE(MAX(s.SessionCapacity), 0) INTO v_max_session_cap
    FROM EVENT e INNER JOIN SESSION s ON e.EventID = s.EventID
    WHERE e.VenueID = NEW.VenueID;

    IF NEW.MaxCapacity < v_max_event_tier_sum OR NEW.MaxCapacity < v_max_session_cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'BR-07 Violation: Cannot reduce Venue.MaxCapacity below existing hosted event ticket-tier or session capacities.';
    END IF;
END$$
DELIMITER ;
```

---

## 6. Audit and Traceability Design

### 6.1 Audited Business Events & Forensic Content (FR-18, SEC-08, SEC-09)

Every sensitive business modification writes an append-only row to `AUDIT_LOG` containing `ActorUserID`, `ActorRole`, `ActionTimestamp`, `ActionType` (`INSERT`, `UPDATE`, `DELETE`, `STATUS_CHANGE`, `ADMIN_OVERRIDE`), `EntityName`, `RecordID`, `OldValue`, `NewValue`, and `Reason`.

```sql
DELIMITER $$

-- Automatic AFTER UPDATE Audit Trigger on TICKET_TIER (Tracks Price & Capacity changes - AC-13 / FR-18)
CREATE TRIGGER trg_tickettier_au_audit
AFTER UPDATE ON TICKET_TIER
FOR EACH ROW
BEGIN
    IF OLD.Price != NEW.Price OR OLD.Capacity != NEW.Capacity THEN
        INSERT INTO AUDIT_LOG (
            ActorUserID, ActorRole, ActionTimestamp, ActionType,
            EntityName, RecordID, OldValue, NewValue, Reason
        )
        VALUES (
            COALESCE(@current_user_id, 1),
            COALESCE(@current_user_role, 'Organizer'),
            NOW(),
            'UPDATE',
            'TICKET_TIER',
            CAST(NEW.TicketID AS CHAR),
            CONCAT('Price=', OLD.Price, ', Capacity=', OLD.Capacity),
            CONCAT('Price=', NEW.Price, ', Capacity=', NEW.Capacity),
            COALESCE(@current_reason, 'Organizer Ticket Tier Price/Capacity Update')
        );
    END IF;
END$$

-- Immutability Triggers on AUDIT_LOG (BR-12 / SEC-08 / AC-16)
CREATE TRIGGER trg_audit_log_bu_immutable
BEFORE UPDATE ON AUDIT_LOG
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'BR-12/SEC-08 Violation: AUDIT_LOG is append-only and immutable. UPDATE operations are prohibited.';
END$$

CREATE TRIGGER trg_audit_log_bd_immutable
BEFORE DELETE ON AUDIT_LOG
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'BR-12/SEC-08 Violation: AUDIT_LOG is append-only and immutable. DELETE operations are prohibited.';
END$$
DELIMITER ;
```

### 6.2 Lifecycle History Reconstruction Query

To trace a business record (`RegistrationID = 501`) across its entire lifecycle (initial atomic registration and payment, session roster enrollment, organizer check-in verification, or cancellation), the demonstration script executes:

```sql
SELECT
    a.LogID,
    a.ActionTimestamp,
    CONCAT(u.FirstName, ' ', u.LastName) AS ActorName,
    a.ActorRole,
    a.ActionType,
    a.EntityName,
    a.RecordID,
    a.OldValue,
    a.NewValue,
    a.Reason
FROM AUDIT_LOG a
INNER JOIN USER u ON a.ActorUserID = u.UserID
WHERE (a.EntityName IN ('REGISTRATION', 'REGISTRATION_PAYMENT', 'PAYMENT') AND a.RecordID = '501')
   OR (a.EntityName = 'SESSION_ROSTER' AND a.RecordID LIKE '501:%')
ORDER BY a.ActionTimestamp ASC, a.LogID ASC;
```

---

## 7. Performance and Index Design

### 7.1 Index Catalog & Access Path Justification

| Index Name | Table | Indexed Columns | Type | Supported Query / Constraint | Performance Benefit & Access Path |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `uq_user_email` | `USER` | `(Email)` | UNIQUE BTREE | FR-01 unique email lookup | $O(\log N)$ `const` point lookup; prevents full scan on `USER` |
| `idx_event_startdate_org` | `EVENT` | `(StartDate, OrganizerID)` | BTREE | RQ-01 date filtering, `ORDER BY StartDate DESC`, and SEC-01 organizer ownership | Index range scan on `StartDate`; avoids external `filesort` |
| `uq_event_ticket` | `TICKET_TIER` | `(EventID, TicketID)` | UNIQUE BTREE | Composite FK target for `REGISTRATION(EventID, TicketID)` (BR-03) | Covering index lookup for cross-event ticket validation (AC-03) |
| `idx_session_speaker_interval` | `SESSION` | `(SpeakerID, StartDateTime, EndDateTime)` | BTREE | Speaker double-booking overlap check (FR-14, BR-09, AC-10) & RQ-04 | Covering index range scan on `SpeakerID` + timestamps; avoids scanning all sessions |
| `idx_session_event_interval` | `SESSION` | `(EventID, StartDateTime, EndDateTime)` | BTREE | Event schedule browsing & attendee session overlap check (FR-15) | Ordered retrieval of sessions within a single event |
| `idx_reg_ticket_status` | `REGISTRATION` | `(TicketID, Status)` | BTREE | Locked capacity count `WHERE TicketID = ? AND Status = 'Confirmed'` (UC-01, FR-10, RQ-03) | Covering index-only scan (`Using index`); minimizes exclusive lock hold time during UC-01 |
| `idx_reg_event_status` | `REGISTRATION` | `(EventID, Status, RegistrationID)` | BTREE | RQ-01 Event Revenue Summary join and status aggregation | Accelerates `LEFT JOIN` and conditional `Confirmed`/`Cancelled` counts per event |
| `uq_reg_active_attendee_event` | `REGISTRATION` | `(ActiveAttendeeEventKey, EventID)` | UNIQUE BTREE | BR-02 single active registration per attendee & event (AC-05) | Declarative uniqueness check; allows multiple historical `'Cancelled'` rows |
| `idx_roster_session_status` | `SESSION_ROSTER` | `(SessionID, CheckInStatus, RegistrationID)` | BTREE | RQ-02 Session Roster Report & UC-03 session capacity count | Reverses PK `(RegistrationID, SessionID)` so queries filtering by `SessionID` use an index `ref` scan |
| `idx_audit_entity_record_time` | `AUDIT_LOG` | `(EntityName, RecordID, ActionTimestamp)` | BTREE | Lifecycle history reconstruction query (Section 6.2) | Selective range scan by target entity and record ID |

### 7.2 Write-Heavy Trade-Off Analysis

* **Write Amplification vs. Lock Duration on `REGISTRATION`:** While every secondary index on `REGISTRATION` incurs B-Tree maintenance during UC-01 inserts, `idx_reg_ticket_status (TicketID, Status)` is critical because `SELECT COUNT(*) FROM REGISTRATION WHERE TicketID = ? AND Status = 'Confirmed'` executes while holding an exclusive row lock (`FOR UPDATE`) on `TICKET_TIER`. Serving that count via a covering index scan (`Using index`) avoids reading table data pages and keeps lock duration under 1 ms.
* **Minimal Indexing on `AUDIT_LOG`:** Because `AUDIT_LOG` is written on every sensitive transaction, we intentionally avoid indexing free-text columns (`OldValue`, `NewValue`, `Reason`) and maintain only `fk_audit_actor` and `idx_audit_entity_record_time`.

### 7.3 Reporting Views (RQ-01–RQ-04) & EXPLAIN Execution Plan Walkthrough

```sql
-- RQ-01: Event Revenue and Registration Summary Report (FR-17 / AC-15)
CREATE OR REPLACE VIEW v_rq01_event_revenue AS
SELECT
    e.EventID,
    e.EventName,
    e.StartDate,
    e.EndDate,
    e.OrganizerID,
    COUNT(DISTINCT CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END) AS ConfirmedRegistrations,
    COUNT(DISTINCT CASE WHEN r.Status = 'Cancelled' THEN r.RegistrationID END) AS CancelledRegistrations,
    COALESCE(SUM(CASE WHEN r.Status = 'Confirmed' THEN p.AmountPaid ELSE 0.00 END), 0.00) AS GrossRecordedRevenue
FROM EVENT e
LEFT JOIN REGISTRATION r ON e.EventID = r.EventID
LEFT JOIN PAYMENT p ON r.RegistrationID = p.RegistrationID
GROUP BY e.EventID, e.EventName, e.StartDate, e.EndDate, e.OrganizerID
ORDER BY e.StartDate DESC, e.EventID ASC;

-- RQ-02: Session Roster and Attendance Detail Report (FR-17 / AC-15)
CREATE OR REPLACE VIEW v_rq02_session_roster AS
SELECT
    s.SessionID,
    s.SessionTitle,
    s.StartDateTime,
    s.EndDateTime,
    s.EventID,
    s.SpeakerID,
    r.RegistrationID,
    u.UserID,
    u.FirstName,
    u.LastName,
    u.Email,
    tt.TierName,
    sr.CheckInStatus
FROM SESSION s
INNER JOIN SESSION_ROSTER sr ON s.SessionID = sr.SessionID
INNER JOIN REGISTRATION r ON sr.RegistrationID = r.RegistrationID
INNER JOIN USER u ON r.AttendeeID = u.UserID
INNER JOIN TICKET_TIER tt ON r.EventID = tt.EventID AND r.TicketID = tt.TicketID
WHERE r.Status = 'Confirmed'
ORDER BY u.LastName ASC, u.FirstName ASC, u.UserID ASC;

```sql
-- RQ-03: Ticket Tier and Session Capacity Exception / Utilization Report (FR-17)  
CREATE OR REPLACE VIEW v_rq03_capacity_utilization AS  
SELECT  
    e.EventID,  
    e.EventName,  
    'TicketTier' AS ResourceType,  
    tt.TicketID AS ResourceID,  
    tt.TierName AS ResourceName,  
    tt.Capacity AS ConfiguredCapacity,  
    COUNT(CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END) AS ActiveConfirmedCount,  
    (tt.Capacity - COUNT(CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END)) AS RemainingSeats,  
    ROUND((COUNT(CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END) / tt.Capacity) * 100, 2) AS UtilizationPct  
FROM EVENT e  
INNER JOIN TICKET_TIER tt ON e.EventID = tt.EventID  
LEFT JOIN REGISTRATION r ON tt.EventID = r.EventID AND tt.TicketID = r.TicketID  
GROUP BY e.EventID, e.EventName, tt.TicketID, tt.TierName, tt.Capacity  
UNION ALL  
SELECT  
    e.EventID,  
    e.EventName,  
    'Session' AS ResourceType,  
    s.SessionID AS ResourceID,  
    s.SessionTitle AS ResourceName,  
    s.SessionCapacity AS ConfiguredCapacity,  
    COUNT(CASE WHEN r.Status = 'Confirmed' THEN sr.RegistrationID END) AS ActiveConfirmedCount,  
    (s.SessionCapacity - COUNT(CASE WHEN r.Status = 'Confirmed' THEN sr.RegistrationID END)) AS RemainingSeats,  
    ROUND((COUNT(CASE WHEN r.Status = 'Confirmed' THEN sr.RegistrationID END) / s.SessionCapacity) * 100, 2) AS UtilizationPct  
FROM EVENT e  
INNER JOIN SESSION s ON e.EventID = s.EventID  
LEFT JOIN SESSION_ROSTER sr ON s.SessionID = sr.SessionID  
LEFT JOIN REGISTRATION r ON sr.RegistrationID = r.RegistrationID  
GROUP BY e.EventID, e.EventName, s.SessionID, s.SessionTitle, s.SessionCapacity;  

-- RQ-04: Speaker Schedule and Assignment Report (FR-17)  
CREATE OR REPLACE VIEW v_rq04_speaker_schedule AS  
SELECT  
    u.UserID AS SpeakerID,  
    u.FirstName,  
    u.LastName,  
    e.EventID,  
    e.EventName,  
    v.VenueName,  
    s.SessionID,  
    s.SessionTitle,  
    s.RoomNumber,  
    s.StartDateTime,  
    s.EndDateTime,  
    s.SessionCapacity,  
    COUNT(CASE WHEN r.Status = 'Confirmed' THEN sr.RegistrationID END) AS EnrolledCount  
FROM USER u  
INNER JOIN SESSION s ON u.UserID = s.SpeakerID  
INNER JOIN EVENT e ON s.EventID = e.EventID  
INNER JOIN VENUE v ON e.VenueID = v.VenueID  
LEFT JOIN SESSION_ROSTER sr ON s.SessionID = sr.SessionID  
LEFT JOIN REGISTRATION r ON sr.RegistrationID = r.RegistrationID  
GROUP BY u.UserID, u.FirstName, u.LastName, e.EventID, e.EventName, v.VenueName,  
         s.SessionID, s.SessionTitle, s.RoomNumber, s.StartDateTime, s.EndDateTime, s.SessionCapacity  
ORDER BY s.StartDateTime ASC, u.UserID ASC;
```
**EXPLAIN Execution Plan Summary for Final Demo:**
* Running `EXPLAIN SELECT * FROM v_rq01_event_revenue WHERE EventID = 1;` shows const access on EVENT (PRIMARY), ref index lookup on REGISTRATION via `idx_reg_event_status`, and eq_ref unique index lookup on PAYMENT via `uq_payment_registration`.
* Running `EXPLAIN SELECT * FROM v_rq02_session_roster WHERE SessionID = 101;` shows const access on SESSION (PRIMARY), ref index scan on SESSION_ROSTER via `idx_roster_session_status`, and eq_ref primary key lookups on REGISTRATION, USER, and TICKET_TIER.

## 8. Testing and Test Evidence Matrix

The automated test script (`sql/04_test_suite_and_demo.sql`) executes all 16 FRD Acceptance Criteria (AC-01–AC-16) plus boundary constraint tests (TC-01–TC-07).

| Test ID | Type | Rule / Req | SQL / Procedure Executed | Expected Result | Actual / Demo Verification Query |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-01** | Positive / Atomic | FR-06–FR-08, BR-10, UC-01 | `CALL sp_register_and_pay(5, 1, 10, 50.00, 'INV-1001');` | Commits 1 Confirmed row in REGISTRATION (AcceptedPrice = 50.00), 1 row in PAYMENT, 1 row in AUDIT_LOG; remaining capacity decreases by 1. | `SELECT * FROM REGISTRATION WHERE AttendeeID=5 AND EventID=1;` + PAYMENT + AUDIT_LOG |
| **AC-02** | Negative / FK Integrity | FR-01, FR-04, FR-06, FR-13, BR-01 | `CALL sp_register_and_pay(999, 1, 10, 50.00, 'INV-ERR1');` & invalid EventID/SpeakerID inserts | Rejected by FK/validation check (SQLSTATE 23000 / 45000); 0 rows added. | Error output and unchanged table row counts |
| **AC-03** | Negative / Cross-Event Ticket | FR-09, BR-03, UC-01 (E1) | `CALL sp_register_and_pay(6, 1, 20, 100.00, 'INV-CROSS');` (TicketID=20 belongs to EventID=2) | Rejected (BR-03 Violation); transaction rolls back. | Error output and `SELECT COUNT(*)` showing 0 rows added |
| **AC-04** | Negative / Cross-Event Roster | FR-15, BR-04, UC-03 (E1) | `CALL sp_enroll_session_roster(5, 501, 201);` (Reg 501 in Event 1; Session 201 in Event 2) | Rejected (BR-04 Violation: Registration and Session must belong to the same EventID). | Error output and `SELECT * FROM SESSION_ROSTER WHERE RegistrationID=501 AND SessionID=201;` (0 rows) |
| **AC-05** | Negative + Lifecycle | FR-09, FR-11, BR-02, UC-01 (E2) | 1. Duplicate `CALL sp_register_and_pay(5, 1, 10, 50.00, 'INV-DUP');` <br>2. `CALL sp_cancel_registration(5, 501, 'Schedule change');` <br>3. `CALL sp_register_and_pay(5, 1, 10, 50.00, 'INV-REREG');` | 1. Duplicate active rejected by `uq_reg_active_attendee_event`. <br>2. Reg 501 becomes 'Cancelled'. <br>3. New registration commits as 'Confirmed'. | Error on step 1; `SELECT RegistrationID, Status FROM REGISTRATION WHERE AttendeeID=5 AND EventID=1;` showing 1 Cancelled and 1 Confirmed |
| **AC-06** | Negative / Duplicate Roster | FR-15, BR-11, UC-03 (E3) | Execute `CALL sp_enroll_session_roster(5, 502, 101);` twice | First call inserts 'Enrolled'; second call rejected by PRIMARY KEY (RegistrationID, SessionID). | Error output on second call; `SELECT COUNT(*) = 1` |
| **AC-07** | Boundary / Full Tier | FR-10, BR-05, UC-01 (E3) | Tier 12 (Capacity = 2) has 2 Confirmed rows; call `sp_register_and_pay(7, 1, 12, 150.00, 'INV-FULL');` | Rejected (0 seats remaining); no registration or payment created. | Error output and `SELECT COUNT(*) = 2` |
| **AC-08** | Concurrency / Last Seat | FR-10, BR-05, UC-01 (E4) | Tier 15 (Capacity = 5) has 4 Confirmed rows. Two concurrent sessions execute `sp_register_and_pay` for the 5th seat. | `FOR UPDATE` lock on `TICKET_TIER` serializes requests: Session A commits 5th seat; Session B sees 5/5 and rolls back. | Dual-session log + `SELECT COUNT(*) FROM REGISTRATION WHERE TicketID=15 AND Status='Confirmed';` (= 5) |
| **AC-09** | Resiliency / Atomic Rollback | FR-06, FR-07, BR-10, UC-01 (E5) | Execute `sp_register_and_pay` with mismatched AmountPaid = 30.00 or duplicate InvoiceNumber = 'INV-1001' | PAYMENT step fails; EXIT HANDLER rolls back the uncommitted REGISTRATION row. | Before/after SELECT on REGISTRATION and PAYMENT proving zero orphaned rows |
| **AC-10** | Negative / Speaker Overlap | FR-14, BR-09, UC-02 (E3) | Speaker 3 scheduled 10:00–11:30; call `sp_schedule_session` for Speaker 3 at 11:00–12:00 | Rejected (FR-14/BR-09 Violation: Assigned Speaker has an overlapping session). | Error output and `SELECT * FROM SESSION WHERE SpeakerID=3;` |
| **AC-11** | Boundary / Session Dates | FR-13, BR-08, UC-02 (E2) | Schedule session outside Event 1 dates (2026-11-15) and session with Start >= End | Both rejected by `sp_schedule_session` / `chk_sess_time`. | Error output and SESSION query |
| **AC-12** | Security / Ownership | FR-02, SEC-01–SEC-04 | 1. Attendee 5 tries to cancel Attendee 6's registration. <br>2. Organizer 2 tries to schedule session on Organizer 4's Event 2. <br>3. Organizer 2 tries to register as attendee for own Event 1. | All three unauthorized calls are rejected (SEC-01, SEC-02, SEC-03 violations). | SQL error logs for all 3 unauthorized attempts |
| **AC-13** | Integrity / Historical Price | FR-08, BR-10 | User 5 registers at $50.00; Organizer 2 updates Tier 10 Price to $75.00; User 6 registers at $75.00. | User 5 row keeps AcceptedPrice = 50.00 and AmountPaid = 50.00; User 6 row records 75.00. | `SELECT RegistrationID, AttendeeID, AcceptedPrice FROM REGISTRATION WHERE TicketID=10;` |
| **AC-14** | Security / Check-In Role | FR-16, BR-11, SEC-06, UC-03 | 1. Attendee 5 or Speaker 3 calls `sp_record_session_checkin(5, 502, 101, 'CheckedIn')`. <br>2. Owning Organizer 2 calls `sp_record_session_checkin(2, 502, 101, 'CheckedIn')`. | 1. Attendee and Speaker calls denied (SEC-06 Violation). <br>2. Owning Organizer call succeeds and writes AUDIT_LOG row. | Error output for step 1; updated SESSION_ROSTER and AUDIT_LOG rows for step 2 |
| **AC-15** | Reporting / Zero-Result | FR-17, SEC-07, RQ-01, RQ-02 | Run `SELECT * FROM v_rq01_event_revenue;` (Event 1 has $50 + $75 confirmed, $50 cancelled; Event 2 has 0 registrations) and `v_rq02_session_roster`. | Event 1 returns Confirmed=2, Cancelled=1, GrossRecordedRevenue=125.00; Event 2 returns 0, 0, 0.00. | Query result sets and EXPLAIN output |
| **AC-16** | Governance / Immutable Audit | FR-18, BR-12, SEC-08, SEC-09 | Admin executes `UPDATE AUDIT_LOG SET NewValue='Tampered' WHERE LogID=1;` and `DELETE FROM AUDIT_LOG WHERE LogID=1;` | Both statements are blocked by `trg_audit_log_bu_immutable` and `trg_audit_log_bd_immutable`. | Trigger error output and `SELECT * FROM AUDIT_LOG WHERE LogID=1;` |

## 9. Repository Layout, Build Sequence, and Final Demonstration Runbook

### 9.1 Repository Directory Structure

```text
event-registration-db/  
├── README.md                                        # Prerequisites, version tag clone, build & demo instructions  
├── docs/  
│   ├── Event_Registration_FRD_v2.md                 # Functional Requirements Document (v2.0)  
│   ├── Event_Registration_TDD_v2.md                 # Technical Design Document (v2.0)  
│   └── erd/  
│       ├── Event_Registration_ERD_v2.drawio         # Editable draw.io ER Diagram  
│       ├── Event_Registration_ERD_v2.svg            # Vector export of ER Diagram  
│       ├── Event_Registration_ERD_v2.png            # Raster export of ER Diagram  
│       └── CS437_Event_Registration_3D_ERD_v4.html  # Interactive 3D ER Diagram & ACID Simulator  
└── sql/  
    ├── 00_build_all.sql                             # Master repeatable build & initialization script  
    ├── 01_schema_ddl.sql                            # Drops/creates schema, 9 3NF tables, constraints, indexes  
    ├── 02_triggers_and_procedures.sql               # Triggers, atomic stored procedures, views, roles/grants  
    ├── 03_seed_sample_data.sql                      # Realistic baseline sample dataset  
    └── 04_test_suite_and_demo.sql                   # Reproducible test suite (AC-01..AC-16) & EXPLAIN plans
