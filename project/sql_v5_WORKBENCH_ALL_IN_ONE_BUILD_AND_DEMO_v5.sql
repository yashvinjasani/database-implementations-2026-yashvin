SET SQL_SAFE_UPDATES = 0;

-- ============================================================================
-- 01_schema_ddl.sql
-- Creates the 3NF Relational Schema (9 Tables), Primary/Foreign Keys,
-- Composite Keys, Generated Columns, CHECK Constraints, Performance Indexes,
-- Reporting Views (RQ-01..RQ-04), Security Views, and Database Roles.
-- ============================================================================

DROP DATABASE IF EXISTS event_registration;
CREATE DATABASE event_registration
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;
USE event_registration;

-- ----------------------------------------------------------------------------
-- 1. USER (Core Master Tier)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- 2. VENUE (Core Master Tier)
-- ----------------------------------------------------------------------------
CREATE TABLE VENUE (
    VenueID INT AUTO_INCREMENT PRIMARY KEY,
    VenueName VARCHAR(120) NOT NULL,
    Address VARCHAR(255) NOT NULL,
    MaxCapacity INT NOT NULL,
    CONSTRAINT uq_venue_name_addr UNIQUE (VenueName, Address),
    CONSTRAINT chk_venue_cap CHECK (MaxCapacity > 0)
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 3. EVENT (Event Configuration Tier)
-- ----------------------------------------------------------------------------
CREATE TABLE EVENT (
    EventID INT AUTO_INCREMENT PRIMARY KEY,
    OrganizerID INT NOT NULL,
    VenueID INT NOT NULL,
    EventName VARCHAR(150) NOT NULL,
    StartDate DATE NOT NULL,
    EndDate DATE NOT NULL,
    CONSTRAINT chk_event_dates CHECK (StartDate <= EndDate),
    CONSTRAINT fk_event_organizer FOREIGN KEY (OrganizerID)
        REFERENCES USER(UserID) ON DELETE RESTRICT,
    CONSTRAINT fk_event_venue FOREIGN KEY (VenueID)
        REFERENCES VENUE(VenueID) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 4. TICKET_TIER (Event Configuration Tier)
-- ----------------------------------------------------------------------------
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
        REFERENCES EVENT(EventID) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 5. SESSION (Event Configuration Tier — Dependent Entity on EVENT)
-- ----------------------------------------------------------------------------
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
        REFERENCES EVENT(EventID) ON DELETE RESTRICT,
    CONSTRAINT fk_session_speaker FOREIGN KEY (SpeakerID)
        REFERENCES USER(UserID) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 6. REGISTRATION (Transactional Tier)
-- ----------------------------------------------------------------------------
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
        REFERENCES USER(UserID) ON DELETE RESTRICT,
    CONSTRAINT fk_reg_event FOREIGN KEY (EventID)
        REFERENCES EVENT(EventID) ON DELETE RESTRICT,
    CONSTRAINT fk_reg_event_ticket FOREIGN KEY (EventID, TicketID)
        REFERENCES TICKET_TIER(EventID, TicketID) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 7. PAYMENT (Transactional Tier — Strict 1:1 with REGISTRATION)
-- ----------------------------------------------------------------------------
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
        REFERENCES REGISTRATION(RegistrationID) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 8. SESSION_ROSTER (Transactional Tier — Associative M:N Entity)
-- ----------------------------------------------------------------------------
CREATE TABLE SESSION_ROSTER (
    RegistrationID INT NOT NULL,
    SessionID INT NOT NULL,
    CheckInStatus ENUM('Enrolled', 'CheckedIn', 'NoShow') NOT NULL DEFAULT 'Enrolled',
    EnrolledAt DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (RegistrationID, SessionID),
    CONSTRAINT fk_roster_registration FOREIGN KEY (RegistrationID)
        REFERENCES REGISTRATION(RegistrationID) ON DELETE RESTRICT,
    CONSTRAINT fk_roster_session FOREIGN KEY (SessionID)
        REFERENCES SESSION(SessionID) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ----------------------------------------------------------------------------
-- 9. AUDIT_LOG (Governance & Security Tier — Append-Only)
-- ----------------------------------------------------------------------------
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
        REFERENCES USER(UserID) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- ============================================================================
-- PERFORMANCE INDEXES (Aligned with TDD Section 4 / Section 10.2)
-- ============================================================================
CREATE INDEX idx_event_startdate_org
    ON EVENT (StartDate, OrganizerID);

CREATE INDEX idx_session_speaker_interval
    ON SESSION (SpeakerID, StartDateTime, EndDateTime);

CREATE INDEX idx_reg_ticket_status
    ON REGISTRATION (TicketID, Status);

CREATE INDEX idx_reg_event_status
    ON REGISTRATION (EventID, Status);

CREATE INDEX idx_roster_session_status
    ON SESSION_ROSTER (SessionID, CheckInStatus, RegistrationID);

CREATE INDEX idx_audit_entity_record
    ON AUDIT_LOG (EntityName, RecordID, ActionTimestamp);

-- ============================================================================
-- REPORTING VIEWS (RQ-01 through RQ-04)
-- ============================================================================

-- RQ-01: Event Revenue and Registration Summary Report
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

-- RQ-02: Session Roster and Attendance Detail Report
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

-- RQ-03: Ticket Tier and Session Capacity Utilization Report
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

-- RQ-04: Speaker Schedule and Assignment Report
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

-- ============================================================================
-- SESSION CONTEXT HELPER FUNCTION & ROW-FILTERED SECURITY VIEWS
-- Note: MySQL 8.0 prohibits raw `@session_variables` directly inside a VIEW's
-- SELECT statement (Error 1351), so wrapping `@current_user_id` inside a
-- deterministic SQL function `fn_current_user_id()` is the standard MySQL
-- pattern for row-level security views!
-- ============================================================================
DROP FUNCTION IF EXISTS fn_current_user_id;
CREATE FUNCTION fn_current_user_id()
RETURNS INT
DETERMINISTIC NO SQL
RETURN @current_user_id;

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
WHERE r.AttendeeID = fn_current_user_id();

CREATE OR REPLACE VIEW v_organizer_event_registrations AS
SELECT e.EventID, e.EventName, e.OrganizerID,
       r.RegistrationID, r.Status, r.AcceptedPrice, r.RegistrationDate,
       u.UserID AS AttendeeID, u.FirstName, u.LastName, u.Email,
       p.PaymentID, p.AmountPaid, p.InvoiceNumber
FROM EVENT e
INNER JOIN REGISTRATION r ON e.EventID = r.EventID
INNER JOIN USER u ON r.AttendeeID = u.UserID
LEFT JOIN PAYMENT p ON r.RegistrationID = p.RegistrationID
WHERE e.OrganizerID = fn_current_user_id();

CREATE OR REPLACE VIEW v_speaker_session_roster AS
SELECT s.SessionID, s.SessionTitle, s.StartDateTime, s.EndDateTime, s.RoomNumber,
       sr.RegistrationID, u.FirstName, u.LastName, sr.CheckInStatus
FROM SESSION s
INNER JOIN SESSION_ROSTER sr ON s.SessionID = sr.SessionID
INNER JOIN REGISTRATION r ON sr.RegistrationID = r.RegistrationID
INNER JOIN USER u ON r.AttendeeID = u.UserID
WHERE s.SpeakerID = fn_current_user_id()
  AND r.Status = 'Confirmed';

-- Create Database Roles and Grant Privileges
CREATE ROLE IF NOT EXISTS 'role_admin', 'role_organizer', 'role_speaker', 'role_attendee';

GRANT SELECT ON v_public_event_catalog TO 'role_attendee', 'role_speaker', 'role_organizer', 'role_admin';
GRANT SELECT ON v_attendee_own_registrations TO 'role_attendee', 'role_speaker', 'role_organizer';
GRANT SELECT ON v_organizer_event_registrations TO 'role_organizer';
GRANT SELECT ON v_speaker_session_roster TO 'role_speaker';
GRANT SELECT ON v_rq01_event_revenue TO 'role_organizer', 'role_admin';
GRANT SELECT ON v_rq02_session_roster TO 'role_organizer', 'role_speaker', 'role_admin';
GRANT SELECT ON v_rq03_capacity_utilization TO 'role_organizer', 'role_admin';
GRANT SELECT ON v_rq04_speaker_schedule TO 'role_organizer', 'role_speaker', 'role_admin';
GRANT SELECT ON AUDIT_LOG TO 'role_admin';


-- ============================================================================
-- 02_triggers_and_procedures.sql
-- Implements all Business Rule Validation Triggers, Audit Immutability
-- Triggers, and Atomic Stored Procedures required by the TDD & FRD v2.
-- ============================================================================

USE event_registration;

DELIMITER $$

-- ----------------------------------------------------------------------------
-- 1. VENUE & TICKET_TIER CAPACITY CEILING / NON-REDUCTION TRIGGERS (BR-06, BR-07)
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_tickettier_bi_cap
BEFORE INSERT ON TICKET_TIER
FOR EACH ROW
BEGIN
    DECLARE v_venue_max INT;
    DECLARE v_existing_sum INT;

    SELECT v.MaxCapacity INTO v_venue_max
      FROM EVENT e
      INNER JOIN VENUE v ON e.VenueID = v.VenueID
     WHERE e.EventID = NEW.EventID;

    SELECT COALESCE(SUM(Capacity), 0) INTO v_existing_sum
      FROM TICKET_TIER
     WHERE EventID = NEW.EventID;

    IF (v_existing_sum + NEW.Capacity) > v_venue_max THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-05/BR-06 Violation: Total ticket tier capacity exceeds Venue MaxCapacity.';
    END IF;
END$$

CREATE TRIGGER trg_tickettier_bu_cap
BEFORE UPDATE ON TICKET_TIER
FOR EACH ROW
BEGIN
    DECLARE v_venue_max INT;
    DECLARE v_other_sum INT;
    DECLARE v_confirmed_count INT;

    SELECT v.MaxCapacity INTO v_venue_max
      FROM EVENT e
      INNER JOIN VENUE v ON e.VenueID = v.VenueID
     WHERE e.EventID = NEW.EventID;

    SELECT COALESCE(SUM(Capacity), 0) INTO v_other_sum
      FROM TICKET_TIER
     WHERE EventID = NEW.EventID
       AND TicketID <> OLD.TicketID;

    IF (v_other_sum + NEW.Capacity) > v_venue_max THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-05/BR-06 Violation: Updated ticket tier capacity exceeds Venue MaxCapacity.';
    END IF;

    SELECT COUNT(*) INTO v_confirmed_count
      FROM REGISTRATION
     WHERE TicketID = OLD.TicketID
       AND Status = 'Confirmed';

    IF NEW.Capacity < v_confirmed_count THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-12/BR-07 Violation: Cannot reduce TicketTier Capacity below active Confirmed registrations.';
    END IF;
END$$

CREATE TRIGGER trg_tickettier_au_audit
AFTER UPDATE ON TICKET_TIER
FOR EACH ROW
BEGIN
    IF OLD.Price <> NEW.Price OR OLD.Capacity <> NEW.Capacity THEN
        INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionType, EntityName, RecordID, OldValue, NewValue, Reason)
        VALUES (
            COALESCE(@current_user_id, 1),
            COALESCE(@current_user_role, 'Organizer'),
            'UPDATE',
            'TICKET_TIER',
            CAST(NEW.TicketID AS CHAR),
            CONCAT('Price=', OLD.Price, ';Capacity=', OLD.Capacity),
            CONCAT('Price=', NEW.Price, ';Capacity=', NEW.Capacity),
            'Ticket tier price or capacity updated'
        );
    END IF;
END$$

CREATE TRIGGER trg_venue_bu_cap
BEFORE UPDATE ON VENUE
FOR EACH ROW
BEGIN
    DECLARE v_max_event_tier_sum INT;
    DECLARE v_max_session_cap INT;

    SELECT COALESCE(MAX(tier_sum), 0) INTO v_max_event_tier_sum
      FROM (
          SELECT SUM(tt.Capacity) AS tier_sum
            FROM EVENT e
            INNER JOIN TICKET_TIER tt ON e.EventID = tt.EventID
           WHERE e.VenueID = OLD.VenueID
           GROUP BY e.EventID
      ) AS t;

    SELECT COALESCE(MAX(s.SessionCapacity), 0) INTO v_max_session_cap
      FROM EVENT e
      INNER JOIN SESSION s ON e.EventID = s.EventID
     WHERE e.VenueID = OLD.VenueID;

    IF NEW.MaxCapacity < v_max_event_tier_sum OR NEW.MaxCapacity < v_max_session_cap THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-12/BR-07 Violation: Cannot reduce Venue MaxCapacity below allocated event/session capacities.';
    END IF;
END$$

-- ----------------------------------------------------------------------------
-- 2. SESSION DATE BOUND & SPEAKER OVERLAP TRIGGERS (FR-13, FR-14, BR-08, BR-09)
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_session_bi_validate
BEFORE INSERT ON SESSION
FOR EACH ROW
BEGIN
    DECLARE v_evt_start DATE;
    DECLARE v_evt_end DATE;
    DECLARE v_venue_max INT;
    DECLARE v_overlap_count INT;

    SELECT e.StartDate, e.EndDate, v.MaxCapacity
      INTO v_evt_start, v_evt_end, v_venue_max
      FROM EVENT e
      INNER JOIN VENUE v ON e.VenueID = v.VenueID
     WHERE e.EventID = NEW.EventID;

    IF DATE(NEW.StartDateTime) < v_evt_start OR DATE(NEW.EndDateTime) > v_evt_end THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-13/BR-08 Violation: Session timestamps must fall within parent Event StartDate and EndDate.';
    END IF;

    IF NEW.SessionCapacity > v_venue_max THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-06 Violation: SessionCapacity cannot exceed Venue MaxCapacity.';
    END IF;

    SELECT COUNT(*) INTO v_overlap_count
      FROM SESSION
     WHERE SpeakerID = NEW.SpeakerID
       AND NEW.StartDateTime < EndDateTime
       AND NEW.EndDateTime > StartDateTime;

    IF v_overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-14/BR-09 Violation: Speaker is already scheduled for an overlapping session interval.';
    END IF;
END$$

CREATE TRIGGER trg_session_bu_cap
BEFORE UPDATE ON SESSION
FOR EACH ROW
BEGIN
    DECLARE v_enrolled_count INT;

    SELECT COUNT(*) INTO v_enrolled_count
      FROM SESSION_ROSTER sr
      INNER JOIN REGISTRATION r ON sr.RegistrationID = r.RegistrationID
     WHERE sr.SessionID = OLD.SessionID
       AND r.Status = 'Confirmed';

    IF NEW.SessionCapacity < v_enrolled_count THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-12/BR-07 Violation: Cannot reduce SessionCapacity below active enrolled count.';
    END IF;
END$$

-- ----------------------------------------------------------------------------
-- 3. PAYMENT & SESSION_ROSTER INTEGRITY TRIGGERS (FR-08, BR-04, BR-10, BR-11)
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_payment_bi_validate
BEFORE INSERT ON PAYMENT
FOR EACH ROW
BEGIN
    DECLARE v_accepted_price DECIMAL(10,2);
    DECLARE v_reg_status VARCHAR(20);

    SELECT AcceptedPrice, Status
      INTO v_accepted_price, v_reg_status
      FROM REGISTRATION
     WHERE RegistrationID = NEW.RegistrationID;

    IF v_reg_status <> 'Confirmed' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-10 Violation: Payment can only be recorded for a Confirmed registration.';
    END IF;

    IF NEW.AmountPaid <> v_accepted_price THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-08/BR-10 Violation: Payment AmountPaid must exactly equal REGISTRATION.AcceptedPrice.';
    END IF;
END$$

CREATE TRIGGER trg_roster_bi_validate
BEFORE INSERT ON SESSION_ROSTER
FOR EACH ROW
BEGIN
    DECLARE v_reg_event_id INT;
    DECLARE v_reg_status VARCHAR(20);
    DECLARE v_sess_event_id INT;
    DECLARE v_sess_cap INT;
    DECLARE v_active_roster INT;

    SELECT EventID, Status INTO v_reg_event_id, v_reg_status
      FROM REGISTRATION
     WHERE RegistrationID = NEW.RegistrationID;

    SELECT EventID, SessionCapacity INTO v_sess_event_id, v_sess_cap
      FROM SESSION
     WHERE SessionID = NEW.SessionID;

    IF v_reg_status <> 'Confirmed' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-04 Violation: Only Confirmed registrations may enroll in a session roster.';
    END IF;

    IF v_reg_event_id <> v_sess_event_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-15/BR-04 Violation: Cross-event session enrollment is prohibited.';
    END IF;

    SELECT COUNT(*) INTO v_active_roster
      FROM SESSION_ROSTER sr
      INNER JOIN REGISTRATION r ON sr.RegistrationID = r.RegistrationID
     WHERE sr.SessionID = NEW.SessionID
       AND r.Status = 'Confirmed';

    IF v_active_roster >= v_sess_cap THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'BR-05 Violation: Session has reached its maximum SessionCapacity.';
    END IF;
END$$

-- ----------------------------------------------------------------------------
-- 4. AUDIT_LOG IMMUTABILITY TRIGGERS (FR-18, BR-12, SEC-08)
-- ----------------------------------------------------------------------------
CREATE TRIGGER trg_audit_log_bu_immutable
BEFORE UPDATE ON AUDIT_LOG
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'BR-12/SEC-08 Violation: AUDIT_LOG is append-only and immutable.';
END$$

CREATE TRIGGER trg_audit_log_bd_immutable
BEFORE DELETE ON AUDIT_LOG
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'BR-12/SEC-08 Violation: AUDIT_LOG is append-only and immutable.';
END$$

-- ============================================================================
-- STORED PROCEDURES (UC-01, UC-02, UC-03, Cancellations & Check-Ins)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Procedure 1: sp_register_and_pay (UC-01 Atomic Registration + 1:1 Payment)
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_register_and_pay(
    IN p_attendee_id INT,
    IN p_event_id INT,
    IN p_ticket_id INT,
    IN p_amount_paid DECIMAL(10,2),
    IN p_invoice_number VARCHAR(60)
)
BEGIN
    DECLARE v_tier_event_id INT;
    DECLARE v_tier_price DECIMAL(10,2);
    DECLARE v_tier_capacity INT;
    DECLARE v_confirmed_count INT;
    DECLARE v_organizer_id INT;
    DECLARE v_new_reg_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT OrganizerID INTO v_organizer_id
      FROM EVENT
     WHERE EventID = p_event_id;

    IF v_organizer_id = p_attendee_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'SEC-03 Violation: Event Organizers cannot register as attendees for their own event.';
    END IF;

    -- Pessimistic row-level lock serializing concurrent seat checks
    SELECT EventID, Price, Capacity
      INTO v_tier_event_id, v_tier_price, v_tier_capacity
      FROM TICKET_TIER
     WHERE TicketID = p_ticket_id
       FOR UPDATE;

    IF v_tier_event_id IS NULL OR v_tier_event_id <> p_event_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-09/BR-03 Violation: Ticket tier does not belong to the specified event.';
    END IF;

    SELECT COUNT(*)
      INTO v_confirmed_count
      FROM REGISTRATION
     WHERE TicketID = p_ticket_id
       AND Status = 'Confirmed';

    IF v_confirmed_count >= v_tier_capacity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-10/BR-05 Violation: Ticket tier has reached maximum capacity.';
    END IF;

    INSERT INTO REGISTRATION (AttendeeID, EventID, TicketID, RegistrationDate, Status, AcceptedPrice)
    VALUES (p_attendee_id, p_event_id, p_ticket_id, NOW(), 'Confirmed', v_tier_price);

    SET v_new_reg_id = LAST_INSERT_ID();

    -- Payment insert validated by trg_payment_bi_validate (AmountPaid == AcceptedPrice)
    INSERT INTO PAYMENT (RegistrationID, AmountPaid, PaymentDate, InvoiceNumber)
    VALUES (v_new_reg_id, p_amount_paid, NOW(), p_invoice_number);

    INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionType, EntityName, RecordID, NewValue, Reason)
    VALUES (
        p_attendee_id,
        'Attendee',
        'INSERT',
        'REGISTRATION',
        CAST(v_new_reg_id AS CHAR),
        CONCAT('Status=Confirmed;AcceptedPrice=', v_tier_price, ';Invoice=', p_invoice_number),
        'UC-01 Atomic Registration and 1:1 Payment'
    );

    COMMIT;
END$$

-- ----------------------------------------------------------------------------
-- Procedure 2: sp_cancel_registration (FR-11 Soft Cancellation & Seat Release)
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_cancel_registration(
    IN p_actor_user_id INT,
    IN p_registration_id INT,
    IN p_reason VARCHAR(255)
)
BEGIN
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_attendee_id INT;
    DECLARE v_event_id INT;
    DECLARE v_organizer_id INT;
    DECLARE v_current_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT RoleType INTO v_actor_role
      FROM USER
     WHERE UserID = p_actor_user_id;

    SELECT r.AttendeeID, r.EventID, r.Status, e.OrganizerID
      INTO v_attendee_id, v_event_id, v_current_status, v_organizer_id
      FROM REGISTRATION r
      INNER JOIN EVENT e ON r.EventID = e.EventID
     WHERE r.RegistrationID = p_registration_id
       FOR UPDATE;

    IF v_attendee_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Registration record not found.';
    END IF;

    IF v_current_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Registration is already Cancelled.';
    END IF;

    -- Row-level ownership check (AC-12)
    IF v_actor_role <> 'Admin'
       AND p_actor_user_id <> v_attendee_id
       AND p_actor_user_id <> v_organizer_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-02/SEC-03 Violation: Actor is not authorized to cancel this registration.';
    END IF;

    -- Release enrolled session seats before transitioning status
    DELETE FROM SESSION_ROSTER
     WHERE RegistrationID = p_registration_id;

    UPDATE REGISTRATION
       SET Status = 'Cancelled'
     WHERE RegistrationID = p_registration_id;

    INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionType, EntityName, RecordID, OldValue, NewValue, Reason)
    VALUES (
        p_actor_user_id,
        v_actor_role,
        'STATUS_CHANGE',
        'REGISTRATION',
        CAST(p_registration_id AS CHAR),
        'Status=Confirmed',
        'Status=Cancelled',
        p_reason
    );

    COMMIT;
