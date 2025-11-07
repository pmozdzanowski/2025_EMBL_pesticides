#!/bin/bash

TARGET_DIR="../data/invitrodb"

mkdir -p "$TARGET_DIR"

curl -L -o "$TARGET_DIR/blob" "https://clowder.edap-cluster.com/files/6481e47ce4b08a6b394e669f/blob"

mv "$TARGET_DIR/blob" "$TARGET_DIR/invitrodb_v4_1_mysql.gz"

# Install mysql version 8 on macOS
brew install mysql@8.0
brew link mysql@8.0 --force
brew services start mysql@8.0

# Create empty database
mysql -u root
CREATE DATABASE invitrodb_v4_1;
EXIT;

# Unzip the compressed sql dump (expanded size is ~100GB)
cd "$TARGET_DIR"
gunzip invitrodb_v4_1_mysql.gz

# Import into database
mysql -u root invitrodb_v4_1 < invitrodb_v4_1_mysql

# Log back in and verify data is there
mysql -u root
USE prod_internal_invitrodb_v4_1;
SHOW TABLES;