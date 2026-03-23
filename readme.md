# In-House Data Lake with CDC Processing, Apache Hudi, and Trino

Welcome to the In-House Data Lake project! This comprehensive data lake solution empowers organizations to efficiently
manage and process data in real-time. It seamlessly captures Change Data Capture (CDC) records from PostgreSQL using
Debezium, streams them to Apache Kafka with Schema Registry, and performs incremental data processing with Apache Hudi.
Processed data is stored in MinIO S3, with table metadata managed by Hive Metastore and exposed for interactive SQL
queries via Trino (Presto). The entire setup is containerized with Docker for easy deployment, and it requires Docker
and Apache Spark 3.4 installed as prerequisites.

![](screenshots/diagram.jpg)

> Editable source for this architecture diagram: `screenshots/diagram-v2.mmd`

```mermaid
flowchart LR
  subgraph Source[Source Database]
    PG[(PostgreSQL\n`hudidb`)]
  end

  subgraph CDC[CDC Layer]
    DBZ[Debezium Connect\n:8083]
    KAFKA[(Kafka)]
    SR[Schema Registry\n:8081]
  end

  subgraph Lake[Data Lake on MinIO]
    SPARK[Hudi Streamer\nSpark 3.4]
    MINIO[(MinIO S3\nwarehouse bucket)]
    HMS[Hive Metastore\n:9083]
  end

  subgraph Query[Query Layer]
    TRINO[Trino / Presto\n:8080]
  end

  USER[[User / SQL Client]]

  PG -- WAL/CDC --> DBZ
  DBZ --> KAFKA
  DBZ --> SR
  SPARK -->|read CDC| KAFKA
  SPARK -->|schema| SR
  SPARK -->|write Hudi table| MINIO
  SPARK -->|sync table metadata| HMS
  TRINO -->|read metadata| HMS
  TRINO -->|read Hudi files| MINIO
  USER -->|run SQL| TRINO

```

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)


## Prerequisites

Before you begin, ensure you have the following prerequisites installed on your system:

- Docker
- Apache Spark 3.4

## Getting Started

To get started with this project, follow these steps:

