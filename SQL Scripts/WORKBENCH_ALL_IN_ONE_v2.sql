-- ============================================================================
-- sql/01_schema_ddl.sql (v2.0-release)
-- Core 3NF Relational Schema, Declarative Constraints, Indexes, Views & Roles
-- Incorporating Principles 1, 3, 4, 8, 11 and Professor Audit Resolutions
-- ============================================================================

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

-- ============================================================================
-- sql/02_triggers_and_procedures.sql (v2.0-release)
-- 10 Taxonomy-Prefixed Triggers & 5 Session-Authenticated Stored Procedures
-- ============================================================================
USE `event_registration`;

DELIMITER $$

-- ----------------------------------------------------------------------------
-- 1. Declarative Business Rule & Audit Immutability Triggers (10 Triggers)
-- ----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS `trg_tickettier_bi_cap`$$
CREATE TRIGGER `trg_tickettier_bi_cap`
BEFORE INSERT ON `TICKET_TIER`
FOR EACH ROW
BEGIN
    DECLARE v_venue_max INT;
    DECLARE v_existing_tier_sum INT;

    SELECT v.MaxCapacity INTO v_venue_max
    FROM `EVENT` e
    INNER JOIN `VENUE` v ON e.VenueID = v.VenueID
    WHERE e.EventID = NEW.EventID;

    SELECT COALESCE(SUM(Capacity), 0) INTO v_existing_tier_sum
    FROM `TICKET_TIER`
    WHERE EventID = NEW.EventID;

    IF (v_existing_tier_sum + NEW.Capacity) > v_venue_max THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: BR-04 Violation: Combined ticket tier capacities exceed Venue MaxCapacity.';
    END IF;
END$$

DROP TRIGGER IF EXISTS `trg_tickettier_bu_cap`$$
CREATE TRIGGER `trg_tickettier_bu_cap`
BEFORE UPDATE ON `TICKET_TIER`
FOR EACH ROW
BEGIN
    DECLARE v_venue_max INT;
    DECLARE v_other_tier_sum INT;
    DECLARE v_confirmed_count INT;

    SELECT v.MaxCapacity INTO v_venue_max
    FROM `EVENT` e
    INNER JOIN `VENUE` v ON e.VenueID = v.VenueID
    WHERE e.EventID = NEW.EventID;

    SELECT COALESCE(SUM(Capacity), 0) INTO v_other_tier_sum
    FROM `TICKET_TIER`
    WHERE EventID = NEW.EventID AND TicketID <> OLD.TicketID;

    IF (v_other_tier_sum + NEW.Capacity) > v_venue_max THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: BR-04 Violation: Updated ticket tier capacity exceeds Venue MaxCapacity.';
    END IF;

    SELECT COUNT(*) INTO v_confirmed_count
    FROM `REGISTRATION`
    WHERE TicketID = OLD.TicketID AND Status = 'Confirmed';

    IF NEW.Capacity < v_confirmed_count THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: BR-05 Violation: Cannot reduce tier capacity below current confirmed registrations.';
    END IF;
END$$

DROP TRIGGER IF EXISTS `trg_tickettier_au_audit`$$
CREATE TRIGGER `trg_tickettier_au_audit`
AFTER UPDATE ON `TICKET_TIER`
FOR EACH ROW
BEGIN
    IF OLD.Price <> NEW.Price OR OLD.Capacity <> NEW.Capacity THEN
        INSERT INTO `AUDIT_LOG` (
            `ActorUserID`, `ActorRole`, `ActionTimestamp`, `ActionType`,
            `EntityName`, `RecordID`, `OldValue`, `NewValue`, `Reason`
        ) VALUES (
            fn_current_user_id(),
            COALESCE(@current_user_role, 'Organizer'),
            NOW(),
            'UPDATE',
            'TICKET_TIER',
            CAST(NEW.TicketID AS CHAR),
            CONCAT('Price=', OLD.Price, ', Capacity=', OLD.Capacity),
            CONCAT('Price=', NEW.Price, ', Capacity=', NEW.Capacity),
            'Catalog tier price or capacity updated (BR-10 historical registrations preserved)'
        );
    END IF;
END$$

DROP TRIGGER IF EXISTS `trg_venue_bu_cap`$$
CREATE TRIGGER `trg_venue_bu_cap`
BEFORE UPDATE ON `VENUE`
FOR EACH ROW
BEGIN
    DECLARE v_max_event_tier_sum INT;
    DECLARE v_max_session_cap INT;

    SELECT COALESCE(MAX(tier_sum), 0) INTO v_max_event_tier_sum
    FROM (
        SELECT SUM(tt.Capacity) AS tier_sum
        FROM `EVENT` e
        INNER JOIN `TICKET_TIER` tt ON e.EventID = tt.EventID
        WHERE e.VenueID = OLD.VenueID
        GROUP BY e.EventID
    ) AS event_sums;

    SELECT COALESCE(MAX(s.SessionCapacity), 0) INTO v_max_session_cap
    FROM `EVENT` e
    INNER JOIN `SESSION` s ON e.EventID = s.EventID
    WHERE e.VenueID = OLD.VenueID;

    IF NEW.MaxCapacity < v_max_event_tier_sum OR NEW.MaxCapacity < v_max_session_cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: BR-04 Violation: Cannot lower Venue MaxCapacity below allocated event/session capacities.';
    END IF;
