Event Registration and Attendee Management System
Week 1 & 2: Business Analysis & Requirements Gathering
Before drafting the requirements document, the following core business analysis questions must be answered for the new system:
 * What organization or service are we modeling?
   An event management and conference organization platform.
 * What problem exists today?
   We assume the organization currently manages attendee registrations, session schedules, speaker assignments, and payments across disconnected spreadsheets and emails. This makes it difficult to track venue capacity, coordinate schedules, manage ticket sales, and generate accurate financial or attendance reports. A centralized relational database will unify these processes.
 * Who uses or depends on the system?
   * Attendees: Depend on it to browse events, purchase tickets, and build personal session schedules.
   * Event Organizers: Depend on it to create events, manage venues, and track ticket sales and capacities.
   * Speakers: Depend on it to view their assigned sessions and access venue details.
   * Administrators: Depend on it to monitor system-wide activity, manage user roles, and generate financial reports.
 * What records must be created and maintained?
   Users (Attendees/Speakers), Events, Venues, Tickets, Registrations, Sessions, Session Rosters, Payments, and Audit Logs.
 * What business events or transactions occur?
   * An organizer creates a new event and its associated sessions.
   * An attendee registers for an event and purchases a ticket.
   * A speaker is assigned to a specific session.
   * A payment is processed, generating an invoice or receipt.
   * An attendee adds a session to their personal itinerary.
 * What must the organization be able to search for, monitor, or report?
   Search for events by date or venue, monitor remaining ticket capacity, report on total revenue, and track session popularity.
 * What must never be allowed to happen?
   Attendees must not be able to register for events that have reached maximum capacity. Speakers cannot be double-booked for overlapping sessions.
 * What information is sensitive, and which roles should be allowed to view or change it?
   Payment and billing information is sensitive; only the purchasing attendee and high-level administrators can view it. Organizers can manage event and session details, while attendees can only modify their own profiles and schedules.
 * Which reasonable assumptions will we make?
   An event can have multiple sessions, and a session belongs to only one event. An attendee can register for multiple events, but each payment corresponds to a single registration transaction.
Entitlements (Role Access)
Based on the system requirements:
 * View: Attendees can view public events and their own registrations. Organizers can view all attendee data for their specific events.
 * Create/Update: Attendees create their own registrations and payments. Organizers create events, sessions, and ticket tiers.
 * Modify Restrictions: Attendees cannot alter event details, ticket prices, or venue capacities.
 * Manager Approval: Issuing refunds or overriding a sold-out event's capacity requires Administrator approval.
 * Audit Log: Changes to ticket prices, refund processing, or deleted events must trigger an audit entry.
Functional Requirements Document (FRD)
1. Project Identification
| Item | Information |
|---|---|
| Project title | Event Registration and Attendee Management System |
| Course/section | 01:198:437 |
| Repository location | GitHub repository (Markdown format) |
2. Business Problem and Purpose
Event organizers struggle to maintain synchronized records of attendees, ticket sales, session capacities, and payments. The purpose of this project is to implement a normalized relational database (3NF) that securely manages event data, ensures transaction integrity during registrations, and provides actionable insights into event performance and revenue.
3. Scope
| In Scope | Out of Scope |
|---|---|
| Managing user, speaker, and organizer profiles | Processing live credit card transactions |
| Tracking event venues, sessions, and capacities | Integration with external calendar apps (Google/Outlook) |
| Processing event registrations and generating invoices | Live streaming or virtual event hosting |
| Generating reports on ticket sales and attendance | Automated marketing or email blasts |
4. Stakeholders and User Roles
| Stakeholder / Role | Responsibilities | Database Needs | Typical Access |
|---|---|---|---|
| Attendee | Browses events, buys tickets, registers for sessions | Events, Sessions, Registrations, Payments | View public events; create/view personal records |
| Event Organizer | Manages event logistics, speakers, and ticketing | Events, Venues, Tickets, Registrations | Create, view, and update event-specific records |
| Speaker | Leads sessions at events | Sessions, Venues | View assigned sessions and schedules |
| Administrator | Oversees platform operations and security | All operational data, Users, Audit Logs | Broad operational and reporting access |
5. Functional Requirements
| ID | Functional Requirement | Priority | Related Data/Entities | Related Role(s) |
|---|---|---|---|---|
| FR-01 | The system shall store and maintain user, speaker, and organizer profiles. | High | User, Speaker | All Users |
| FR-02 | The system shall allow organizers to create events, venues, and sessions. | High | Event, Venue, Session | Organizer |
| FR-03 | The system shall process attendee registrations and deduct from total ticket capacity. | High | Registration, Ticket, Event | Attendee, Organizer |
| FR-04 | The system shall enforce constraints to prevent overbooking sessions or events. | High | Registration, Session | System |
| FR-05 | The system shall generate a revenue report based on ticket sales and payments. | Medium | Payment, Ticket, Event | Organizer, Admin |
| FR-06 | The system shall capture audit logs for critical changes like refunds or deleted events. | Medium | AuditLog, Event, Payment | Admin |
Week 3 Expectations: Technical Design & ER Diagram
By Week 3, the project must transition from functional requirements to technical design. The expectations include:
 * Entity-Relationship (ER) Diagram: Must include a minimum of 8 to 10 entities with meaningful relationships.
 * Relationships & Cardinality: The diagram must display 1:1, 1:N, and M:N relationships, alongside total/partial participation constraints and weak entities.
 * Normalization: The database schema must be demonstrably normalized to the Third Normal Form (3NF).
 * Deliverables: A formalized Technical Design Document (TDD) and ER diagram exported from draw.io must be stored in the GitHub repository.
12-Week Project Progress Layout
The overall semester follows a strict three-phase deployment schedule managed via Git, with weekly standups, peer evaluations, a minimum of 4 commits per member, and bi-weekly TA check-ins:
 * Phase 1: Planning & Design (Weeks 1-4)
   * Week 1: Business analysis and requirements gathering.
   * Week 2: Functional requirements document finalization.
   * Week 3: Technical design document and ER diagram.
   * Week 4: System architecture approval.
 * Phase 2: Development (Weeks 5-8)
   * Week 5: Database implementation using a schema build file with initial data.
   * Week 6 (Mid-Project Review): Presentation of the working schema, basic CRUD operations, SQL reports, transaction demonstrations, and progress report submission.
   * Week 7: Microservices development.
   * Week 8: Web interface prototype.
 * Phase 3: Testing & Deployment (Weeks 9-12)
   * Week 9: System integration.
   * Week 10: User acceptance testing.
   * Week 11: Final adjustments.
   * Week 12 (Final Review): Live system demonstration (including triggers, constraints, and rolled-back transactions), code walkthrough, and submission of final deliverables.
