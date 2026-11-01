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
An event management organization needs a centralized relational database system to manage multi-session events, venue capacities, tiered ticket sales, speaker schedules, attendee registrations, and financial records.

### Project Purpose
The purpose of this project is to design and implement a normalized (3NF) MySQL relational database that enables event organizers to schedule events and sessions within strict capacity and time boundaries while preserving accurate accounting and audit records.

---

## 3. Scope

| In Scope | Out of Scope |
| :--- | :--- |
| Maintaining user accounts with base role capabilities and event-specific ownership/participation permissions | Live credit-card processing or integration with external payment gateways |
| Managing venues, events, ticket tiers, and scheduled sessions with start/end timestamps | Automated partial payments or automated bank refund disbursements |
| Enforcing venue, ticket-tier, and session capacity limits under concurrent registration requests | Physical room-entity modeling and room-level capacity enforcement |
| Atomic recording of single-ticket event registrations and fictional payment references | Integration with external calendar platforms |
| Preserving historical ticket prices accepted at the time of registration | Virtual event streaming or webinar hosting infrastructure |
| Enforcing cross-event consistency and preventing speaker schedule overlaps | Automated marketing campaigns or external email notification services |
| Separating attendee session roster enrollment from organizer-recorded attendance check-in | Attendee self-check-in via mobile QR scanning hardware |
| Generating operational and management reports for event revenue, session rosters, and capacity utilization | Financial accounting beyond gross recorded registration payments |
| Recording immutable audit logs for sensitive data modifications and defined administrative overrides | |

---

## 4. Stakeholders and User Roles

### User-Role and Permission Model
The system enforces a hybrid role and ownership permission model combining a user's assigned account role with the user's relationship to a specific event or session.

1. Global Account Capabilities: Every user account holds a primary base role (Admin, Organizer, Speaker, or Attendee).
    * Admin provides governance, read-only access to the system audit log, and reporting.
    * Organizer creates new events and becomes the assigned owner of those events.
    * Speaker is eligible to be assigned by an Organizer to lead a session.
    * Attendee is the standard participant capability allowing a user to register for events.
2. Event-Specific and Ownership Rules:
    * Organizer ownership and attendee participation: an Organizer may view, modify, schedule sessions for, and record check-ins only for events they own.
    * Speaker participation across events/sessions: a user assigned as SpeakerID for a session has read-only access to that session's details and roster.
    * Attendee ownership: any user acting as an Attendee for an event may view and manage only their own registrations, payments, and session roster enrollments.

| Stakeholder or Role | Responsibilities | Database Needs | Typical Access |
| :--- | :--- | :--- | :--- |
| **Admin** | Account administration, security monitoring, and executing defined administrative overrides | `USER`, `AUDIT_LOG`, and read access to operational/financial views | Full oversight and support capability |
| **Organizer** | Creates events, configures ticket tiers, schedules sessions, assigns speakers, records session check-ins, and monitors revenue for owned events | `VENUE`, and owned records in `EVENT`, `TICKET_TIER`, `SESSION`, `REGISTRATION` | Create, view, and update event-specific records |
| **Speaker** | Delivers presentations at assigned event sessions | Assigned records in `SESSION`, `EVENT`, `VENUE`, `SESSION_ROSTER` | View assigned session details and roster |
| **Attendee** | Browses public events, registers and pays for tickets, enrolls in eligible sessions, and views personal check-in and payment status | Public `EVENT`, `VENUE`, `TICKET_TIER`, `SESSION`, and personal `REGISTRATION` / `PAYMENT` | View public events and manage personal records |

---

## 5. Functional Requirements

