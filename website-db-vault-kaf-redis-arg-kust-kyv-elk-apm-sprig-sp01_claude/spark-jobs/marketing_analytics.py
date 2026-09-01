"""
Spark job: agregacja zdarzen z tematu Kafka 'marketing-events'
(np. liczba zgod marketingowych dziennie) i zapis wynikow do Postgresql,
skad Grafana/Spring-app moga je pokazac.
Uruchamiane cyklicznie na spark-master/spark-worker (spark-submit) lub jako CronJob.
"""
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, window, count
from pyspark.sql.types import StructType, StringType

KAFKA_BOOTSTRAP = "kafka-kraft:9092"
JDBC_URL = "jdbc:postgresql://postgres-clusterip:5432/davtro"

schema = StructType() \
    .add("event_id", StringType()) \
    .add("guest_email", StringType()) \
    .add("guest_name", StringType()) \
    .add("type", StringType())

if __name__ == "__main__":
    spark = SparkSession.builder.appName("marketing-analytics").getOrCreate()

    df = spark.readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP) \
        .option("subscribe", "marketing-events") \
        .load()

    parsed = df.select(from_json(col("value").cast("string"), schema).alias("data")).select("data.*")

    agg = parsed.groupBy(window(parsed.event_id, "1 hour")).agg(count("*").alias("events_count"))

    query = agg.writeStream \
        .outputMode("update") \
        .format("console") \
        .start()

    query.awaitTermination()