END$$

-- ----------------------------------------------------------------------------
-- Procedure 3: sp_schedule_session (UC-02 Organizer Session Scheduling)
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_schedule_session(
    IN p_actor_user_id INT,
    IN p_event_id INT,
    IN p_speaker_id INT,
    IN p_title VARCHAR(150),
    IN p_start_dt DATETIME,
    IN p_end_dt DATETIME,
    IN p_capacity INT,
    IN p_room VARCHAR(40)
)
BEGIN
    DECLARE v_organizer_id INT;
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_new_session_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT RoleType INTO v_actor_role FROM USER WHERE UserID = p_actor_user_id;
    SELECT OrganizerID INTO v_organizer_id FROM EVENT WHERE EventID = p_event_id;

    IF v_actor_role <> 'Admin' AND p_actor_user_id <> v_organizer_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-02/SEC-01 Violation: Only the owning Event Organizer or Admin can schedule sessions.';
    END IF;

    INSERT INTO SESSION (EventID, SpeakerID, SessionTitle, StartDateTime, EndDateTime, SessionCapacity, RoomNumber)
    VALUES (p_event_id, p_speaker_id, p_title, p_start_dt, p_end_dt, p_capacity, p_room);

    SET v_new_session_id = LAST_INSERT_ID();

    INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionType, EntityName, RecordID, NewValue, Reason)
    VALUES (
        p_actor_user_id,
        v_actor_role,
        'INSERT',
        'SESSION',
        CAST(v_new_session_id AS CHAR),
        CONCAT('Title=', p_title, ';SpeakerID=', p_speaker_id, ';Room=', p_room),
        'UC-02 Scheduled Event Session'
    );

    COMMIT;
