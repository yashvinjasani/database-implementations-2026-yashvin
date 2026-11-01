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
