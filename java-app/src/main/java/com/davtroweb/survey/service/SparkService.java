package com.davtroweb.survey.service;

import com.davtroweb.survey.model.SurveyResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import java.util.HashMap;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class SparkService {
    
    private final KafkaTemplate<String, Object> kafkaTemplate;
    private final RestTemplate restTemplate;
    
    private static final String KAFKA_TOPIC = "survey-events";
    private static final String SPARK_MASTER_URL = "http://spark-master:8080";
    
    public void sendToKafka(SurveyResponse surveyResponse) {
        try {
            Map<String, Object> event = new HashMap<>();
            event.put("type", "SURVEY_SUBMITTED");
            event.put("surveyId", surveyResponse.getSurveyId());
            event.put("userId", surveyResponse.getUserId());
            event.put("timestamp", System.currentTimeMillis());
            event.put("data", surveyResponse.getAnswers());
            
            kafkaTemplate.send(KAFKA_TOPIC, surveyResponse.getSurveyId(), event);
            log.info("Sent survey to Kafka: surveyId={}", surveyResponse.getSurveyId());
            
        } catch (Exception e) {
            log.error("Error sending to Kafka", e);
        }
    }
    
    public Map<String, Object> getSparkStatus() {
        Map<String, Object> status = new HashMap<>();
        
        try {
            // Sprawdź status Spark Master
            String response = restTemplate.getForObject(
                SPARK_MASTER_URL + "/api/v1/applications", 
                String.class
            );
            
            status.put("sparkMaster", "RUNNING");
            status.put("applications", response);
            
        } catch (Exception e) {
            log.warn("Spark master not available", e);
            status.put("sparkMaster", "UNAVAILABLE");
            status.put("error", e.getMessage());
        }
        
        status.put("timestamp", System.currentTimeMillis());
        return status;
    }
    
    public Map<String, Object> triggerSparkJob(String jobType) {
        Map<String, Object> result = new HashMap<>();
        
        try {
            // Tutaj można dodać wywołanie REST API Spark do uruchomienia zadania
            // lub wysłać wiadomość do Kafka, którą Spark Stream będzie nasłuchiwał
            
            Map<String, String> jobRequest = new HashMap<>();
            jobRequest.put("jobType", jobType);
            jobRequest.put("triggeredBy", "spring-boot");
            jobRequest.put("timestamp", String.valueOf(System.currentTimeMillis()));
            
            kafkaTemplate.send("spark-jobs", jobType, jobRequest);
            
            result.put("success", true);
            result.put("message", "Spark job triggered: " + jobType);
            result.put("jobId", "job_" + System.currentTimeMillis());
            
        } catch (Exception e) {
            log.error("Error triggering Spark job", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }
        
        return result;
    }
}
