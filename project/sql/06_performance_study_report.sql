-- =============================================================================
-- sql/06_performance_study_report.sql (v2.0-release)
-- Principle 9: Empirical Performance Benchmark at Scale (50,000+ Rows)
-- Compares Query Execution Plans & Latencies With and Without Covering Indexes
-- =============================================================================
USE `event_registration`;

-- 1. Verify Scale Dataset Volume
SELECT
    (SELECT COUNT(*) FROM `USER`) AS TotalUsers,
    (SELECT COUNT(*) FROM `VENUE`) AS TotalVenues,
    (SELECT COUNT(*) FROM `EVENT`) AS TotalEvents,
    (SELECT COUNT(*) FROM `TICKET_TIER`) AS TotalTicketTiers,
    (SELECT COUNT(*) FROM `REGISTRATION`) AS TotalRegistrations,
    (SELECT COUNT(*) FROM `PAYMENT`) AS TotalPayments;

-- -----------------------------------------------------------------------------
-- STUDY 1: Locked Capacity Check (FR-10 / BR-05)
-- Query: SELECT COUNT(*) FROM REGISTRATION WHERE TicketID = 1001 AND Status = 'Confirmed'
-- -----------------------------------------------------------------------------

-- Step 1A: BEFORE — Drop covering index idx_reg_ticket_status (Forces Table Scan)
ALTER TABLE `REGISTRATION` DROP INDEX `idx_reg_ticket_status`;
ANALYZE TABLE `REGISTRATION`;

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM `REGISTRATION`
WHERE `TicketID` = 1001 AND `Status` = 'Confirmed';

-- Step 1B: AFTER — Restore covering index idx_reg_ticket_status (Index-Only Scan)
ALTER TABLE `REGISTRATION` ADD INDEX `idx_reg_ticket_status` (`TicketID`, `Status`);
ANALYZE TABLE `REGISTRATION`;

EXPLAIN ANALYZE
SELECT COUNT(*)
FROM `REGISTRATION`
WHERE `TicketID` = 1001 AND `Status` = 'Confirmed';

-- -----------------------------------------------------------------------------
-- STUDY 2: Event Registration Lookup & Revenue Aggregation (RQ-01)
-- -----------------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    e.EventID,
    e.EventName,
    COUNT(r.RegistrationID) AS ConfirmedCount,
    COALESCE(SUM(p.AmountPaid), 0.00) AS TotalRevenue
FROM `EVENT` e
LEFT JOIN `REGISTRATION` r ON e.EventID = r.EventID AND r.Status = 'Confirmed'
LEFT JOIN `PAYMENT` p ON r.RegistrationID = p.RegistrationID
WHERE e.EventID = 105
GROUP BY e.EventID, e.EventName;

-- -----------------------------------------------------------------------------
-- STUDY 3: Keyset Pagination vs. Offset Pagination on REGISTRATION
-- -----------------------------------------------------------------------------

-- Step 3A: Deep OFFSET Pagination (Scans and discards 40,000 rows)
EXPLAIN ANALYZE
SELECT `RegistrationID`, `AttendeeID`, `EventID`, `TicketID`, `Status`, `AcceptedPrice`
FROM `REGISTRATION`
ORDER BY `RegistrationID` ASC
LIMIT 50 OFFSET 40000;

-- Step 3B: Keyset Seek Pagination (Direct Primary Key range seek)
EXPLAIN ANALYZE
SELECT `RegistrationID`, `AttendeeID`, `EventID`, `TicketID`, `Status`, `AcceptedPrice`
FROM `REGISTRATION`
WHERE `RegistrationID` > 41000
ORDER BY `RegistrationID` ASC
LIMIT 50;
