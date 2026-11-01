# Event Registration & Attendee Management System (`v2.0-release`)
**Course:** 01:198:437 Database Systems Implementation  
**Database Engine:** MySQL 8.0+ (InnoDB, `utf8mb4_0900_ai_ci`)  

---

## 1. Architectural Overview & 11 Governing Principles

This repository contains the complete, production-hardened relational database implementation for the **Event Registration and Attendee Management System**, engineered from the ground up across all course principles:

1. **Normalized 3NF Relational Core:** 9 core operational tables (`USER`, `VENUE`, `EVENT`, `TICKET_TIER`, `SESSION`, `REGISTRATION`, `PAYMENT`, `SESSION_ROSTER`, `AUDIT_LOG`) plus 4 governance/metadata tables (`SCHEMA_VERSION`, `INDICATOR_VALUE`, `WORKFLOW_TRANSITION`, `APP_LOGIN_MAP`).
2. **Immutable Forensic Audit Trail:** `AUDIT_LOG` protected by `BEFORE UPDATE` and `BEFORE DELETE` immutability triggers (`trg_audit_log_bu_immutable`, `trg_audit_log_bd_immutable`).
3. **Zero-Trust Session Identity & RBAC:** Stored procedures derive the executing actor via `fn_current_user_id()` (`@current_user_id`) and map MySQL logins via `APP_LOGIN_MAP`.
4. **Metadata-Driven State Machine:** Check-in and registration lifecycle transitions are governed declaratively via `WORKFLOW_TRANSITION`.
5. **Structured Error Taxonomy:** Every custom `SIGNAL SQLSTATE '45000'` error is prefixed with `forbidden:`, `invalid:`, `conflict:`, or `not_found:`.
6. **Single-Entrypoint Fail-Fast Build:** Deterministic build orchestrated via `sql/manifest.txt` and `build/build_database.sh` (or `build/build_database.ps1`).
7. **Tagged Release Provenance:** Built and verified against Git release tag `v2.0-release`.
8. **In-Database Schema Versioning:** Tracked via `SCHEMA_VERSION` with non-destructive upgrade proof in `sql/07_schema_migration_v2.sql`.
9. **Empirical Performance at 50k+ Scale:** `sql/05_scale_data_generator.sql` loads 10,000 users and 50,000 registrations; `sql/06_performance_study_report.sql` proves a **506x speedup** (`24.81 ms -> 0.05 ms`) using covering index `idx_reg_ticket_status`.
10. **End-to-End Traceability:** Every requirement (`FR-01`–`FR-18`, `BR-01`–`BR-12`, `SEC-01`–`SEC-09`) traces to schema objects, tests, and committed logs in `docs/TRACEABILITY_MATRIX_AND_PROOF_LOG.md`.
11. **Metadata Indicator Value Pattern:** Domain statuses and roles are governed by `INDICATOR_VALUE` with composite foreign keys and exposed to UI clients via `v_ui_indicator_options`.

---

## 2. Repository Directory Structure

```text
project/
├── README.md                                        <-- Root documentation & quickstart
├── build/
│   ├── build_database.sh                            <-- Automated POSIX build & test runner
│   └── build_database.ps1                           <-- Automated PowerShell build & test runner
├── docs/
│   ├── FRD_Functional_Requirements_Document.md      <-- Functional Requirements Document
│   ├── TDD_Technical_Design_Document.md             <-- Technical Design Document
│   ├── MIDTERM_REVIEW_RESPONSES.md                  <-- Point-by-point midterm audit responses
│   ├── TRACEABILITY_MATRIX_AND_PROOF_LOG.md         <-- Requirements -> Objects -> Test results
│   ├── erd/
│   │   └── ERD_Event_Registration_v2.jpg            <-- Crow's Foot 3NF Entity-Relationship Diagram
│   └── logs/
│       ├── build_execution.log                      <-- Captured output of full build + test suite
│       ├── ac08_dual_session_proof.log              <-- Captured output of 2-session concurrency test
│       └── explain_analyze_scale_proof.log          <-- Captured output of 50k+ scale EXPLAIN ANALYZE
└── sql/
    ├── manifest.txt                                 <-- Authoritative ordered build manifest
    ├── 01_schema_ddl.sql                            <-- 3NF tables, metadata tables, views & roles
    ├── 02_triggers_and_procedures.sql               <-- 10 triggers & 5 session-authenticated procedures
    ├── 03_seed_data.sql                             <-- Baseline seed data (7 users, 2 venues, 2 events)
    ├── 04_test_suite_and_demo.sql                   <-- Automated acceptance test suite & 13 result tabs
    ├── 05_scale_data_generator.sql                  <-- Procedural generator (10k users, 50k registrations)
    ├── 06_performance_study_report.sql              <-- EXPLAIN ANALYZE before/after index & keyset study
    ├── 07_schema_migration_v2.sql                   <-- Idempotent v2.0 schema evolution & survival proof
    └── 08_concurrency_and_entitlement_proofs.sql    <-- RBAC login test & AC-08 concurrency verification
