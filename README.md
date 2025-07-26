# Mini PaaS Platform Prototype — Complete Functional Guide

An end-to-end Platform Engineering demo: Flask → Docker → Kubernetes (Helm) → CI/CD → Monitoring → Cleanup.

## Table of Contents

* [Prerequisites](#prerequisites)
* [Environment Setup](#environment-setup)
* [1. Application Code](#1-application-code)
* [2. Local Testing](#2-local-testing)
* [3. Dockerization](#3-dockerization)
* [4. Helm Chart (Kubernetes)](#4-helm-chart-kubernetes)
* [5. CI/CD Pipeline](#5-cicd-pipeline)
* [6. Monitoring with Prometheus & Grafana](#6-monitoring-with-prometheus--grafana)
* [7. Troubleshooting](#7-troubleshooting)
* [8. Cleanup](#8-cleanup)
* [Security Best Practices](#security-best-practices)

---

## Prerequisites

* macOS or Linux with Docker Desktop (Kubernetes enabled)
* Docker CLI v24+
* kubectl v1.28+
* Helm v3+
* Python 3.9+ & pip

---

## Environment Setup

```bash
git clone git@github.com:<your-username>/platform-demo.git
cd platform-demo

# create and activate Python venv\python3 -m venv venv
python3 -m venv venv
source venv/bin/activate

# install Flask
printf "flask==2.3.2\nprometheus-client==0.16.0" > requirements.txt
pip install --no-cache-dir -r requirements.txt
```

---

## 1. Application Code

**`app.py`**

```python
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
```

---

## 2. Local Testing

```bash
python app.py &
# Verify
curl http://localhost:5001
curl http://localhost:5001/metrics
curl http://localhost:5001/health
```

---

## 3. Dockerization

**`Dockerfile`**

```dockerfile
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py ./
EXPOSE 5001 9090
HEALTHCHECK --interval=15s --timeout=3s \
  CMD curl --fail http://localhost:5001/health || exit 1
CMD ["sh","-c","python -m prometheus_client --bind 0.0.0.0:9090 & python app.py"]
```

```bash
# Build and run
docker build -t platform-demo:latest .
docker run -d --name platform-demo -p 5001:5001 -p 9090:9090 platform-demo:latest
# Test
curl http://localhost:5001
curl http://localhost:9090
```

---

## 4. Helm Chart (Kubernetes)

Create chart at `charts/platform-demo/` with these files:

### `_helpers.tpl`

```yaml
{{- define "platform-demo.name" -}}
platform-demo
{{- end }}

{{- define "platform-demo.fullname" -}}
{{ include "platform-demo.name" . }}-app
{{- end }}
```

### `Chart.yaml`

```yaml
apiVersion: v2
name: platform-demo
version: 0.1.0
appVersion: "latest"
```

### `values.yaml`

```yaml
replicaCount: 1
image:
  repository: platform-demo
  tag: latest
  pullPolicy: IfNotPresent
service:
  port: 5001
  nodePort: 30001
```

### `templates/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "platform-demo.fullname" . }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ include "platform-demo.name" . }}
  template:
    metadata:
      labels:
        app: {{ include "platform-demo.name" . }}
    spec:
      containers:
        - name: web
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.port }}
          readinessProbe:
            httpGet:
              path: /
              port: {{ .Values.service.port }}
            initialDelaySeconds: 5
            periodSeconds: 10
```

### `templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "platform-demo.fullname" . }}-svc
spec:
  type: NodePort
  selector:
    app: {{ include "platform-demo.name" . }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.port }}
      nodePort: {{ .Values.service.nodePort }}
```

```bash
# Deploy to cluster
helm install platform-demo charts/platform-demo \
  --set image.pullPolicy=IfNotPresent
# Verify
kubectl get pods,svc
kubectl port-forward svc/platform-demo-app-svc 5001:5001 &
curl http://localhost:5001
```

---

## 5. CI/CD Pipeline

**`.github/workflows/ci-cd.yml`**

```yaml
name: CI/CD
on: [push]
jobs:
  build-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-python@v4
        with: { python-version: '3.9' }
      - run: pip install -r requirements.txt
      - run: |
          docker build -t platform-demo:latest .
          docker run -d -p 5001:5001 --name pd-test platform-demo:latest
          sleep 5
          curl --fail http://localhost:5001
          docker rm -f pd-test
```

---

## 6. Monitoring with Prometheus & Grafana

### `prometheus-values.yaml`

```yaml
alertmanager:
  enabled: false
pushgateway:
  enabled: false
server:
  global:
    scrape_interval: 15s
  service:
    type: ClusterIP
  resources:
    requests: { cpu: "100m", memory: "128Mi" }
    limits:   { cpu: "200m", memory: "256Mi" }
```

### `grafana-values.yaml`

```yaml
resources:
  requests: { cpu: "100m", memory: "128Mi" }
  limits:   { cpu: "200m", memory: "256Mi" }
persistence: { enabled: false }
```

```bash
# Add repos
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install monitoring
helm install prometheus prometheus-community/prometheus \
  -f prometheus-values.yaml
helm install grafana grafana/grafana \
  -f grafana-values.yaml \
  --set adminPassword="YourPassword"

# Wait for pods to be Running
kubectl rollout status deployment/prometheus-server
kubectl rollout status deployment/grafana

# Port-forward
kubectl port-forward svc/prometheus-server 9090:80 &
kubectl port-forward svc/grafana 3000:80 &

# Access UIs
# Prometheus: http://localhost:9090
# Grafana:    http://localhost:3000 (user: admin / password from values)
```

---

## 7. Troubleshooting

* **Lint Helm chart:** `helm lint charts/platform-demo`
* **Describe pods:** `kubectl describe pod <name>`
* **View logs:** `kubectl logs <pod>`
* **Resource issues:** adjust CPU/memory in values files
* **Image pull:** ensure `imagePullPolicy=IfNotPresent` and Docker image loaded

---

## 8. Cleanup

```bash
# Kill port-forwards
pkill -f "kubectl port-forward"

# Remove Helm releases
helm uninstall platform-demo prometheus grafana --ignore-not-found

# Delete Kubernetes resources
kubectl delete all --all

# Remove Docker artifacts
docker rm -f platform-demo pd-test || true
docker rmi platform-demo:latest || true
docker system prune -a -f --volumes
```

---

## Security Best Practices

* Use minimal base images
* Pin dependency versions
* Least-privilege RBAC
* Deploy with TLS in production
* Store secrets in Kubernetes Secrets or Vault
* Scan images with Trivy or Docker Scout

---

You now have a complete, functional Platform Engineering demo to showcase end-to-end workflows.
