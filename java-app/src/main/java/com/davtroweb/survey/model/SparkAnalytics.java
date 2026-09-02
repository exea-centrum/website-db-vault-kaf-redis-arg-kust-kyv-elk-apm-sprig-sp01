package com.davtroweb.survey.model;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.index.CompoundIndex;
import java.time.LocalDateTime;
import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Document(collection = "spark_analytics")
@CompoundIndex(name = "type_timestamp_idx", def = "{'analysisType': 1, 'timestamp': -1}")
public class SparkAnalytics {
    
    @Id
    private String id;
    
    private String analysisType; // "sentiment", "trend", "correlation", "prediction"
    private LocalDateTime timestamp;
    private LocalDateTime dataStartTime;
    private LocalDateTime dataEndTime;
    
    private Map<String, Object> results;
    private Map<String, Double> metrics; // accuracy, precision, recall, etc.
    private Map<String, Object> parameters;
    
    private String sparkJobId;
    private String sparkApplicationId;
    private ProcessingStatus status;
    
    public enum ProcessingStatus {
        PENDING, PROCESSING, COMPLETED, FAILED
    }
}
