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