| ID | Functional Requirement | Priority | Related Data/Entities | Related Role(s) |
| :--- | :--- | :--- | :--- | :--- |
| **FR-01** | The system shall store and maintain one user account record per individual, including a unique identifier, first name, last name, unique email address, account status, and assigned base role. | High | `USER` | All Users |
| **FR-02** | The system shall determine user permissions from the user's assigned base role and, where applicable, the user's ownership or participation relationship to the target event, session, or registration. | High | `USER`, `EVENT`, `SESSION`, `REGISTRATION` | All Users |
| **FR-03** | The system shall store and maintain venue records, including venue name, physical address, and a positive maximum capacity. | High | `VENUE` | Admin, Organizer |
| **FR-04** | The system shall allow an authorized Organizer to create and update event records, including event name, start date, end date, assigned venue, and owning organizer. | High | `EVENT` | Organizer |
| **FR-05** | The system shall allow the owning Organizer of an event to create and update ticket tiers for that event, specifying tier name, current price, and maximum tier capacity. | High | `TICKET_TIER` | Organizer |
| **FR-06** | The system shall allow a user to register for one ticket in a selected ticket tier of an event and atomically record the corresponding payment. | High | `REGISTRATION`, `PAYMENT` | Attendee |
| **FR-07** | The system shall record fictional or externally supplied payment references, payment dates, and payment amounts. | High | `PAYMENT` | Attendee, Admin |
| **FR-08** | The system shall preserve the ticket price accepted at registration time on the registration record and require payment to match that value. | High | `REGISTRATION`, `PAYMENT` | System |
| **FR-09** | The system shall reject any registration where the selected `TicketID` does not belong to the specified `EventID`, or where the attendee already holds an active confirmed registration. | High | `REGISTRATION` | System |
| **FR-10** | The system shall enforce ticket-tier capacity such that only confirmed registrations consume capacity and concurrent registration attempts shall not cause overbooking. | High | `REGISTRATION`, `TICKET_TIER` | System |
| **FR-11** | The system shall allow an attendee or the owning Organizer/Admin to cancel a confirmed registration, releasing one seat of capacity. | High | `REGISTRATION` | Attendee, Organizer, Admin |
| **FR-12** | The system shall prohibit reducing a venue's maximum capacity below any hosted event's total ticket-tier capacity, reducing a ticket tier's capacity below its current confirmed registrations, or reducing a session's capacity below its roster count. | High | `VENUE`, `TICKET_TIER`, `SESSION` | System |
| **FR-13** | The system shall allow the owning Organizer of an event to schedule event sessions specifying session title, times, capacity, and informational room label. | High | `SESSION` | Organizer |
| **FR-14** | The system shall reject a session creation or update if the assigned speaker is already assigned to another overlapping session. | High | `SESSION` | System |
| **FR-15** | The system shall allow an attendee with a confirmed registration for an event to join or leave a session roster for that same event. | High | `SESSION_ROSTER` | Attendee |
| **FR-16** | The system shall allow only the owning Event Organizer or an Administrator to record session attendance by updating a roster entry's check-in status. | High | `SESSION_ROSTER` | Organizer, Admin |
| **FR-17** | The system shall produce event revenue, session roster, capacity utilization, and speaker schedule reports. | Medium | Reporting queries | Organizer, Admin |
| **FR-18** | The system shall automatically record an immutable entry in `AUDIT_LOG` for sensitive changes and defined administrative overrides. | High | `AUDIT_LOG` | Admin |

---

## 6. Transaction Flows / Use Cases

### Use Case UC-01: Attendee Event Registration and Atomic Payment Recording

| Item | Description |
| :--- | :--- |
| **Goal** | Register an eligible user for one seat in a specific event's ticket tier, lock and consume one unit of available capacity, preserve the accepted ticket price, and atomically record the corresponding payment. |
| **Primary actor** | Attendee |
| **Trigger** | The actor submits a registration request specifying `EventID`, `TicketID`, and payment details. |
| **Preconditions** | The actor has an active `USER` account and is not the assigned `OrganizerID` of the target `EVENT`. |
| **Related requirements** | FR-02, FR-06, FR-07, FR-08, FR-09, FR-10, FR-18 |
| **Transaction boundary** | Steps execute within a single atomic database transaction (`START TRANSACTION` ... `COMMIT` / `ROLLBACK`). |
| **Main success flow** | 1. Actor initiates a registration request. 2. System validates event, ticket tier, and capacity. 3. Registration and payment are inserted atomically. 4. Capacity is reduced and an audit log entry is created. |
| **Alternate / exception flows** | Wrong event/ticket mismatch, duplicate active registration, full ticket tier, or payment mismatch triggers rejection and rollback. |
| **Postconditions** | One valid confirmed registration and its required payment record are committed with accepted price preserved. |

