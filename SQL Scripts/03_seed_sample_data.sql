-- ============================================================================
-- sql/03_seed_sample_data.sql (v2.0-release)
-- Baseline Realistic Sample Data Across All Roles, Venues, Events, Tiers,
-- Sessions, Registrations, Payments, and Roster Records
-- ============================================================================
USE `event_registration`;

-- 1. Seed Users Across All 4 Roles
INSERT INTO `USER` (`UserID`, `FirstName`, `LastName`, `Email`, `RoleType`, `IsActive`) VALUES
(1, 'Alice',   'Admin',     'alice@test.com',   'Admin',     TRUE),
(2, 'Bob',     'Organizer', 'bob@test.com',     'Organizer', TRUE),
(3, 'Charlie', 'Speaker',   'charlie@test.com', 'Speaker',   TRUE),
(4, 'Dave',    'Attendee',  'dave@test.com',    'Attendee',  TRUE),
(5, 'Elena',   'Rostova',   'elena@test.com',   'Attendee',  TRUE),
(6, 'Frank',   'Miller',    'frank@test.com',   'Organizer', TRUE),
(7, 'Grace',   'Hopper',    'grace@test.com',   'Speaker',   TRUE);

-- 2. Seed Venues
INSERT INTO `VENUE` (`VenueID`, `VenueName`, `Address`, `MaxCapacity`) VALUES
(1, 'Grand Tech Center', '100 Innovation Way, San Jose, CA', 100),
(2, 'Civic Auditorium',  '250 Main St, San Francisco, CA',    50);

-- 3. Seed Events (Event 2 has $0.00 revenue to prove LEFT JOIN + COALESCE in RQ-01)
INSERT INTO `EVENT` (`EventID`, `OrganizerID`, `VenueID`, `EventName`, `StartDate`, `EndDate`) VALUES
(1, 2, 1, 'Tech Conference 2026',     '2026-09-10', '2026-09-12'),
(2, 6, 2, 'AI & Robotics Symposium',  '2026-10-05', '2026-10-06');

-- 4. Seed Ticket Tiers (Combined capacity for Event 1 = 50 + 1 + 20 = 71 <= 100 Venue MaxCapacity)
INSERT INTO `TICKET_TIER` (`TicketID`, `EventID`, `TierName`, `Price`, `Capacity`) VALUES
(10, 1, 'General Admission', 50.00,  50),
(20, 1, 'VIP Pass',          150.00, 1),
(30, 1, 'Workshop Pass',     80.00,  20),
(40, 2, 'Standard Pass',     100.00, 30);

-- 5. Seed Sessions (Assigned to Speakers 3 and 7)
INSERT INTO `SESSION` (`SessionID`, `EventID`, `SpeakerID`, `SessionTitle`, `StartDateTime`, `EndDateTime`, `SessionCapacity`, `RoomNumber`) VALUES
(101, 1, 3, 'Database Architecture & Resiliency', '2026-09-10 09:00:00', '2026-09-10 10:30:00', 30, 'Room A'),
(102, 1, 7, 'High-Concurrency Transaction Design', '2026-09-10 11:00:00', '2026-09-10 12:30:00', 1,  'Room B'),
(201, 2, 3, 'Autonomous Systems Keynote',          '2026-10-05 10:00:00', '2026-10-05 11:30:00', 25, 'Hall 1');

-- 6. Baseline Transactional Seed via v2.0 Session-Resolved Procedures (Elena = UserID 5)
SET @current_user_id = 5;
SET @current_user_role = 'Attendee';

CALL `sp_register_and_pay`(1, 10, 50.00, 'INV-1001');
CALL `sp_enroll_session_roster`(1, 101);
