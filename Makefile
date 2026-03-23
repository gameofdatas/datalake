SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT_DIR := hudi-datalake
COMPOSE := docker-compose -f $(PROJECT_DIR)/docker-compose.yml
SPARK_COMPOSE := docker-compose -f $(PROJECT_DIR)/docker-compose.spark.yml
CONNECT_URL := http://localhost:8083/connectors
CONNECT_NAME := transactions-connector

.PHONY: help start start-quick stop reset ps connector connector-status streamer

help:
	@echo "Available targets:"
	@echo "  make start            Start services in sequence with readiness checks"
	@echo "  make start-quick      Start core services directly with docker-compose"
	@echo "  make stop             Stop core services"
	@echo "  make reset            Stop services and remove volumes (full reset)"
	@echo "  make ps               Show running containers"
	@echo "  make connector        Create Debezium connector from connector.json"
	@echo "  make connector-status Show Debezium connector status"
	@echo "  make streamer         Run Spark Hudi streamer in continuous mode"

start:
	@bash scripts/start-sequence.sh

start-quick:
	@echo "Starting data lake services (quick mode)..."
	@$(COMPOSE) up -d
	@echo "Services started. Run 'make ps' to verify."

stop:
	@echo "Stopping data lake services..."
	@$(COMPOSE) down
	@echo "Services stopped."

reset:
	@echo "Stopping and removing volumes (full reset)..."
	@$(COMPOSE) down -v
	@echo "Reset complete."

ps:
	@docker ps

connector:
	@echo "Creating Debezium connector ($(CONNECT_NAME))..."
	@curl -sS -X POST $(CONNECT_URL) \
		-H 'Content-Type: application/json' \
		--data @$(PROJECT_DIR)/connector.json || true
	@echo
	@echo "Done. If it already exists, use 'make connector-status'."

connector-status:
	@curl -sS $(CONNECT_URL)/$(CONNECT_NAME)/status
	@echo

streamer:
	@echo "Starting Spark Hudi streamer (continuous mode)..."
	@$(SPARK_COMPOSE) run --rm spark-hudi-streamer