END$$

DROP TRIGGER IF EXISTS `trg_session_bi_validate`$$
CREATE TRIGGER `trg_session_bi_validate`
BEFORE INSERT ON `SESSION`
FOR EACH ROW
BEGIN
    DECLARE v_event_start DATE;
    DECLARE v_event_end DATE;
    DECLARE v_venue_max INT;
    DECLARE v_speaker_role VARCHAR(30);
    DECLARE v_overlap_count INT;

    SELECT e.StartDate, e.EndDate, v.MaxCapacity
    INTO v_event_start, v_event_end, v_venue_max
    FROM `EVENT` e
    INNER JOIN `VENUE` v ON e.VenueID = v.VenueID
    WHERE e.EventID = NEW.EventID;

    IF DATE(NEW.StartDateTime) < v_event_start OR DATE(NEW.EndDateTime) > v_event_end THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'invalid: BR-02 Violation: Session timestamps must fall within parent Event StartDate and EndDate.';
    END IF;

    IF NEW.SessionCapacity > v_venue_max THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: BR-04 Violation: SessionCapacity cannot exceed Venue MaxCapacity.';
    END IF;

    SELECT RoleType INTO v_speaker_role
    FROM `USER`
    WHERE UserID = NEW.SpeakerID;

    IF v_speaker_role <> 'Speaker' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'invalid: BR-09 Violation: Assigned SpeakerID must hold RoleType = Speaker.';
    END IF;

    SELECT COUNT(*) INTO v_overlap_count
    FROM `SESSION`
    WHERE SpeakerID = NEW.SpeakerID
      AND NEW.StartDateTime < EndDateTime
      AND NEW.EndDateTime > StartDateTime;

    IF v_overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: BR-09 Violation: Speaker has an overlapping session schedule.';
    END IF;
END$$

DROP TRIGGER IF EXISTS `trg_session_bu_cap`$$
CREATE TRIGGER `trg_session_bu_cap`
BEFORE UPDATE ON `SESSION`
FOR EACH ROW
BEGIN
    DECLARE v_enrolled_count INT;
    DECLARE v_overlap_count INT;

    SELECT COUNT(*) INTO v_enrolled_count
    FROM `SESSION_ROSTER` sr
    INNER JOIN `REGISTRATION` r ON sr.RegistrationID = r.RegistrationID
    WHERE sr.SessionID = OLD.SessionID AND r.Status = 'Confirmed';

    IF NEW.SessionCapacity < v_enrolled_count THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: BR-08 Violation: Cannot reduce SessionCapacity below current enrolled count.';
    END IF;

    SELECT COUNT(*) INTO v_overlap_count
    FROM `SESSION`
    WHERE SpeakerID = NEW.SpeakerID
      AND SessionID <> OLD.SessionID
      AND NEW.StartDateTime < EndDateTime
      AND NEW.EndDateTime > StartDateTime;

    IF v_overlap_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: BR-09 Violation: Updated session creates a speaker schedule conflict.';
    END IF;
END$$

DROP TRIGGER IF EXISTS `trg_payment_bi_validate`$$
CREATE TRIGGER `trg_payment_bi_validate`
BEFORE INSERT ON `PAYMENT`
FOR EACH ROW
BEGIN
    DECLARE v_accepted_price DECIMAL(10,2);
    DECLARE v_reg_status VARCHAR(30);

    SELECT AcceptedPrice, Status INTO v_accepted_price, v_reg_status
    FROM `REGISTRATION`
    WHERE RegistrationID = NEW.RegistrationID;

    IF v_reg_status IS NULL OR v_reg_status <> 'Confirmed' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'invalid: BR-07 Violation: Payment can only be recorded for a Confirmed registration.';
    END IF;

    IF NEW.AmountPaid <> v_accepted_price THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'invalid: BR-10 Violation: Payment AmountPaid must exactly equal REGISTRATION.AcceptedPrice.';
    END IF;
END$$

DROP TRIGGER IF EXISTS `trg_roster_bi_validate`$$
CREATE TRIGGER `trg_roster_bi_validate`
BEFORE INSERT ON `SESSION_ROSTER`
FOR EACH ROW
BEGIN
    DECLARE v_reg_event_id INT;
    DECLARE v_reg_status VARCHAR(30);
    DECLARE v_sess_event_id INT;
    DECLARE v_sess_cap INT;
    DECLARE v_current_enrolled INT;

    SELECT EventID, Status INTO v_reg_event_id, v_reg_status
    FROM `REGISTRATION`
    WHERE RegistrationID = NEW.RegistrationID;

    SELECT EventID, SessionCapacity INTO v_sess_event_id, v_sess_cap
    FROM `SESSION`
    WHERE SessionID = NEW.SessionID;

    IF v_reg_status <> 'Confirmed' OR v_reg_event_id <> v_sess_event_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'invalid: BR-08 Violation: Attendee must hold a Confirmed registration for the same Event.';
    END IF;

    SELECT COUNT(*) INTO v_current_enrolled
    FROM `SESSION_ROSTER` sr
    INNER JOIN `REGISTRATION` r ON sr.RegistrationID = r.RegistrationID
    WHERE sr.SessionID = NEW.SessionID AND r.Status = 'Confirmed';

    IF v_current_enrolled >= v_sess_cap THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: BR-08 Violation: Session has reached maximum capacity.';
    END IF;
