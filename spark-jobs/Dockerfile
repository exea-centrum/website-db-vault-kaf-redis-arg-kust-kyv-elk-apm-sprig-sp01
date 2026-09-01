FROM bitnami/spark:3.5.0
COPY target/scala-2.12/davtro-spark-jobs-assembly-1.0.0.jar /opt/bitnami/spark/jobs/
CMD ["spark-submit","--class","com.davtro.jobs.MarketingAnalyticsJob","/opt/bitnami/spark/jobs/davtro-spark-jobs-assembly-1.0.0.jar"]
