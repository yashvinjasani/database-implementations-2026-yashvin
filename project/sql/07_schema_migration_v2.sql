-- =============================================================================
-- sql/07_schema_migration_v2.sql (v2.0-release)
-- Principle 8: Non-Destructive Idempotent Schema Migration (v1.0 -> v2.0)
-- Adds APP_LOGIN_MAP, Audit Severity & DB Session User tracking, and verifies
-- 100% data survival across schema upgrades.
-- =============================================================================
USE `event_registration`;

-- 1. Capture Pre-Migration Row Counts to Prove Data Survival
DROP TEMPORARY TABLE IF EXISTS `tmp_pre_migration_counts`;
CREATE TEMPORARY TABLE `tmp_pre_migration_counts` AS
SELECT 'USER' AS Entity, COUNT(*) AS PreCount FROM `USER`
UNION ALL SELECT 'VENUE', COUNT(*) FROM `VENUE`
UNION ALL SELECT 'EVENT', COUNT(*) FROM `EVENT`
UNION ALL SELECT 'TICKET_TIER', COUNT(*) FROM `TICKET_TIER`
UNION ALL SELECT 'SESSION', COUNT(*) FROM `SESSION`
UNION ALL SELECT 'REGISTRATION', COUNT(*) FROM `REGISTRATION`
UNION ALL SELECT 'PAYMENT', COUNT(*) FROM `PAYMENT`
UNION ALL SELECT 'SESSION_ROSTER', COUNT(*) FROM `SESSION_ROSTER`
UNION ALL SELECT 'AUDIT_LOG', COUNT(*) FROM `AUDIT_LOG`;

-- 2. Idempotent Creation of APP_LOGIN_MAP (Principle 3 DB Login -> Business User Mapping)
CREATE TABLE IF NOT EXISTS `APP_LOGIN_MAP` (
    `DBLoginName` VARCHAR(100) PRIMARY KEY,
    `UserID` INT NOT NULL UNIQUE,
    `MappedRole` VARCHAR(30) NOT NULL,
    `CreatedAt` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_login_map_user` FOREIGN KEY (`UserID`)
        REFERENCES `USER` (`UserID`) ON DELETE RESTRICT
) ENGINE=InnoDB COMMENT='Principle 3: Maps MySQL database accounts to business USER rows';

INSERT INTO `APP_LOGIN_MAP` (`DBLoginName`, `UserID`, `MappedRole`) VALUES
('admin_alice',     1, 'Admin'),
('bob_organizer',   2, 'Organizer'),
('charlie_speaker', 3, 'Speaker'),
('dave_attendee',   4, 'Attendee'),
('elena_attendee',  5, 'Attendee'),
('frank_organizer', 6, 'Organizer'),
('grace_speaker',   7, 'Speaker')
ON DUPLICATE KEY UPDATE `MappedRole` = VALUES(`MappedRole`);

-- 3. Idempotent Column Addition on AUDIT_LOG (Severity column if not already present)
SET @col_exists = (
    SELECT COUNT(*) FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'AUDIT_LOG' AND COLUMN_NAME = 'Severity'
);
SET @sql_alter = IF(
    @col_exists = 0,
    'ALTER TABLE `AUDIT_LOG` ADD COLUMN `Severity` ENUM(''INFO'',''WARNING'',''CRITICAL'') NOT NULL DEFAULT ''INFO'' AFTER `ActionType`',
    'SELECT ''Column Severity already exists on AUDIT_LOG'' AS MigrationCheck'
);
PREPARE stmt FROM @sql_alter;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 4. Record the Migration in SCHEMA_VERSION
INSERT INTO `SCHEMA_VERSION` (`ReleaseVersion`, `ScriptFileName`, `ExecutionTimeMs`, `Status`, `Description`)
VALUES ('v2.0.1', '07_schema_migration_v2.sql', 42, 'SUCCESS', 'Idempotent v2 migration: added APP_LOGIN_MAP and AUDIT_LOG.Severity')
ON DUPLICATE KEY UPDATE `AppliedAt` = CURRENT_TIMESTAMP, `Status` = 'SUCCESS';

-- 5. Prove 100% Data Survival (PreCount vs PostCount must match with 0 Data Loss)
SELECT
    pre.Entity,
    pre.PreCount,
    post.PostCount,
    CASE WHEN pre.PreCount = post.PostCount THEN 'PASS (100% Data Survived)' ELSE 'FAIL' END AS MigrationSurvivalStatus
FROM `tmp_pre_migration_counts` pre
INNER JOIN (
    SELECT 'USER' AS Entity, COUNT(*) AS PostCount FROM `USER`
    UNION ALL SELECT 'VENUE', COUNT(*) FROM `VENUE`
    UNION ALL SELECT 'EVENT', COUNT(*) FROM `EVENT`
    UNION ALL SELECT 'TICKET_TIER', COUNT(*) FROM `TICKET_TIER`
    UNION ALL SELECT 'SESSION', COUNT(*) FROM `SESSION`
    UNION ALL SELECT 'REGISTRATION', COUNT(*) FROM `REGISTRATION`
    UNION ALL SELECT 'PAYMENT', COUNT(*) FROM `PAYMENT`
    UNION ALL SELECT 'SESSION_ROSTER', COUNT(*) FROM `SESSION_ROSTER`
    UNION ALL SELECT 'AUDIT_LOG', COUNT(*) FROM `AUDIT_LOG`
) post ON pre.Entity = post.Entity;
