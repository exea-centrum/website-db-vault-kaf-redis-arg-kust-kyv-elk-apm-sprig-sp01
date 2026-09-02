package com.davtroweb.survey.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.Indexed;
import java.time.LocalDateTime;
import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "survey_responses")
public class SurveyResponse {
    
    @Id
    private String id;
    
    @Indexed
    private String surveyId;
    
    private String userId;
    private String sessionId;
    
    private Map<String, Object> answers;
    private SurveyMetadata metadata;
    
    @Indexed
    private LocalDateTime submittedAt;
    
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class SurveyMetadata {
        private String surveyType;
        private String browser;
        private String ipAddress;
        private String userAgent;
        private String referer;
        private Map<String, Object> technicalData;
    }
}
