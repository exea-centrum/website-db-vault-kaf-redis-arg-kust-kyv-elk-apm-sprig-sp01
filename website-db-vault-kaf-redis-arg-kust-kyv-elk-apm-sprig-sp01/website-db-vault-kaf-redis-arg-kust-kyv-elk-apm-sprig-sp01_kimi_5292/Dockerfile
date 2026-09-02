FROM python:3.11-slim
WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY backend-fastapi/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend-fastapi/app/ ./app/
EXPOSE 8080
CMD ["python","-m","uvicorn","app.main:app","--host","0.0.0.0","--port","8080"]
