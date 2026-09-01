from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import redis
import json
import os
import logging
import uuid
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Question Processing System", version="1.0.0")

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "")

redis_client = redis.Redis(
    host=REDIS_HOST,
    port=REDIS_PORT,
    password=REDIS_PASSWORD if REDIS_PASSWORD else None,
    decode_responses=True
)

class Question(BaseModel):
    id: str = None
    content: str
    author: str
    timestamp: str = None

    def __init__(self, **data):
        super().__init__(**data)
        if not self.id:
            self.id = f"Q-{uuid.uuid4().hex[:8]}"
        if not self.timestamp:
            self.timestamp = datetime.utcnow().isoformat()

@app.get("/", response_class=HTMLResponse)
async def root():
    return """
    <!DOCTYPE html>
    <html lang="pl">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>System Przetwarzania Pytań</title>
        <style>
            * { box-sizing: border-box; margin: 0; padding: 0; }
            body {
                font-family: 'Segoe UI', Tahoma, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                padding: 40px 20px;
            }
            .container {
                max-width: 900px;
                margin: 0 auto;
                background: white;
                border-radius: 20px;
                box-shadow: 0 20px 60px rgba(0,0,0,0.3);
                overflow: hidden;
            }
            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                padding: 40px;
                text-align: center;
            }
            .header h1 { font-size: 2.5em; margin-bottom: 10px; }
            .header p { opacity: 0.9; font-size: 1.1em; }
            .content { padding: 40px; }
            .flow-diagram {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-bottom: 40px;
                padding: 20px;
                background: #f8f9fa;
                border-radius: 10px;
                flex-wrap: wrap;
            }
            .flow-step {
                padding: 15px 25px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                border-radius: 8px;
                font-weight: 600;
                text-align: center;
                min-width: 120px;
            }
            .flow-arrow { color: #667eea; font-size: 28px; font-weight: bold; }
            .form-group { margin-bottom: 20px; }
            label {
                display: block;
                margin-bottom: 8px;
                color: #333;
                font-weight: 600;
            }
            input, textarea {
                width: 100%;
                padding: 12px;
                border: 2px solid #e0e0e0;
                border-radius: 8px;
                font-size: 16px;
                transition: border-color 0.3s;
                font-family: inherit;
            }
            input:focus, textarea:focus {
                outline: none;
                border-color: #667eea;
            }
            textarea { min-height: 120px; resize: vertical; }
            button {
                width: 100%;
                padding: 15px;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                border: none;
                border-radius: 8px;
                font-size: 18px;
                font-weight: 600;
                cursor: pointer;
                transition: transform 0.2s, box-shadow 0.2s;
            }
            button:hover:not(:disabled) {
                transform: translateY(-2px);
                box-shadow: 0 10px 20px rgba(102, 126, 234, 0.4);
            }
            button:disabled { opacity: 0.6; cursor: not-allowed; }
            .status {
                margin-top: 20px;
                padding: 15px;
                border-radius: 8px;
                display: none;
                font-weight: 500;
            }
            .status.success {
                background: #d4edda;
                color: #155724;
                border: 1px solid #c3e6cb;
            }
            .status.error {
                background: #f8d7da;
                color: #721c24;
                border: 1px solid #f5c6cb;
            }
            .stats {
                margin-top: 30px;
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 15px;
            }
            .stat-card {
                background: #f8f9fa;
                padding: 20px;
                border-radius: 10px;
                text-align: center;
                border-left: 4px solid #667eea;
            }
            .stat-value { font-size: 2em; font-weight: bold; color: #667eea; }
            .stat-label { color: #666; margin-top: 5px; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🎓 System Przetwarzania Pytań</h1>
                <p>Zadaj pytanie - przejdzie przez Redis, Kafka do PostgreSQL</p>
            </div>
            <div class="content">
                <div class="flow-diagram">
                    <div class="flow-step">📝 FastAPI</div>
                    <div class="flow-arrow">→</div>
                    <div class="flow-step">⚡ Redis</div>
                    <div class="flow-arrow">→</div>
                    <div class="flow-step">📨 Kafka</div>
                    <div class="flow-arrow">→</div>
                    <div class="flow-step">🗄️ PostgreSQL</div>
                </div>

                <form id="questionForm">
                    <div class="form-group">
                        <label for="author">Autor (Student):</label>
                        <input type="text" id="author" required placeholder="Jan Kowalski">
                    </div>
                    <div class="form-group">
                        <label for="content">Treść pytania:</label>
                        <textarea id="content" required placeholder="Wpisz swoje pytanie do wykładowcy..."></textarea>
                    </div>
                    <button type="submit" id="submitBtn">🚀 Wyślij pytanie</button>
                </form>

                <div id="status" class="status"></div>

                <div class="stats">
                    <div class="stat-card">
                        <div class="stat-value" id="totalSent">0</div>
                        <div class="stat-label">Wysłanych pytań</div>
                    </div>
                    <div class="stat-card">
                        <div class="stat-value" id="lastQuestion">-</div>
                        <div class="stat-label">Ostatnie ID</div>
                    </div>
                </div>
            </div>
        </div>

        <script>
            let totalSent = 0;
            document.getElementById('questionForm').addEventListener('submit', async (e) => {
                e.preventDefault();
                const statusDiv = document.getElementById('status');
                const submitBtn = document.getElementById('submitBtn');
                submitBtn.disabled = true;
                submitBtn.textContent = '⏳ Wysyłanie...';

                const questionData = {
                    author: document.getElementById('author').value,
                    content: document.getElementById('content').value
                };

                try {
                    const response = await fetch('/api/questions', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(questionData)
                    });
                    if (response.ok) {
                        const result = await response.json();
                        statusDiv.className = 'status success';
                        statusDiv.innerHTML = `✅ <strong>Pytanie przyjęte!</strong><br>ID: ${result.question_id}<br>Status: ${result.status}<br>Timestamp: ${result.timestamp}`;
                        statusDiv.style.display = 'block';
                        totalSent++;
                        document.getElementById('totalSent').textContent = totalSent;
                        document.getElementById('lastQuestion').textContent = result.question_id;
                        e.target.reset();
                    } else {
                        throw new Error('Błąd serwera');
                    }
                } catch (error) {
                    statusDiv.className = 'status error';
                    statusDiv.textContent = `❌ Błąd: ${error.message}`;
                    statusDiv.style.display = 'block';
                } finally {
                    submitBtn.disabled = false;
                    submitBtn.textContent = '🚀 Wyślij pytanie';
                }
            });
        </script>
    </body>
    </html>
    """

@app.post("/api/questions")
async def submit_question(question: Question):
    try:
        question_data = {
            "id": question.id,
            "content": question.content,
            "author": question.author,
            "timestamp": question.timestamp,
            "status": "received"
        }
        redis_client.setex(f"question:{question.id}", 3600, json.dumps(question_data))
        redis_client.lpush("questions:queue", json.dumps(question_data))
        redis_client.incr("stats:questions_total")
        logger.info(f"Question {question.id} queued")
        return {
            "status": "accepted",
            "message": "Question queued for processing",
            "question_id": question.id,
            "timestamp": question.timestamp
        }
    except Exception as e:
        logger.error(f"Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/questions/{question_id}")
async def get_question(question_id: str):
    data = redis_client.get(f"question:{question_id}")
    if not data:
        raise HTTPException(status_code=404, detail="Not found")
    return json.loads(data)

@app.get("/health")
async def health():
    try:
        redis_client.ping()
        return {"status": "healthy", "redis": "connected"}
    except Exception as e:
        return {"status": "unhealthy", "error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