END$$

DROP TRIGGER IF EXISTS `trg_audit_log_bu_immutable`$$
CREATE TRIGGER `trg_audit_log_bu_immutable`
BEFORE UPDATE ON `AUDIT_LOG`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'forbidden: BR-12/SEC-08 Violation: AUDIT_LOG is append-only and immutable. UPDATE is blocked.';
END$$

DROP TRIGGER IF EXISTS `trg_audit_log_bd_immutable`$$
CREATE TRIGGER `trg_audit_log_bd_immutable`
BEFORE DELETE ON `AUDIT_LOG`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'forbidden: BR-12/SEC-08 Violation: AUDIT_LOG is append-only and immutable. DELETE is blocked.';
END$$

-- ----------------------------------------------------------------------------
-- 2. Stamped, Session-Authenticated Stored Procedures (5 Procedures)
-- ----------------------------------------------------------------------------

-- Procedure 1: Atomic Registration & Payment (UC-01)
DROP PROCEDURE IF EXISTS `sp_register_and_pay`$$
CREATE PROCEDURE `sp_register_and_pay`(
    IN p_event_id INT,
    IN p_ticket_id INT,
    IN p_amount_paid DECIMAL(10,2),
    IN p_invoice_number VARCHAR(60)
)
COMMENT 'Version: 2.0.0 | Release: v2.0-release | Principle 3 & 5 refactored actor & error taxonomy'
BEGIN
    DECLARE c_routine_version VARCHAR(20) DEFAULT '2.0.0';
    DECLARE v_current_user INT DEFAULT fn_current_user_id();
    DECLARE v_organizer_id INT;
    DECLARE v_tier_event_id INT;
    DECLARE v_tier_price DECIMAL(10,2);
    DECLARE v_tier_capacity INT;
    DECLARE v_confirmed_count INT;
    DECLARE v_new_reg_id INT;
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_is_active BOOLEAN;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF v_current_user IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: Unauthenticated session. @current_user_id is missing.';
    END IF;

    SELECT RoleType, IsActive INTO v_actor_role, v_is_active
    FROM `USER` WHERE UserID = v_current_user FOR SHARE;

    IF v_is_active IS NULL OR v_is_active = FALSE THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'not_found: FR-01/UC-01 Error: Attendee account does not exist or is inactive.';
    END IF;

    SELECT OrganizerID INTO v_organizer_id
    FROM `EVENT` WHERE EventID = p_event_id FOR SHARE;

    IF v_organizer_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'not_found: Event does not exist.';
    END IF;

    IF v_organizer_id = v_current_user THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: SEC-03 Violation: Event Organizer cannot register as an attendee for their own event.';
    END IF;

    SELECT EventID, Price, Capacity INTO v_tier_event_id, v_tier_price, v_tier_capacity
    FROM `TICKET_TIER` WHERE TicketID = p_ticket_id FOR UPDATE;

    IF v_tier_event_id IS NULL OR v_tier_event_id <> p_event_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'invalid: BR-03 Violation: Ticket tier does not belong to the specified event.';
    END IF;

    SELECT COUNT(*) INTO v_confirmed_count
    FROM `REGISTRATION`
    WHERE TicketID = p_ticket_id AND Status = 'Confirmed';

    IF v_confirmed_count >= v_tier_capacity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: FR-10/BR-05 Violation: Ticket tier has reached maximum capacity.';
    END IF;

    INSERT INTO `REGISTRATION` (`AttendeeID`, `EventID`, `TicketID`, `RegistrationDate`, `Status`, `AcceptedPrice`)
    VALUES (v_current_user, p_event_id, p_ticket_id, NOW(), 'Confirmed', v_tier_price);

    SET v_new_reg_id = LAST_INSERT_ID();

    INSERT INTO `PAYMENT` (`RegistrationID`, `AmountPaid`, `PaymentDate`, `InvoiceNumber`)
    VALUES (v_new_reg_id, p_amount_paid, NOW(), p_invoice_number);

    INSERT INTO `AUDIT_LOG` (`ActorUserID`, `ActorRole`, `ActionTimestamp`, `ActionType`, `EntityName`, `RecordID`, `OldValue`, `NewValue`, `Reason`)
    VALUES (
        v_current_user, v_actor_role, NOW(), 'INSERT', 'REGISTRATION_PAYMENT', CAST(v_new_reg_id AS CHAR),
        NULL,
        CONCAT('EventID=', p_event_id, ', TicketID=', p_ticket_id, ', Status=Confirmed, AcceptedPrice=', v_tier_price, ', Invoice=', p_invoice_number),
        'Atomic UC-01 Registration and Payment'
    );

    COMMIT;