END$$

-- ----------------------------------------------------------------------------
-- Procedure 4: sp_enroll_session_roster (UC-03A Attendee Roster Enrollment)
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_enroll_session_roster(
    IN p_actor_user_id INT,
    IN p_registration_id INT,
    IN p_session_id INT
)
BEGIN
    DECLARE v_attendee_id INT;
    DECLARE v_sess_cap INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT AttendeeID INTO v_attendee_id
      FROM REGISTRATION
     WHERE RegistrationID = p_registration_id;

    IF v_attendee_id IS NULL OR v_attendee_id <> p_actor_user_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-02 Violation: Attendee may only enroll their own registration into a session.';
    END IF;

    -- Lock session row to serialize concurrent capacity check
    SELECT SessionCapacity INTO v_sess_cap
      FROM SESSION
     WHERE SessionID = p_session_id
       FOR UPDATE;

    INSERT INTO SESSION_ROSTER (RegistrationID, SessionID, CheckInStatus, EnrolledAt)
    VALUES (p_registration_id, p_session_id, 'Enrolled', NOW());

    INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionType, EntityName, RecordID, NewValue, Reason)
    VALUES (
        p_actor_user_id,
        'Attendee',
        'INSERT',
        'SESSION_ROSTER',
        CONCAT(p_registration_id, ':', p_session_id),
        'CheckInStatus=Enrolled;RegistrationID=' ,
        CONCAT('Enrolled RegistrationID=', p_registration_id, ' into SessionID=', p_session_id)
    );

    COMMIT;
