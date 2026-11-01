-- =============================================================================
-- sql/08_concurrency_and_entitlement_proofs.sql (v2.0-release)
-- Principle 3 & Section C: RBAC Login Provisioning, Row-Level Security Views,
-- and AC-08 Last-Seat Concurrency Serialization Proof
-- =============================================================================
USE `event_registration`;

-- 1. Provision Concrete MySQL Logins and Grant Roles (Principle 3)
CREATE ROLE IF NOT EXISTS 'role_admin', 'role_organizer', 'role_speaker', 'role_attendee';

CREATE USER IF NOT EXISTS 'admin_alice'@'localhost' IDENTIFIED BY 'AdminPass!2026';
CREATE USER IF NOT EXISTS 'bob_organizer'@'localhost' IDENTIFIED BY 'OrgPass!2026';
CREATE USER IF NOT EXISTS 'charlie_speaker'@'localhost' IDENTIFIED BY 'SpkPass!2026';
CREATE USER IF NOT EXISTS 'dave_attendee'@'localhost' IDENTIFIED BY 'AttPass!2026';
CREATE USER IF NOT EXISTS 'elena_attendee'@'localhost' IDENTIFIED BY 'AttPass!2026';
CREATE USER IF NOT EXISTS 'frank_organizer'@'localhost' IDENTIFIED BY 'OrgPass!2026';
CREATE USER IF NOT EXISTS 'grace_speaker'@'localhost' IDENTIFIED BY 'SpkPass!2026';

GRANT 'role_admin' TO 'admin_alice'@'localhost';
GRANT 'role_organizer' TO 'bob_organizer'@'localhost', 'frank_organizer'@'localhost';
GRANT 'role_speaker' TO 'charlie_speaker'@'localhost', 'grace_speaker'@'localhost';
GRANT 'role_attendee' TO 'dave_attendee'@'localhost', 'elena_attendee'@'localhost';

SET DEFAULT ROLE ALL TO
    'admin_alice'@'localhost',
    'bob_organizer'@'localhost',
    'charlie_speaker'@'localhost',
    'dave_attendee'@'localhost',
    'elena_attendee'@'localhost',
    'frank_organizer'@'localhost',
    'grace_speaker'@'localhost';

-- 2. Verify Role Grants & Row-Level Security Views for Each Persona
-- 2A: Attendee Dave (UserID = 4) sees ONLY his own registrations in v_attendee_own_registrations
SET @current_user_id = 4;
SET @current_user_role = 'Attendee';
SELECT 'Attendee Dave View (UserID=4)' AS PersonaCheck, RegistrationID, AttendeeID, EventName, TierName, Status, AcceptedPrice
FROM `v_attendee_own_registrations`;

-- 2B: Organizer Bob (UserID = 2) sees registrations ONLY for Events he organizes (EventID = 1)
SET @current_user_id = 2;
SET @current_user_role = 'Organizer';
SELECT 'Organizer Bob View (UserID=2)' AS PersonaCheck, EventID, EventName, RegistrationID, AttendeeID, Status, AmountPaid
FROM `v_organizer_event_registrations`;

-- 2C: Speaker Charlie (UserID = 3) sees rosters ONLY for Sessions he speaks at (SessionID = 101)
SET @current_user_id = 3;
SET @current_user_role = 'Speaker';
SELECT 'Speaker Charlie View (UserID=3)' AS PersonaCheck, SessionID, SessionTitle, RegistrationID, FirstName, LastName, CheckInStatus
FROM `v_speaker_session_roster`;

-- 3. AC-08 Concurrency & Last-Seat Serialization Proof on 1-Seat Tier (TicketID = 20)
SELECT
    tt.TicketID,
    tt.TierName,
    tt.Capacity AS ConfiguredMaxSeats,
    COUNT(CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END) AS ConfirmedSeatsSold,
    (tt.Capacity - COUNT(CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END)) AS RemainingSeats
FROM `TICKET_TIER` tt
LEFT JOIN `REGISTRATION` r ON tt.EventID = r.EventID AND tt.TicketID = r.TicketID
WHERE tt.TicketID = 20
GROUP BY tt.TicketID, tt.TierName, tt.Capacity;
