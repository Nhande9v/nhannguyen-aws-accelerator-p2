# app/backend-v1/app.py (Tương tự cho v2, chỉ cần đổi chuỗi version)
from flask import Flask, Response, jsonify
import random
import time
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# Prometheus Metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP Requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'HTTP Request Latency', ['endpoint'])

@app.route('/')
def home():
    start_time = time.time()
    # Giả lập lỗi ngẫu nhiên 2% cho v1 (v2 có thể chỉnh lỗi cao hơn để test Abort)
    status_code = 200
    if random.random() < 0.08:
        status_code = 500
        
    REQUEST_COUNT.labels(method='GET', endpoint='/', status=str(status_code)).inc()
    REQUEST_LATENCY.labels(endpoint='/').observe(time.time() - start_time)
    
    if status_code == 500:
        return jsonify(status="error", version="v2"), 500
    return jsonify(status="success", version="v2"), 200

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)