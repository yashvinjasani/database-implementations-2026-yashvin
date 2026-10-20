-- ============================================================================
-- 03_seed_sample_data.sql
-- Seeds realistic baseline data across all 9 tables so every view, report,
-- join, trigger, and test scenario works immediately out of the box.
-- ============================================================================

USE event_registration;

-- 1. Seed Users (Admins, Organizers, Speakers, Attendees)
INSERT INTO USER (UserID, FirstName, LastName, Email, RoleType, IsActive) VALUES
(1, 'Alice',   'Admin',     'alice@test.com',   'Admin',     TRUE),
(2, 'Bob',     'Organizer', 'bob@test.com',     'Organizer', TRUE),
(3, 'Charlie', 'Speaker',   'charlie@test.com', 'Speaker',   TRUE),
(4, 'Dave',    'Attendee',  'dave@test.com',    'Attendee',  TRUE),
(5, 'Elena',   'Rostova',   'elena@test.com',   'Attendee',  TRUE),
(6, 'Frank',   'Miller',    'frank@test.com',   'Organizer', TRUE),
(7, 'Grace',   'Hopper',    'grace@test.com',   'Speaker',   TRUE);

-- 2. Seed Venues
INSERT INTO VENUE (VenueID, VenueName, Address, MaxCapacity) VALUES
(1, 'Main Hall',             '123 Tech St, New Brunswick, NJ', 500),
(2, 'Livingston Innovation', '84 Joyce Kilmer Ave, Piscataway, NJ', 200);

-- 3. Seed Events (Event 1 has registrations; Event 2 has 0 registrations to test RQ-01 LEFT JOIN $0.00)
INSERT INTO EVENT (EventID, OrganizerID, VenueID, EventName, StartDate, EndDate) VALUES
(1, 2, 1, 'Tech Conference 2026',       '2026-11-01', '2026-11-03'),
(2, 6, 2, 'AI & Robotics Symposium',    '2026-12-05', '2026-12-06');

-- 4. Seed Ticket Tiers
-- Note: Tier 3 ('Workshop Pass') has Capacity = 1 to test boundary/last-seat contention (AC-07, AC-08)
INSERT INTO TICKET_TIER (TicketID, EventID, TierName, Price, Capacity) VALUES
(1, 1, 'General Admission', 50.00,  100),
(2, 1, 'VIP',               150.00, 10),
(3, 1, 'Executive 1-Seat',  250.00, 1),
(4, 2, 'Symposium Standard', 75.00, 120);

-- 5. Seed Sessions (For Event 1 and Event 2)
INSERT INTO SESSION (SessionID, EventID, SpeakerID, SessionTitle, StartDateTime, EndDateTime, SessionCapacity, RoomNumber) VALUES
(101, 1, 3, 'InnoDB Internals & Buffer Pool Tuning', '2026-11-01 09:00:00', '2026-11-01 10:30:00', 50, 'Room 204'),
(102, 1, 7, 'ACID Transactions & Row-Level Locking', '2026-11-01 11:00:00', '2026-11-01 12:30:00', 40, 'Room 205'),
(201, 2, 3, 'Autonomous Navigation Architectures',   '2026-12-05 10:00:00', '2026-12-05 11:30:00', 60, 'Auditorium A');

-- 6. Seed Baseline Registration & Payment for User 5 (Elena) via sp_register_and_pay
CALL sp_register_and_pay(5, 1, 1, 50.00, 'INV-1000');

-- 7. Seed Baseline Session Roster Enrollment for User 5 (RegistrationID = 1) into Session 101
CALL sp_enroll_session_roster(5, 1, 101);
