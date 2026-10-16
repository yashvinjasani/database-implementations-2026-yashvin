# Functional Requirements Document (FRD)

## 1. Project Identification

| Item | Information |
| :--- | :--- |
| **Project title** | Event Registration and Attendee Management System |
| **Prepared by** | Yashvin Jasani |
| **Course/section** | CS 437 (01:198:437) Database Implementation |
| **Date** | October 16, 2026 |
| **Version** | 2.0 |
| **Repository location** | [https://github.com/yashvinjasani/database-implementations-2026-yashvin/] |

---

## 2. Business Problem and Purpose

### Business Problem
An event management organization needs a centralized relational database system to manage multi-session events, venue capacities, tiered ticket sales, speaker schedules, attendee registrations, payments, and session attendance. Currently, records are maintained across disconnected spreadsheets and manual forms. This fragmentation causes ticket and venue overbooking, double-booked speakers, inconsistent historical pricing when ticket rates change, unverified session check-ins, and inaccurate financial reporting.

### Project Purpose
The purpose of this project is to design and implement a normalized (3NF) MySQL relational database that enables event organizers to schedule events and sessions within strict capacity and time boundaries, allows attendees to register for events and enroll in sessions with transactional integrity, allows speakers to view assigned session schedules and rosters, and provides administrators with immutable audit logging. The database serves as the single authoritative source for capacity enforcement, access control, attendance tracking, and revenue reporting.

---

## 3. Scope

| In Scope | Out of Scope |
| :--- | :--- |
| Maintaining user accounts with base role capabilities and event-specific ownership/participation permissions | Live credit-card processing or integration with external payment gateways (e.g., Stripe, PayPal) |
| Managing venues, events, ticket tiers, and scheduled sessions with start/end timestamps | Automated partial payments, installment plans, or automated bank refund disbursements |
| Enforcing venue, ticket-tier, and session capacity limits under concurrent registration requests | Physical room-entity modeling and room-level capacity enforcement (session room numbers are stored as informational labels only) |
| Atomic recording of single-ticket event registrations and fictional/externally supplied payment references | Integration with external calendar platforms (e.g., Google Calendar, Outlook) |
| Preserving historical ticket prices accepted at the time of registration | Virtual event streaming or webinar hosting infrastructure |
| Enforcing cross-event consistency for ticket tiers and session rosters, and preventing speaker schedule overlaps | Automated marketing campaigns or external email notification services |
| Separating attendee session roster enrollment from organizer-recorded attendance check-in | Attendee self-check-in via mobile QR scanning hardware |
| Generating operational and management reports for event revenue, session rosters, and capacity utilization | Financial accounting beyond gross recorded registration payments (e.g., venue rental expenses or net profit calculation) |
| Recording immutable audit logs for sensitive data modifications and defined administrative overrides | |

---

## 4. Stakeholders and User Roles

### User-Role and Permission Model
The system enforces a **hybrid role and ownership permission model** combining a user's assigned account role (`RoleType`) with the user's relationship to a specific event or session:
1. **Global Account Capabilities:** Every user account holds a primary base role (`Admin`, `Organizer`, `Speaker`, or `Attendee`).
   * **Admin** is a strictly global governance role providing user account administration, read-only access to the system audit log, global report viewing, and specific, logged administrative overrides. Administrators do **not** perform routine event creation or session scheduling and cannot bypass database integrity or capacity constraints.
   * **Organizer** grants the capability to create new events and become the assigned owner (`OrganizerID`) of those events.
   * **Speaker** designates eligibility to be assigned by an Organizer to lead a session (`SpeakerID`).
   * **Attendee** is the standard participant capability allowing a user to register for events.
2. **Event-Specific and Ownership Rules:**
   * **Organizer Ownership & Attendee Participation:** An Organizer may view, modify, schedule sessions for, and record check-ins **only** for events where they are the assigned `OrganizerID`. An Organizer **may** register as an attendee for events managed by *other* organizers, but is prohibited from registering as an attendee for an event they organize themselves.
   * **Speaker Participation across Events/Sessions:** A user assigned as the `SpeakerID` for a session has read-only access to that session's details and roster. A Speaker **may** also register as an attendee for the same event (or any other event) and enroll in other sessions of that event, provided they hold a `Confirmed` registration for that event and the sessions do not overlap with their speaking assignments.
   * **Attendee Ownership:** Any user acting as an Attendee for an event may view and manage **only** their own registrations, payments, and session roster enrollments.

| Stakeholder or Role | Responsibilities | Database Needs | Typical Access |
| :--- | :--- | :--- | :--- |
| **Admin** | Account administration, security monitoring, and executing defined administrative overrides | `USER`, `AUDIT_LOG`, and read access to operational/financial views; override access on `REGISTRATION`, `PAYMENT`, `EVENT` | Global account management; read-only access to `AUDIT_LOG` (append-only via system triggers/procedures); logged override operations |
| **Organizer** | Creates events, configures ticket tiers, schedules sessions, assigns speakers, records session check-ins, and monitors revenue for owned events | `VENUE`, and owned records in `EVENT`, `TICKET_TIER`, `SESSION`, `REGISTRATION`, `SESSION_ROSTER`, `PAYMENT` | Create/update/view strictly for events where `EVENT.OrganizerID = UserID`; may register as an Attendee for non-owned events |
| **Speaker** | Delivers presentations at assigned event sessions | Assigned records in `SESSION`, `EVENT`, `VENUE`, and `SESSION_ROSTER` | View assigned session details and assigned session rosters; may register as an Attendee and join non-overlapping sessions if holding a `Confirmed` registration |
| **Attendee** | Browses public events, registers and pays for tickets, enrolls in eligible sessions, and views personal check-in and payment status | Public `EVENT`, `VENUE`, `TICKET_TIER`, `SESSION` records; personal records in `REGISTRATION`, `PAYMENT`, `SESSION_ROSTER` | View public event catalog; create/view/cancel own registrations and session roster entries; view own payment and check-in records only |

---

## 5. Functional Requirements

| ID | Functional Requirement | Priority | Related Data/Entities | Related Role(s) |
| :--- | :--- | :--- | :--- | :--- |
| **FR-01** | The system shall store and maintain one user account record per individual, including a unique identifier, first name, last name, unique email address, account status, and assigned base role (`Admin`, `Organizer`, `Speaker`, or `Attendee`). | High | `USER` | Admin |
| **FR-02** | The system shall determine user permissions from the user's assigned base role and, where applicable, the user's ownership or participation relationship to the target event, session, or registration. | High | `USER`, `EVENT`, `SESSION`, `REGISTRATION` | All Roles |
| **FR-03** | The system shall store and maintain venue records, including venue name, physical address, and a positive maximum capacity (`MaxCapacity`). | High | `VENUE` | Admin, Organizer |
| **FR-04** | The system shall allow an authorized Organizer to create and update event records, including event name, start date, end date, assigned venue, and owning organizer. | High | `EVENT`, `VENUE`, `USER` | Organizer |
| **FR-05** | The system shall allow the owning Organizer of an event to create and update ticket tiers for that event, specifying tier name, current unit price (`Price >= 0.00`), and maximum tier capacity (`Capacity > 0`), provided the sum of all ticket-tier capacities for the event does not exceed the assigned venue's `MaxCapacity`. | High | `TICKET_TIER`, `EVENT`, `VENUE` | Organizer |
| **FR-06** | The system shall allow a user (excluding the event's owning Organizer) to register for one ticket in a selected ticket tier of an event and atomically record the corresponding payment within a single transaction, setting the registration status to `Confirmed`. | High | `REGISTRATION`, `PAYMENT`, `EVENT`, `TICKET_TIER`, `USER` | Attendee, Organizer (other events), Speaker |
| **FR-07** | The system shall record fictional or externally supplied payment references (`InvoiceNumber`), payment dates, and payment amounts (`AmountPaid`), and shall not collect or store live credit-card credentials. | High | `PAYMENT`, `REGISTRATION` | Attendee, Admin |
| **FR-08** | The system shall preserve the ticket price accepted at registration time (`AcceptedPrice`) on the registration record and require `Payment.AmountPaid` to equal `AcceptedPrice`; subsequent changes to `TicketTier.Price` shall not alter existing registration charges or recorded payments. | High | `REGISTRATION`, `TICKET_TIER`, `PAYMENT` | Organizer, Attendee |
| **FR-09** | The system shall reject any registration where the selected `TicketID` does not belong to the specified `EventID`, or where the attendee already holds an active (`Confirmed`) registration for that event. | High | `REGISTRATION`, `TICKET_TIER`, `EVENT` | Attendee, System |
| **FR-10** | The system shall enforce ticket-tier capacity such that only `Confirmed` registrations consume capacity (one seat per registration), and concurrent registration attempts shall not cause the number of `Confirmed` registrations to exceed the ticket tier's configured `Capacity`. | High | `REGISTRATION`, `TICKET_TIER` | Attendee, System |
| **FR-11** | The system shall allow an attendee (for their own registration) or the owning Organizer/Admin to cancel a `Confirmed` registration by updating its status to `Cancelled`, which releases its consumed ticket-tier capacity and removes or releases associated session roster seats. | Medium | `REGISTRATION`, `TICKET_TIER`, `SESSION_ROSTER` | Attendee, Organizer, Admin |
| **FR-12** | The system shall prohibit reducing a venue's `MaxCapacity` below any hosted event's total ticket-tier capacity, reducing a ticket tier's `Capacity` below its current count of `Confirmed` registrations, or reducing a session's `SessionCapacity` below its current enrolled roster count. | High | `VENUE`, `TICKET_TIER`, `SESSION`, `REGISTRATION`, `SESSION_ROSTER` | Organizer, Admin |
| **FR-13** | The system shall allow the owning Organizer of an event to schedule event sessions specifying session title, `StartDateTime`, `EndDateTime`, `SessionCapacity`, informational `RoomNumber` label, and exactly one assigned Speaker (`SpeakerID`), provided the session falls within the parent event's start and end dates and `StartDateTime < EndDateTime`. | High | `SESSION`, `EVENT`, `USER` | Organizer |
| **FR-14** | The system shall reject a session creation or update if the assigned speaker (`SpeakerID`) is already assigned to another session (in the same or any other event) whose time interval (`StartDateTime` to `EndDateTime`) overlaps the proposed session. | High | `SESSION`, `USER` | Organizer, System |
| **FR-15** | The system shall allow an attendee with a `Confirmed` registration for an event to join or leave a session roster for that same event (setting initial `CheckInStatus` to `'Enrolled'`), and shall reject enrollment if the session belongs to a different event, the registration is `Cancelled`, the session has reached `SessionCapacity`, the registration is already on that session's roster, or the session overlaps another session on the attendee's roster. | High | `SESSION_ROSTER`, `REGISTRATION`, `SESSION`, `EVENT` | Attendee |
| **FR-16** | The system shall allow only the owning Event Organizer (or an Administrator) to record session attendance by updating a roster entry's `CheckInStatus` from `'Enrolled'` to `'CheckedIn'` or `'NoShow'`, while allowing attendees to view their own check-in status and speakers to view rosters for their assigned sessions. | High | `SESSION_ROSTER`, `SESSION`, `EVENT`, `USER` | Organizer, Admin, Speaker, Attendee |
| **FR-17** | The system shall produce an Event Revenue Summary Report (`RQ-01`), a Session Roster and Attendance Report (`RQ-02`), a Capacity Utilization and Exception Report (`RQ-03`), and a Speaker Schedule Report (`RQ-04`) restricted to authorized roles. | Medium | `EVENT`, `TICKET_TIER`, `REGISTRATION`, `PAYMENT`, `SESSION`, `SESSION_ROSTER`, `USER` | Organizer, Speaker, Admin |
| **FR-18** | The system shall automatically record an immutable entry in `AUDIT_LOG`—capturing actor user ID, timestamp, action type, affected entity, record ID, old/new values, and reason—whenever ticket prices/capacities, event/session schedules, speaker assignments, registration cancellations, check-in statuses, payment corrections, or administrative overrides occur. | High | `AUDIT_LOG`, `USER`, `EVENT`, `TICKET_TIER`, `SESSION`, `REGISTRATION`, `PAYMENT`, `SESSION_ROSTER` | System, Admin |

---

## 6. Transaction Flows / Use Cases

### Use Case UC-01: Attendee Event Registration and Atomic Payment Recording

| Item | Description |
| :--- | :--- |
| **Goal** | Register an eligible user for one seat in a specific event's ticket tier, lock and consume one unit of available capacity, preserve the accepted ticket price, and atomically record the corresponding payment. |
| **Primary actor** | Attendee (or an Organizer/Speaker registering as an attendee for an event they do not organize). |
| **Trigger** | The actor submits a registration request specifying `EventID`, `TicketID`, and an external/fictional payment reference (`InvoiceNumber`) and `AmountPaid`. |
| **Preconditions** | 1. The actor has an active `USER` account and is not the assigned `OrganizerID` of the target `EVENT`.<br>2. The target `EVENT` and `TICKET_TIER` exist.<br>3. The actor does not currently hold a `Confirmed` registration for `EventID`. |
| **Related requirements** | FR-02, FR-06, FR-07, FR-08, FR-09, FR-10, FR-18 |
| **Transaction boundary** | Steps 2 through 8 execute within a single atomic database transaction (`START TRANSACTION` ... `COMMIT` / `ROLLBACK`) using concurrency-safe locking on the target `TICKET_TIER` record. |
| **Main success flow** | 1. Actor initiates a registration request with `AttendeeID`, `EventID`, `TicketID`, `AmountPaid`, and `InvoiceNumber`.<br>2. System begins a database transaction and locks the target `TICKET_TIER` row for validation.<br>3. System verifies that `TICKET_TIER.EventID` matches the requested `EventID`, that `AttendeeID != EVENT.OrganizerID`, and that no `Confirmed` registration exists for `(AttendeeID, EventID)`.<br>4. System calculates remaining availability as `TicketTier.Capacity - COUNT(Confirmed registrations for TicketID)` (`TicketTier.Capacity` stores the configured maximum limit; only `Confirmed` registrations consume capacity). System verifies remaining availability is $\ge 1$.<br>5. System captures `AcceptedPrice = TicketTier.Price` and validates that the supplied `AmountPaid == AcceptedPrice` and `InvoiceNumber` is unique.<br>6. System inserts a new `REGISTRATION` record with `Status = 'Confirmed'`, `RegistrationDate = CURRENT_DATE`, and `AcceptedPrice = TicketTier.Price`.<br>7. System inserts the corresponding 1:1 `PAYMENT` record linked to the new `RegistrationID` with `AmountPaid`, `PaymentDate = CURRENT_DATE`, and `InvoiceNumber` (even if `AcceptedPrice = 0.00` for a free tier).<br>8. System writes an audit entry in `AUDIT_LOG` and commits the transaction. |
| **Alternate / exception flows** | * **E1 (Cross-Event Ticket Mismatch):** `TicketID` does not belong to `EventID`. System rejects the request and rolls back.<br>* **E2 (Duplicate Active Registration):** Actor already has a `Confirmed` registration for `EventID`. System rejects the duplicate request and rolls back. (If the actor's only prior registration for `EventID` has `Status = 'Cancelled'`, the new registration is permitted).<br>* **E3 (Ticket Tier Full):** Calculated remaining availability is 0 (even when configured `TicketTier.Capacity > 0`). System rejects the registration and rolls back.<br>* **E4 (Concurrent Last-Seat Contention):** Two actors concurrently request the last remaining seat (`Remaining = 1`). The first transaction to acquire the lock commits and consumes the final seat; the second transaction observes `Remaining = 0` upon lock acquisition, is rejected, and rolls back without exceeding `TicketTier.Capacity`.<br>* **E5 (Payment Validation or Insert Failure):** `AmountPaid != AcceptedPrice`, `InvoiceNumber` is duplicated, or payment insertion fails after step 6. The entire transaction rolls back so no orphan or unpaid `REGISTRATION` record persists.<br>* **E6 (Self-Registration by Event Organizer):** `AttendeeID == EVENT.OrganizerID`. System rejects the request and rolls back. |
| **Postconditions** | One valid `Confirmed` registration and its required 1:1 payment record are committed with `AcceptedPrice` preserved. Available capacity is reduced by one, and no partial registration or payment records remain if any step fails. |

---

### Use Case UC-02: Event Session Scheduling and Speaker Assignment

| Item | Description |
| :--- | :--- |
| **Goal** | Schedule a session within an event's date boundaries and assign an eligible speaker without creating speaker time conflicts. |
| **Primary actor** | Organizer |
| **Trigger** | The Organizer submits a request to create or update a session for an event. |
| **Preconditions** | 1. The actor is authenticated as an Organizer and is the assigned `OrganizerID` for the target `EVENT`.<br>2. The target `EVENT` (and its associated `VENUE`) exists.<br>3. The target Speaker (`SpeakerID`) exists in `USER` and holds Speaker eligibility. |
| **Related requirements** | FR-02, FR-12, FR-13, FR-14, FR-18 |
| **Main success flow** | 1. Organizer submits `EventID`, `SpeakerID`, `SessionTitle`, `StartDateTime`, `EndDateTime`, `SessionCapacity`, and `RoomNumber` (informational label).<br>2. System verifies that the actor is the owning `OrganizerID` for `EventID` and that `SpeakerID` is an eligible speaker.<br>3. System validates that `StartDateTime < EndDateTime` and that the date range of `[StartDateTime, EndDateTime]` falls completely within `[Event.StartDate, Event.EndDate]`.<br>4. System validates that `SessionCapacity > 0` and `SessionCapacity <= Venue.MaxCapacity`.<br>5. System queries existing `SESSION` records for `SpeakerID` across all events to verify no overlapping interval exists (overlap occurs when `Existing.StartDateTime < New.EndDateTime` AND `Existing.EndDateTime > New.StartDateTime`).<br>6. System inserts the `SESSION` record and writes a creation/assignment entry to `AUDIT_LOG`, then commits the transaction. |
| **Alternate / exception flows** | * **E1 (Unauthorized Organizer):** Actor is not the `OrganizerID` of `EventID`. System rejects the action.<br>* **E2 (Invalid Time Interval or Outside Event Dates):** `StartDateTime >= EndDateTime`, or session timestamps fall before `Event.StartDate` or after `Event.EndDate`. System rejects the session.<br>* **E3 (Invalid Speaker or Speaker Double-Booked):** `SpeakerID` does not exist, lacks speaker capability, or has an overlapping session during `[StartDateTime, EndDateTime]`. System rejects the assignment and rolls back.<br>* **E4 (Invalid Session Capacity):** `SessionCapacity <= 0` or `SessionCapacity > Venue.MaxCapacity` (or, on update, `SessionCapacity` is less than current enrolled roster count). System rejects the operation. |
| **Postconditions** | A valid `SESSION` record linked to `EventID` and `SpeakerID` is committed with verified start/end timestamps and capacity, and an audit log record is created. |

---

### Use Case UC-03: Session Roster Enrollment and Organizer Attendance Check-In

| Item | Description |
| :--- | :--- |
| **Goal** | Allow a registered attendee to reserve a seat on an eligible session roster (`'Enrolled'`), and allow the owning Event Organizer to record actual session attendance (`'CheckedIn'` or `'NoShow'`). |
| **Primary actor** | Part A: Attendee (Roster Enrollment); Part B: Organizer (Attendance Check-In). |
| **Trigger** | Part A: Attendee requests to join a session roster using their `RegistrationID` and target `SessionID`.<br>Part B: Owning Organizer submits an attendance check-in update for `(RegistrationID, SessionID)`. |
| **Preconditions** | 1. Both the `REGISTRATION` and `SESSION` records exist.<br>2. For Part A, the actor owns the `REGISTRATION` (`Registration.AttendeeID = ActorUserID`).<br>3. For Part B, the actor is the owning `OrganizerID` of `Session.EventID` (or an `Admin`). |
| **Related requirements** | FR-02, FR-15, FR-16, FR-18 |
| **Main success flow** | **Part A — Attendee Roster Enrollment:**<br>1. Attendee submits `(RegistrationID, SessionID)` to join a session roster.<br>2. System begins a transaction and locks the target `SESSION` row.<br>3. System verifies that `Registration.AttendeeID` matches the actor, `Registration.Status == 'Confirmed'`, and `Registration.EventID == Session.EventID` (same-event rule).<br>4. System verifies that `(RegistrationID, SessionID)` does not already exist in `SESSION_ROSTER` and that the attendee is not enrolled in another session with an overlapping `[StartDateTime, EndDateTime]`.<br>5. System calculates current roster count for `SessionID` (across `Confirmed` registrations) and verifies it is strictly less than `Session.SessionCapacity`.<br>6. System inserts `(RegistrationID, SessionID, CheckInStatus = 'Enrolled')` into `SESSION_ROSTER` and commits.<br><br>**Part B — Organizer Attendance Check-In:**<br>7. At the session, the owning Organizer selects `(RegistrationID, SessionID)` on the session roster and submits `CheckInStatus = 'CheckedIn'` (or `'NoShow'`).<br>8. System verifies the actor is the owning `OrganizerID` for `Session.EventID` (or `Admin`).<br>9. System updates `SESSION_ROSTER.CheckInStatus` to `'CheckedIn'` (recording actual attendance), writes an entry to `AUDIT_LOG`, and commits. |
| **Alternate / exception flows** | * **E1 (Cross-Event Roster Mismatch):** `Registration.EventID != Session.EventID`. System rejects the roster enrollment.<br>* **E2 (Cancelled Registration):** `Registration.Status == 'Cancelled'`. System rejects the roster enrollment.<br>* **E3 (Duplicate Roster Entry or Time Conflict):** `(RegistrationID, SessionID)` already exists or overlaps another enrolled session for that registration. System rejects the enrollment.<br>* **E4 (Session Full):** Current enrolled count equals `Session.SessionCapacity`. Concurrent requests for the final seat are serialized so at most one succeeds; excess requests are rejected and rolled back.<br>* **E5 (Unauthorized Check-In Attempt by Attendee or Other User):** An Attendee or non-owning Organizer attempts to update `CheckInStatus` to `'CheckedIn'`. System denies the operation. |
| **Postconditions** | Part A: A `SESSION_ROSTER` entry exists with `CheckInStatus = 'Enrolled'`, reserving one session seat.<br>Part B: `SESSION_ROSTER.CheckInStatus` reflects verified attendance (`'CheckedIn'` or `'NoShow'`), and an audit entry is recorded. |

---

## 7. Data Requirements

The data requirements below define the business information the system must maintain independently of the preliminary diagram. While the preliminary ERD established the core 9-table structure, these requirements refine the necessary attributes (such as `AcceptedPrice` on `REGISTRATION`, `StartDateTime`/`EndDateTime` and `SessionCapacity` on `SESSION`, and full before/after change tracking on `AUDIT_LOG`) that the final ERD and schema build file will implement.

| Data Subject | Information to Store | Example Identifier | Likely Relationship(s) |
| :--- | :--- | :--- | :--- |
| **USER** | First name, last name, unique email address, account active status, and base role (`Admin`, `Organizer`, `Speaker`, `Attendee`) | `UserID` | Organizes `EVENT` (1:N); Speaks at `SESSION` (1:N); Registers via `REGISTRATION` (1:N); Performs actions recorded in `AUDIT_LOG` (1:N) |
| **VENUE** | Venue name, street/city/state address, and positive maximum building capacity (`MaxCapacity`) | `VenueID` | Hosts `EVENT` (1:N) |
| **EVENT** | Event name, start date, end date, owning organizer reference, and assigned venue reference | `EventID` | Belongs to one `VENUE` (N:1) and one owning `USER` Organizer (N:1); Offers `TICKET_TIER` (1:N); Contains `SESSION` (1:N); Referenced by `REGISTRATION` (1:N) |
| **TICKET_TIER** | Tier name (e.g., General, VIP, Student), current listed unit price (`Price >= 0.00`), configured maximum seat capacity (`Capacity > 0`), and parent event reference | `TicketID` | Belongs to one `EVENT` (N:1); Selected by `REGISTRATION` (1:N) |
| **SESSION** | Session title, `StartDateTime`, `EndDateTime`, `SessionCapacity`, informational `RoomNumber` label (room booking/inventory is outside scope), parent event reference, and assigned speaker reference | `SessionID` | Dependent on one parent `EVENT` (N:1); Assigned to one Speaker `USER` (N:1); Linked to `REGISTRATION` via `SESSION_ROSTER` (M:N) |
| **REGISTRATION** | Registration date, status (`Confirmed`, `Cancelled`), historical `AcceptedPrice` captured at registration time, attendee user reference, event reference, and selected ticket tier reference (each registration represents 1 attendee and 1 ticket for 1 event) | `RegistrationID` | Belongs to one Attendee `USER` (N:1), one `EVENT` (N:1), and one `TICKET_TIER` (N:1); Associated with exactly one `PAYMENT` (1:1); Enrolls in `SESSION` via `SESSION_ROSTER` (M:N) |
| **PAYMENT** | Amount paid (`AmountPaid == Registration.AcceptedPrice`), payment date, unique fictional/external invoice reference (`InvoiceNumber`), and registration reference | `PaymentID` | Linked 1:1 to `REGISTRATION` (unique `RegistrationID` foreign key) |
| **SESSION_ROSTER** | Composite reference to registration and session, enrollment timestamp, and `CheckInStatus` (`'Enrolled'`, `'CheckedIn'`, `'NoShow'`) distinguishing roster enrollment from verified attendance | `(RegistrationID, SessionID)` | Associative entity resolving the M:N relationship between `REGISTRATION` and `SESSION` |
| **AUDIT_LOG** | Actor user reference (`ActorUserID`), actor role, action timestamp (`ActionTimestamp`), operation type (`ActionType`), target entity name (`EntityName`), target record identifier (`RecordID`), old value summary (`OldValue`), new value summary (`NewValue`), and reason (`Reason`) | `LogID` | References the acting `USER` (N:1); immutable append-only log tracking sensitive system and administrative changes |

---

## 8. Business Rules and Validation Rules

| ID | Business Rule | Why It Matters | Possible Enforcement Approach |
| :--- | :--- | :--- | :--- |
| **BR-01** | Every `EVENT` must belong to exactly one `VENUE` and have exactly one owning Organizer (`USER`), while a `VENUE` or Organizer may be associated with zero or many events. | Establishes required event ownership and physical location capacity context. | `FOREIGN KEY (VenueID) NOT NULL`, `FOREIGN KEY (OrganizerID) NOT NULL`, plus role validation procedure/trigger. |
| **BR-02** | Each `REGISTRATION` represents exactly one attendee and one ticket for one event. An attendee may hold at most one active (`Confirmed`) registration per event; if a prior registration was `Cancelled`, the attendee may submit a new registration. | Simplifies seat counting and prevents duplicate active registrations by the same user for the same event. | Controlled registration procedure/trigger checking active (`Confirmed`) registrations for `(AttendeeID, EventID)` (or functional unique index). |
| **BR-03** | A registration's selected `TicketID` must belong to the same `EventID` specified on the registration. | Prevents cross-event data corruption where an attendee registers for Event A using a ticket tier from Event B. | Composite `FOREIGN KEY (EventID, TicketID) REFERENCES TICKET_TIER(EventID, TicketID)` and validation in registration procedure/trigger. |
| **BR-04** | A `SESSION_ROSTER` entry may be created only when the referenced `REGISTRATION` and `SESSION` belong to the exact same `EventID`, and the registration status is `Confirmed`. | Prevents an attendee registered for Event A from joining a session belonging to Event B, or a cancelled registration from holding a session seat. | Validation in controlled enrollment procedure and `BEFORE INSERT` trigger on `SESSION_ROSTER`. |
| **BR-05** | Only `Confirmed` registrations consume ticket-tier capacity; cancelling a registration (`Status = 'Cancelled'`) releases one seat of ticket-tier capacity and removes/releases associated session roster seats. Concurrent registration attempts shall not cause the number of capacity-consuming (`Confirmed`) registrations to exceed `TicketTier.Capacity`. | Prevents overbooking under both sequential and simultaneous last-seat registration requests. | Controlled registration transaction with concurrency-safe capacity validation; implementation details documented in the TDD. |
| **BR-06** | The sum of `Capacity` across all ticket tiers for an event must not exceed the `MaxCapacity` of the event's assigned `VENUE`. Similarly, each session's `SessionCapacity` must be $> 0$ and $\le 	ext{Venue.MaxCapacity}$, and enrolled roster entries cannot exceed `SessionCapacity`. | Connects ticket and session limits to the physical limits of the hosting venue. | Controlled transaction and `BEFORE INSERT/UPDATE` triggers on `TICKET_TIER`, `SESSION`, and `SESSION_ROSTER` plus `CHECK (Capacity > 0)`. |
| **BR-07** | Reducing `Venue.MaxCapacity` below any hosted event's total ticket-tier capacity, reducing `TicketTier.Capacity` below its current count of `Confirmed` registrations, or reducing `Session.SessionCapacity` below its current enrolled roster count is prohibited. | Prevents retroactive capacity reductions that would invalidate already-confirmed registrations or session enrollments. | `BEFORE UPDATE` triggers / controlled update procedures on `VENUE`, `TICKET_TIER`, and `SESSION`. |
| **BR-08** | Every `SESSION` must have `StartDateTime < EndDateTime`, and both timestamps must fall within the parent event's `StartDate` and `EndDate`. | Prevents negative/zero-duration sessions and sessions scheduled outside the event's operating dates. | `CHECK (StartDateTime < EndDateTime)` and `BEFORE INSERT/UPDATE` trigger verifying parent `EVENT` dates. |
| **BR-09** | Each `SESSION` is assigned to exactly one Speaker (`SpeakerID`), and a speaker cannot be assigned to two sessions whose `[StartDateTime, EndDateTime]` intervals overlap across any event. | Prevents speaker double-booking. | `FOREIGN KEY (SpeakerID) NOT NULL` and `BEFORE INSERT/UPDATE` conflict check in session scheduling procedure/trigger. |
| **BR-10** | Registration creation and payment recording must execute atomically in a single 1:1 transaction: `Registration.AcceptedPrice` captures `TicketTier.Price` at registration time, `Payment.AmountPaid` must equal `Registration.AcceptedPrice` (`>= 0.00`), `Payment.InvoiceNumber` must be unique, and both records must succeed together or roll back completely. | Ensures historical price preservation, prevents unpaid active registrations, and guarantees 1:1 payment traceability. | Database transaction (`COMMIT`/`ROLLBACK`), `UNIQUE (RegistrationID)` and `UNIQUE (InvoiceNumber)` on `PAYMENT`, and `CHECK (AmountPaid >= 0)`. |
| **BR-11** | A `REGISTRATION` may appear at most once on a given `SESSION`'s roster, and an attendee cannot enroll in two overlapping sessions. Roster insertion sets `CheckInStatus = 'Enrolled'`; only the owning Event Organizer or an Admin may update `CheckInStatus` to `'CheckedIn'` or `'NoShow'`. | Prevents duplicate seats for one person in the same session and separates seat reservation from verified physical attendance. | Composite `PRIMARY KEY (RegistrationID, SessionID)`, overlap check on enrollment, and role/ownership check on `SESSION_ROSTER` update. |
| **BR-12** | All sensitive changes and defined administrative overrides must be logged in `AUDIT_LOG`, and `AUDIT_LOG` rows must be immutable (no updates or deletions permitted by any role). | Guarantees tamper-evident accountability. | `AFTER` triggers / controlled procedures writing to `AUDIT_LOG`, and `BEFORE UPDATE/DELETE` triggers on `AUDIT_LOG` rejecting modifications. |

---

## 9. Security, Entitlements, and Auditing

### Role and Entitlement Requirements

| ID | Security / Entitlement Requirement | Role(s) Affected | Protected Action or Data |
| :--- | :--- | :--- | :--- |
| **SEC-01** | The system shall allow any authenticated user to view public `EVENT`, `VENUE`, `TICKET_TIER`, and `SESSION` schedule details, but shall restrict creation and modification of `EVENT`, `TICKET_TIER`, and `SESSION` records strictly to the owning Organizer (`EVENT.OrganizerID = CurrentUserID`). | Organizer, Attendee, Speaker, Admin | `EVENT`, `TICKET_TIER`, `SESSION` |
| **SEC-02** | The system shall restrict Attendees to viewing, creating, and cancelling only their own `REGISTRATION` and `SESSION_ROSTER` records and viewing only their own `PAYMENT` records (`Registration.AttendeeID = CurrentUserID`), preventing any Attendee from viewing or modifying another attendee's registrations, payments, or contact information. | Attendee | `REGISTRATION`, `PAYMENT`, `SESSION_ROSTER`, `USER` |
| **SEC-03** | The system shall prohibit an Event's owning Organizer from registering as an attendee for their own event, while permitting them to register as an attendee for events owned by other organizers. | Organizer | `REGISTRATION` |
| **SEC-04** | The system shall allow an Event's owning Organizer to view attendee contact details (`FirstName`, `LastName`, `Email`), registration statuses, and payment summaries strictly for registrations belonging to their own events (`EVENT.OrganizerID = CurrentUserID`). | Organizer | `USER`, `REGISTRATION`, `PAYMENT` |
| **SEC-05** | The system shall allow a Speaker to view session details and the session roster (`FirstName`, `LastName`, `CheckInStatus`) strictly for sessions where `SESSION.SpeakerID = CurrentUserID`, and shall prevent Speakers from modifying session details, ticket prices, or other users' check-in statuses. | Speaker | `SESSION`, `SESSION_ROSTER`, `USER` |
| **SEC-06** | The system shall allow Attendees to insert (join) or delete (leave) their own `SESSION_ROSTER` entry with `CheckInStatus = 'Enrolled'`, but shall allow **only** the owning Event Organizer or an Administrator to update `CheckInStatus` to `'CheckedIn'` or `'NoShow'`. | Attendee, Organizer, Admin | `SESSION_ROSTER.CheckInStatus` |
| **SEC-07** | The system shall restrict the Event Revenue Summary Report (`RQ-01`) to the owning Organizer of the selected event and to Administrators. | Organizer, Admin | `RQ-01`, `PAYMENT`, `REGISTRATION` |
| **SEC-08** | The system shall restrict read access on `AUDIT_LOG` strictly to Administrators (attendees may view their own `PAYMENT` and `REGISTRATION` history, not `AUDIT_LOG`), and shall prohibit all roles—including Administrators—from updating or deleting existing `AUDIT_LOG` records. | Admin, All Roles | `AUDIT_LOG` |
| **SEC-09** | The system shall restrict Administrative Overrides to Administrators only, limited specifically to: (a) cancelling a registration on behalf of a user/event with a required reason, (b) recording a documented payment reference/amount correction, and (c) reassigning `EVENT.OrganizerID` when an organizer account is deactivated. Administrators shall not bypass capacity limits, cross-event consistency rules, or speaker conflict checks. | Admin | `REGISTRATION`, `PAYMENT`, `EVENT`, `AUDIT_LOG` |

### Audit Specification
Every auditable event writes an immutable row to `AUDIT_LOG` containing:
* **Actor:** `ActorUserID` and active role context
* **Timestamp:** `ActionTimestamp` (exact date and time of the operation)
* **Action:** `ActionType` (`INSERT`, `UPDATE`, `DELETE`, `STATUS_CHANGE`, `ADMIN_OVERRIDE`)
* **Target:** `EntityName` and `RecordID` (primary key or composite key of the affected record)
* **Values:** `OldValue` and `NewValue` (structured summary of changed fields, such as old/new `Price`, `Capacity`, `Status`, `SpeakerID`, or `CheckInStatus`)
* **Reason:** Mandatory textual explanation for administrative overrides, cancellations, and price/capacity modifications

**Audited Operations:**
1. Creation or modification of `TICKET_TIER.Price` or `TICKET_TIER.Capacity`
2. Changes to `EVENT` dates, venue assignment, or `OrganizerID`
3. Creation, rescheduling (`StartDateTime`/`EndDateTime`), or speaker reassignment (`SpeakerID`) of a `SESSION`
4. Registration creation and status transitions (`Confirmed` to `Cancelled`)
5. Session attendance check-in status changes (`'Enrolled'` to `'CheckedIn'` or `'NoShow'`)
6. Payment recording and any administrative override operation

---

## 10. Reports and Queries

| ID | Report / Query Name | Business Question | Required Result & Filter / Access Specification | Likely SQL Features |
| :--- | :--- | :--- | :--- | :--- |
| **RQ-01** | **Event Revenue and Registration Summary Report** | How much gross recorded payment revenue and how many confirmed vs. cancelled registrations has each event generated within a selected date range or for a specific event? | **Filters:** Optional `EventID` or `Event.StartDate` range.<br>**Included Statuses:** Aggregates count of `Confirmed` registrations, count of `Cancelled` registrations, and gross recorded revenue (`SUM(Payment.AmountPaid)` for `Confirmed` registrations; represents gross recorded payments, not net profit).<br>**Zero-Payment Behavior:** Events with zero registrations or `$0.00` payments must appear with `0` counts and `0.00` total revenue.<br>**Sorting:** `Event.StartDate DESC, Event.EventID ASC`.<br>**Access:** Owning Organizer (for own events only) and Admin (all events). | `LEFT JOIN` (`EVENT`, `REGISTRATION`, `PAYMENT`), `GROUP BY`, `COUNT`, `SUM`, `COALESCE`, `CASE WHEN` |
| **RQ-02** | **Session Roster and Attendance Detail Report** | Which attendees are enrolled in a selected session, and what is their current attendance check-in status? | **Filters:** Required `SessionID`; optional `CheckInStatus` filter (`All`, `'Enrolled'`, `'CheckedIn'`, `'NoShow'`).<br>**Columns:** `SessionID`, `SessionTitle`, `StartDateTime`, `EndDateTime`, `RegistrationID`, `UserID`, `FirstName`, `LastName`, `Email`, `TierName`, `CheckInStatus`. (Only `Confirmed` registrations are included on active rosters).<br>**Sorting:** `USER.LastName ASC, USER.FirstName ASC, USER.UserID ASC`.<br>**Access:** Owning Event Organizer, assigned Session Speaker, and Admin. | Multi-table `INNER JOIN` (`SESSION`, `SESSION_ROSTER`, `REGISTRATION`, `USER`, `TICKET_TIER`), `WHERE`, `ORDER BY` |
| **RQ-03** | **Ticket Tier and Session Capacity Exception / Utilization Report** | Which ticket tiers or sessions for an event are at or near capacity (e.g., $\ge 90\%$ full or $0$ remaining seats), and how many seats remain available? | **Filters:** Optional `EventID` and capacity threshold percentage.<br>**Columns:** `EventName`, resource type (`TicketTier` or `Session`), resource name, configured `Capacity`, active `Confirmed` count, calculated `RemainingSeats` (`Capacity - ActiveCount`), and utilization percentage.<br>**Zero-Registration Behavior:** Tiers or sessions with zero registrations display `0` active count and full capacity remaining.<br>**Access:** Owning Event Organizer and Admin. | `LEFT JOIN`, subquery/CTE or `UNION ALL`, `GROUP BY`, `COUNT`, `HAVING` |
| **RQ-04** | **Speaker Schedule and Assignment Report** | What sessions is each speaker scheduled to lead across upcoming events, including venue, room label, time interval, and current enrolled roster count? | **Filters:** Optional `SpeakerID` or date range.<br>**Columns:** `SpeakerID`, `FirstName`, `LastName`, `EventName`, `VenueName`, `SessionID`, `SessionTitle`, `RoomNumber`, `StartDateTime`, `EndDateTime`, `SessionCapacity`, `EnrolledCount`.<br>**Sorting:** `StartDateTime ASC, SpeakerID ASC`.<br>**Access:** Assigned Speaker (own schedule), Event Organizer (for own event sessions), and Admin. | `INNER JOIN` (`USER`, `SESSION`, `EVENT`, `VENUE`), `LEFT JOIN` (`SESSION_ROSTER`), `GROUP BY`, `ORDER BY` |

---

## 11. Assumptions and Constraints

### Assumptions
* **Single-Seat Registration:** Each `REGISTRATION` record represents exactly one attendee and one ticket for one event. Group or multi-seat cart purchases are outside scope.
* **Atomic Registration and Payment:** A registration and its 1:1 payment record are always created together in a single atomic transaction. Free ticket tiers (`Price = 0.00`) are permitted and generate a `$0.00` payment record with a unique `InvoiceNumber` so that every `Confirmed` registration has a corresponding payment record.
* **Stored Limit vs. Calculated Availability:** `Venue.MaxCapacity`, `TicketTier.Capacity`, and `Session.SessionCapacity` store the configured maximum limits; remaining seat availability is calculated dynamically from active `Confirmed` registrations/roster entries inside concurrency-safe transactions.
* **Informational Room Labels:** `Session.RoomNumber` is stored as a descriptive text label only; separate room entities and room-level capacity enforcement are outside scope.
* **Single Speaker per Session:** Each session has exactly one assigned primary speaker (`SpeakerID`).
* **Re-Registration after Cancellation:** An attendee may have at most one `Confirmed` registration per event, but if an attendee's registration is changed to `Cancelled`, that attendee is permitted to submit a new registration for the event later if capacity remains.

### Constraints
* **DBMS Platform:** The database will be implemented in MySQL (InnoDB engine to support ACID transactions, row-level locking, and foreign keys) and normalized to Third Normal Form (3NF).
* **Fictional Data & Payment Boundary:** Only fictional user and payment data will be stored. Live payment card numbers (PAN, CVV) are strictly prohibited.
* **Repository Deliverables:** All documentation in Markdown, editable `.drawio` files, exported `.svg`/`.png` diagrams, schema build scripts, and test scripts will be maintained in the course GitHub repository.

---

## 12. Acceptance Criteria and Traceability

Each acceptance test specifies the required setup, action executed, expected result, and demonstration evidence.

| Test ID | Related Req / Rule | Test Scenario | Setup | Action | Expected Result | Evidence to Show |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **AC-01** | FR-06, FR-07, FR-08, BR-10, UC-01 | Valid atomic registration and payment recording | Active `EVENT` (Event 1), `TICKET_TIER` (Tier 10, `Price = 50.00`, `Capacity = 100`, 0 existing registrations), and eligible `Attendee` (User 5). | Execute registration transaction for User 5, Event 1, Tier 10 with `AmountPaid = 50.00` and unique `InvoiceNumber = 'INV-1001'`. | Transaction commits; 1 `Confirmed` row in `REGISTRATION` with `AcceptedPrice = 50.00`, 1 linked row in `PAYMENT`, 1 row in `AUDIT_LOG`, and calculated remaining capacity is 99. | SQL transaction call and `SELECT` output from `REGISTRATION`, `PAYMENT`, `AUDIT_LOG`, and capacity view. |
| **AC-02** | FR-01, FR-04, FR-06, FR-13, BR-01 | Rejection of invalid foreign key references | Database populated with baseline users, events, and venues. | Attempt to insert a `REGISTRATION` referencing a nonexistent `EventID`, `TicketID`, or `AttendeeID`, and a `SESSION` referencing a nonexistent `SpeakerID`. | All invalid inserts are rejected by foreign key or validation checks; zero rows are added. | SQL error output and row count verification. |
| **AC-03** | FR-09, BR-03, UC-01 (E1) | Rejection of ticket tier from the wrong event (cross-event registration mismatch) | Event 1 offers Ticket Tier 10; Event 2 offers Ticket Tier 20. | Attendee submits a registration specifying `EventID = 1` and `TicketID = 20`. | System detects the cross-event mismatch, rejects the registration, and rolls back the transaction. | Procedure/trigger error message and `SELECT` confirming no registration or payment was created. |
| **AC-04** | FR-15, BR-04, UC-03 (E1) | Rejection of joining a session from another event (cross-event roster mismatch) | User 5 holds a `Confirmed` registration (`RegistrationID = 501`) for Event 1; Session 201 belongs to Event 2. | User 5 attempts to insert `(RegistrationID = 501, SessionID = 201)` into `SESSION_ROSTER`. | System rejects the roster entry because `Registration.EventID != Session.EventID`. | SQL error output and `SELECT` on `SESSION_ROSTER` showing 0 rows added. |
| **AC-05** | FR-09, FR-11, BR-02, UC-01 (E2) | Rejection of duplicate active event registration & allowed re-registration after cancellation | User 5 already holds a `Confirmed` registration for Event 1. | 1. User 5 submits a second registration request for Event 1.<br>2. Cancel User 5's first registration (`Status = 'Cancelled'`), then submit a new registration request for Event 1. | 1. Second active registration is rejected.<br>2. After cancellation, the new registration succeeds and is marked `Confirmed`. | SQL error on duplicate active attempt; `SELECT` showing 1 `Cancelled` and 1 new `Confirmed` registration after step 2. |
| **AC-06** | FR-15, BR-11, UC-03 (E3) | Rejection of duplicate session roster entry | `RegistrationID = 501` is already enrolled in `SessionID = 101` (`CheckInStatus = 'Enrolled'`). | Attempt to insert `(RegistrationID = 501, SessionID = 101)` a second time. | System rejects the duplicate composite key / enrollment request. | Primary key / procedure error output and `SESSION_ROSTER` query. |
| **AC-07** | FR-10, BR-05, UC-01 (E3) | Rejection when a ticket tier with nonzero configured capacity is full | Ticket Tier 12 has configured `Capacity = 2` and already has 2 `Confirmed` registrations. | A third attendee submits a registration request for Ticket Tier 12. | System calculates remaining availability as `2 - 2 = 0`, rejects the registration, and creates no payment record. | Error output and `SELECT COUNT(*)` showing `Confirmed` count remains 2. |
| **AC-08** | FR-10, BR-05, UC-01 (E4) | Concurrency test: two requests competing for the last available place | Ticket Tier 15 has `Capacity = 5` and currently has 4 `Confirmed` registrations (1 seat left). Open two concurrent database sessions (Session A and Session B). | Both Session A (User 8) and Session B (User 9) concurrently execute the registration transaction for Ticket Tier 15. | Locking serializes validation: exactly one session commits (`Confirmed` count becomes 5), and the other session is rejected and rolled back. Total `Confirmed` registrations never exceed 5. | Dual-session execution log and final `SELECT` on `REGISTRATION` and `PAYMENT` showing exactly 5 `Confirmed` rows. |
| **AC-09** | FR-06, FR-07, BR-10, UC-01 (E5) | Payment validation failure and full atomic transaction rollback | Ticket Tier 10 has `Price = 50.00` and available capacity. | Execute registration transaction where step 6 creates the `REGISTRATION` row, but step 7 fails due to invalid payment amount (`AmountPaid = 30.00`) or duplicate `InvoiceNumber` (or forced interruption). | Transaction rolls back completely; the pending `REGISTRATION` row is removed and available capacity is unchanged. | Before/after `SELECT` queries on `REGISTRATION` and `PAYMENT` proving rollback. |
| **AC-10** | FR-14, BR-09, UC-02 (E3) | Rejection of speaker scheduling overlap | Speaker (User 3) is assigned to Session 101 from `2026-11-10 10:00` to `2026-11-10 11:30`. | Organizer attempts to create Session 102 assigning User 3 from `2026-11-10 11:00` to `2026-11-10 12:00`. | System detects the overlapping interval for User 3 and rejects Session 102. | Trigger/procedure error message and `SELECT` on `SESSION` for User 3. |
| **AC-11** | FR-13, BR-08, UC-02 (E2) | Rejection of session outside event dates or with invalid start/end order | Event 1 runs from `2026-11-10` to `2026-11-12`. | Organizer attempts to schedule a session on `2026-11-15`, and another session where `StartDateTime >= EndDateTime`. | Both session creation attempts are rejected. | Constraint/trigger error output and `SELECT` on `SESSION`. |
| **AC-12** | FR-02, SEC-01, SEC-02, SEC-03, SEC-04 | Enforcement of role and ownership restrictions across attendees and organizers | Attendee A (User 5), Attendee B (User 6), Organizer A (User 2, owns Event 1), Organizer B (User 4, owns Event 2). | 1. Attendee A attempts to view/cancel Attendee B's registration/payment.<br>2. Organizer A attempts to update Event 2.<br>3. Organizer A attempts to register as an attendee for Event 1. | All three unauthorized actions are denied by role/ownership enforcement. | Controlled access query/procedure results demonstrating permission denial. |
| **AC-13** | FR-08, BR-10 | Historical ticket price preservation after organizer updates tier price | User 5 registers for Ticket Tier 10 when `TicketTier.Price = 50.00` (`Registration.AcceptedPrice = 50.00`, `Payment.AmountPaid = 50.00`). | Owning Organizer updates `TicketTier.Price` for Tier 10 to `75.00`, and User 6 subsequently registers for Tier 10. | User 5's existing registration still shows `AcceptedPrice = 50.00` and `AmountPaid = 50.00`; User 6's new registration records `AcceptedPrice = 75.00` and `AmountPaid = 75.00`. | `SELECT` comparing User 5 and User 6 rows in `REGISTRATION` and `PAYMENT` alongside `TICKET_TIER`. |
| **AC-14** | FR-16, BR-11, SEC-06, UC-03 | Session check-in permission enforcement | User 5 is enrolled in Session 101 (`CheckInStatus = 'Enrolled'`). | 1. User 5 (Attendee) or Session Speaker attempts to update `CheckInStatus` to `'CheckedIn'`.<br>2. Owning Organizer of Event 1 updates `CheckInStatus` to `'CheckedIn'`. | 1. Attendee and Speaker attempts are rejected.<br>2. Owning Organizer update succeeds and logs an audit entry. | Error output for step 1; updated `SESSION_ROSTER` and `AUDIT_LOG` rows for step 2. |
| **AC-15** | FR-17, SEC-07, RQ-01, RQ-02 | Exact report totals and zero-result behavior | Event 1 has two `Confirmed` payments (`$50.00` and `$75.00`) and one `Cancelled` registration (`$50.00`). Event 2 is a newly created event with 0 registrations and 0 payments. | Execute `RQ-01` (Event Revenue Summary) across both events, and `RQ-02` for Session 101. | `RQ-01` returns Event 1 with `Confirmed = 2`, `Cancelled = 1`, `GrossRevenue = 125.00`, and returns Event 2 with `Confirmed = 0`, `Cancelled = 0`, `GrossRevenue = 0.00`. `RQ-02` returns sorted roster rows with check-in statuses. | SQL query execution output matching expected calculations. |
| **AC-16** | FR-18, BR-12, SEC-08, SEC-09 | Audit log generation and immutability protection | `AUDIT_LOG` contains entries generated from price changes and an Admin override cancellation. | An Administrator (or any user) attempts to execute `UPDATE` or `DELETE` on an existing row in `AUDIT_LOG`. | The modification or deletion attempt on `AUDIT_LOG` is blocked and rejected; all historical audit records remain intact. | Trigger/privilege error output and `SELECT` on `AUDIT_LOG` confirming record integrity. |

---

### Traceability Matrix

| Requirement / Query | Related Entity / Table Candidates | Rule / Relationship Implied | Planned Implementation Evidence |
| :--- | :--- | :--- | :--- |
| **FR-01, FR-02, SEC-01–SEC-09** | `USER`, `EVENT`, `SESSION`, `REGISTRATION` | PK `UserID`, ` UNIQUE (Email)`, base role + event/session ownership checks | ERD, `CREATE TABLE USER`, role/ownership procedures & access tests (`AC-12`, `AC-14`) |
| **FR-03, FR-04, FR-05, FR-12** | `VENUE`, `EVENT`, `TICKET_TIER` | 1:N `Venue -> Event`, 1:N `Event -> TicketTier`, capacity sum and non-reduction rules (`BR-01`, `BR-06`, `BR-07`) | ERD, FK constraints, `BEFORE INSERT/UPDATE` capacity triggers |
| **FR-06, FR-07, FR-08, FR-09, FR-10, FR-11** | `REGISTRATION`, `PAYMENT`, `TICKET_TIER` | 1:1 `Registration <-> Payment`, composite FK `(EventID, TicketID)`, `AcceptedPrice`, concurrency-safe capacity enforcement (`BR-02`, `BR-03`, `BR-05`, `BR-10`) | Atomic registration stored procedure with row locking, rollback demo, concurrency test (`AC-01`–`AC-09`, `AC-13`) |
| **FR-13, FR-14** | `SESSION`, `EVENT`, `USER` | Weak/dependent entity `Session` on `Event`, `StartDateTime < EndDateTime`, within event dates, speaker overlap prevention (`BR-08`, `BR-09`) | `CHECK` constraint, `BEFORE INSERT/UPDATE` session scheduling trigger (`AC-10`, `AC-11`) |
| **FR-15, FR-16** | `SESSION_ROSTER`, `REGISTRATION`, `SESSION` | M:N associative table, same-event rule (`BR-04`), session capacity check, `'Enrolled'` vs. `'CheckedIn'` permission separation (`BR-11`) | Composite PK `(RegistrationID, SessionID)`, enrollment & check-in procedures (`AC-04`, `AC-06`, `AC-14`) |
| **FR-17, RQ-01–RQ-04** | All operational tables | Multi-table joins, `LEFT JOIN` with `COALESCE` for zero-payment events, grouped aggregates | SQL query script and views (`AC-15`) |
| **FR-18, BR-12** | `AUDIT_LOG`, `USER` | Append-only audit table with actor, timestamp, entity, record ID, old/new values, reason | `AFTER` audit triggers and `BEFORE UPDATE/DELETE` immutability triggers on `AUDIT_LOG` (`AC-16`) |
