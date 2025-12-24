#!/bin/bash

set -euo pipefail

# My token
DEFAULT_TOKEN="b81e8bdb8bbdbeb9"

# Using env variable
if [ -z "${HACKATTIC_TOKEN:-}" ]; then
    echo "HACKATTIC_TOKEN is not set, using default token"
    echo "Run: export HACKATTIC_TOKEN=\"your_token_here\""
    TOKEN="$DEFAULT_TOKEN"
else
    echo "Using token from environment variable HACKATTIC_TOKEN"
    TOKEN="$HACKATTIC_TOKEN"
fi

# Url backup_restore challenge
BASE_URL="https://hackattic.com/challenges/backup_restore"

# Unique container name
CONTAINER="hackattic-$(openssl rand -hex 6)"

# PostgreSQL Docker image and configuration
IMAGE="postgres:16.11-alpine3.23"
DB="hackattic"
USER="postgres"
PASS="postgres"

# Check for running docker
if ! docker info >/dev/null 2>&1; then
    echo "Docker is not running, please start it and rerun the script"
    exit 1
fi

# Check for image locally; pull if missing
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Postgres image not fount, pulling $IMAGE..."
    docker pull "$IMAGE"
fi

# Remove any existing container with same name
echo "Remove old container with same name"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

# Start container
echo "Starting container"
docker run -d \
  --name "$CONTAINER" \
  -e POSTGRES_PASSWORD="$PASS" \
  -e POSTGRES_DB="$DB" \
  "$IMAGE" >/dev/null

# Wait until container is ready
echo "Waiting for container"
until docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; do
  sleep 0.1
done

# Request task
echo "Fetch task"
DUMP_B64=$(curl -s "$BASE_URL/problem?access_token=$TOKEN&playground=1" | jq -r '.dump')

# Decode and restore dump
echo "Restoring dump"
echo "$DUMP_B64" \
  | base64 --decode \
  | gunzip \
  | sed -E '/default_with_oids/d; s/WITH[[:space:]]+OIDS//Ig' \
  | docker exec -i "$CONTAINER" psql -U "$USER" -d "$DB" >/dev/null

# Query alive_ssns with status 'alive'
echo "Query alive_ssns"
SSNS=$(docker exec "$CONTAINER" psql -U "$USER" -d "$DB" -At -c \
"SELECT COALESCE(json_agg(ssn), '[]') FROM criminal_records WHERE status = 'alive';")

# Build json
JSON=$(jq -n --argjson ssns "$SSNS" '{alive_ssns: $ssns}')

# POST solution
echo "POST solution"
RESULT=$(curl -s -X POST "$BASE_URL/solve?access_token=$TOKEN&playground=1" \
  -H "Content-Type: application/json" \
  -d "$JSON")

# Print result
echo "$RESULT"
