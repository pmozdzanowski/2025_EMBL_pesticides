#!/bin/bash
#SBATCH --job-name=invitrodb43
#SBATCH --cpus-per-task=4
#SBATCH --mem=80G
#SBATCH --time=48:00:00
#SBATCH --output=invitrodb43_%j.out
#SBATCH --error=invitrodb43_%j.err

set -euo pipefail

module load mysql

TARGET_DIR="../02_outputs/invitrodb"
DB_NAME="invitrodb_v4_3"

MYSQL_DIR="$TARGET_DIR/mysql_data_v4_3"
SOCKET="$TARGET_DIR/mysql_v4_3.sock"

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# Download invitroDB v4.3 MySQL dump
curl -L -o "$TARGET_DIR/blob" "https://clowder.edap-cluster.com/datasets/687e3940e4b02565bc3e291e?space=687e388ce4b02565bc3e28e4#"

mv "$TARGET_DIR/blob" "$TARGET_DIR/invitrodb_v4_3_mysql.gz"

# Unzip the compressed sql dump
gunzip -f invitrodb_v4_3_mysql.gz

# Initialise local MySQL database directory
mkdir -p "$MYSQL_DIR"

if [ ! -d "$MYSQL_DIR/mysql" ]; then
    mysqld --no-defaults --initialize-insecure --datadir="$MYSQL_DIR"
fi

# Start local MySQL server
mysqld --no-defaults \
    --datadir="$MYSQL_DIR" \
    --socket="$SOCKET" \
    --skip-networking \
    --local-infile=1 &

sleep 20

# Create empty database
mysql --socket="$SOCKET" -u root -e "DROP DATABASE IF EXISTS $DB_NAME;"
mysql --socket="$SOCKET" -u root -e "CREATE DATABASE $DB_NAME;"

# Import into database
mysql --socket="$SOCKET" -u root "$DB_NAME" < invitrodb_v4_3_mysql

# Verify data is there
mysql --socket="$SOCKET" -u root -e "USE $DB_NAME; SHOW TABLES;"

# Stop MySQL server
mysqladmin --socket="$SOCKET" -u root shutdown
