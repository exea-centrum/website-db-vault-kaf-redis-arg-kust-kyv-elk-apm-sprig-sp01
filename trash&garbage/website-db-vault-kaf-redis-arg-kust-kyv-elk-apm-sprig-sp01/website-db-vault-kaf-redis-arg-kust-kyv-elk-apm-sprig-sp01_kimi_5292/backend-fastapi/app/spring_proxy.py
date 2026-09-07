"""
Proxy do komunikacji z Spring Boot API
"""
from fastapi import APIRouter, HTTPException
import httpx
import logging
from typing import List, Dict, Any

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/api/v2", tags=["spring-survey"])

# Konfiguracja Spring Boot API
SPRING_API_URL = "http://spring-app-service:8080/api"

@router.get("/survey/questions")
async def get_spring_survey_questions():
    """
    Pobiera pytania z Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{SPRING_API_URL}/survey/questions",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching questions from Spring: {e}")
        # Fallback questions
        return [
            {
                "id": 1,
                "text": "Jak oceniasz wydajność Spring Boot API?",
                "type": "rating",
                "options": ["1 - Słabo", "2", "3", "4", "5 - Doskonale"]
            },
            {
                "id": 2,
                "text": "Która technologia Java Cię interesuje?",
                "type": "choice",
                "options": ["Spring Boot", "Apache Spark", "Hibernate", "MongoDB", "Kafka Streams"]
            },
            {
                "id": 3,
                "text": "Jak oceniasz integrację z Python/FastAPI?",
                "type": "rating",
                "options": ["1 - Słaba", "2", "3", "4", "5 - Doskonała"]
            },
            {
                "id": 4,
                "text": "Czy uważasz, że ELK Stack jest przydatny?",
                "type": "choice",
                "options": ["Tak, zdecydowanie", "Raczej tak", "Nie wiem", "Raczej nie", "Nie"]
            },
            {
                "id": 5,
                "text": "Twoje sugestie dotyczące architektury:",
                "type": "text",
                "placeholder": "Podziel się swoimi pomysłami..."
            }
        ]

@router.post("/survey/submit")
async def submit_spring_survey(data: Dict[str, Any]):
    """
    Wysyła odpowiedzi do Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{SPRING_API_URL}/survey/submit",
                json=data,
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error submitting to Spring: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error submitting survey: {str(e)}"
        )

@router.get("/survey/stats")
async def get_spring_survey_stats():
    """
    Pobiera statystyki z Spring Boot API
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                f"{SPRING_API_URL}/survey/stats",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching stats from Spring: {e}")
        return {
            "totalResponses": 0,
            "avgRating": 0.0,
            "uniqueUsers": 0,
            "charts": {
                "ratings": {"labels": [], "datasets": []},
                "technologies": {"labels": [], "datasets": []}
            }
        }

@router.get("/spark/jobs")
async def get_spark_jobs():
    """
    Pobiera status zadań Spark
    """
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(
                "http://spark-master:8080/api/v1/applications",
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error fetching Spark jobs: {e}")
        return []

@router.get("/elk/logs")
async def search_elk_logs(query: str = "", size: int = 10):
    """
    Wyszukuje logi w Elasticsearch
    """
    try:
        async with httpx.AsyncClient() as client:
            es_query = {
                "query": {
                    "bool": {
                        "must": [
                            {"match": {"message": query}} if query else {"match_all": {}}
                        ]
                    }
                },
                "size": size,
                "sort": [{"@timestamp": {"order": "desc"}}]
            }
            
            response = await client.post(
                "http://elasticsearch:9200/logs*/_search",
                json=es_query,
                headers={"Content-Type": "application/json"},
                timeout=10.0
            )
            response.raise_for_status()
            return response.json()
    except Exception as e:
        logger.error(f"Error searching ELK logs: {e}")
        return {"hits": {"hits": []}}