END$$

-- ----------------------------------------------------------------------------
-- Procedure 5: sp_record_session_checkin (UC-03B Organizer Attendance Check-In)
-- ----------------------------------------------------------------------------
CREATE PROCEDURE sp_record_session_checkin(
    IN p_actor_user_id INT,
    IN p_registration_id INT,
    IN p_session_id INT,
    IN p_new_status ENUM('CheckedIn', 'NoShow')
)
BEGIN
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_organizer_id INT;
    DECLARE v_old_status VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT RoleType INTO v_actor_role FROM USER WHERE UserID = p_actor_user_id;

    SELECT e.OrganizerID INTO v_organizer_id
      FROM SESSION s
      INNER JOIN EVENT e ON s.EventID = e.EventID
     WHERE s.SessionID = p_session_id;

    IF v_actor_role <> 'Admin' AND p_actor_user_id <> v_organizer_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'FR-16/SEC-06 Violation: Only the owning Event Organizer or Admin can update CheckInStatus.';
    END IF;

    SELECT CheckInStatus INTO v_old_status
      FROM SESSION_ROSTER
     WHERE RegistrationID = p_registration_id
       AND SessionID = p_session_id
       FOR UPDATE;

    IF v_old_status IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Roster enrollment record does not exist.';
    END IF;

    UPDATE SESSION_ROSTER
       SET CheckInStatus = p_new_status
     WHERE RegistrationID = p_registration_id
       AND SessionID = p_session_id;

    INSERT INTO AUDIT_LOG (ActorUserID, ActorRole, ActionType, EntityName, RecordID, OldValue, NewValue, Reason)
    VALUES (
        p_actor_user_id,
        v_actor_role,
        'STATUS_CHANGE',
        'SESSION_ROSTER',
        CAST(p_registration_id AS CHAR),
        CONCAT('SessionID=', p_session_id, ';CheckInStatus=', v_old_status),
        CONCAT('SessionID=', p_session_id, ';CheckInStatus=', p_new_status),
        'UC-03B Organizer verified session attendance'
    );

    COMMIT;