---

### Use Case UC-02: Event Session Scheduling and Speaker Assignment

| Item | Description |
| :--- | :--- |
| **Goal** | Schedule a session within an event's date boundaries and assign an eligible speaker without creating schedule conflicts. |
| **Primary actor** | Organizer |
| **Trigger** | The Organizer submits a request to create or update a session for an event. |
| **Preconditions** | The actor is the assigned `OrganizerID` for the target `EVENT`. |
| **Related requirements** | FR-02, FR-12, FR-13, FR-14, FR-18 |
| **Main success flow** | 1. Organizer submits `EventID`, `SpeakerID`, times, and capacity. 2. System validates assignment and time window. 3. Session is inserted and audit log entry is created. |
| **Alternate / exception flows** | Unauthorized organizer, invalid time interval, or speaker overlap triggers rejection. |
| **Postconditions** | A valid `SESSION` record linked to `EventID` and `SpeakerID` is committed. |

---

### Use Case UC-03: Session Roster Enrollment and Organizer Attendance Check-In

| Item | Description |
| :--- | :--- |
| **Goal** | Allow a registered attendee to reserve a seat on an eligible session roster, and allow the owning Event Organizer to record actual attendance. |
| **Primary actor** | Part A: Attendee; Part B: Organizer |
| **Trigger** | Attendee requests to join a session roster or organizer updates attendance for a roster record. |
| **Preconditions** | Both the `REGISTRATION` and `SESSION` records exist, and the registration must be confirmed. |
| **Related requirements** | FR-02, FR-15, FR-16, FR-18 |
| **Main success flow** | Part A: attendee joins a compatible session. Part B: organizer marks attendance. |
| **Alternate / exception flows** | Cross-event roster mismatch or invalid check-in status transitions trigger rejection. |
| **Postconditions** | A `SESSION_ROSTER` entry exists with `CheckInStatus` set appropriately. |

---

## 7. Data Requirements

The data requirements below define the business information the system must maintain.

| Data Subject | Information to Store | Example Identifier | Likely Relationship(s) |
| :--- | :--- | :--- | :--- |
| **USER** | First name, last name, unique email address, account active status, and base role | `UserID` | Organizes `EVENT`; speaks at `SESSION`; attends registrations |
| **VENUE** | Venue name, physical address, and positive maximum building capacity | `VenueID` | Hosts `EVENT` |
| **EVENT** | Event name, start date, end date, owning organizer, and assigned venue | `EventID` | Belongs to one `VENUE`; offers `TICKET_TIER` and `SESSION` |
| **TICKET_TIER** | Tier name, listed unit price, configured capacity, and event reference | `TicketID` | belongs to an `EVENT` |
| **SESSION** | Session title, start/end timestamps, session capacity, room label, parent event, and assigned speaker | `SessionID` | belongs to an `EVENT`; has roster entries |
| **REGISTRATION** | Registration date, status, historical accepted price, attendee, event, and ticket | `RegistrationID` | references `USER`, `EVENT`, `TICKET_TIER` |
| **PAYMENT** | Payment amount, payment date, external invoice reference, and registration reference | `PaymentID` | linked to `REGISTRATION` |
| **SESSION_ROSTER** | Composite references to registration and session, enrollment time, and check-in status | composite key | links `REGISTRATION` and `SESSION` |
| **AUDIT_LOG** | Actor user, timestamp, action type, target entity, record ID, old/new values, and reason | `AuditID` | append-only log |

---

## 8. Business Rules and Validation Rules

