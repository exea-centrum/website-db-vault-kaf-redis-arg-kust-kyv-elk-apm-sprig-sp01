package com.davtroweb.analytics

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._
import org.apache.spark.sql.streaming.{OutputMode, Trigger}
import org.apache.spark.sql.{Dataset, Row}
import java.time.LocalDateTime
import scala.collection.JavaConverters._

object SurveyAnalytics {
  
  def main(args: Array[String]): Unit = {
    
    val spark = SparkSession.builder()
      .appName("SurveyAnalytics")
      .master("spark://spark-master:7077")
      .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
      .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer")
      .config("spark.kryoserializer.buffer.max", "512m")
      .getOrCreate()
    
    import spark.implicits._
    
    // Schemat danych ankietowych
    val surveySchema = StructType(Array(
      StructField("surveyId", StringType, nullable = false),
      StructField("userId", StringType, nullable = true),
      StructField("sessionId", StringType, nullable = false),
      StructField("answers", MapType(StringType, StringType), nullable = false),
      StructField("submittedAt", TimestampType, nullable = false),
      StructField("metadata", StructType(Array(
        StructField("surveyType", StringType, nullable = true),
        StructField("browser", StringType, nullable = true),
        StructField("ipAddress", StringType, nullable = true)
      )))
    ))
    
    // Czytaj dane z Kafka
    val kafkaStream = spark.readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", "kafka:9092")
      .option("subscribe", "survey-events")
      .option("startingOffsets", "latest")
      .load()
    
    // Przetwórz dane JSON
    val surveyStream = kafkaStream
      .select(from_json(col("value").cast("string"), surveySchema).as("data"))
      .select("data.*")
    
    // 1. Analiza sentymentu odpowiedzi tekstowych
    val textAnalysis = surveyStream
      .filter(col("answers").getItem("architecture_suggestions").isNotNull)
      .select(
        col("surveyId"),
        col("userId"),
        col("answers").getItem("architecture_suggestions").as("suggestion"),
        col("submittedAt")
      )
      .withColumn("suggestion_length", length(col("suggestion")))
      .withColumn("suggestion_words", size(split(col("suggestion"), " ")))
      .withColumn("sentiment_score", 
        when(col("suggestion").contains("dobr") || col("suggestion").contains("super") || 
             col("suggestion").contains("świetn"), 1.0)
        .when(col("suggestion").contains("kieps") || col("suggestion").contains("słab") || 
              col("suggestion").contains("problem"), -1.0)
        .otherwise(0.0)
      )
    
    // 2. Agregacje ocen
    val ratingAnalysis = surveyStream
      .filter(col("answers").getItem("spring_performance").isNotNull)
      .select(
        col("surveyId"),
        col("answers").getItem("spring_performance").as("rating"),
        col("submittedAt")
      )
      .withColumn("rating_numeric", 
        when(col("rating").contains("1"), 1)
        .when(col("rating").contains("2"), 2)
        .when(col("rating").contains("3"), 3)
        .when(col("rating").contains("4"), 4)
        .when(col("rating").contains("5"), 5)
        .otherwise(0)
      )
      .groupBy(window(col("submittedAt"), "5 minutes").as("window"))
      .agg(
        count("*").as("total_responses"),
        avg("rating_numeric").as("avg_rating"),
        stddev("rating_numeric").as("rating_stddev"),
        collect_list("rating_numeric").as("all_ratings")
      )
    
    // 3. Analiza popularności technologii
    val techAnalysis = surveyStream
      .filter(col("answers").getItem("java_tech_interest").isNotNull)
      .select(
        explode(split(col("answers").getItem("java_tech_interest"), ",")).as("technology"),
        col("submittedAt")
      )
      .withColumn("technology_clean", trim(col("technology")))
      .groupBy(col("technology_clean"))
      .agg(
        count("*").as("total_votes"),
        countDistinct("submittedAt").as("unique_sessions")
      )
      .orderBy(desc("total_votes"))
    
    // 4. Zapisz wyniki do MongoDB
    val query1 = textAnalysis.writeStream
      .outputMode(OutputMode.Append())
      .foreachBatch { (batchDF: Dataset[Row], batchId: Long) =>
        batchDF.write
          .format("mongo")
          .mode("append")
          .option("uri", "mongodb://mongodb:27017")
          .option("database", "survey_analytics")
          .option("collection", "text_analysis")
          .save()
      }
      .trigger(Trigger.ProcessingTime("30 seconds"))
      .start()
    
    val query2 = ratingAnalysis.writeStream
      .outputMode(OutputMode.Update())
      .foreachBatch { (batchDF: Dataset[Row], batchId: Long) =>
        batchDF.write
          .format("mongo")
          .mode("append")
          .option("uri", "mongodb://mongodb:27017")
          .option("database", "survey_analytics")
          .option("collection", "rating_analysis")
          .save()
      }
      .trigger(Trigger.ProcessingTime("1 minute"))
      .start()
    
    val query3 = techAnalysis.writeStream
      .outputMode(OutputMode.Complete())
      .foreachBatch { (batchDF: Dataset[Row], batchId: Long) =>
        batchDF.write
          .format("mongo")
          .mode("overwrite")
          .option("uri", "mongodb://mongodb:27017")
          .option("database", "survey_analytics")
          .option("collection", "tech_popularity")
          .save()
      }
      .trigger(Trigger.ProcessingTime("2 minutes"))
      .start()
    
    // 5. Zapisz logi do Elasticsearch
    val elkStream = surveyStream
      .select(
        lit("survey_event").as("type"),
        col("surveyId"),
        col("userId"),
        col("sessionId"),
        col("submittedAt"),
        to_json(col("answers")).as("answers_json"),
        lit(LocalDateTime.now().toString).as("@timestamp")
      )
    
    val query4 = elkStream.writeStream
      .outputMode(OutputMode.Append())
      .format("org.elasticsearch.spark.sql")
      .option("es.nodes", "elasticsearch")
      .option("es.port", "9200")
      .option("es.resource", "spark_surveys/_doc")
      .option("checkpointLocation", "/tmp/elk-checkpoint")
      .trigger(Trigger.ProcessingTime("10 seconds"))
      .start()
    
    // Czekaj na zakończenie
    spark.streams.awaitAnyTermination()
  }
}
