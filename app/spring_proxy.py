# Simple proxy that forwards requests to Spring Boot API
import requests
from fastapi import FastAPI, Request
app = FastAPI()
SPRING_URL = 'http://spring:8080'

@app.post('/proxy/{path:path}')
async def proxy(path: str, request: Request):
    data = await request.body()
    r = requests.post(f"{SPRING_URL}/{path}", data=data, headers=dict(request.headers))
    return r.text