1. Clone the repository:
   ```bash
   git clone git@github.com:Rahul7794/datalake.git
   cd datalake

2. Build and run the Docker containers:
   ```bash
   cd hudi-datalake
   docker-compose up -d
   ```
3. Once the docker containers are up and running, one should be able to view the containers by:
   ```bash
   docker ps
   ```
   List of containers looks like this:
   ![](screenshots/dockerps.png)
4. Now It's time to run the debezium postgres connectors which dumps cdc changes to kafka topics
   ```bash
   curl -H 'Content-Type: application/json' localhost:8083/connectors --data '
   {
   "name": "transactions-connector",
   "config": {
   "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
   "database.hostname": "hudidb",
   "plugin.name": "pgoutput",
   "database.port": "5432",
   "database.user": "postgres",
   "database.password": "root123",
   "database.dbname" : "dev",
   "topic.prefix": "test",
   "database.server.name": "test1",
   "schema.include.list": "v1"
    }
   }'
   ```
   | Property                       | Description                                                       | Example Value         |
      |---------------------------------|-------------------------------------------------------------------|-----------------------|
   | `name`                          | Name of the connector, unique within Kafka Connect.               | `transactions-connector` |
   | `connector.class`               | Class of the connector to be used (Debezium connector for PostgreSQL). | `io.debezium.connector.postgresql.PostgresConnector` |
   | `database.hostname`             | Hostname of the PostgreSQL database server.                        | `hudidb`               |
   | `plugin.name`                   | Name of the PostgreSQL plugin to be used for capturing changes.    | `pgoutput`             |
   | `database.port`                 | Port on which the PostgreSQL database is listening.                | `5432`                  |
   | `database.user`                 | Username to connect to the PostgreSQL database.                    | `postgres`              |
   | `database.password`             | Password for the PostgreSQL user.                                  | `root123`               |
   | `database.dbname`               | Name of the PostgreSQL database from which change data should be captured. | `dev`                   |
   | `topic.prefix`                  | Prefix for Kafka topics to which change data will be streamed.     | `test`                  |
   | `database.server.name`          | Unique name for this database server (used as a namespace for Kafka topics). | `test1`                 |
   | `schema.include.list`           | Schema(s) within the database to monitor for changes.              | `v1`                    |

5. Now verify the topic information by running below command:
   ```bash
   docker run --tty \
   --network psql-kafka_default \
   confluentinc/cp-kafkacat \
   kafkacat -b kafka:9092 -C \
   -s key=s -s value=avro \
   -r http://schema-registry:8081 \
   -t test1.v1.retail_transactions
   ```
6. Once the data is in kafka topic, we can now run the hudi deltastreamer which takes cdc changes from kafka and
   performs a continuous incremental processing and dumps processed data to defined location(localfolder/s3). <br>
   After verfiying spark version and downloading jar in the location `utilities-jar` by downloading the jar from the url
   mentioned in `utilities-jar/jar.txt`

   ```bash
   spark-submit \
   --class org.apache.hudi.utilities.deltastreamer.HoodieDeltaStreamer \
   --packages org.apache.hudi:hudi-spark3.4-bundle_2.12:0.14.0 \
   --properties-file config/spark-config.properties \
   --master 'local[*]' \
   --executor-memory 1g \
   utilities-jar/hudi-utilities-slim-bundle_2.12-0.14.0.jar \
   --table-type COPY_ON_WRITE \
   --target-base-path file:///Users/rahul/PythonWorkSpace/datalake/hudidb/  \
   --target-table retail_transactions \
   --source-ordering-field tran_date \
   --source-class org.apache.hudi.utilities.sources.debezium.PostgresDebeziumSource \
   --payload-class org.apache.hudi.common.model.debezium.PostgresDebeziumAvroPayload \
   --op UPSERT \
   --continuous \
   --source-limit 4000000 \
   --min-sync-interval-seconds 20 \
   --hoodie-conf bootstrap.servers=localhost:9092 \
   --hoodie-conf schema.registry.url=http://localhost:8081 \
   --hoodie-conf hoodie.deltastreamer.schemaprovider.registry.url=http://localhost:8081/subjects/test1.v1.retail_transactions-value/versions/latest \
   --hoodie-conf hoodie.deltastreamer.source.kafka.value.deserializer.class=io.confluent.kafka.serializers.KafkaAvroDeserializer \
   --hoodie-conf hoodie.deltastreamer.source.kafka.topic=test1.v1.retail_transactions \
   --hoodie-conf auto.offset.reset=earliest \
   --hoodie-conf hoodie.datasource.write.recordkey.field=tran_id \
   --hoodie-conf hoodie.datasource.write.partitionpath.field=store_city \
   --hoodie-conf hoodie.datasource.write.keygenerator.class=org.apache.hudi.keygen.SimpleKeyGenerator \
   --hoodie-conf hoodie.datasource.write.hive_style_partitioning=true \
   --hoodie-conf hoodie.datasource.write.precombine.field=tran_date
   ```
   **Command explanation**

| Property                              | Description                                     | Example Value                                      |
|---------------------------------------|-------------------------------------------------|----------------------------------------------------|
| `--class`                             | Main class to be executed with Spark.            | `org.apache.hudi.utilities.deltastreamer.HoodieDeltaStreamer` |
| `--packages`                          | Comma-separated list of packages to be used by Spark. | `org.apache.hudi:hudi-spark3.4-bundle_2.12:0.14.0` |
| `--properties-file`                   | Path to the properties file containing Spark configuration. | `config/spark-config.properties`                 |
| `--master`                            | Specifies the Spark master URL.                  | `'local[*]'`                                       |
| `--executor-memory`                   | Amount of memory to allocate per executor.       | `1g`                                               |
| `<utilities-jar>`                    | Path to the Hudi utilities JAR file.             | `utilities-jar/hudi-utilities-slim-bundle_2.12-0.14.0.jar` |
| `--table-type`                        | Type of the Hudi table (COPY_ON_WRITE or MERGE_ON_READ). | `COPY_ON_WRITE`                                |
| `--target-base-path`                  | Base path where the Hudi dataset will be stored. | `file:///Users/rahul/PythonWorkSpace/datalake/hudidb/` |
| `--target-table`                      | Name of the target Hudi table.                   | `retail_transactions`                              |
| `--source-ordering-field`             | Field used for ordering incoming records.        | `tran_date`                                      |
| `--source-class`                      | Source class for reading data (e.g., Debezium source). | `org.apache.hudi.utilities.sources.debezium.PostgresDebeziumSource` |
| `--payload-class`                     | Class for parsing the payload (e.g., Debezium Avro payload). | `org.apache.hudi.common.model.debezium.PostgresDebeziumAvroPayload` |
| `--op`                                | Operation type (e.g., UPSERT).                   | `UPSERT`                                         |
| `--continuous`                        | Indicates continuous streaming mode.             | (Flag, no value)                                 |
| `--source-limit`                      | Maximum number of records to read from the source. | `4000000`                                      |
| `--min-sync-interval-seconds`         | Minimum sync interval in seconds.                | `20`                                             |
| `--hoodie-conf`                       | Various Hudi configuration properties. Multiple flags can be used with different properties. | (Multiple properties, see examples below) |
| `bootstrap.servers`                   | Kafka bootstrap servers for connecting to Kafka. | `localhost:9092`                                |
| `schema.registry.url`                 | URL for the Avro Schema Registry.               | `http://localhost:8081`                         |
| `hoodie.deltastreamer.schemaprovider.registry.url` | URL for the schema provider in DeltaStreamer. | `http://localhost:8081/subjects/test1.v1.retail_transactions-value/versions/latest` |
| `hoodie.deltastreamer.source.kafka.value.deserializer.class` | Kafka Avro deserializer class. | `io.confluent.kafka.serializers.KafkaAvroDeserializer` |
| `hoodie.deltastreamer.source.kafka.topic` | Kafka topic for source data.                | `test1.v1.retail_transactions`                  |
| `auto.offset.reset`                   | Kafka offset reset strategy.                    | `earliest`                                       |
| `hoodie.datasource.write.recordkey.field` | Field in the record used as the record key.   | `tran_id`                                        |
| `hoodie.datasource.write.partitionpath.field` | Field used for partitioning the data.       | `store_city`                                     |
| `hoodie.datasource.write.keygenerator.class` | Key generator class for Hudi.               | `org.apache.hudi.keygen.SimpleKeyGenerator`     |
| `hoodie.datasource.write.hive_style_partitioning` | Enable Hive-style partitioning.           | `true`                                           |
| `hoodie.datasource.write.precombine.field` | Field for pre-combining records.           | `tran_date`                                      |

   The above writes the data to localfolder mentioned in `--target-base-path` <br>

   If we want to dump records to localstack s3 we need pass few extra properties information mentioned in `config/spark-config-s3.properties` and the spark submit commands will change slightly:

   ```bash
   spark-submit \
   --class org.apache.hudi.utilities.streamer.HoodieStreamer \
   --packages 'org.apache.hudi:hudi-spark3.4-bundle_2.12:0.14.0,org.apache.hadoop:hadoop-aws:3.3.2' \
   --repositories 'https://repo.maven.apache.org/maven2' \
   --properties-file config/spark-config-s3.properties \
   --master 'local[*]' \
   --executor-memory 1g \
   utilities-jar/hudi-utilities-slim-bundle_2.12-0.14.0.jar \
   --table-type COPY_ON_WRITE \
   --target-base-path s3a://warehouse/retail_transactions/  \
   --target-table retail_transactions \
   --source-ordering-field tran_date \
   --source-class org.apache.hudi.utilities.sources.debezium.PostgresDebeziumSource \
   --payload-class org.apache.hudi.common.model.debezium.PostgresDebeziumAvroPayload \
   --op UPSERT \
    --continuous \
    --source-limit 4000000 \
    --min-sync-interval-seconds 20 \
   --hoodie-conf bootstrap.servers=localhost:9092 \
   --hoodie-conf schema.registry.url=http://localhost:8081 \
   --hoodie-conf hoodie.deltastreamer.schemaprovider.registry.url=http://localhost:8081/subjects/test1.v1.retail_transactions-value/versions/latest \
   --hoodie-conf hoodie.deltastreamer.source.kafka.value.deserializer.class=io.confluent.kafka.serializers.KafkaAvroDeserializer \
   --hoodie-conf hoodie.deltastreamer.source.kafka.topic=test1.v1.retail_transactions \
   --hoodie-conf auto.offset.reset=earliest \
   --hoodie-conf hoodie.datasource.write.recordkey.field=tran_id \
   --hoodie-conf hoodie.datasource.write.partitionpath.field=store_city \
   --hoodie-conf hoodie.datasource.write.keygenerator.class=org.apache.hudi.keygen.SimpleKeyGenerator \
   --hoodie-conf hoodie.datasource.write.hive_style_partitioning=true \
   --hoodie-conf hoodie.datasource.write.precombine.field=tran_date
   ```

