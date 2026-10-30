FROM python:3.12-slim
WORKDIR /app
COPY requirements-stage3.txt requirements-learning.txt ./
RUN pip install --no-cache-dir -r requirements-learning.txt
COPY . .
USER 65532:65532
EXPOSE 8080
CMD ["uvicorn", "server_v3:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]
