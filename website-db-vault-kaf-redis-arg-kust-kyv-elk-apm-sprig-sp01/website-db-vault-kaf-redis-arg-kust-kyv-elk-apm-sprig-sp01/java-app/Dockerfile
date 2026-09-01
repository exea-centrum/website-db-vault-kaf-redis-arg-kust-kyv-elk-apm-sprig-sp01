FROM eclipse-temurin:17-jdk-alpine
WORKDIR /app
COPY target/rental-processor-1.0.0.jar app.jar
EXPOSE 8081
ENTRYPOINT ["java","-jar","app.jar"]
