package com.davtro.app;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

// Rola tego serwisu: panel administracyjny / raportowanie rezerwacji
// (odczyt z tej samej bazy Postgresql co FastAPI, agregaty do Grafany).
@SpringBootApplication
@RestController
public class SpringAppApplication {

    public static void main(String[] args) {
        SpringApplication.run(SpringAppApplication.class, args);
    }

    @GetMapping("/actuator/health/custom")
    public String health() {
        return "OK";
    }
}
