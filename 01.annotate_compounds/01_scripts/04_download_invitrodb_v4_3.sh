#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$MODULE_DIR/02_outputs/invitrodb"

mkdir -p "$TARGET_DIR"

DB_DEFAULT="invitrodb_v4_3"
GZ_DUMP="$TARGET_DIR/invitrodb_v4_3_mysql.gz"
TMP_DOWNLOAD="$GZ_DUMP.download"

URL="https://clowder.edap-cluster.com/files/68c3365ce4b02565fc7cd3f3/blob"

cd "$TARGET_DIR"

echo "Target directory:"
echo "$TARGET_DIR"

echo "Checking Homebrew..."
command -v brew >/dev/null 2>&1 || {
    echo "Homebrew not found. Install Homebrew first." >&2
    exit 1
}

echo "Installing/checking MySQL 8.0..."
if ! brew list mysql@8.0 >/dev/null 2>&1; then
    brew install mysql@8.0
fi

MYSQL_PREFIX="$(brew --prefix mysql@8.0)"
export PATH="$MYSQL_PREFIX/bin:$PATH"

echo "Using MySQL:"
mysql --version

echo "Starting MySQL service..."
brew services start mysql@8.0 >/dev/null 2>&1 || true

echo "Waiting for MySQL server..."
for i in {1..60}; do
    if mysqladmin -u root ping --silent >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

mysqladmin -u root ping --silent

if [[ ! -s "$GZ_DUMP" ]]; then
    echo "Downloading invitroDB v4.3 MySQL dump..."
    curl \
        --fail \
        --location \
        --continue-at - \
        --connect-timeout 60 \
        --retry 10 \
        --retry-all-errors \
        --retry-delay 30 \
        --speed-limit 1024 \
        --speed-time 120 \
        --output "$TMP_DOWNLOAD" \
        "$URL"

    echo "Validating compressed SQL dump..."
    gzip -t "$TMP_DOWNLOAD"
    mv "$TMP_DOWNLOAD" "$GZ_DUMP"
fi

if [[ ! -s "$GZ_DUMP" ]]; then
    echo "Compressed SQL dump not found or empty: $GZ_DUMP" >&2
    exit 1
fi

echo "Validating compressed SQL dump..."
gzip -t "$GZ_DUMP"

echo "Detecting database name from dump..."

DUMP_DB_NAME="$(
    gzip -dc "$GZ_DUMP" \
    | grep -m 1 -E '^[[:space:]]*USE `[^`]+`;' \
    | sed -E 's/^[[:space:]]*USE `([^`]+)`;/\1/' \
    || true
)"

DB_NAME="${DUMP_DB_NAME:-$DB_DEFAULT}"

echo "Database name:"
echo "$DB_NAME"

echo "Preparing database..."
mysql -u root -e "
    DROP DATABASE IF EXISTS \`$DB_NAME\`;
    CREATE DATABASE \`$DB_NAME\`;
    SET GLOBAL max_allowed_packet = 1073741824;
"

echo "Importing compressed SQL dump by streaming directly into MySQL."
echo "This may take a long time..."

gzip -dc "$GZ_DUMP" | mysql \
    -u root \
    --binary-mode=1 \
    --max_allowed_packet=1G \
    "$DB_NAME"

echo "Verifying import..."
mysql -u root -e "
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
