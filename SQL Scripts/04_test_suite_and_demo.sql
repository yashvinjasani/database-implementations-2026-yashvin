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
