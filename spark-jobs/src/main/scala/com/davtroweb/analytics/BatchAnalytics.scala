package com.davtroweb.analytics

import org.apache.spark.sql.SparkSession
import org.apache.spark.sql.functions._
import org.apache.spark.sql.expressions.Window
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

object BatchAnalytics {
  
  def main(args: Array[String]): Unit = {
    
    val spark = SparkSession.builder()
      .appName("BatchSurveyAnalytics")
      .master("spark://spark-master:7077")
      .config("spark.mongodb.input.uri", "mongodb://mongodb:27017/survey_db.survey_responses")
      .config("spark.mongodb.output.uri", "mongodb://mongodb:27017/survey_analytics")
      .getOrCreate()
    
    import spark.implicits._
    
    // Czytaj dane z MongoDB
    val surveyDF = spark.read
      .format("mongo")
      .option("database", "survey_db")
      .option("collection", "survey_responses")
      .load()
    
    // 1. Dzienne statystyki
    val dailyStats = surveyDF
      .withColumn("date", to_date($"submittedAt"))
      .groupBy($"date")
      .agg(
        count("*").as("total_submissions"),
        countDistinct($"userId").as("unique_users"),
        countDistinct($"sessionId").as("unique_sessions"),
        avg(when($"answers.spring_performance".contains("5"), 5)
          .when($"answers.spring_performance".contains("4"), 4)
          .when($"answers.spring_performance".contains("3"), 3)
          .when($"answers.spring_performance".contains("2"), 2)
          .when($"answers.spring_performance".contains("1"), 1)
          .otherwise(0)).as("avg_rating")
      )
      .orderBy(desc("date"))
    
    // 2. Analiza trendów technologicznych
    val techTrends = surveyDF
      .filter($"answers.java_tech_interest".isNotNull)
      .withColumn("technology", explode(split($"answers.java_tech_interest", ",")))
      .withColumn("technology_clean", trim($"technology"))
      .withColumn("date", to_date($"submittedAt"))
      .groupBy($"date", $"technology_clean")
      .agg(count("*").as("daily_votes"))
      .orderBy(desc("date"), desc("daily_votes"))
    
    // 3. Korelacje między odpowiedziami
    val correlations = surveyDF
      .select(
        when($"answers.spring_performance".contains("5"), 5)
          .when($"answers.spring_performance".contains("4"), 4)
          .when($"answers.spring_performance".contains("3"), 3)
          .when($"answers.spring_performance".contains("2"), 2)
          .when($"answers.spring_performance".contains("1"), 1)
          .otherwise(0).as("spring_rating"),
        when($"answers.integration_quality".contains("5"), 5)
          .when($"answers.integration_quality".contains("4"), 4)
          .when($"answers.integration_quality".contains("3"), 3)
          .when($"answers.integration_quality".contains("2"), 2)
          .when($"answers.integration_quality".contains("1"), 1)
          .otherwise(0).as("integration_rating"),
        when($"answers.elk_usefulness".contains("Tak, zdecydowanie"), 2)
          .when($"answers.elk_usefulness".contains("Raczej tak"), 1)
          .when($"answers.elk_usefulness".contains("Raczej nie"), -1)
          .when($"answers.elk_usefulness".contains("Nie"), -2)
          .otherwise(0).as("elk_sentiment")
      )
      .na.drop()
      .agg(
        corr("spring_rating", "integration_rating").as("spring_integration_corr"),
        corr("spring_rating", "elk_sentiment").as("spring_elk_corr"),
        corr("integration_rating", "elk_sentiment").as("integration_elk_corr")
      )
    
    // 4. Raport godzinowy
    val hourlyReport = surveyDF
      .withColumn("hour", hour($"submittedAt"))
      .groupBy($"hour")
      .agg(
        count("*").as("submissions"),
        countDistinct($"userId").as("users"),
        avg(when($"answers.spring_performance".contains("5"), 5)
          .when($"answers.spring_performance".contains("4"), 4)
          .otherwise(3)).as("avg_rating")
      )
      .orderBy("hour")
    
    // 5. Zapisz wyniki do MongoDB
    dailyStats.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "daily_stats")
      .save()
    
    techTrends.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "tech_trends")
      .save()
    
    correlations.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "correlations")
      .save()
    
    hourlyReport.write
      .format("mongo")
      .mode("overwrite")
      .option("database", "survey_analytics")
      .option("collection", "hourly_report")
      .save()
    
    // 6. Wygeneruj raport do Elasticsearch
    val reportTimestamp = LocalDateTime.now()
      .format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss"))
    
    val finalReport = spark.createDataFrame(Seq(
      (reportTimestamp, dailyStats.count(), hourlyReport.count(), 
       correlations.first().getAs[Double]("spring_integration_corr"))
    )).toDF("generated_at", "total_days", "total_hours", "avg_correlation")
    
    finalReport.write
      .format("org.elasticsearch.spark.sql")
      .option("es.nodes", "elasticsearch")
      .option("es.port", "9200")
      .option("es.resource", "survey_reports/_doc")
      .save()
    
    spark.stop()
  }
}
