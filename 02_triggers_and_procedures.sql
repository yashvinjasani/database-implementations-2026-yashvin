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
