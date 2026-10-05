Based on the instructions from the **student\_functional\_requirements\_guide (1).pdf** and the database schema outlined in **Event Registration and Attendee Management.drawio (1).png**, here is the preparation and the drafted Functional Requirements Document (FRD) for your project.  
*(Note: I will continue to utilize these documents as active sources in your notebook for future interactions to maintain project context).*

### **Pre-Drafting: The 9 Planning Questions**

Before writing the requirements, here are the answers to the 9 group questions based on your specific solo project parameters:

> 1. **What organization or service are we modeling?** An event management and attendee registration service.  
> 2. **What problem exists today?** Event organizers struggle to maintain synchronized records of attendees, ticket sales, session capacities, and payments across disjointed systems.  
> 3. **Who uses or depends on the system?** Attendees, Event Organizers, Speakers, and System Administrators.  
> 4. **What records must be created and maintained?** Users, Venues, Events, Sessions, Ticket Tiers, Registrations, Session Rosters, Payments, and Audit Logs.  
> 5. **What business events or transactions occur?** Organizers creating events/sessions, attendees purchasing tickets/registering, assigning speakers to sessions, and processing payments.  
> 6. **What must the organization be able to search for, monitor, or report?** They must monitor ticket capacities, track session attendance, and report on total event revenues.  
> 7. **What must never be allowed to happen?** An attendee registering for a ticket tier that has reached its maximum capacity, or a double-booked speaker.  
> 8. **What information is sensitive, and which roles should be allowed to view or change it?** Payment and audit log data are sensitive and should only be viewable by administrators or the respective purchasing attendee.  
> 9. **Which reasonable assumptions will we make?** Each payment maps strictly to one registration (1:1), and an event is hosted at exactly one venue.

### **Functional Requirements Document (FRD)**

**What an FRD Is—and Is Not:** An FRD describes the required behavior of the proposed system in plain, precise business language, focusing on what users need the system to do and conditions the system must enforce. It is *not* a collection of detailed SQL code, exact MySQL data types, or screen UI layouts.

#### **1\. Project Identification**

| Item | Information |
| :---- | :---- |
| **Project title** | Event Registration and Attendee Management System |
| **Prepared by** | Yashvin Jasani |
| **Course/section** | CS 437 Database Implementation |
| **Date** | October 5, 2026 |
| **Version** | 1.0 |
| **Repository location** | https://github.com/yashvinjasani/database-implementations-2026-yashvin |

#### **2\. Business Problem and Purpose**

**Business problem:** Event organizers need a centralized database system to manage event logistics, ticketing, and attendee rosters. Currently, tracking venue capacities, validating ticket availability, and matching payments to registrations is handled via separate tools, causing overbookings and data inconsistencies. **Project purpose:** The purpose of this project is to create a relational database that allows attendees to register for events securely and empowers organizers to manage schedules and capacities. The database will provide a reliable source of information for revenue reporting and attendance tracking.

#### **3\. Scope**

| In scope | Out of scope |
| :---- | :---- |
| Tracking event venues, sessions, and speakers | Live streaming or virtual event hosting |
| Processing attendee registrations and recording payments | Processing real-time credit card transactions via external gateways |
| Enforcing ticket tier capacities | Integration with external calendar applications |
| Role-based user profiles and administrative auditing | Automated marketing or email blasts |

#### **4\. Stakeholders and User Roles**

| Stakeholder or role | Responsibilities | Database needs | Typical access |
| :---- | :---- | :---- | :---- |
| **Admin** | System oversight & security | Users, Audit Logs, Payments | Administrative access |
| **Organizer** | Event logistics & ticketing | Events, Venues, Tickets, Registrations | Create/update event records |
| **Attendee** | Browsing events & registering | Events, Registrations, Payments, Sessions | View public data; Create own records |
| **Speaker** | Leading sessions | Sessions, Venues | View assigned sessions |

#### **5\. Functional Requirements**

| ID | Functional requirement | Priority | Related data/entities | Related role(s) |
| :---- | :---- | :---- | :---- | :---- |
| **FR-01** | The system shall store one profile record per user, including contact details and role type. | High | USER | Admin |
| **FR-02** | The system shall allow organizers to create events mapped to a specific venue. | High | EVENT, VENUE | Organizer |
| **FR-03** | The system shall maintain ticket tiers linked to an event, including price and capacity constraints. | High | TICKET\_TIER, EVENT | Organizer |
| **FR-04** | The system shall process attendee registrations linked to a specific event and ticket tier. | High | REGISTRATION, EVENT, TICKET\_TIER | Attendee |
| **FR-05** | The system shall record a payment associated with a successfully created registration. | High | PAYMENT, REGISTRATION | Attendee |
| **FR-06** | The system shall allow organizers to create event sessions and assign them to speakers. | High | SESSION, EVENT, USER | Organizer |
| **FR-07** | The system shall allow registered attendees to join a session roster and track check-in status. | Medium | SESSION\_ROSTER, REGISTRATION, SESSION | Attendee |
| **FR-08** | The system shall prevent an attendee from registering if the desired ticket tier has reached its capacity. | High | REGISTRATION, TICKET\_TIER | System |
| **FR-09** | The system shall generate audit logs tracking administrative changes. | Medium | AUDIT\_LOG, USER | Admin |

