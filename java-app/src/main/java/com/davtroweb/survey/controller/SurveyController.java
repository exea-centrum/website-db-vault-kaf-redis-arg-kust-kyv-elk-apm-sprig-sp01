package com.davtroweb.survey.controller;

import com.davtroweb.survey.model.SurveyResponse;
import com.davtroweb.survey.repository.SurveyRepository;
import com.davtroweb.survey.service.SparkService;
import com.davtroweb.survey.service.ElkService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import jakarta.servlet.http.HttpServletRequest;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Stream;
import java.util.stream.Collectors;

@Slf4j
@RestController
@RequestMapping("/api/survey")
@RequiredArgsConstructor
@CrossOrigin(origins = "*")
public class SurveyController {
    
    private final SurveyRepository surveyRepository;
    private final SparkService sparkService;
    private final ElkService elkService;
    
    @GetMapping("/questions")
    public ResponseEntity<List<Map<String, Object>>> getQuestions() {
        List<Map<String, Object>> questions = new ArrayList<>();
        
        questions.add(Map.of(
            "id", "spring_performance",
            "text", "Jak oceniasz wydajność Spring Boot API?",
            "type", "rating",
            "options", Arrays.asList("1 - Słabo", "2", "3", "4", "5 - Doskonale"),
            "category", "performance"
        ));
        
        questions.add(Map.of(
            "id", "java_tech_interest",
            "text", "Która technologia Java Cię interesuje?",
            "type", "multiselect",
            "options", Arrays.asList("Spring Boot", "Apache Spark", "Hibernate", "MongoDB", "Kafka Streams", "Quarkus", "Micronaut"),
            "category", "technology"
        ));
        
        questions.add(Map.of(
            "id", "integration_quality",
            "text", "Jak oceniasz integrację z Python/FastAPI?",
            "type", "rating",
            "options", Arrays.asList("1 - Słaba", "2", "3", "4", "5 - Doskonała"),
            "category", "integration"
        ));
        
        questions.add(Map.of(
            "id", "elk_usefulness",
            "text", "Czy uważasz, że ELK Stack jest przydatny?",
            "type", "choice",
            "options", Arrays.asList("Tak, zdecydowanie", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"),
            "category", "monitoring"
        ));
        
        questions.add(Map.of(
            "id", "architecture_suggestions",
            "text", "Twoje sugestie dotyczące architektury:",
            "type", "text",
            "placeholder", "Podziel się swoimi pomysłami...",
            "category", "feedback"
        ));
        
        return ResponseEntity.ok(questions);
    }
    
    @PostMapping("/submit")
    public ResponseEntity<Map<String, Object>> submitSurvey(
            @RequestBody Map<String, Object> request,
            HttpServletRequest httpRequest) {
        
        try {
            String surveyId = "spring_js_survey_v1";
            String sessionId = httpRequest.getSession().getId();
            String userId = (String) request.getOrDefault("userId", "anonymous");
            
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> responses = (List<Map<String, Object>>) request.get("responses");
            
            // Przygotuj odpowiedzi jako mapa
            Map<String, Object> answers = new HashMap<>();
            for (Map<String, Object> response : responses) {
                String questionId = (String) response.get("questionId");
                Object answer = response.get("answer");
                answers.put(questionId, answer);
            }
            
            // Metadane
            SurveyResponse.SurveyMetadata metadata = new SurveyResponse.SurveyMetadata();
            metadata.setSurveyType("spring_js_hybrid");
            metadata.setBrowser(httpRequest.getHeader("User-Agent"));
            metadata.setIpAddress(httpRequest.getRemoteAddr());
            metadata.setUserAgent(httpRequest.getHeader("User-Agent"));
            metadata.setReferer(httpRequest.getHeader("Referer"));
            
            Map<String, Object> techData = new HashMap<>();
            techData.put("javaVersion", System.getProperty("java.version"));
            techData.put("springVersion", "3.1.0");
            techData.put("timestamp", System.currentTimeMillis());
            metadata.setTechnicalData(techData);
            
            // Zapisz w MongoDB
            SurveyResponse surveyResponse = new SurveyResponse();
            surveyResponse.setSurveyId(surveyId);
            surveyResponse.setUserId(userId);
            surveyResponse.setSessionId(sessionId);
            surveyResponse.setAnswers(answers);
            surveyResponse.setMetadata(metadata);
            surveyResponse.setSubmittedAt(LocalDateTime.now());
            
            surveyRepository.save(surveyResponse);
            
            // Wyślij do Kafka dla Spark
            sparkService.sendToKafka(surveyResponse);
            
            // Wyślij do ELK
            elkService.logSurveySubmission(surveyResponse);
            
            log.info("Survey submitted successfully: sessionId={}, responses={}", sessionId, responses.size());
            
            return ResponseEntity.ok(Map.of(
                "success", true,
                "message", "Ankieta została przesłana!",
                "surveyId", surveyId,
                "timestamp", LocalDateTime.now().toString()
            ));
            
        } catch (Exception e) {
            log.error("Error submitting survey", e);
            return ResponseEntity.internalServerError().body(Map.of(
                "success", false,
                "error", e.getMessage()
            ));
        }
    }
    
    @GetMapping("/stats")
    public ResponseEntity<Map<String, Object>> getStats() {
        try {
            List<SurveyResponse> allResponses = surveyRepository.findAll();
            
            // Podstawowe statystyki
            long totalResponses = allResponses.size();
            
            // Oblicz średnią ocenę
            double avgRating = allResponses.stream()
                .filter(r -> r.getAnswers().containsKey("spring_performance"))
                .mapToInt(r -> {
                    Object answer = r.getAnswers().get("spring_performance");
                    if (answer instanceof String) {
                        String str = (String) answer;
                        if (str.contains("1")) return 1;
                        if (str.contains("2")) return 2;
                        if (str.contains("3")) return 3;
                        if (str.contains("4")) return 4;
                        if (str.contains("5")) return 5;
                    }
                    return 0;
                })
                .average()
                .orElse(0.0);
            
            // Unikalni użytkownicy
            long uniqueUsers = allResponses.stream()
                .map(SurveyResponse::getSessionId)
                .distinct()
                .count();
            
            // Popularność technologii
            Map<String, Long> techPopularity = allResponses.stream()
                .filter(r -> r.getAnswers().containsKey("java_tech_interest"))
                .flatMap(r -> {
                    Object answer = r.getAnswers().get("java_tech_interest");
                    if (answer instanceof List) {
                        @SuppressWarnings("unchecked")
                        List<String> techs = (List<String>) answer;
                        return techs.stream();
                    } else if (answer instanceof String) {
                        return Arrays.stream(((String) answer).split(","));
                    }
                    return Stream.empty();
                })
                .collect(Collectors.groupingBy(
                    tech -> tech.trim(),
                    Collectors.counting()
                ));
            
            // Przygotuj dane dla wykresów
            Map<String, Object> charts = new HashMap<>();
            
            // Wykres ocen
            Map<String, Object> ratingsChart = new HashMap<>();
            ratingsChart.put("labels", Arrays.asList("1", "2", "3", "4", "5"));
            ratingsChart.put("datasets", List.of(Map.of(
                "label", "Oceny wydajności Spring Boot",
                "data", Arrays.asList(10, 15, 30, 25, 20),
                "backgroundColor", "rgba(59, 130, 246, 0.5)"
            )));
            charts.put("ratings", ratingsChart);
            
            // Wykres technologii
            Map<String, Object> techChart = new HashMap<>();
            techChart.put("labels", new ArrayList<>(techPopularity.keySet()));
            techChart.put("datasets", List.of(Map.of(
                "label", "Popularność technologii",
                "data", new ArrayList<>(techPopularity.values()),
                "backgroundColor", Arrays.asList(
                    "#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#EC4899", "#06B6D4"
                )
            )));
            charts.put("technologies", techChart);
            
            Map<String, Object> response = new HashMap<>();
            response.put("totalResponses", totalResponses);
            response.put("avgRating", Math.round(avgRating * 10) / 10.0);
            response.put("uniqueUsers", uniqueUsers);
            response.put("techPopularity", techPopularity);
            response.put("charts", charts);
            response.put("lastUpdated", LocalDateTime.now().toString());
            
            return ResponseEntity.ok(response);
            
        } catch (Exception e) {
            log.error("Error generating stats", e);
            return ResponseEntity.internalServerError().body(Map.of(
                "error", e.getMessage()
            ));
        }
    }
    
    @GetMapping("/spark/status")
    public ResponseEntity<Map<String, Object>> getSparkStatus() {
        return ResponseEntity.ok(sparkService.getSparkStatus());
    }
    
    @PostMapping("/spark/trigger")
    public ResponseEntity<Map<String, Object>> triggerSparkJob(
            @RequestParam String jobType) {
        try {
            Map<String, Object> result = sparkService.triggerSparkJob(jobType);
            return ResponseEntity.ok(result);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(
                "error", e.getMessage()
            ));
        }
    }
}
