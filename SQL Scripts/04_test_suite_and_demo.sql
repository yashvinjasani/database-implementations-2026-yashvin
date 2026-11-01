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