| ID | Business Rule | Why It Matters | Possible Enforcement Approach |
| :--- | :--- | :--- | :--- |
| **BR-01** | Every `EVENT` must belong to exactly one `VENUE` and have exactly one owning Organizer. | Establishes ownership and event domain. | Foreign keys and constraints |
| **BR-02** | Each `REGISTRATION` represents exactly one attendee and one ticket for one event. | Prevents duplicate active registrations. | Unique constraints and validation |
| **BR-03** | A registration's selected `TicketID` must belong to the same `EventID`. | Prevents cross-event data corruption. | Composite foreign keys |
| **BR-04** | A `SESSION_ROSTER` entry may be created only when the referenced `REGISTRATION` and `SESSION` belong to the same `EventID` and the registration is confirmed. | Prevents invalid roster linkage. | Validation in stored procedure |
| **BR-05** | Only confirmed registrations consume ticket-tier capacity; cancellation releases one seat. | Preserves correct seat counts. | Trigger or procedure |
| **BR-06** | The sum of `Capacity` across all ticket tiers for an event must not exceed the `MaxCapacity` of the event's assigned venue. | Maintains venue capacity integrity. | Validation trigger |
| **BR-07** | Reducing venue or ticket capacity below current confirmed counts is prohibited. | Avoids inconsistent occupancy. | Validation rule |
| **BR-08** | Every `SESSION` must have `StartDateTime < EndDateTime` and both must fall within the event's date range. | Prevents invalid scheduling. | Check constraints or triggers |
| **BR-09** | Each `SESSION` is assigned to exactly one Speaker, and a speaker cannot be assigned to overlapping sessions. | Ensures schedule feasibility. | Unique check / trigger |
| **BR-10** | Registration creation and payment recording must execute atomically in a single transaction. | Prevents partial or inconsistent payments. | Transaction + rollback handler |
| **BR-11** | A `REGISTRATION` may appear at most once on a given `SESSION` roster and an attendee cannot enroll in overlapping sessions. | Keeps rosters consistent. | Unique composite / validation |
| **BR-12** | All sensitive changes and defined administrative overrides must be logged in `AUDIT_LOG`, and `AUDIT_LOG` rows must be immutable. | Supports governance and accountability. | Trigger-based audit protection |

---

## 9. Security, Entitlements, and Auditing

### Role and Entitlement Requirements

| ID | Security / Entitlement Requirement | Role(s) Affected | Protected Action or Data |
| :--- | :--- | :--- | :--- |
| **SEC-01** | Authenticated users may view public event and venue information, but modifications require proper ownership/role. | All | Event/venue records |
| **SEC-02** | Attendees may view, create, and cancel only their own registrations and payments. | Attendee | Personal registration/payment records |
| **SEC-03** | An Event's owning Organizer may not register as an attendee for their own event. | Organizer | Event registration integrity |
| **SEC-04** | The owning Organizer may view attendee details only for their own events. | Organizer | Event-specific attendee information |
| **SEC-05** | Speakers may view only sessions where they are assigned. | Speaker | Session roster access |
| **SEC-06** | Attendees may join or leave only their own session roster entries; organizer/admin performs attendance check-in. | Attendee, Organizer, Admin | Session roster actions |
| **SEC-07** | Revenue reports are restricted to owning Organizer or Administrator. | Organizer, Admin | Revenue reporting |
| **SEC-08** | `AUDIT_LOG` is restricted to administrators and is immutable. | Admin | Audit trail |
| **SEC-09** | Administrative overrides are restricted to Administrators only. | Admin | Override actions |

### Audit Specification
Every auditable event writes an immutable row to `AUDIT_LOG` containing actor, timestamp, action, target, values, and reason.

---

## 10. Reports and Queries

| ID | Report / Query Name | Business Question | Required Result & Filter / Access Specification |
| :--- | :--- | :--- | :--- |
| **RQ-01** | Event Revenue and Registration Summary Report | How much revenue and how many registered attendees does each event have? | Aggregation by event and filter by organizer/admin access |
| **RQ-02** | Session Roster and Attendance Detail Report | Which attendees are enrolled in a selected session and what is their status? | Filter by session and organizer/admin/speaker access |
| **RQ-03** | Ticket Tier and Session Capacity Exception / Utilization Report | Which ticket tiers or sessions are nearing capacity? | Event-level capacity analysis |
| **RQ-04** | Speaker Schedule and Assignment Report | What sessions is each speaker scheduled to lead across upcoming events? | Query by speaker and time window |

---

## 11. Assumptions and Constraints

