#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR/hudi-datalake"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
CONNECTOR_FILE="$PROJECT_DIR/connector.json"
CONNECT_URL="http://localhost:8083/connectors"
CONNECT_NAME="transactions-connector"

MAX_RETRIES="${MAX_RETRIES:-60}"
SLEEP_SECONDS="${SLEEP_SECONDS:-3}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--skip-connector]

Starts core services in sequence and waits for readiness checks.
Environment overrides:
  MAX_RETRIES   Number of retries per readiness check (default: 60)
  SLEEP_SECONDS Sleep between retries in seconds (default: 3)

Options:
  --skip-connector  Skip Debezium connector registration
  -h, --help        Show this help message
EOF
}

SKIP_CONNECTOR="false"
if [[ "${1:-}" == "--skip-connector" ]]; then
  SKIP_CONNECTOR="true"
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ -n "${1:-}" ]]; then
  echo "Unknown argument: $1"
  usage
  exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1; then
  echo "docker-compose not found in PATH"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found in PATH"
  exit 1
fi

run_compose() {
  docker-compose -f "$COMPOSE_FILE" "$@"
}

wait_for_tcp() {
  local host="$1"
  local port="$2"
  local name="$3"

  echo "Waiting for $name at $host:$port ..."
  for ((i = 1; i <= MAX_RETRIES; i++)); do
    if timeout 1 bash -c "</dev/tcp/$host/$port" >/dev/null 2>&1; then
      echo "$name is reachable"
      return 0
    fi
    sleep "$SLEEP_SECONDS"
  done

  echo "Timed out waiting for $name at $host:$port"
  return 1
}

wait_for_http() {
  local url="$1"
  local name="$2"

  echo "Waiting for $name at $url ..."
  for ((i = 1; i <= MAX_RETRIES; i++)); do
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' "$url" || true)"
    if [[ "$code" =~ ^2[0-9][0-9]$ ]]; then
      echo "$name is responding (HTTP $code)"
      return 0
    fi
    sleep "$SLEEP_SECONDS"
  done

  echo "Timed out waiting for $name at $url"
  return 1
}

wait_for_container_cmd() {
  local container="$1"
  local name="$2"
  shift 2

  echo "Waiting for $name in container $container ..."
  for ((i = 1; i <= MAX_RETRIES; i++)); do
    if docker exec "$container" "$@" >/dev/null 2>&1; then
      echo "$name is ready"
      return 0
    fi
    sleep "$SLEEP_SECONDS"
  done

  echo "Timed out waiting for $name in container $container"
  return 1
}

wait_for_container_running() {
  local container="$1"
  local name="$2"

  echo "Waiting for container $name ($container) to be running ..."
  for ((i = 1; i <= MAX_RETRIES; i++)); do
    local status
    status="$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null || true)"
    if [[ "$status" == "running" ]]; then
      echo "$name container is running"
      return 0
    fi
    sleep "$SLEEP_SECONDS"
  done

  echo "Timed out waiting for container $name ($container)"
  return 1
}

start_service() {
  local service="$1"
  echo "Starting service: $service"
  run_compose up -d "$service"
  sleep "$SLEEP_SECONDS"
}

echo "Starting services in sequence..."
start_service minio
wait_for_tcp localhost 9000 "MinIO API"

start_service postgres
wait_for_container_cmd hudidb "Postgres" pg_isready -U postgres

start_service zookeeper
wait_for_tcp localhost 2181 "Zookeeper"

start_service kafka
wait_for_tcp localhost 9092 "Kafka"

start_service schema-registry
wait_for_http "http://localhost:8081/subjects" "Schema Registry"

start_service debezium
wait_for_http "http://localhost:8083/connectors" "Debezium Connect"

start_service metastore-db
wait_for_container_running metastore-db "Metastore DB"

start_service hive-metastore
wait_for_tcp localhost 9083 "Hive Metastore"

start_service trino
wait_for_http "http://localhost:8080/v1/info" "Trino"

start_service mc
wait_for_container_running mc "MinIO Client"

if [[ "$SKIP_CONNECTOR" == "false" ]]; then
  echo "Ensuring Debezium connector exists: $CONNECT_NAME"
  status_code="$(curl -s -o /dev/null -w '%{http_code}' "$CONNECT_URL/$CONNECT_NAME" || true)"

  if [[ "$status_code" == "200" ]]; then
    echo "Connector already exists"
  else
    create_code="$(curl -s -o /tmp/connector-create.out -w '%{http_code}' -X POST "$CONNECT_URL" \
      -H 'Content-Type: application/json' \
      --data @"$CONNECTOR_FILE" || true)"

    if [[ "$create_code" == "201" || "$create_code" == "409" ]]; then
      echo "Connector create call completed (HTTP $create_code)"
    else
      echo "Connector creation failed (HTTP $create_code)"
      cat /tmp/connector-create.out || true
      exit 1
    fi
  fi

  echo "Connector status:"
  curl -s "$CONNECT_URL/$CONNECT_NAME/status" || true
  echo
fi

echo "All core services are up in sequence."
echo "Next: run 'make streamer' in another terminal for continuous ingestion."
