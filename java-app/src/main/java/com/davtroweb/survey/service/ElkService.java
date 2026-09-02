package com.davtroweb.survey.service;

import com.davtroweb.survey.model.SurveyResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;
import java.util.HashMap;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
public class ElkService {
    
    private final RestTemplate restTemplate;
    
    private static final String ELASTICSEARCH_URL = "http://elasticsearch:9200";
    private static final String LOGSTASH_URL = "http://logstash:5000";
    
    public void logSurveySubmission(SurveyResponse surveyResponse) {
        try {
            // Przygotuj dokument dla Elasticsearch
            Map<String, Object> logEntry = new HashMap<>();
            logEntry.put("@timestamp", System.currentTimeMillis());
            logEntry.put("level", "INFO");
            logEntry.put("logger", "SurveyController");
            logEntry.put("message", "Survey submitted: " + surveyResponse.getSurveyId());
            logEntry.put("surveyId", surveyResponse.getSurveyId());
            logEntry.put("userId", surveyResponse.getUserId());
            logEntry.put("sessionId", surveyResponse.getSessionId());
            logEntry.put("responseCount", surveyResponse.getAnswers().size());
            logEntry.put("source", "spring-boot");
            
            // Wyślij do Elasticsearch
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(logEntry, headers);
            
            ResponseEntity<String> response = restTemplate.postForEntity(
                ELASTICSEARCH_URL + "/logs/_doc",
                request,
                String.class
            );
            
            if (response.getStatusCode().is2xxSuccessful()) {
                log.debug("Log sent to Elasticsearch: surveyId={}", surveyResponse.getSurveyId());
            }
            
            // Równolegle wyślij do Logstash (jeśli potrzebne)
            try {
                restTemplate.postForEntity(
                    LOGSTASH_URL,
                    request,
                    String.class
                );
            } catch (Exception e) {
                log.debug("Logstash not available, skipping");
            }
            
        } catch (Exception e) {
            log.error("Error sending log to ELK", e);
        }
    }
    
    public Map<String, Object> searchLogs(String query, int size) {
        Map<String, Object> result = new HashMap<>();
        
        try {
            // Przygotuj zapytanie Elasticsearch
            Map<String, Object> searchQuery = new HashMap<>();
            searchQuery.put("query", Map.of(
                "match", Map.of("message", query)
            ));
            searchQuery.put("size", size);
            searchQuery.put("sort", List.of(
                Map.of("@timestamp", Map.of("order", "desc"))
            ));
            
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(searchQuery, headers);
            
            ResponseEntity<Map> response = restTemplate.postForEntity(
                ELASTICSEARCH_URL + "/logs/_search",
                request,
                Map.class
            );
            
            if (response.getStatusCode().is2xxSuccessful()) {
                result.put("success", true);
                result.put("data", response.getBody());
            } else {
                result.put("success", false);
                result.put("error", "Elasticsearch query failed");
            }
            
        } catch (Exception e) {
            log.error("Error searching logs", e);
            result.put("success", false);
            result.put("error", e.getMessage());
        }
        
        return result;
    }
}
