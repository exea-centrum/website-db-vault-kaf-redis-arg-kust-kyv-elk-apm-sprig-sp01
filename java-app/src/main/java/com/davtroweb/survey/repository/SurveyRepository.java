package com.davtroweb.survey.repository;

import com.davtroweb.survey.model.SurveyResponse;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import org.springframework.stereotype.Repository;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@Repository
public interface SurveyRepository extends MongoRepository<SurveyResponse, String> {
    
    List<SurveyResponse> findBySurveyId(String surveyId);
    
    @Query("{'submittedAt': {$gte: ?0, $lte: ?1}}")
    List<SurveyResponse> findByDateRange(LocalDateTime start, LocalDateTime end);
    
    @Query("{'surveyId': ?0, 'answers.?1': ?2}")
    List<SurveyResponse> findByAnswerValue(String surveyId, String questionKey, Object value);
    
    @Query(value = "{'surveyId': ?0}", count = true)
    long countBySurveyId(String surveyId);
    
    @Query(value = "{}", fields = "{'answers': 1, 'submittedAt': 1}")
    List<Map<String, Object>> findAllForAnalytics();
}
