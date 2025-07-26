from flask import Flask
from prometheus_client import start_http_server, Counter

app = Flask(__name__)
REQUESTS = Counter("app_requests_total", "Total HTTP requests")

@app.before_request
def count_requests():
    REQUESTS.inc()

@app.route('/health')
def health():
    return {"status":"ok"}

@app.route('/')
def index():
    return {"message":"Hello, Platform Engineering!"}

if __name__ == '__main__':
    start_http_server(9090)
    app.run(host='0.0.0.0', port=5001)