END$$

DELIMITER ;

-- Grant Execute Permissions to Database Roles
GRANT EXECUTE ON PROCEDURE sp_register_and_pay TO 'role_attendee', 'role_speaker', 'role_organizer';
GRANT EXECUTE ON PROCEDURE sp_cancel_registration TO 'role_attendee', 'role_organizer', 'role_admin';
GRANT EXECUTE ON PROCEDURE sp_schedule_session TO 'role_organizer', 'role_admin';
GRANT EXECUTE ON PROCEDURE sp_enroll_session_roster TO 'role_attendee', 'role_speaker', 'role_organizer';
GRANT EXECUTE ON PROCEDURE sp_record_session_checkin TO 'role_organizer', 'role_admin';


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


-- ============================================================================
-- 04_test_suite_and_demo.sql (v5 — Exact Row Counts + Clean Result Tabs)
-- Complete, Self-Contained Live Demonstration & Verification Script
-- Aligned with `Project_Deliverables_and_Demo_Requirements.pdf` and TDD Section 13.
-- ============================================================================

USE event_registration;

-- ============================================================================
-- PART 1: FRESH BUILD & DATA INITIALIZATION VERIFICATION
-- ============================================================================

-- Result Tab 1: Exact Baseline Row Counts Across All 9 InnoDB Tables
SELECT 'USER' AS TableName, 'InnoDB' AS Engine, COUNT(*) AS ExactRowCount FROM USER
UNION ALL SELECT 'VENUE', 'InnoDB', COUNT(*) FROM VENUE
UNION ALL SELECT 'EVENT', 'InnoDB', COUNT(*) FROM EVENT
UNION ALL SELECT 'TICKET_TIER', 'InnoDB', COUNT(*) FROM TICKET_TIER
UNION ALL SELECT 'SESSION', 'InnoDB', COUNT(*) FROM SESSION
UNION ALL SELECT 'REGISTRATION', 'InnoDB', COUNT(*) FROM REGISTRATION
UNION ALL SELECT 'PAYMENT', 'InnoDB', COUNT(*) FROM PAYMENT
UNION ALL SELECT 'SESSION_ROSTER', 'InnoDB', COUNT(*) FROM SESSION_ROSTER
UNION ALL SELECT 'AUDIT_LOG', 'InnoDB', COUNT(*) FROM AUDIT_LOG;

