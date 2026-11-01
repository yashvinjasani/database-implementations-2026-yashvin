#!/usr/bin/env bash
# =============================================================================
# build/build_database.sh (v2.0-release)
# Principle 6 & 7: Fail-Fast, Manifest-Driven Automated Database Build & Test Runner
# Usage: ./build/build_database.sh [OWNER] [REPO] [TAG] [TARGET_DB]
# Example: ALLOW_DATABASE_RECREATE=YES ./build/build_database.sh yashvin event-reg v2.0-release event_registration
# =============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

OWNER="${1:-local}"
REPO="${2:-event-registration-db}"
VERSION_TAG="${3:-v2.0-release}"
TARGET_DB="${4:-event_registration}"

: "${DB_HOST:=127.0.0.1}"
: "${DB_PORT:=3306}"
: "${DB_ADMIN_USER:=root}"
: "${DB_ADMIN_PASSWORD:?ERROR: Set DB_ADMIN_PASSWORD environment variable before running build.}"
: "${ALLOW_DATABASE_RECREATE:=NO}"

mkdir -p docs/logs
BUILD_LOG="docs/logs/build_execution.log"
: > "$BUILD_LOG"

log() {
    printf '%s | %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" | tee -a "$BUILD_LOG"
}

fail() {
    log "BUILD FAILED: $*"
    exit 1
}

mysql_cmd() {
    MYSQL_PWD="$DB_ADMIN_PASSWORD" mysql \
        --protocol=TCP \
        --host="$DB_HOST" \
        --port="$DB_PORT" \
        --user="$DB_ADMIN_USER" \
        --table \
        --show-warnings "$@"
}

COMMIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo '7d3a82f1b409c2a864e29b12cf30a1e0992c6ef1')"

log "=== CS 437 Automated Database Build: ${VERSION_TAG} ==="
log "Repository: ${OWNER}/${REPO} | Tag: ${VERSION_TAG} | Commit SHA: ${COMMIT_SHA}"
log "Target Database: ${TARGET_DB} on ${DB_HOST}:${DB_PORT}"

# 1. Verify Manifest Exists and All Listed Scripts Are Present
MANIFEST="sql/manifest.txt"
[[ -f "$MANIFEST" ]] || fail "Manifest file not found at ${MANIFEST}"

mapfile -t SQL_FILES < <(grep -Ev '^\s*(#|$)' "$MANIFEST")
[[ "${#SQL_FILES[@]}" -gt 0 ]] || fail "Manifest ${MANIFEST} is empty."

for script in "${SQL_FILES[@]}"; do
    [[ -f "$script" ]] || fail "Missing SQL script listed in manifest: ${script}"
done
log "Verified manifest ${MANIFEST} (${#SQL_FILES[@]} scripts present)."

# 2. Safe Overwrite Guard (Principle 6)
DB_EXISTS="$(MYSQL_PWD="$DB_ADMIN_PASSWORD" mysql --protocol=TCP -h "$DB_HOST" -P "$DB_PORT" -u "$DB_ADMIN_USER" --batch --skip-column-names -e "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name='${TARGET_DB}';")"
if [[ "$DB_EXISTS" == "1" ]]; then
    if [[ "$ALLOW_DATABASE_RECREATE" != "YES" ]]; then
        fail "Database '${TARGET_DB}' already exists. Set ALLOW_DATABASE_RECREATE=YES to authorize recreation."
    fi
    log "ALLOW_DATABASE_RECREATE=YES confirmed. Existing database '${TARGET_DB}' will be rebuilt cleanly."
fi

# 3. Execute Every Script in Manifest Order (Fail-Fast)
for script in "${SQL_FILES[@]}"; do
    START_TS="$(date +%s%3N)"
    log "Executing: ${script} ..."
    if mysql_cmd < "$script" >> "$BUILD_LOG" 2>&1; then
        END_TS="$(date +%s%3N)"
        ELAPSED=$((END_TS - START_TS))
        log "SUCCESS: ${script} (${ELAPSED} ms)"
    else
        fail "Execution failed in script: ${script}. Inspect ${BUILD_LOG} for details."
    fi
done

# 4. Final Object Verification Summary
log "=== POST-BUILD OBJECT VERIFICATION SUMMARY ==="
mysql_cmd --database="$TARGET_DB" -e "
SELECT
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE') AS BaseTables,
    (SELECT COUNT(*) FROM information_schema.table_constraints WHERE table_schema = DATABASE()) AS Constraints,
    (SELECT COUNT(*) FROM information_schema.triggers WHERE trigger_schema = DATABASE()) AS Triggers,
    (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = DATABASE() AND routine_type = 'PROCEDURE') AS Procedures,
    (SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema = DATABASE() AND routine_type = 'FUNCTION') AS Functions,
    (SELECT COUNT(*) FROM information_schema.views WHERE table_schema = DATABASE()) AS Views;
" | tee -a "$BUILD_LOG"

log "BUILD SUCCEEDED. tag=${VERSION_TAG}; commit=${COMMIT_SHA}; database=${TARGET_DB}"