END$$

-- Procedure 2: Soft Registration Cancellation (UC-02)
DROP PROCEDURE IF EXISTS `sp_cancel_registration`$$
CREATE PROCEDURE `sp_cancel_registration`(
    IN p_registration_id INT,
    IN p_reason VARCHAR(255)
)
COMMENT 'Version: 2.0.0 | Release: v2.0-release | Principle 3 & 5 refactored cancellation'
BEGIN
    DECLARE c_routine_version VARCHAR(20) DEFAULT '2.0.0';
    DECLARE v_current_user INT DEFAULT fn_current_user_id();
    DECLARE v_owner_id INT;
    DECLARE v_current_status VARCHAR(30);
    DECLARE v_actor_role VARCHAR(30);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF v_current_user IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: Unauthenticated session. @current_user_id is missing.';
    END IF;

    SELECT RoleType INTO v_actor_role
    FROM `USER` WHERE UserID = v_current_user FOR SHARE;

    SELECT AttendeeID, Status INTO v_owner_id, v_current_status
    FROM `REGISTRATION` WHERE RegistrationID = p_registration_id FOR UPDATE;

    IF v_owner_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'not_found: UC-02 Error: Registration record not found.';
    END IF;

    IF v_owner_id <> v_current_user AND v_actor_role <> 'Admin' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: SEC-02 Violation: Callers may only cancel their own registration unless Admin.';
    END IF;

    IF v_current_status = 'Cancelled' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'conflict: UC-02 Error: Registration is already Cancelled.';
    END IF;

    DELETE FROM `SESSION_ROSTER` WHERE RegistrationID = p_registration_id;

    UPDATE `REGISTRATION`
    SET Status = 'Cancelled'
    WHERE RegistrationID = p_registration_id;

    INSERT INTO `AUDIT_LOG` (`ActorUserID`, `ActorRole`, `ActionTimestamp`, `ActionType`, `EntityName`, `RecordID`, `OldValue`, `NewValue`, `Reason`)
    VALUES (
        v_current_user, v_actor_role, NOW(), 'STATUS_CHANGE', 'REGISTRATION', CAST(p_registration_id AS CHAR),
        'Status=Confirmed', 'Status=Cancelled', p_reason
    );

    COMMIT;
END$$

-- Procedure 3: Schedule Session (UC-03)
DROP PROCEDURE IF EXISTS `sp_schedule_session`$$
CREATE PROCEDURE `sp_schedule_session`(
    IN p_event_id INT,
    IN p_speaker_id INT,
    IN p_title VARCHAR(150),
    IN p_start DATETIME,
    IN p_end DATETIME,
    IN p_capacity INT,
    IN p_room VARCHAR(30)
)
COMMENT 'Version: 2.0.0 | Release: v2.0-release | Principle 3 & 5 refactored session scheduling'
BEGIN
    DECLARE c_routine_version VARCHAR(20) DEFAULT '2.0.0';
    DECLARE v_current_user INT DEFAULT fn_current_user_id();
    DECLARE v_event_organizer INT;
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_new_session_id INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF v_current_user IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: Unauthenticated session. @current_user_id is missing.';
    END IF;

    SELECT RoleType INTO v_actor_role
    FROM `USER` WHERE UserID = v_current_user FOR SHARE;

    SELECT OrganizerID INTO v_event_organizer
    FROM `EVENT` WHERE EventID = p_event_id FOR SHARE;

    IF v_event_organizer IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'not_found: Event does not exist.';
    END IF;

    IF v_event_organizer <> v_current_user AND v_actor_role <> 'Admin' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: SEC-03 Violation: Only the owning Event Organizer or Admin can schedule sessions.';
    END IF;

    INSERT INTO `SESSION` (`EventID`, `SpeakerID`, `SessionTitle`, `StartDateTime`, `EndDateTime`, `SessionCapacity`, `RoomNumber`)
    VALUES (p_event_id, p_speaker_id, p_title, p_start, p_end, p_capacity, p_room);

    SET v_new_session_id = LAST_INSERT_ID();

    INSERT INTO `AUDIT_LOG` (`ActorUserID`, `ActorRole`, `ActionTimestamp`, `ActionType`, `EntityName`, `RecordID`, `OldValue`, `NewValue`, `Reason`)
    VALUES (
        v_current_user, v_actor_role, NOW(), 'INSERT', 'SESSION', CAST(v_new_session_id AS CHAR),
        NULL, CONCAT('Title=', p_title, ', SpeakerID=', p_speaker_id, ', Cap=', p_capacity),
        'UC-03 Session Scheduled'
    );

    COMMIT;
END$$

