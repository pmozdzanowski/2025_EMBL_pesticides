#!/bin/bash
#SBATCH --job-name=invitrodb43
#SBATCH --cpus-per-task=4
#SBATCH --mem=80G
#SBATCH --time=48:00:00
#SBATCH --output=slurm-%x-%j.out
#SBATCH --error=slurm-%x-%j.err

set -Eeuo pipefail

module load mysql/8.0.29

SUBMIT_DIR="${SLURM_SUBMIT_DIR:-$PWD}"
JOB_ID="${SLURM_JOB_ID:-manual}"

if [[ -d "$SUBMIT_DIR/00_inputs" && -d "$SUBMIT_DIR/01_scripts" ]]; then
    MODULE_DIR="$SUBMIT_DIR"
elif [[ -d "$SUBMIT_DIR/../00_inputs" && -d "$SUBMIT_DIR/../01_scripts" ]]; then
    MODULE_DIR="$(cd "$SUBMIT_DIR/.." && pwd)"
else
    echo "Could not locate module directory from SLURM_SUBMIT_DIR=$SUBMIT_DIR" >&2
    echo "Submit from 01.annotate_compounds or 01.annotate_compounds/01_scripts." >&2
    exit 1
fi

TARGET_DIR="$MODULE_DIR/02_outputs/invitrodb"
LOG_DIR="$MODULE_DIR/02_outputs/logs"

mkdir -p "$TARGET_DIR" "$LOG_DIR"

exec > >(tee -a "$LOG_DIR/invitrodb43_${JOB_ID}.out")
exec 2> >(tee -a "$LOG_DIR/invitrodb43_${JOB_ID}.err" >&2)

DEFAULT_DB_NAME="invitrodb_v4_3"

MYSQL_DIR="$TARGET_DIR/mysql_data_v4_3"
SOCKET="/tmp/invitrodb_v4_3_${USER}_${JOB_ID}.sock"
PID_FILE="$TARGET_DIR/mysql_${JOB_ID}.pid"
MYSQL_ERROR_LOG="$LOG_DIR/mysql_${JOB_ID}.err"

SQL_DUMP="$TARGET_DIR/invitrodb_v4_3_mysql"
GZ_DUMP="$SQL_DUMP.gz"
TMP_DOWNLOAD="$GZ_DUMP.download"
IMPORT_MARKER="$TARGET_DIR/invitrodb_v4_3.import_done"

URL="https://clowder.edap-cluster.com/files/68c3365ce4b02565fc7cd3f3/blob"

cd "$TARGET_DIR"

echo "Using MySQL:"
mysql --version

command -v mysql >/dev/null 2>&1 || { echo "mysql not found." >&2; exit 127; }
command -v mysqld >/dev/null 2>&1 || { echo "mysqld not found." >&2; exit 127; }

MYSQLD_BIN="$(command -v mysqld)"

MYSQL_CLIENT=(
    mysql
    --protocol=SOCKET
    --socket="$SOCKET"
    -u root
    --local-infile=1
    --binary-mode=1
    --max_allowed_packet=1G
)

MYSQL_ADMIN=(
    mysqladmin
    --protocol=SOCKET
    --socket="$SOCKET"
    -u root
)

cleanup() {
    if [[ -n "${MYSQLD_PID:-}" ]] && kill -0 "$MYSQLD_PID" 2>/dev/null; then
        "${MYSQL_ADMIN[@]}" shutdown >/dev/null 2>&1 || kill "$MYSQLD_PID" >/dev/null 2>&1 || true
    fi
    rm -f "$SOCKET"
}
trap cleanup EXIT

if [[ ! -s "$SQL_DUMP" ]]; then
    if [[ ! -s "$GZ_DUMP" ]]; then
        echo "Downloading invitroDB v4.3 MySQL dump..."
        curl --fail --location --retry 3 --retry-delay 10 -o "$TMP_DOWNLOAD" "$URL"
        mv "$TMP_DOWNLOAD" "$GZ_DUMP"
    fi

    echo "Decompressing SQL dump..."
    if command -v pigz >/dev/null 2>&1; then
        pigz -dkf -p "${SLURM_CPUS_PER_TASK:-4}" "$GZ_DUMP"
    else
        gzip -dkf "$GZ_DUMP"
    fi
fi

if [[ ! -s "$SQL_DUMP" ]]; then
    echo "SQL dump not found or empty: $SQL_DUMP" >&2
    exit 1
fi

DUMP_DB_NAME="$(
    grep -m 1 -E '^USE `[^`]+`;' "$SQL_DUMP" \
    | sed -E 's/^USE `([^`]+)`;/\1/' \
    || true
)"

DB_NAME="${DUMP_DB_NAME:-$DEFAULT_DB_NAME}"

echo "Database name for import: $DB_NAME"

if [[ ! -d "$MYSQL_DIR/mysql" ]]; then
    echo "Initialising MySQL data directory..."
    rm -rf "$MYSQL_DIR"
    mkdir -p "$MYSQL_DIR"

    "$MYSQLD_BIN" \
        --no-defaults \
        --initialize-insecure \
        --datadir="$MYSQL_DIR" \
        --log-error="$LOG_DIR/mysql_init_${JOB_ID}.err"
fi

echo "Starting local MySQL server..."

"$MYSQLD_BIN" \
    --no-defaults \
    --datadir="$MYSQL_DIR" \
    --socket="$SOCKET" \
    --pid-file="$PID_FILE" \
    --skip-networking \
    --skip-log-bin \
    --local-infile=1 \
    --max-allowed-packet=1G \
    --innodb-buffer-pool-size=48G \
    --innodb-log-file-size=2G \
    --innodb-flush-log-at-trx-commit=2 \
    --tmpdir="$TARGET_DIR" \
    --log-error="$MYSQL_ERROR_LOG" &

MYSQLD_PID=$!

echo "Waiting for MySQL server..."

for i in {1..120}; do
    if "${MYSQL_ADMIN[@]}" ping --silent >/dev/null 2>&1; then
        break
    fi

    if ! kill -0 "$MYSQLD_PID" 2>/dev/null; then
        echo "mysqld exited during startup. Error log:" >&2
        cat "$MYSQL_ERROR_LOG" >&2 || true
        exit 1
    fi

    sleep 2
done

"${MYSQL_ADMIN[@]}" ping --silent

if [[ -f "$IMPORT_MARKER" && "${FORCE_IMPORT:-0}" != "1" ]]; then
    echo "Import marker exists: $IMPORT_MARKER"
    echo "Skipping import. Set FORCE_IMPORT=1 to reimport."
else
    echo "Preparing database $DB_NAME..."

    "${MYSQL_CLIENT[@]}" -e "
        DROP DATABASE IF EXISTS \`$DB_NAME\`;
        CREATE DATABASE \`$DB_NAME\`;
    "

    echo "Importing SQL dump..."
    "${MYSQL_CLIENT[@]}" "$DB_NAME" < "$SQL_DUMP"

    date > "$IMPORT_MARKER"
fi

echo "Verifying import..."

"${MYSQL_CLIENT[@]}" -e "
    SHOW DATABASES;

    SELECT table_schema, COUNT(*) AS n_tables
    FROM information_schema.tables
    WHERE table_schema NOT IN ('mysql', 'information_schema', 'performance_schema', 'sys')
    GROUP BY table_schema
    ORDER BY table_schema;

    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = '$DB_NAME'
    ORDER BY table_name
    LIMIT 30;
"

echo "Import finished successfully."