#### **6\. Transaction Flows / Use Cases**

**Use Case UC-01: Attendee Event Registration**

* **Goal:** Record an attendee's registration and associated payment.  
* **Primary actor:** Attendee  
* **Preconditions:** The event and ticket tier must exist and have available capacity.  
* **Related requirements:** FR-01, FR-04, FR-05, FR-08  
* **Main success flow:** 1\. Attendee selects an event and ticket tier. 2\. System validates that ticket capacity is available. 3\. Attendee provides payment details. 4\. System saves the REGISTRATION record. 5\. System saves the related PAYMENT record.  
* **Alternate flow:** If the ticket tier capacity is 0, the system rejects the registration and prevents the transaction.  
* **Postconditions:** A new registration and payment record exist; available capacity is reduced.

**Use Case UC-02: Event Session Scheduling**

* **Goal:** Create an event session and assign a speaker.  
* **Primary actor:** Organizer  
* **Related requirements:** FR-02, FR-06  
* **Main success flow:** 1\. Organizer selects an existing Event. 2\. Organizer inputs session title, start time, and room number. 3\. Organizer assigns a Speaker (USER). 4\. System saves the SESSION record.

#### **7\. Data Requirements**

*(Based entirely on created table schema)*

| Data subject | Information to store | Example identifier | Likely relationship(s) |
| :---- | :---- | :---- | :---- |
| **USER** | Role type, first name, last name, email | UserID | Creates Audit Logs, Organizes Events, Speaks at Sessions |
| **VENUE** | Name, max capacity, address | VenueID | Hosts Events |
| **EVENT** | Name, start date, end date | EventID | Organized by User, Hosted at Venue |
| **TICKET\_TIER** | Tier name, price, capacity | TicketID | Offered by Event |
| **SESSION** | Title, start time, room number | SessionID | Contained in Event, Speaker is User |
| **REGISTRATION** | Registration date, status | RegistrationID | Tied to Attendee, Event, and Ticket |
| **PAYMENT** | Amount paid, date, invoice number | PaymentID | 1:1 linked to Registration |
| **SESSION\_ROSTER** | Check-in status | RegID \+ SessionID | Bridge table linking Registration to Session |
| **AUDIT\_LOG** | Action type, date, description | LogID | Linked to Admin User |

#### **8\. Business Rules and Validation Rules**

| ID | Business rule | Why it matters | Possible enforcement approach |
| :---- | :---- | :---- | :---- |
| **BR-01** | Every EVENT must belong to exactly one VENUE. | Defines required relationship | Foreign key (VenueID) \+ NOT NULL |
| **BR-02** | An Attendee Registration connects to many Sessions, and a Session connects to many Registrations. | Defines M:N relationship | Associative table (SESSION\_ROSTER) |
| **BR-03** | A REGISTRATION is related to a maximum of one PAYMENT. | Avoids billing duplication | 1:1 Foreign key logic |
| **BR-04** | Total registrations for a ticket tier cannot exceed its defined Capacity. | Prevents overbooking | BEFORE INSERT Trigger or CHECK constraint |

#### **9\. Security, Entitlements, and Auditing**

| ID | Security/entitlement requirement | Role(s) affected | Protected action or data |
| :---- | :---- | :---- | :---- |
| **SEC-01** | The system shall allow only Organizers to create or update Events and Sessions. | Organizer | EVENT, SESSION |
| **SEC-02** | The system shall prevent Attendees from modifying Event details or Ticket Prices. | Attendee | EVENT, TICKET\_TIER |
| **SEC-03** | The system shall record the Admin ID, action date, and description when sensitive administrative overrides occur. | Admin | AUDIT\_LOG |

#### **10\. Reports and Queries**

| ID | Report/query name | Business question | Required result | Likely SQL features |
| :---- | :---- | :---- | :---- | :---- |
| **RQ-01** | Event Revenue Summary | How much revenue did an event generate based on paid registrations? | Event name, total amount paid | JOIN, GROUP BY, SUM |
| **RQ-02** | Session Roster List | Which attendees are registered for a specific session? | Attendee names, session titles, check-in status | Multiple JOINs (User, Registration, Session\_Roster, Session) |

#### **11\. Assumptions and Constraints**

* **Assumption:** A system user might be an attendee for one event and a speaker for another, so roles are managed at the user level, but access rights adjust accordingly.  
* **Assumption:** Each payment applies strictly to a single registration.  
* **Constraint:** The database will be implemented in MySQL and verified to 3NF standards.  
* **Constraint:** Processing of live credit card data is outside the scope of this project.

#### **12\. Acceptance Criteria and Traceability**

| Requirement | Acceptance criterion | Evidence to show |
| :---- | :---- | :---- |
| **FR-04** | Complete a valid attendee registration linking user, event, and ticket. | SQL transaction script and resulting joined records |
| **FR-08** | Attempt an invalid registration when ticket tier capacity is 0 and show it is rejected. | Constraint/trigger error result |
| **RQ-01** | Run the revenue summary report with sample payment data. | SQL aggregate query output |
| **SEC-03** | Force an administrative change and show the resulting log entry. | Audit table contents and triggering operation |