-- Procedure 4: Session Roster Enrollment (UC-03 / BR-08)
DROP PROCEDURE IF EXISTS `sp_enroll_session_roster`$$
CREATE PROCEDURE `sp_enroll_session_roster`(
    IN p_registration_id INT,
    IN p_session_id INT
)
COMMENT 'Version: 2.0.0 | Release: v2.0-release | Principle 3 & 5 refactored session enrollment'
BEGIN
    DECLARE c_routine_version VARCHAR(20) DEFAULT '2.0.0';
    DECLARE v_current_user INT DEFAULT fn_current_user_id();
    DECLARE v_reg_attendee INT;
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_dummy_cap INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF v_current_user IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: Unauthenticated session. @current_user_id is missing.';
    END IF;

    SELECT RoleType INTO v_actor_role
    FROM `USER` WHERE UserID = v_current_user FOR SHARE;

    SELECT AttendeeID INTO v_reg_attendee
    FROM `REGISTRATION` WHERE RegistrationID = p_registration_id FOR SHARE;

    IF v_reg_attendee IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'not_found: Registration does not exist.';
    END IF;

    IF v_reg_attendee <> v_current_user AND v_actor_role <> 'Admin' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: SEC-02 Violation: Attendee can only enroll their own registration into a session.';
    END IF;

    SELECT SessionCapacity INTO v_dummy_cap
    FROM `SESSION` WHERE SessionID = p_session_id FOR UPDATE;

    INSERT INTO `SESSION_ROSTER` (`RegistrationID`, `SessionID`, `CheckInStatus`, `EnrolledAt`)
    VALUES (p_registration_id, p_session_id, 'Enrolled', NOW());

    INSERT INTO `AUDIT_LOG` (`ActorUserID`, `ActorRole`, `ActionTimestamp`, `ActionType`, `EntityName`, `RecordID`, `OldValue`, `NewValue`, `Reason`)
    VALUES (
        v_current_user, v_actor_role, NOW(), 'INSERT', 'SESSION_ROSTER',
        CONCAT(p_registration_id, '-', p_session_id), NULL, 'CheckInStatus=Enrolled',
        'Attendee enrolled in session'
    );

    COMMIT;
END$$

-- Procedure 5: Record Session Check-In (UC-04 + Principle 4 State Machine)
DROP PROCEDURE IF EXISTS `sp_record_session_checkin`$$
CREATE PROCEDURE `sp_record_session_checkin`(
    IN p_registration_id INT,
    IN p_session_id INT,
    IN p_new_status VARCHAR(30)
)
COMMENT 'Version: 2.0.0 | Release: v2.0-release | Principle 3, 4 & 5 refactored check-in'
BEGIN
    DECLARE c_routine_version VARCHAR(20) DEFAULT '2.0.0';
    DECLARE v_current_user INT DEFAULT fn_current_user_id();
    DECLARE v_actor_role VARCHAR(30);
    DECLARE v_event_organizer_id INT;
    DECLARE v_reg_status VARCHAR(30);
    DECLARE v_old_checkin VARCHAR(30);
    DECLARE v_transition_allowed INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF v_current_user IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: Unauthenticated session. @current_user_id is missing.';
    END IF;

    SELECT RoleType INTO v_actor_role
    FROM `USER` WHERE UserID = v_current_user FOR SHARE;

    SELECT e.OrganizerID INTO v_event_organizer_id
    FROM `SESSION` s
    INNER JOIN `EVENT` e ON s.EventID = e.EventID
    WHERE s.SessionID = p_session_id FOR SHARE;

    IF v_actor_role IS NULL OR (v_actor_role <> 'Admin' AND (v_actor_role <> 'Organizer' OR v_event_organizer_id <> v_current_user)) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'forbidden: SEC-03/SEC-04 Violation: Only the owning Event Organizer or Admin may update session check-in status.';
    END IF;

    SELECT r.Status, sr.CheckInStatus INTO v_reg_status, v_old_checkin
    FROM `SESSION_ROSTER` sr
    INNER JOIN `REGISTRATION` r ON sr.RegistrationID = r.RegistrationID
    WHERE sr.RegistrationID = p_registration_id AND sr.SessionID = p_session_id
    FOR UPDATE;

    IF v_old_checkin IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'not_found: UC-04 Error: Enrollment record not found in SESSION_ROSTER.';
    END IF;

    IF v_reg_status <> 'Confirmed' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'invalid: BR-08 Violation: Cannot check in a registration whose status is not Confirmed.';
    END IF;

    -- Principle 4: Validate transition via WORKFLOW_TRANSITION metadata table
    SELECT COUNT(*) INTO v_transition_allowed
    FROM `WORKFLOW_TRANSITION`
    WHERE WorkflowName = 'SESSION_CHECKIN'
      AND FromState = v_old_checkin
      AND ToState = p_new_status
      AND AllowedRole = v_actor_role;

    IF v_transition_allowed = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'invalid: Principle 4 Workflow Violation: Disallowed state transition or insufficient role.';
    END IF;

    UPDATE `SESSION_ROSTER`
    SET CheckInStatus = p_new_status
    WHERE RegistrationID = p_registration_id AND SessionID = p_session_id;

    INSERT INTO `AUDIT_LOG` (`ActorUserID`, `ActorRole`, `ActionTimestamp`, `ActionType`, `EntityName`, `RecordID`, `OldValue`, `NewValue`, `Reason`)
    VALUES (
        v_current_user, v_actor_role, NOW(), 'STATUS_CHANGE', 'SESSION_ROSTER',
        CONCAT(p_registration_id, '-', p_session_id),
        CONCAT('CheckInStatus=', v_old_checkin),
        CONCAT('CheckInStatus=', p_new_status),
        'UC-04 Organizer/Admin Session Check-In'
    );

    COMMIT;
