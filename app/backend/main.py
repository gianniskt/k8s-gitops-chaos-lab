from fastapi import FastAPI
import socket

app = FastAPI()

@app.get("/api/message")
def read_root():
    hostname = socket.gethostname()
    return {"message": "Hello from the backend!", "hostname": hostname}