8. Monitor the data flow and storage under the path mentioned in `--target-base-path`

![](screenshots/miniorefactor.jpg)

## Trino (Presto) query layer on top of Hudi in MinIO

To query Hudi data in MinIO with Trino, this repo now includes:

- Hive Metastore service (`hive-metastore`) for table metadata
- Trino coordinator (`trino`) with Hudi catalog
- Metastore DB (`metastore-db`)

### 1) Bring up enhanced stack

```bash
cd hudi-datalake
docker-compose up -d
```

This starts Trino at `http://localhost:8080` and Hive Metastore at `thrift://localhost:9083`.

### 1.1) Run Hudi streamer using Docker Compose

If you want to run the Spark Hudi job in a container (instead of local Spark), use:

```bash
cd hudi-datalake
docker-compose -f docker-compose.spark.yml run --rm spark-hudi-streamer
```

Notes:
- This uses the same command from `commands.txt` (S3 target + Hive sync) with container-friendly endpoints (`kafka`, `schema-registry`, `minio`, `hive-metastore`).
- Keep the main stack up first via `docker-compose up -d`.
- Ensure `utilities-jar/hudi-utilities-slim-bundle_2.12-0.14.0.jar` exists before running.
- Docker run uses `config/spark-config-s3-docker.properties` (endpoint `http://minio:9000`).

