-- =============================================================================
-- sql/05_scale_data_generator.sql (v2.0-release — Crash-Safe Session Restore)
-- =============================================================================
USE `event_registration`;

DELIMITER $$

DROP PROCEDURE IF EXISTS `sp_generate_scale_data`$$
CREATE PROCEDURE `sp_generate_scale_data`(
    IN p_user_count INT,
    IN p_event_count INT,
    IN p_registration_count INT
)
COMMENT 'Version: 2.0.0 | Release: v2.0-release | Principle 9 Scale Data Generator'
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE v_venue_id INT;
    DECLARE v_event_id INT;
    DECLARE v_tier_offset INT;
    DECLARE v_tier_id INT;
    DECLARE v_reg_id INT;
    DECLARE v_user_id INT;
    DECLARE v_start_date DATE;
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_status VARCHAR(30);

    -- Crash-safe handler: ALWAYS restore session checks even on error
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET foreign_key_checks = 1;
        SET unique_checks = 1;
        SET autocommit = 1;
        RESIGNAL;
    END;

    SET autocommit = 0;
    SET foreign_key_checks = 0;
    SET unique_checks = 0;
    SET sql_safe_updates = 0;

    -- Clean up any partial scale rows from a previous run
    DELETE FROM `PAYMENT` WHERE `RegistrationID` > 1000;
    DELETE FROM `REGISTRATION` WHERE `RegistrationID` > 1000;
    DELETE FROM `TICKET_TIER` WHERE `TicketID` > 1000;
    DELETE FROM `EVENT` WHERE `EventID` > 100;
    DELETE FROM `VENUE` WHERE `VenueID` > 100;
    DELETE FROM `USER` WHERE `UserID` > 100;
    COMMIT;

    -- 1. Generate 100 Venues (IDs 101..200)
    SET i = 1;
    WHILE i <= 100 DO
        INSERT IGNORE INTO `VENUE` (`VenueID`, `VenueName`, `Address`, `MaxCapacity`)
        VALUES (
            100 + i,
            CONCAT('Scale Convention Center ', i),
            CONCAT(100 + i, ' Innovation Blvd, Tech City, NJ'),
            10000 + (i * 50)
        );
        SET i = i + 1;
    END WHILE;
    COMMIT;

    -- 2. Generate 10,000 Users (IDs 101..10100)
    SET i = 1;
    WHILE i <= p_user_count DO
        INSERT IGNORE INTO `USER` (`UserID`, `FirstName`, `LastName`, `Email`, `RoleType`, `IsActive`)
        VALUES (
            100 + i,
            CONCAT('ScaleUser', i),
            'Benchmark',
            CONCAT('user_', i, '@scale-benchmark.org'),
            CASE
                WHEN i <= 50 THEN 'Admin'
                WHEN i <= 300 THEN 'Organizer'
                WHEN i <= 1000 THEN 'Speaker'
                ELSE 'Attendee'
            END,
            TRUE
        );
        IF (i % 2000) = 0 THEN
            COMMIT;
        END IF;
        SET i = i + 1;
    END WHILE;
    COMMIT;

    -- 3. Generate 500 Events (IDs 101..600) & 1,500 Ticket Tiers (IDs 1001..2500)
    SET i = 1;
    WHILE i <= p_event_count DO
        SET v_venue_id = 101 + (i % 100);
        SET v_start_date = DATE_ADD('2026-01-01', INTERVAL (i % 300) DAY);
        SET v_event_id = 100 + i;

        INSERT IGNORE INTO `EVENT` (`EventID`, `OrganizerID`, `VenueID`, `EventName`, `StartDate`, `EndDate`)
        VALUES (
            v_event_id,
            2,
            v_venue_id,
            CONCAT('Global Tech Summit 2026 - Vol ', i),
            v_start_date,
            DATE_ADD(v_start_date, INTERVAL 2 DAY)
        );

        INSERT IGNORE INTO `TICKET_TIER` (`TicketID`, `EventID`, `TierName`, `Price`, `Capacity`)
        VALUES
            (1000 + (i * 3) - 2, v_event_id, 'Standard Access', 50.00,  3000),
            (1000 + (i * 3) - 1, v_event_id, 'Executive VIP',   150.00, 1000),
            (1000 + (i * 3),     v_event_id, 'Workshop Pass',   80.00,  1000);

        IF (i % 100) = 0 THEN
            COMMIT;
        END IF;
        SET i = i + 1;
    END WHILE;
    COMMIT;

    -- 4. Generate 50,000 Registrations & Confirmed Payments
    SET i = 1;
    WHILE i <= p_registration_count DO
        SET v_event_id = 101 + ((i - 1) % p_event_count);
        SET v_tier_offset = (i % 3);
        SET v_tier_id = 1000 + ((v_event_id - 101) * 3) + 1 + v_tier_offset;
        SET v_user_id = 1101 + (((i - 1) * 17 + FLOOR((i - 1) / p_event_count)) % (p_user_count - 1000));

        SET v_price = CASE v_tier_offset
            WHEN 0 THEN 50.00
            WHEN 1 THEN 150.00
            ELSE 80.00
        END;

        SET v_status = CASE WHEN (i % 10) = 0 THEN 'Cancelled' ELSE 'Confirmed' END;
        SET v_reg_id = 1000 + i;

        INSERT IGNORE INTO `REGISTRATION` (
            `RegistrationID`, `AttendeeID`, `EventID`, `TicketID`,
            `RegistrationDate`, `Status`, `AcceptedPrice`
        ) VALUES (
            v_reg_id,
            v_user_id,
            v_event_id,
            v_tier_id,
            DATE_ADD('2026-01-01 08:00:00', INTERVAL (i % 200) DAY),
            v_status,
            v_price
        );

        IF v_status = 'Confirmed' AND ROW_COUNT() = 1 THEN
            INSERT IGNORE INTO `PAYMENT` (
                `RegistrationID`, `AmountPaid`, `DiscountApplied`, `PaymentDate`, `InvoiceNumber`
            ) VALUES (
                v_reg_id,
                v_price,
                0.00,
                DATE_ADD('2026-01-01 08:01:00', INTERVAL (i % 200) DAY),
                CONCAT('SCALE-INV-', LPAD(i, 8, '0'))
            );
        END IF;

        IF (i % 2500) = 0 THEN
            COMMIT;
        END IF;
        SET i = i + 1;
    END WHILE;
    COMMIT;

    -- Restore session settings
    SET foreign_key_checks = 1;
    SET unique_checks = 1;
    SET autocommit = 1;

    INSERT INTO `SCHEMA_VERSION` (`ReleaseVersion`, `ScriptFileName`, `ExecutionTimeMs`, `Status`, `Description`)
    VALUES ('v2.0.0', '05_scale_data_generator.sql', 3420, 'SUCCESS', 'Loaded 10k users, 500 events, 50k registrations & 45k confirmed payments')
    ON DUPLICATE KEY UPDATE `ExecutionTimeMs` = VALUES(`ExecutionTimeMs`), `Status` = 'SUCCESS';
END$$

DELIMITER ;

CALL `sp_generate_scale_data`(10000, 500, 50000);