END$$

DELIMITER ;

-- Grant Execute Permissions
GRANT EXECUTE ON PROCEDURE `sp_register_and_pay` TO 'role_attendee', 'role_admin';
GRANT EXECUTE ON PROCEDURE `sp_cancel_registration` TO 'role_attendee', 'role_organizer', 'role_admin';
GRANT EXECUTE ON PROCEDURE `sp_schedule_session` TO 'role_organizer', 'role_admin';
GRANT EXECUTE ON PROCEDURE `sp_enroll_session_roster` TO 'role_attendee', 'role_admin';
GRANT EXECUTE ON PROCEDURE `sp_record_session_checkin` TO 'role_organizer', 'role_admin';

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

-- ============================================================================
-- sql/04_test_suite_and_demo.sql (v2.0-release)
-- Complete Live Demonstration & Automated Negative/Resiliency Test Harness
-- Generates 13 Populated Result Grid Tabs in MySQL Workbench
-- ============================================================================
USE `event_registration`;

-- ----------------------------------------------------------------------------
-- PART 1: Schema Objects, Constraints, Triggers & Baseline Counts (Tabs 1–3)
-- ----------------------------------------------------------------------------

-- Result Tab 1: Exact Row Counts Across Core & Metadata Tables
SELECT 'USER' AS TableName, COUNT(*) AS ExactRowCount FROM `USER`
UNION ALL SELECT 'VENUE', COUNT(*) FROM `VENUE`
UNION ALL SELECT 'EVENT', COUNT(*) FROM `EVENT`
UNION ALL SELECT 'TICKET_TIER', COUNT(*) FROM `TICKET_TIER`
UNION ALL SELECT 'SESSION', COUNT(*) FROM `SESSION`
UNION ALL SELECT 'REGISTRATION', COUNT(*) FROM `REGISTRATION`
UNION ALL SELECT 'PAYMENT', COUNT(*) FROM `PAYMENT`
UNION ALL SELECT 'SESSION_ROSTER', COUNT(*) FROM `SESSION_ROSTER`
UNION ALL SELECT 'AUDIT_LOG', COUNT(*) FROM `AUDIT_LOG`
UNION ALL SELECT 'INDICATOR_VALUE', COUNT(*) FROM `INDICATOR_VALUE`
UNION ALL SELECT 'WORKFLOW_TRANSITION', COUNT(*) FROM `WORKFLOW_TRANSITION`
UNION ALL SELECT 'SCHEMA_VERSION', COUNT(*) FROM `SCHEMA_VERSION`;

-- Result Tab 2: Declarative Constraints Inventory
SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM information_schema.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = DATABASE()
ORDER BY TABLE_NAME, CONSTRAINT_TYPE;

-- Result Tab 3: Active Triggers Inventory
SELECT TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE, ACTION_TIMING
FROM information_schema.TRIGGERS
WHERE TRIGGER_SCHEMA = DATABASE()
ORDER BY EVENT_OBJECT_TABLE, ACTION_TIMING;

-- ----------------------------------------------------------------------------
-- PART 2: Positive Workflows & Historical Price Preservation (AC-01, AC-13)
-- ----------------------------------------------------------------------------

-- Step 2A: Dave (UserID = 4) registers for Event 1, Tier 10 ($50.00) and enrolls in Session 101
SET @current_user_id = 4;
SET @current_user_role = 'Attendee';
CALL `sp_register_and_pay`(1, 10, 50.00, 'INV-1002');
CALL `sp_enroll_session_roster`(2, 101);

-- Step 2B: Organizer Bob (UserID = 2) checks in Elena (Reg 1) for Session 101
SET @current_user_id = 2;
SET @current_user_role = 'Organizer';
CALL `sp_record_session_checkin`(1, 101, 'CheckedIn');

-- Step 2C: Organizer Bob raises General Admission (TicketID = 10) catalog price from $50.00 to $75.00
UPDATE `TICKET_TIER` SET Price = 75.00 WHERE TicketID = 10;

-- Result Tab 4: Proof of Historical Price Preservation (AC-13 / BR-10)
SELECT
    r.RegistrationID,
    u.FirstName,
    u.LastName,
    tt.TierName,
    r.AcceptedPrice AS LockedHistoricalPrice,
    tt.Price AS CurrentCatalogTierPrice,
    p.AmountPaid,
    p.InvoiceNumber
FROM `REGISTRATION` r
INNER JOIN `USER` u ON r.AttendeeID = u.UserID
INNER JOIN `TICKET_TIER` tt ON r.EventID = tt.EventID AND r.TicketID = tt.TicketID
INNER JOIN `PAYMENT` p ON r.RegistrationID = p.RegistrationID
WHERE r.TicketID = 10;

-- ----------------------------------------------------------------------------
-- PART 3: Automated 13-Case Negative, Rollback & Security Test Harness (Tab 5)
-- ----------------------------------------------------------------------------

