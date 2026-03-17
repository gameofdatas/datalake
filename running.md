# Running Guide (Simple)

This is the quickest end-to-end way to run CDC (Postgres -> Kafka/Debezium -> Hudi on MinIO -> Trino).

## Architecture diagram (editable)

Use editable source: `screenshots/diagram-v2.mmd`

If you want to update the diagram image in `readme.md` (`screenshots/diagram.jpg`), keep these flows in sync:

- `PostgreSQL -> Debezium -> Kafka`
- `Spark Hudi Streamer <- Kafka + Schema Registry`
- `Spark -> MinIO (Hudi files)`
- `Spark -> Hive Metastore (table sync)`
- `Trino -> Hive Metastore + MinIO`

## 1) Start services

From project root:

```bash
cd hudi-datalake
docker-compose up -d
```

Verify:

```bash
docker ps
```

You should see containers like: `hudidb`, `kafka`, `schema-registry`, `hive-metastore`, `trino`, `minio`.

## 2) Create Debezium connector

```bash
curl -X POST http://localhost:8083/connectors \
  -H 'Content-Type: application/json' \
  --data @hudi-datalake/connector.json
```

Check status:

```bash
curl http://localhost:8083/connectors/transactions-connector/status
```

## 3) Start Hudi streamer in continuous mode

Keep this running in a separate terminal:

```bash
docker-compose -f /home/rahulkumarsingh/ScalaWorkspace/datalake/hudi-datalake/docker-compose.spark.yml run --rm spark-hudi-streamer
```

## 4) Generate source CDC changes (INSERT/UPDATE/DELETE)

Run from any terminal:

```bash
docker exec hudidb psql -U postgres -d dev -c "ALTER TABLE v1.retail_transactions REPLICA IDENTITY FULL;"

docker exec hudidb psql -U postgres -d dev -c "SET search_path TO v1; INSERT INTO retail_transactions VALUES (1001, CURRENT_DATE, 11, 'BOSTON', 'MA', 2, 44.50);"

docker exec hudidb psql -U postgres -d dev -c "SET search_path TO v1; UPDATE retail_transactions SET quantity = quantity + 1, total = total + 10 WHERE tran_id = 2;"

docker exec hudidb psql -U postgres -d dev -c "SET search_path TO v1; DELETE FROM retail_transactions WHERE tran_id = 3;"
```

## 5) Query in Trino (Presto)

```bash
docker exec -it trino trino --execute "SHOW TABLES FROM hudi.default;"

docker exec -it trino trino --execute "SELECT tran_id, store_city, quantity, total FROM hudi.default.retail_transactions ORDER BY tran_id;"
```

## 6) Stop

Stop only services:

```bash
cd hudi-datalake
docker-compose down
```

Stop and remove volumes (full reset):

```bash
cd hudi-datalake
docker-compose down -v
```

---

## Notes

- Use `config/spark-config-s3.properties` when Spark runs on host.
- Use `config/spark-config-s3-docker.properties` when Spark runs in Docker.
- If `docker-compose` shows `ContainerConfig` recreate issues, run:
  - `cd hudi-datalake && docker-compose down --remove-orphans && docker-compose up -d`
