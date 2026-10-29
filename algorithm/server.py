from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from teamix_engine.engine import solve
from teamix_engine.schema import InputError

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5000"],
    allow_methods=["POST"],
    allow_headers=["*"],
)

@app.post("/solve")
def run(snapshot: dict):
    try:
        return solve(snapshot)["public"]  # internal(비공개 지표)은 절대 반환하지 않음
    except InputError as e:
        return {"status": "ERROR", "messages": [str(e)], "teams": []}
