-- ============================================================================
-- sql/01_schema_ddl.sql (v2.0-release)
-- Core 3NF Relational Schema, Declarative Constraints, Indexes, Views & Roles
-- Incorporating Principles 1, 3, 4, 8, 11 and Professor Audit Resolutions
-- ============================================================================
SET FOREIGN_KEY_CHECKS = 1;
SET UNIQUE_CHECKS = 1;
SET AUTOCOMMIT = 1;
SET SQL_SAFE_UPDATES = 0;


DROP DATABASE IF EXISTS `event_registration`;
CREATE DATABASE `event_registration` 
    CHARACTER SET utf8mb4 
    COLLATE utf8mb4_0900_ai_ci;
USE `event_registration`;

-- ----------------------------------------------------------------------------
-- 1. Metadata & Reference Entities (Principle 8 & Principle 11)
-- ----------------------------------------------------------------------------

-- Principle 8: Schema Version Ledger
CREATE TABLE `SCHEMA_VERSION` (
    `VersionID` INT AUTO_INCREMENT PRIMARY KEY,
    `ReleaseVersion` VARCHAR(20) NOT NULL,
    `ScriptFileName` VARCHAR(120) NOT NULL,
    `GitCommitSHA` VARCHAR(40) NULL,
    `AppliedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `AppliedBy` VARCHAR(100) NOT NULL DEFAULT (CURRENT_USER()),
    `ExecutionTimeMs` INT NOT NULL,
    `Status` ENUM('SUCCESS', 'FAILED') NOT NULL,
    `Description` VARCHAR(255) NULL,
    UNIQUE KEY `uq_schema_release` (`ReleaseVersion`, `ScriptFileName`)
) ENGINE=InnoDB COMMENT='Principle 8: In-database schema migration audit trail';

INSERT INTO `SCHEMA_VERSION` (`ReleaseVersion`, `ScriptFileName`, `ExecutionTimeMs`, `Status`, `Description`)
VALUES ('v2.0.0', '01_schema_ddl.sql', 85, 'SUCCESS', 'Base schema with metadata-driven indicators & workflow tables');

-- Principle 11: Unified Indicator Value Pattern (No Hard-Coded Enums)
CREATE TABLE `INDICATOR_VALUE` (
    `IndicatorName` VARCHAR(50) NOT NULL,
    `IndicatorCode` VARCHAR(30) NOT NULL,
    `DisplayLabel` VARCHAR(100) NOT NULL,
    `DisplayOrder` INT NOT NULL DEFAULT 1,
    `IsActive` BOOLEAN NOT NULL DEFAULT TRUE,
    `CreatedTimestamp` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`IndicatorName`, `IndicatorCode`),
    INDEX `idx_indicator_query` (`IndicatorName`, `IsActive`, `DisplayOrder`)
) ENGINE=InnoDB COMMENT='Principle 11: Coded domain indicator values';

INSERT INTO `INDICATOR_VALUE` (`IndicatorName`, `IndicatorCode`, `DisplayLabel`, `DisplayOrder`) VALUES
('ROLE_TYPE', 'Admin', 'System Administrator', 1),
('ROLE_TYPE', 'Organizer', 'Event Organizer', 2),
('ROLE_TYPE', 'Speaker', 'Keynote / Speaker', 3),
('ROLE_TYPE', 'Attendee', 'General Attendee', 4),

('REG_STATUS', 'Confirmed', 'Registration Confirmed', 1),
('REG_STATUS', 'Cancelled', 'Registration Cancelled', 2),
('REG_STATUS', 'Waitlisted', 'Waitlisted Position', 3),

('CHECKIN_STATUS', 'Enrolled', 'Enrolled in Session', 1),
('CHECKIN_STATUS', 'CheckedIn', 'Checked In at Venue', 2),
('CHECKIN_STATUS', 'NoShow', 'No-Show / Absent', 3),
('CHECKIN_STATUS', 'Cancelled', 'Session Enrollment Cancelled', 4),

('ACTION_TYPE', 'INSERT', 'Record Created', 1),
('ACTION_TYPE', 'UPDATE', 'Record Updated', 2),
('ACTION_TYPE', 'DELETE', 'Record Deleted', 3),
('ACTION_TYPE', 'STATUS_CHANGE', 'Lifecycle Status Change', 4),
('ACTION_TYPE', 'ADMIN_OVERRIDE', 'Administrative Override', 5);

-- Principle 4: Metadata-Driven Workflow Transitions
CREATE TABLE `WORKFLOW_TRANSITION` (
    `WorkflowName` VARCHAR(60) NOT NULL,
    `FromState` VARCHAR(60) NOT NULL,
    `ToState` VARCHAR(60) NOT NULL,
    `AllowedRole` VARCHAR(30) NOT NULL,
    PRIMARY KEY (`WorkflowName`, `FromState`, `ToState`, `AllowedRole`)
) ENGINE=InnoDB COMMENT='Principle 4: Workflow state machine metadata';

INSERT INTO `WORKFLOW_TRANSITION` (`WorkflowName`, `FromState`, `ToState`, `AllowedRole`) VALUES
('SESSION_CHECKIN', 'Enrolled', 'CheckedIn', 'Organizer'),
('SESSION_CHECKIN', 'Enrolled', 'CheckedIn', 'Admin'),
('SESSION_CHECKIN', 'Enrolled', 'NoShow', 'Organizer'),
('SESSION_CHECKIN', 'Enrolled', 'NoShow', 'Admin'),
('SESSION_CHECKIN', 'CheckedIn', 'Enrolled', 'Admin'),
('SESSION_CHECKIN', 'NoShow', 'Enrolled', 'Admin');

-- ----------------------------------------------------------------------------
-- 2. Core Operational Entities (3NF Normalized, MySQL Keywords Escaped)
-- ----------------------------------------------------------------------------

CREATE TABLE `USER` (
    `UserID` INT AUTO_INCREMENT PRIMARY KEY,
    `FirstName` VARCHAR(50) NOT NULL,
    `LastName` VARCHAR(50) NOT NULL,
    `Email` VARCHAR(100) NOT NULL,
    `RoleType` VARCHAR(30) NOT NULL,
    `IsActive` BOOLEAN NOT NULL DEFAULT TRUE,
    `CreatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `RoleType_Ind` VARCHAR(50) GENERATED ALWAYS AS ('ROLE_TYPE') STORED,
    CONSTRAINT `uq_user_email` UNIQUE (`Email`),
    CONSTRAINT `chk_user_email_fmt` CHECK (`Email` LIKE '%_@__%.__%'),
    CONSTRAINT `fk_user_role_indicator` FOREIGN KEY (`RoleType_Ind`, `RoleType`)
        REFERENCES `INDICATOR_VALUE` (`IndicatorName`, `IndicatorCode`)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE `VENUE` (
    `VenueID` INT AUTO_INCREMENT PRIMARY KEY,
    `VenueName` VARCHAR(100) NOT NULL,
    `Address` VARCHAR(255) NOT NULL,
    `MaxCapacity` INT NOT NULL,
    CONSTRAINT `uq_venue_name_addr` UNIQUE (`VenueName`, `Address`),
    CONSTRAINT `chk_venue_cap` CHECK (`MaxCapacity` > 0)
) ENGINE=InnoDB;

CREATE TABLE `EVENT` (
    `EventID` INT AUTO_INCREMENT PRIMARY KEY,
    `OrganizerID` INT NOT NULL,
    `VenueID` INT NOT NULL,
    `EventName` VARCHAR(150) NOT NULL,
    `StartDate` DATE NOT NULL,
    `EndDate` DATE NOT NULL,
    CONSTRAINT `fk_event_organizer` FOREIGN KEY (`OrganizerID`)
        REFERENCES `USER` (`UserID`) ON DELETE RESTRICT,
    CONSTRAINT `fk_event_venue` FOREIGN KEY (`VenueID`)
        REFERENCES `VENUE` (`VenueID`) ON DELETE RESTRICT,
    CONSTRAINT `chk_event_dates` CHECK (`StartDate` <= `EndDate`)
) ENGINE=InnoDB;

CREATE TABLE `TICKET_TIER` (
    `TicketID` INT AUTO_INCREMENT PRIMARY KEY,
    `EventID` INT NOT NULL,
    `TierName` VARCHAR(50) NOT NULL,
    `Price` DECIMAL(10,2) NOT NULL,
    `Capacity` INT NOT NULL,
    CONSTRAINT `fk_tier_event` FOREIGN KEY (`EventID`)
        REFERENCES `EVENT` (`EventID`) ON DELETE RESTRICT,
    CONSTRAINT `uq_tier_event_ticket` UNIQUE (`EventID`, `TicketID`),
    CONSTRAINT `uq_tier_event_name` UNIQUE (`EventID`, `TierName`),
    CONSTRAINT `chk_tier_price` CHECK (`Price` >= 0.00),
    CONSTRAINT `chk_tier_cap` CHECK (`Capacity` > 0)
) ENGINE=InnoDB;

CREATE TABLE `SESSION` (
    `SessionID` INT AUTO_INCREMENT PRIMARY KEY,
    `EventID` INT NOT NULL,
    `SpeakerID` INT NOT NULL,
    `SessionTitle` VARCHAR(150) NOT NULL,
    `StartDateTime` DATETIME NOT NULL,
    `EndDateTime` DATETIME NOT NULL,
    `SessionCapacity` INT NOT NULL,
    `RoomNumber` VARCHAR(30) NOT NULL,
    CONSTRAINT `fk_session_event` FOREIGN KEY (`EventID`)
        REFERENCES `EVENT` (`EventID`) ON DELETE RESTRICT,
    CONSTRAINT `fk_session_speaker` FOREIGN KEY (`SpeakerID`)
        REFERENCES `USER` (`UserID`) ON DELETE RESTRICT,
    CONSTRAINT `uq_session_event_session` UNIQUE (`EventID`, `SessionID`),
    CONSTRAINT `chk_sess_time` CHECK (`StartDateTime` < `EndDateTime`),
    CONSTRAINT `chk_sess_cap` CHECK (`SessionCapacity` > 0)
) ENGINE=InnoDB;

CREATE TABLE `REGISTRATION` (
    `RegistrationID` INT AUTO_INCREMENT PRIMARY KEY,
    `AttendeeID` INT NOT NULL,
    `EventID` INT NOT NULL,
    `TicketID` INT NOT NULL,
    `RegistrationDate` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `Status` VARCHAR(30) NOT NULL DEFAULT 'Confirmed',
    `AcceptedPrice` DECIMAL(10,2) NOT NULL,
    `ActiveAttendeeEventKey` INT GENERATED ALWAYS AS (
        CASE WHEN `Status` = 'Confirmed' THEN `AttendeeID` ELSE NULL END
    ) STORED,
    `Status_Ind` VARCHAR(50) GENERATED ALWAYS AS ('REG_STATUS') STORED,
    CONSTRAINT `fk_reg_attendee` FOREIGN KEY (`AttendeeID`)
        REFERENCES `USER` (`UserID`) ON DELETE RESTRICT,
    CONSTRAINT `fk_reg_event` FOREIGN KEY (`EventID`)
        REFERENCES `EVENT` (`EventID`) ON DELETE RESTRICT,
    CONSTRAINT `fk_reg_event_ticket` FOREIGN KEY (`EventID`, `TicketID`)
        REFERENCES `TICKET_TIER` (`EventID`, `TicketID`) ON DELETE RESTRICT,
    CONSTRAINT `fk_reg_status_indicator` FOREIGN KEY (`Status_Ind`, `Status`)
        REFERENCES `INDICATOR_VALUE` (`IndicatorName`, `IndicatorCode`)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT `uq_reg_active_attendee_event` UNIQUE (`ActiveAttendeeEventKey`, `EventID`)
) ENGINE=InnoDB;

CREATE TABLE `PAYMENT` (
    `PaymentID` INT AUTO_INCREMENT PRIMARY KEY,
    `RegistrationID` INT NOT NULL,
    `AmountPaid` DECIMAL(10,2) NOT NULL,
    `DiscountApplied` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    `PaymentDate` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `InvoiceNumber` VARCHAR(60) NOT NULL,
    CONSTRAINT `fk_pay_registration` FOREIGN KEY (`RegistrationID`)
        REFERENCES `REGISTRATION` (`RegistrationID`) ON DELETE RESTRICT,
    CONSTRAINT `uq_payment_registration` UNIQUE (`RegistrationID`),
    CONSTRAINT `uq_payment_invoice` UNIQUE (`InvoiceNumber`),
    CONSTRAINT `chk_pay_amount` CHECK (`AmountPaid` >= 0.00)
) ENGINE=InnoDB;

CREATE TABLE `SESSION_ROSTER` (
    `RegistrationID` INT NOT NULL,
    `SessionID` INT NOT NULL,
    `CheckInStatus` VARCHAR(30) NOT NULL DEFAULT 'Enrolled',
    `EnrolledAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `CheckIn_Ind` VARCHAR(50) GENERATED ALWAYS AS ('CHECKIN_STATUS') STORED,
    PRIMARY KEY (`RegistrationID`, `SessionID`),
    CONSTRAINT `fk_roster_reg` FOREIGN KEY (`RegistrationID`)
        REFERENCES `REGISTRATION` (`RegistrationID`) ON DELETE RESTRICT,
    CONSTRAINT `fk_roster_session` FOREIGN KEY (`SessionID`)
        REFERENCES `SESSION` (`SessionID`) ON DELETE RESTRICT,
    CONSTRAINT `fk_roster_status_indicator` FOREIGN KEY (`CheckIn_Ind`, `CheckInStatus`)
        REFERENCES `INDICATOR_VALUE` (`IndicatorName`, `IndicatorCode`)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE `AUDIT_LOG` (
    `LogID` INT AUTO_INCREMENT PRIMARY KEY,
    `SystemUser` VARCHAR(100) NOT NULL DEFAULT (CURRENT_USER()),
    `ActorUserID` INT NULL,
    `ActorRole` VARCHAR(30) NOT NULL,
    `ActionTimestamp` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `ActionType` VARCHAR(30) NOT NULL,
    `EntityName` VARCHAR(60) NOT NULL,
    `RecordID` VARCHAR(60) NOT NULL,
    `OldValue` TEXT NULL,
    `NewValue` TEXT NULL,
    `Reason` VARCHAR(255) NULL,
    `Action_Ind` VARCHAR(50) GENERATED ALWAYS AS ('ACTION_TYPE') STORED,
    CONSTRAINT `fk_audit_user` FOREIGN KEY (`ActorUserID`)
        REFERENCES `USER` (`UserID`) ON DELETE RESTRICT,
    CONSTRAINT `fk_audit_action_indicator` FOREIGN KEY (`Action_Ind`, `ActionType`)
        REFERENCES `INDICATOR_VALUE` (`IndicatorName`, `IndicatorCode`)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB COMMENT='Principle 2: Append-only immutable audit ledger';

-- ----------------------------------------------------------------------------
-- 3. Secondary Performance Indexes
-- ----------------------------------------------------------------------------

CREATE INDEX `idx_event_startdate_org` ON `EVENT` (`StartDate`, `OrganizerID`);
CREATE INDEX `idx_session_speaker_interval` ON `SESSION` (`SpeakerID`, `StartDateTime`, `EndDateTime`);
CREATE INDEX `idx_reg_ticket_status` ON `REGISTRATION` (`TicketID`, `Status`);
CREATE INDEX `idx_reg_event_status` ON `REGISTRATION` (`EventID`, `Status`);
CREATE INDEX `idx_roster_session_status` ON `SESSION_ROSTER` (`SessionID`, `CheckInStatus`);
CREATE INDEX `idx_audit_entity_record` ON `AUDIT_LOG` (`EntityName`, `RecordID`);

-- ----------------------------------------------------------------------------
-- 4. Context Resolution Functions & Views
-- ----------------------------------------------------------------------------

DELIMITER $$
DROP FUNCTION IF EXISTS `fn_current_user_id`$$
CREATE FUNCTION `fn_current_user_id`()
RETURNS INT
DETERMINISTIC NO SQL
COMMENT 'Version: 2.0.0 | Principle 3 Session Actor Resolution'
BEGIN
    RETURN @current_user_id;
END$$

DROP FUNCTION IF EXISTS `fn_current_user_role`$$
CREATE FUNCTION `fn_current_user_role`()
RETURNS VARCHAR(30)
DETERMINISTIC NO SQL
COMMENT 'Version: 2.0.0 | Principle 3 Session Role Resolution'
BEGIN
    RETURN COALESCE(@current_user_role, 'Anonymous');
END$$
DELIMITER ;

CREATE OR REPLACE VIEW `v_public_event_catalog` AS
SELECT e.EventID, e.EventName, e.StartDate, e.EndDate,
       v.VenueName, v.Address, v.MaxCapacity,
       tt.TicketID, tt.TierName, tt.Price, tt.Capacity
FROM `EVENT` e
INNER JOIN `VENUE` v ON e.VenueID = v.VenueID
INNER JOIN `TICKET_TIER` tt ON e.EventID = tt.EventID;

CREATE OR REPLACE VIEW `v_attendee_own_registrations` AS
SELECT r.RegistrationID, r.AttendeeID, r.EventID, e.EventName,
       r.TicketID, tt.TierName, r.RegistrationDate, r.Status,
       r.AcceptedPrice, p.PaymentID, p.AmountPaid, p.PaymentDate, p.InvoiceNumber
FROM `REGISTRATION` r
INNER JOIN `EVENT` e ON r.EventID = e.EventID
INNER JOIN `TICKET_TIER` tt ON r.EventID = tt.EventID AND r.TicketID = tt.TicketID
LEFT JOIN `PAYMENT` p ON r.RegistrationID = p.RegistrationID
WHERE r.AttendeeID = fn_current_user_id();

CREATE OR REPLACE VIEW `v_organizer_event_registrations` AS
SELECT e.EventID, e.EventName, e.OrganizerID,
       r.RegistrationID, r.Status, r.AcceptedPrice, r.RegistrationDate,
       u.UserID AS AttendeeID, u.FirstName, u.LastName, u.Email,
       p.PaymentID, p.AmountPaid, p.InvoiceNumber
FROM `EVENT` e
INNER JOIN `REGISTRATION` r ON e.EventID = r.EventID
INNER JOIN `USER` u ON r.AttendeeID = u.UserID
LEFT JOIN `PAYMENT` p ON r.RegistrationID = p.RegistrationID
WHERE e.OrganizerID = fn_current_user_id();

CREATE OR REPLACE VIEW `v_speaker_session_roster` AS
SELECT s.SessionID, s.SessionTitle, s.StartDateTime, s.EndDateTime, s.RoomNumber,
       sr.RegistrationID, u.FirstName, u.LastName, sr.CheckInStatus
FROM `SESSION` s
INNER JOIN `SESSION_ROSTER` sr ON s.SessionID = sr.SessionID
INNER JOIN `REGISTRATION` r ON sr.RegistrationID = r.RegistrationID
INNER JOIN `USER` u ON r.AttendeeID = u.UserID
WHERE s.SpeakerID = fn_current_user_id()
  AND r.Status = 'Confirmed';

CREATE OR REPLACE VIEW `v_ui_indicator_options` AS
SELECT `IndicatorName`, `IndicatorCode` AS `OptionValue`, `DisplayLabel` AS `OptionText`, `DisplayOrder`
FROM `INDICATOR_VALUE`
WHERE `IsActive` = TRUE
ORDER BY `IndicatorName` ASC, `DisplayOrder` ASC;

CREATE OR REPLACE VIEW `v_rq01_event_revenue` AS
SELECT
    e.EventID, e.EventName, e.StartDate, e.EndDate, e.OrganizerID,
    COUNT(DISTINCT CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END) AS ConfirmedRegistrations,
    COUNT(DISTINCT CASE WHEN r.Status = 'Cancelled' THEN r.RegistrationID END) AS CancelledRegistrations,
    COALESCE(SUM(CASE WHEN r.Status = 'Confirmed' THEN p.AmountPaid ELSE 0.00 END), 0.00) AS GrossRecordedRevenue
FROM `EVENT` e
LEFT JOIN `REGISTRATION` r ON e.EventID = r.EventID
LEFT JOIN `PAYMENT` p ON r.RegistrationID = p.RegistrationID
GROUP BY e.EventID, e.EventName, e.StartDate, e.EndDate, e.OrganizerID;

CREATE OR REPLACE VIEW `v_rq02_session_roster` AS
SELECT
    s.SessionID, s.SessionTitle, s.StartDateTime, s.EndDateTime, s.EventID, s.SpeakerID,
    r.RegistrationID, u.UserID, u.FirstName, u.LastName, u.Email,
    tt.TierName, sr.CheckInStatus
FROM `SESSION` s
INNER JOIN `SESSION_ROSTER` sr ON s.SessionID = sr.SessionID
INNER JOIN `REGISTRATION` r ON sr.RegistrationID = r.RegistrationID
INNER JOIN `USER` u ON r.AttendeeID = u.UserID
INNER JOIN `TICKET_TIER` tt ON r.EventID = tt.EventID AND r.TicketID = tt.TicketID
WHERE r.Status = 'Confirmed';

CREATE OR REPLACE VIEW `v_rq03_capacity_utilization` AS
SELECT
    e.EventID, e.EventName, 'TicketTier' AS ResourceType,
    tt.TicketID AS ResourceID, tt.TierName AS ResourceName,
    tt.Capacity AS ConfiguredCapacity,
    COUNT(CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END) AS ActiveConfirmedCount,
    (tt.Capacity - COUNT(CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END)) AS RemainingSeats,
    ROUND((COUNT(CASE WHEN r.Status = 'Confirmed' THEN r.RegistrationID END) / tt.Capacity) * 100, 2) AS UtilizationPct
FROM `EVENT` e
INNER JOIN `TICKET_TIER` tt ON e.EventID = tt.EventID
LEFT JOIN `REGISTRATION` r ON tt.EventID = r.EventID AND tt.TicketID = r.TicketID
GROUP BY e.EventID, e.EventName, tt.TicketID, tt.TierName, tt.Capacity
UNION ALL
SELECT
    e.EventID, e.EventName, 'Session' AS ResourceType,
    s.SessionID AS ResourceID, s.SessionTitle AS ResourceName,
    s.SessionCapacity AS ConfiguredCapacity,
    COUNT(CASE WHEN r.Status = 'Confirmed' THEN sr.RegistrationID END) AS ActiveConfirmedCount,
    (s.SessionCapacity - COUNT(CASE WHEN r.Status = 'Confirmed' THEN sr.RegistrationID END)) AS RemainingSeats,
    ROUND((COUNT(CASE WHEN r.Status = 'Confirmed' THEN sr.RegistrationID END) / s.SessionCapacity) * 100, 2) AS UtilizationPct
FROM `EVENT` e
INNER JOIN `SESSION` s ON e.EventID = s.EventID
LEFT JOIN `SESSION_ROSTER` sr ON s.SessionID = sr.SessionID
LEFT JOIN `REGISTRATION` r ON sr.RegistrationID = r.RegistrationID
GROUP BY e.EventID, e.EventName, s.SessionID, s.SessionTitle, s.SessionCapacity;

CREATE OR REPLACE VIEW `v_rq04_speaker_schedule` AS
SELECT
    u.UserID AS SpeakerID, u.FirstName, u.LastName,
    e.EventID, e.EventName, v.VenueName,
    s.SessionID, s.SessionTitle, s.RoomNumber, s.StartDateTime, s.EndDateTime, s.SessionCapacity,
    COUNT(CASE WHEN r.Status = 'Confirmed' THEN sr.RegistrationID END) AS EnrolledCount
FROM `USER` u
INNER JOIN `SESSION` s ON u.UserID = s.SpeakerID
INNER JOIN `EVENT` e ON s.EventID = e.EventID
INNER JOIN `VENUE` v ON e.VenueID = v.VenueID
LEFT JOIN `SESSION_ROSTER` sr ON s.SessionID = sr.SessionID
LEFT JOIN `REGISTRATION` r ON sr.RegistrationID = r.RegistrationID
GROUP BY u.UserID, u.FirstName, u.LastName, e.EventID, e.EventName, v.VenueName,
         s.SessionID, s.SessionTitle, s.RoomNumber, s.StartDateTime, s.EndDateTime, s.SessionCapacity;

-- ----------------------------------------------------------------------------
-- 5. Role Definitions and Least-Privilege Grants
-- ----------------------------------------------------------------------------

CREATE ROLE IF NOT EXISTS 'role_admin', 'role_organizer', 'role_speaker', 'role_attendee';

GRANT SELECT ON `v_public_event_catalog` TO 'role_attendee', 'role_speaker', 'role_organizer', 'role_admin';
GRANT SELECT ON `v_ui_indicator_options` TO 'role_attendee', 'role_speaker', 'role_organizer', 'role_admin';
GRANT SELECT ON `v_attendee_own_registrations` TO 'role_attendee';
GRANT SELECT ON `v_organizer_event_registrations` TO 'role_organizer';
GRANT SELECT ON `v_speaker_session_roster` TO 'role_speaker';
GRANT SELECT ON `AUDIT_LOG` TO 'role_admin';
GRANT SELECT ON `v_rq01_event_revenue` TO 'role_organizer', 'role_admin';
GRANT SELECT ON `v_rq02_session_roster` TO 'role_organizer', 'role_speaker', 'role_admin';
GRANT SELECT ON `v_rq03_capacity_utilization` TO 'role_organizer', 'role_admin';
GRANT SELECT ON `v_rq04_speaker_schedule` TO 'role_organizer', 'role_admin';