-- Result Tab 2: All Declarative Constraints (PK, FK, UNIQUE, CHECK)
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
  FROM information_schema.TABLE_CONSTRAINTS
 WHERE TABLE_SCHEMA = DATABASE()
 ORDER BY TABLE_NAME, CONSTRAINT_TYPE;

-- Result Tab 3: All 10 Active Triggers
SELECT TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_TIMING
  FROM information_schema.TRIGGERS
 WHERE TRIGGER_SCHEMA = DATABASE()
 ORDER BY EVENT_OBJECT_TABLE, ACTION_TIMING;

-- ============================================================================
-- PART 2: POSITIVE WORKFLOWS (AC-01, UC-01, UC-03, AC-13 Historical Price)
-- ============================================================================

-- AC-01: Valid Atomic Registration & 1:1 Payment for User 4 (Dave)
CALL sp_register_and_pay(4, 1, 1, 50.00, 'INV-1001');

-- Enroll User 4 (RegistrationID = 2) into Session 101 and mark CheckedIn by Organizer Bob (User 2)
CALL sp_enroll_session_roster(4, 2, 101);
CALL sp_record_session_checkin(2, 2, 101, 'CheckedIn');

-- AC-13: Organizer updates General Admission price from $50.00 to $75.00;
-- verify existing registrations (Reg 1 & 2) retain AcceptedPrice = $50.00!
SET @current_user_id = 2;
SET @current_user_role = 'Organizer';
UPDATE TICKET_TIER SET Price = 75.00 WHERE TicketID = 1;

-- Result Tab 4: Proof of Atomic Registration & Historical Price Preservation (AC-01 & AC-13)
SELECT r.RegistrationID, u.FirstName, r.Status,
       r.AcceptedPrice AS LockedHistoricalPrice,
       tt.Price AS CurrentCatalogTierPrice,
       p.AmountPaid, p.InvoiceNumber
  FROM REGISTRATION r
  INNER JOIN USER u ON r.AttendeeID = u.UserID
  INNER JOIN TICKET_TIER tt ON r.EventID = tt.EventID AND r.TicketID = tt.TicketID
  INNER JOIN PAYMENT p ON r.RegistrationID = p.RegistrationID
 WHERE r.EventID = 1;