### 1.2) Continuous mode (recommended for live CDC)

The Spark container command already runs with `--continuous`, so keep it running in one terminal:

```bash
cd hudi-datalake
docker-compose -f docker-compose.spark.yml run --rm spark-hudi-streamer
```

Cleanup applied for continuous mode:
- Removed unnecessary `--source-limit` from containerized continuous job
- Removed redundant inline `spark.hadoop.fs.s3a.*` overrides (already in `config/spark-config-s3-docker.properties`)
- Switched deprecated keys to `hoodie.streamer.source.kafka.*`

### 2) Enable Hudi Hive sync in streamer job

When writing Hudi data to MinIO (`s3a://warehouse/retail_transactions/`), include the Hive sync properties:

```bash
--enable-hive-sync \
--hoodie-conf hoodie.datasource.hive_sync.enable=true \
--hoodie-conf hoodie.datasource.hive_sync.mode=hms \
--hoodie-conf hoodie.datasource.hive_sync.metastore.uris=thrift://localhost:9083 \
--hoodie-conf hoodie.datasource.hive_sync.database=default \
--hoodie-conf hoodie.datasource.hive_sync.table=retail_transactions \
--hoodie-conf hoodie.datasource.hive_sync.partition_fields=store_city \
--hoodie-conf hoodie.datasource.hive_sync.support_timestamp=true
```

This registers/updates the Hudi table metadata in Hive Metastore so Trino can discover it.

### 3) Query from Trino

Example checks:

```sql
SHOW CATALOGS;
SHOW SCHEMAS FROM hudi;
SHOW TABLES FROM hudi.default;
SELECT tran_id, tran_date, store_city, total
FROM hudi.default.retail_transactions
ORDER BY tran_id;
```

### 3.1) Generate INSERT/UPDATE/DELETE and watch changes in Presto/Trino

Run these against Postgres while streamer is in continuous mode:

```bash
docker exec -it hudidb psql -U postgres -d dev -c "SET search_path TO v1; INSERT INTO retail_transactions VALUES (1001, CURRENT_DATE, 11, 'BOSTON', 'MA', 2, 44.50);"
docker exec -it hudidb psql -U postgres -d dev -c "SET search_path TO v1; UPDATE retail_transactions SET quantity = quantity + 1, total = total + 10 WHERE tran_id = 2;"
docker exec -it hudidb psql -U postgres -d dev -c "SET search_path TO v1; DELETE FROM retail_transactions WHERE tran_id = 3;"
```

If UPDATE/DELETE fails with replica identity error on an existing DB, run once:

```bash
docker exec -it hudidb psql -U postgres -d dev -c "ALTER TABLE v1.retail_transactions REPLICA IDENTITY FULL;"
```

(`init.sh` now sets this automatically for fresh environments.)

Then query from Trino:

```sql
SELECT tran_id, store_city, quantity, total
FROM hudi.default.retail_transactions
ORDER BY tran_id;
```

You can also use the ready SQL file: `hudi-datalake/sql/retail_transactions_cdc.sql`.

### 4) What changed in this enhancement

- `hudi-datalake/docker-compose.yml`
   - Added `metastore-db`, `hive-metastore`, `trino` services
   - Parameterized MinIO/Postgres credentials through `.env`
- `hudi-datalake/.env`
   - Centralized local credentials for the stack
- `hudi-datalake/trino/etc/*`
   - Added Trino coordinator + Hudi catalog configuration for MinIO + HMS

## Project Structure

```bash
├── commands.txt
├── config
│   ├── spark-config-s3.properties
│   └── spark-config.properties
├── hudi-datalake
│   ├── connector.json
│   ├── .env
│   ├── docker-compose.yml
│   ├── docker-compose.spark.yml
│   ├── dockerfile
│   ├── hive
│   │   └── conf
│   │       └── core-site.xml
│   └── init.sh
│   ├── sql
│   │   └── retail_transactions_cdc.sql
│   └── trino
│       └── etc
│           ├── catalog
│           │   └── hudi.properties
│           ├── config.properties
│           ├── jvm.config
│           └── node.properties
├── readme.md
├── screenshots
│   └── dockerps.png
└── utilities-jar
    └── jar.txt
```


