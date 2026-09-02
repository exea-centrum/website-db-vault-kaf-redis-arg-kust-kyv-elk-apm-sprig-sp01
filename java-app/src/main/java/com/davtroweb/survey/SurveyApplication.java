package com.davtroweb.survey;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.mongodb.config.EnableMongoAuditing;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.kafka.annotation.EnableKafka;

@SpringBootApplication
@EnableMongoAuditing
@EnableScheduling
@EnableKafka
public class SurveyApplication {
    public static void main(String[] args) {
        SpringApplication.run(SurveyApplication.class, args);
    }
}