### Assumptions
* Each `REGISTRATION` record represents exactly one attendee and one ticket for one event.
* A registration and its 1:1 payment record are always created together in a single atomic transaction.
* `Venue.MaxCapacity`, `TicketTier.Capacity`, and `Session.SessionCapacity` store configured limits.
* `Session.RoomNumber` is informational only.
* Each session has exactly one assigned primary speaker.
* An attendee may re-register after cancellation when done according to policy.

### Constraints
* Database implemented in MySQL (InnoDB) and normalized to 3NF.
* Fictional payment data only; no live payment card data.
* Repository deliverables include Markdown documentation, schema build scripts, and test scripts.

---

## 12. Acceptance Criteria and Traceability

Each acceptance test specifies the required setup, action executed, expected result, and demonstration evidence.

| Test ID | Related Req / Rule | Test Scenario | Expected Result |
| :--- | :--- | :--- | :--- |
| **AC-01** | FR-06, FR-07, FR-08 | Valid atomic registration and payment recording | Registration and payment are committed together |
| **AC-02** | FR-01, FR-04 | Rejection of invalid foreign key references | Invalid insert rejected |
| **AC-03** | FR-09, BR-03 | Rejection of ticket tier from the wrong event | Cross-event registration rejected |
| **AC-04** | FR-15, BR-04 | Rejection of joining a session from another event | Cross-event roster rejected |
| **AC-05** | FR-11, BR-02 | Rejection of duplicate active event registration | Duplicate active rejected |
| **AC-06** | FR-15, BR-11 | Rejection of duplicate session roster entry | Duplicate roster rejected |
| **AC-07** | FR-10, BR-05 | Rejection when a ticket tier is full | Capacity check blocks registration |
| **AC-08** | FR-10, BR-05 | Concurrency test: two requests competing for the last seat | One commit, one rollback |
| **AC-09** | FR-06, FR-07, BR-10 | Payment validation failure and full atomic rollback | Full rollback on mismatch |
| **AC-10** | FR-14, BR-09 | Rejection of speaker scheduling overlap | Overlap rejected |
| **AC-11** | FR-13, BR-08 | Rejection of session outside event dates or invalid time order | Invalid session rejected |
| **AC-12** | FR-02, SEC-01–SEC-04 | Enforcement of role and ownership restrictions | Unauthorized access rejected |
| **AC-13** | FR-08, BR-10 | Historical ticket price preservation | Old registration retains accepted price |
| **AC-14** | FR-16, BR-11, SEC-06 | Session check-in permission enforcement | Only organizer/admin updates check-in |
| **AC-15** | FR-17, SEC-07, RQ-01, RQ-02 | Exact report totals and zero-result behavior | Revenue and roster reports accurate |
| **AC-16** | FR-18, BR-12, SEC-08, SEC-09 | Audit log generation and immutability protection | Logs appended; updates/deletes blocked |

---

### Traceability Matrix

| Requirement / Query | Related Entity / Table Candidates | Rule / Relationship Implied | Planned Implementation Evidence |
| :--- | :--- | :--- | :--- |
| **FR-01, FR-02, SEC-01–SEC-09** | `USER`, `EVENT`, `SESSION`, `REGISTRATION` | Role-based access and ownership model | Schema and validations |
| **FR-03, FR-04, FR-05, FR-12** | `VENUE`, `EVENT`, `TICKET_TIER` | Capacity and ownership constraints | ERD and triggers |
| **FR-06, FR-07, FR-08, FR-09, FR-10, FR-11** | `REGISTRATION`, `PAYMENT`, `TICKET_TIER` | Atomic registration and payment recording | Transaction procedures |
| **FR-13, FR-14** | `SESSION`, `EVENT`, `USER` | Session scheduling and speaker validation | Check constraints and triggers |
| **FR-15, FR-16** | `SESSION_ROSTER`, `REGISTRATION`, `SESSION` | Roster rules and attendance policies | Stored procedure and validation |
| **FR-17, RQ-01–RQ-04** | All operational tables | Multi-table joins and reporting queries | SQL reports |
| **FR-18, BR-12** | `AUDIT_LOG`, `USER` | Immutable append-only audit trail | Audit triggers |
