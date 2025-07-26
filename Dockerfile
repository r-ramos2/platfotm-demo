FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./
EXPOSE 5001 9090
HEALTHCHECK --interval=15s --timeout=3s \
  CMD curl --fail http://localhost:5001/health || exit 1
CMD ["sh","-c","python -m prometheus_client --bind 0.0.0.0:9090 & python app.py"]