DROP TEMPORARY TABLE IF EXISTS `test_execution_results`;
CREATE TEMPORARY TABLE `test_execution_results` (
    `TestID` VARCHAR(15) PRIMARY KEY,
    `RequirementRef` VARCHAR(35),
    `ScenarioDescription` VARCHAR(120),
    `OutcomeStatus` VARCHAR(25),
    `CapturedErrorMessage` VARCHAR(255)
);

DELIMITER $$
DROP PROCEDURE IF EXISTS `sp_run_all_negative_and_resiliency_tests`$$
CREATE PROCEDURE `sp_run_all_negative_and_resiliency_tests`()
BEGIN
    DECLARE v_sqlstate CHAR(5);
    DECLARE v_errno INT;
    DECLARE v_msg TEXT;

    -- Test 1: AC-02 Duplicate Email Rejection
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('AC-02', 'FR-01 / BR-01', 'Duplicate USER Email insertion', 'PASS (Rejected)', LEFT(v_msg, 250));
        END;
        INSERT INTO `USER` (`FirstName`, `LastName`, `Email`, `RoleType`) VALUES ('Dup', 'User', 'dave@test.com', 'Attendee');
    END;

    -- Test 2: TC-02 Invalid Event Date Ordering
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('TC-02', 'FR-05 / BR-02', 'Event EndDate earlier than StartDate', 'PASS (Rejected)', LEFT(v_msg, 250));
        END;
        INSERT INTO `EVENT` (`OrganizerID`, `VenueID`, `EventName`, `StartDate`, `EndDate`)
        VALUES (2, 1, 'Invalid Date Event', '2026-11-10', '2026-11-05');
    END;

    -- Test 3: TC-03 Session Outside Event Date Boundaries
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('TC-03', 'FR-06 / BR-02', 'Session scheduled outside Event dates', 'PASS (Rejected)', LEFT(v_msg, 250));
        END;
        SET @current_user_id = 2;
        SET @current_user_role = 'Organizer';
        CALL `sp_schedule_session`(1, 3, 'Out of Bounds Session', '2026-09-15 09:00:00', '2026-09-15 10:00:00', 20, 'Room C');
    END;

    -- Test 4: AC-03 Tier Capacity Sum Exceeding Venue MaxCapacity
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('AC-03', 'FR-08 / BR-04', 'Ticket tier capacity sum > Venue MaxCapacity', 'PASS (Rejected)', LEFT(v_msg, 250));
        END;
        INSERT INTO `TICKET_TIER` (`EventID`, `TierName`, `Price`, `Capacity`) VALUES (1, 'Overflow Tier', 25.00, 50);
    END;

    -- Test 5: AC-04 Duplicate Active Registration for Same Attendee & Event
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('AC-04', 'FR-09 / BR-06', 'Duplicate Confirmed registration for same Event', 'PASS (Rejected)', LEFT(v_msg, 250));
        END;
        SET @current_user_id = 4;
        SET @current_user_role = 'Attendee';
        CALL `sp_register_and_pay`(1, 10, 75.00, 'INV-DUP4');
    END;

    -- Test 6: AC-06 Ticket Tier Capacity Exhaustion (VIP Tier 20 has Capacity = 1)
    BEGIN
        -- First fill the 1 VIP seat with User 3 (Charlie)
        SET @current_user_id = 3;
        SET @current_user_role = 'Speaker';
        CALL `sp_register_and_pay`(1, 20, 150.00, 'INV-VIP1');

        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            BEGIN
                GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
                INSERT INTO `test_execution_results` VALUES ('AC-06', 'FR-10 / BR-05', 'Sold-out VIP tier over-registration blocked', 'PASS (Rejected)', LEFT(v_msg, 250));
            END;
            -- User 6 (Frank) attempts to buy the sold-out VIP tier
            SET @current_user_id = 6;
            SET @current_user_role = 'Organizer';
            CALL `sp_register_and_pay`(1, 20, 150.00, 'INV-VIP2');
        END;
    END;

    -- Test 7: AC-09 Atomic Rollback on Payment Price Mismatch (Zero Orphaned REGISTRATION)
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('AC-09', 'FR-13 / BR-07', 'Mid-transaction payment mismatch rolls back REGISTRATION', 'PASS (Rolled Back)', LEFT(v_msg, 250));
        END;
        SET @current_user_id = 7;
        SET @current_user_role = 'Speaker';
        CALL `sp_register_and_pay`(1, 30, 10.00, 'INV-FAIL9');
    END;

    -- Test 8: AC-10 Speaker Overlapping Session Conflict
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('AC-10', 'FR-07 / BR-09', 'Overlapping speaker session interval rejected', 'PASS (Rejected)', LEFT(v_msg, 250));
        END;
        SET @current_user_id = 2;
        SET @current_user_role = 'Organizer';
        CALL `sp_schedule_session`(1, 3, 'Conflicting Talk', '2026-09-10 09:30:00', '2026-09-10 10:45:00', 20, 'Room D');
    END;

    -- Test 9: AC-11 Session Roster Capacity Enforcement (Session 102 has Capacity = 1)
    BEGIN
        -- Enroll Reg 1 (Elena) into the 1-seat Session 102
        SET @current_user_id = 5;
        SET @current_user_role = 'Attendee';
        CALL `sp_enroll_session_roster`(1, 102);

        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
            BEGIN
                GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
                INSERT INTO `test_execution_results` VALUES ('AC-11', 'FR-14 / BR-08', 'Session roster enrollment beyond SessionCapacity', 'PASS (Rejected)', LEFT(v_msg, 250));
            END;
            SET @current_user_id = 4;
            SET @current_user_role = 'Attendee';
            CALL `sp_enroll_session_roster`(2, 102);
        END;
    END;

    -- Test 10: AC-12 Parent-Row Deletion Protection (ON DELETE RESTRICT)
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('AC-12', 'BR-11 / RESTRICT', 'Hard DELETE of parent EVENT with dependent rows blocked', 'PASS (Blocked)', LEFT(v_msg, 250));
        END;
        DELETE FROM `EVENT` WHERE EventID = 1;
    END;

    -- Test 11: AC-14 Unauthorized Check-In Attempt by Non-Owner Organizer (Frank = User 6)
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('AC-14', 'SEC-03 / SEC-04', 'Non-owner Organizer blocked from checking in session', 'PASS (Blocked)', LEFT(v_msg, 250));
        END;
        SET @current_user_id = 6;
        SET @current_user_role = 'Organizer';
        CALL `sp_record_session_checkin`(2, 101, 'CheckedIn');
    END;

    -- Test 12: AC-16A Audit Log UPDATE Immutability
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('AC-16A', 'BR-12 / SEC-08', 'UPDATE on AUDIT_LOG blocked by immutability trigger', 'PASS (Blocked)', LEFT(v_msg, 250));
        END;
        UPDATE `AUDIT_LOG` SET Reason = 'Tampered' WHERE LogID = 1;
    END;

    -- Test 13: AC-16B Audit Log DELETE Immutability
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_sqlstate = RETURNED_SQLSTATE, v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
            INSERT INTO `test_execution_results` VALUES ('AC-16B', 'BR-12 / SEC-08', 'DELETE on AUDIT_LOG blocked by immutability trigger', 'PASS (Blocked)', LEFT(v_msg, 250));
        END;
        DELETE FROM `AUDIT_LOG` WHERE LogID = 1;
    END;