-- ============================================================================
-- PART 3: NEGATIVE, BOUNDARY, ROLLBACK & ENTITLEMENT TESTS (AC-02..AC-16)
-- ============================================================================

DROP TEMPORARY TABLE IF EXISTS test_execution_results;
CREATE TEMPORARY TABLE test_execution_results (
    TestID VARCHAR(15),
    Category VARCHAR(30),
    TestDescription VARCHAR(120),
    Outcome VARCHAR(20),
    CapturedMessage VARCHAR(255)
);

DELIMITER $$
DROP PROCEDURE IF EXISTS sp_run_all_negative_and_resiliency_tests$$
CREATE PROCEDURE sp_run_all_negative_and_resiliency_tests()
BEGIN
    DECLARE v_sqlstate CHAR(5);
    DECLARE v_errno INT;
    DECLARE v_msg TEXT;
    DECLARE v_reg_count_before INT;
    DECLARE v_reg_count_after INT;

    -- Handler captures the expected SQL exception so the demo script continues cleanly
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_sqlstate = RETURNED_SQLSTATE,
            v_errno = MYSQL_ERRNO,
            v_msg = MESSAGE_TEXT;
    END;

    -- 1. AC-02: Duplicate Email Constraint
    SET v_msg = NULL;
    INSERT INTO USER (FirstName, LastName, Email, RoleType)
    VALUES ('Eve', 'Duplicate', 'alice@test.com', 'Attendee');
    INSERT INTO test_execution_results VALUES (
        'AC-02', 'Negative (UNIQUE)', 'Reject duplicate USER.Email (alice@test.com)',
        IF(v_msg IS NOT NULL, 'PASS (Rejected)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 2. TC-02: Venue MaxCapacity <= 0 CHECK Constraint
    SET v_msg = NULL;
    INSERT INTO VENUE (VenueName, Address, MaxCapacity)
    VALUES ('Invalid Hall', '999 Zero Cap Rd', 0);
    INSERT INTO test_execution_results VALUES (
        'TC-02', 'Boundary (CHECK)', 'Reject VENUE with MaxCapacity = 0',
        IF(v_msg IS NOT NULL, 'PASS (Rejected)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 3. TC-03: Ticket Tier Capacity Sum > Venue MaxCapacity Trigger
    SET v_msg = NULL;
    INSERT INTO TICKET_TIER (EventID, TierName, Price, Capacity)
    VALUES (1, 'Oversized Tier', 25.00, 600);
    INSERT INTO test_execution_results VALUES (
        'TC-03', 'Boundary (Trigger)', 'Reject TICKET_TIER exceeding Venue.MaxCapacity (500)',
        IF(v_msg IS NOT NULL, 'PASS (Rejected)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 4. AC-03: Cross-Event Ticket Mismatch (Event 1 with Ticket 4 from Event 2)
    SET v_msg = NULL;
    CALL sp_register_and_pay(4, 1, 4, 75.00, 'INV-CROSS');
    INSERT INTO test_execution_results VALUES (
        'AC-03', 'Negative (Comp FK)', 'Reject registration with TicketID from a different EventID',
        IF(v_msg IS NOT NULL, 'PASS (Rejected)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 5. AC-04: Cross-Event Session Roster Enrollment (Event 1 Reg 2 into Event 2 Session 201)
    SET v_msg = NULL;
    CALL sp_enroll_session_roster(4, 2, 201);
    INSERT INTO test_execution_results VALUES (
        'AC-04', 'Negative (Trigger)', 'Reject SESSION_ROSTER enrollment across different events',
        IF(v_msg IS NOT NULL, 'PASS (Rejected)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 6. AC-06: Duplicate Session Roster Enrollment (Reg 2 into Session 101 again)
    SET v_msg = NULL;
    CALL sp_enroll_session_roster(4, 2, 101);
    INSERT INTO test_execution_results VALUES (
        'AC-06', 'Negative (Comp PK)', 'Reject duplicate (RegistrationID, SessionID) enrollment',
        IF(v_msg IS NOT NULL, 'PASS (Rejected)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 7. AC-09: Resiliency / Atomic Rollback on Payment Amount Mismatch
    SELECT COUNT(*) INTO v_reg_count_before FROM REGISTRATION;
    SET v_msg = NULL;
    CALL sp_register_and_pay(7, 1, 2, 20.00, 'INV-FAIL-ROLLBACK');
    SELECT COUNT(*) INTO v_reg_count_after FROM REGISTRATION;
    INSERT INTO test_execution_results VALUES (
        'AC-09', 'Resiliency (Rollback)',
        CONCAT('Payment mismatch rolls back REGISTRATION (Before=', v_reg_count_before, ', After=', v_reg_count_after, ')'),
        IF(v_msg IS NOT NULL AND v_reg_count_before = v_reg_count_after, 'PASS (Rolled Back)', 'FAIL'),
        COALESCE(v_msg, 'No error raised')
    );

    -- 8. AC-10: Speaker Overlapping Session Interval (Speaker 3 at 09:30-10:30 overlaps 09:00-10:30)
    SET v_msg = NULL;
    CALL sp_schedule_session(2, 1, 3, 'Overlapping Talk', '2026-11-01 09:30:00', '2026-11-01 10:30:00', 30, 'Room 210');
    INSERT INTO test_execution_results VALUES (
        'AC-10', 'Negative (Overlap)', 'Reject scheduling Speaker 3 for overlapping session time',
        IF(v_msg IS NOT NULL, 'PASS (Rejected)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 9. AC-11: Session Outside Parent Event Date Bounds
    SET v_msg = NULL;
    CALL sp_schedule_session(2, 1, 3, 'Out of Bounds Talk', '2026-11-10 09:00:00', '2026-11-10 10:00:00', 30, 'Room 210');
    INSERT INTO test_execution_results VALUES (
        'AC-11', 'Boundary (Dates)', 'Reject session scheduled outside Event StartDate..EndDate',
        IF(v_msg IS NOT NULL, 'PASS (Rejected)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 10. AC-12: Unauthorized Row-Level Cancellation (User 4 tries to cancel User 5's Registration 1)
    SET v_msg = NULL;
    CALL sp_cancel_registration(4, 1, 'Unauthorized attempt by another attendee');
    INSERT INTO test_execution_results VALUES (
        'AC-12', 'Security (Row Owner)', 'Reject Attendee 4 attempting to cancel Attendee 5 registration',
        IF(v_msg IS NOT NULL, 'PASS (Blocked)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 11. AC-14: Unauthorized Check-In Attempt by Attendee (User 4 tries to mark User 5 CheckedIn)
    SET v_msg = NULL;
    CALL sp_record_session_checkin(4, 1, 101, 'CheckedIn');
    INSERT INTO test_execution_results VALUES (
        'AC-14', 'Security (Role/Owner)', 'Reject Attendee attempting to set CheckInStatus = CheckedIn',
        IF(v_msg IS NOT NULL, 'PASS (Blocked)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    -- 12. AC-16: Audit Log Immutability Protection (Admin attempts UPDATE and DELETE on AUDIT_LOG)
    SET v_msg = NULL;
    UPDATE AUDIT_LOG SET Reason = 'Tampered' WHERE LogID = 1;
    INSERT INTO test_execution_results VALUES (
        'AC-16A', 'Governance (Audit)', 'Block UPDATE on append-only AUDIT_LOG table',
        IF(v_msg IS NOT NULL, 'PASS (Blocked)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );

    SET v_msg = NULL;
    DELETE FROM AUDIT_LOG WHERE LogID = 1;
    INSERT INTO test_execution_results VALUES (
        'AC-16B', 'Governance (Audit)', 'Block DELETE on append-only AUDIT_LOG table',
        IF(v_msg IS NOT NULL, 'PASS (Blocked)', 'FAIL'), COALESCE(v_msg, 'No error raised')
    );
END$$
DELIMITER ;

CALL sp_run_all_negative_and_resiliency_tests();

-- Result Tab 5: Automated Test Matrix Results (All 13 Negative, Boundary, Rollback & Security Tests)
SELECT * FROM test_execution_results;

-- ============================================================================
-- PART 4: LIFECYCLE CANCELLATION & RE-REGISTRATION DEMO (AC-05)
-- ============================================================================

-- Cancel User 4's Registration (RegistrationID = 2) and re-register User 4 at the new $75.00 price
CALL sp_cancel_registration(4, 2, 'Attendee requested schedule change');
CALL sp_register_and_pay(4, 1, 1, 75.00, 'INV-1002-REREG');

-- Result Tab 6: Soft Cancellation & Re-Registration Lifecycle (AC-05)
SELECT RegistrationID, AttendeeID, EventID, TicketID, Status, AcceptedPrice, ActiveAttendeeEventKey
  FROM REGISTRATION
 WHERE AttendeeID = 4;

-- ============================================================================
-- PART 5: REPORTING VIEWS (RQ-01..RQ-04) & EXPLAIN PERFORMANCE EVIDENCE (AC-15)
-- ============================================================================

-- Result Tab 7: RQ-01 Event Revenue Summary
SELECT * FROM v_rq01_event_revenue;

-- Result Tab 8: RQ-02 Session Roster Detail
SELECT * FROM v_rq02_session_roster;

-- Result Tab 9: RQ-03 Capacity Utilization Report
SELECT * FROM v_rq03_capacity_utilization;

-- Result Tab 10: RQ-04 Speaker Schedule Report
SELECT * FROM v_rq04_speaker_schedule;

-- Result Tab 11: EXPLAIN Plan 1 — Covering Index Lookup on Capacity Check (idx_reg_ticket_status)
EXPLAIN SELECT COUNT(*) FROM REGISTRATION WHERE TicketID = 1 AND Status = 'Confirmed';

-- Result Tab 12: EXPLAIN Plan 2 — Index Lookup on Session Roster Report (idx_roster_session_status)
EXPLAIN SELECT * FROM v_rq02_session_roster WHERE SessionID = 101;

-- ============================================================================
-- PART 6: AUDIT TRAIL & LIFECYCLE RECONSTRUCTION QUERY (AC-16)
-- ============================================================================

-- Result Tab 13: Immutable Audit Log Chronological Trace
SELECT LogID, ActionTimestamp, ActorUserID, ActorRole, ActionType,
       EntityName, RecordID, OldValue, NewValue, Reason
  FROM AUDIT_LOG
 ORDER BY LogID ASC;