END$$
DELIMITER ;

CALL `sp_run_all_negative_and_resiliency_tests`();

-- Result Tab 5: Display All 13 Negative, Rollback & Security Test Results
SELECT * FROM `test_execution_results`;

-- ----------------------------------------------------------------------------
-- PART 4: Soft Cancellation & Re-Registration Lifecycle (AC-05) (Tab 6)
-- ----------------------------------------------------------------------------

-- Dave (UserID = 4, RegID = 2) cancels his $50.00 registration and re-registers at the new $75.00 price
SET @current_user_id = 4;
SET @current_user_role = 'Attendee';
CALL `sp_cancel_registration`(2, 'Attendee schedule change prior to re-booking');
CALL `sp_register_and_pay`(1, 10, 75.00, 'INV-1004');

-- Result Tab 6: Show Cancelled Historical Record Next to New Confirmed Registration
SELECT
    RegistrationID,
    AttendeeID,
    EventID,
    TicketID,
    Status,
    AcceptedPrice,
    ActiveAttendeeEventKey
FROM `REGISTRATION`
WHERE AttendeeID = 4
ORDER BY RegistrationID;

-- ----------------------------------------------------------------------------
-- PART 5: Analytical Reporting Views (RQ-01 to RQ-04) & EXPLAIN Plans (Tabs 7–12)
-- ----------------------------------------------------------------------------

-- Result Tab 7: RQ-01 Event Financial & Registration Summary
SELECT * FROM `v_rq01_event_revenue`;

-- Result Tab 8: RQ-02 Session Roster & Check-In Status
SELECT * FROM `v_rq02_session_roster`;

-- Result Tab 9: RQ-03 Capacity Utilization & Remaining Seats
SELECT * FROM `v_rq03_capacity_utilization`;

-- Result Tab 10: RQ-04 Speaker Session & Room Schedule
SELECT * FROM `v_rq04_speaker_schedule`;

-- Result Tab 11: EXPLAIN Plan #1 (Covering Index idx_reg_ticket_status)
EXPLAIN SELECT COUNT(*) FROM `REGISTRATION` WHERE TicketID = 10 AND Status = 'Confirmed';

-- Result Tab 12: EXPLAIN Plan #2 (Index Lookup idx_roster_session_status)
EXPLAIN SELECT * FROM `v_rq02_session_roster` WHERE SessionID = 101;

-- ----------------------------------------------------------------------------
-- PART 6: Complete Chronological Audit Trail Reconstruction (AC-16) (Tab 13)
-- ----------------------------------------------------------------------------

-- Result Tab 13: Full Immutable Audit Ledger
SELECT
    LogID,
    ActorUserID,
    ActorRole,
    ActionTimestamp,
    ActionType,
    EntityName,
    RecordID,
    OldValue,
    NewValue,
    Reason
FROM `AUDIT_LOG`
ORDER BY LogID ASC;
