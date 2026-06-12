# GitOps + Canary + Observability Lab

## 📋 Mục tiêu

Triển khai phiên bản API mới **an toàn, tự động & có khả năng phục hồi** bằng cách kết hợp:
- **GitOps** (ArgoCD): Mọi thay đổi qua Git
- **Canary Deployment** (Argo Rollouts): Thả dần phiên bản mới, tự động rollback nếu lỗi
- **Observability** (Prometheus + Alertmanager): Đo lường chất lượng, gửi alert email

---

## 🏗️ Cấu trúc thư mục

```
gitops/
├── process.md                     # Hướng dẫn quy trình (đã dịch Tiếng Việt)
├── README.md                      # File này
├── .github/
│   └── workflows/
│       └── validate.yml           # CI/CD validation
├── argocd/
│   ├── root.yaml                  # Root Application quản lý tất cả apps
│   └── apps/
│       ├── backend.yml            # Backend service app
│       ├── frontend.yaml          # Frontend app
│       ├── observability.yaml     # Monitoring stack app
│       └── web.yaml               # Web service app
├── k8s/
│   ├── backend/
│   │   ├── rollout.yaml           # Argo Rollouts canary config
│   │   └── analysis-template.yaml # Auto-analysis template
│   ├── frontend/
│   │   └── deployment.yaml
│   ├── observability/
│   │   ├── namespace.yaml         # Monitoring namespace
│   │   ├── prometheus.yaml        # Prometheus server
│   │   ├── prometheus-rule.yaml   # Alert rules
│   │   ├── alertmanager.yaml      # Alert manager + Gmail config
│   │   └── mailhog.yaml           # Email testing tool
│   └── web/
│       ├── namespace.yaml
│       └── web.yaml
```

---

## 📄 Chi tiết từng file

### 🔴 **argocd/root.yaml**
**Tác dụng**: Quản lý tất cả ứng dụng trong cluster qua ArgoCD

**Làm gì**:
- Định nghĩa một `Application` chứa các "sub-applications"
- ArgoCD theo dõi các thay đổi trong Git
- Tự động sync manifest từ repo vào cluster
- Đảm bảo **GitOps principle**: Git là single source of truth

**Chú ý**:
- `repo`: Phải trỏ tới Git repo của bạn
- `targetRevision: main`: Luôn sync từ branch `main`
- Nếu sửa file trong cluster trực tiếp (kubectl apply), ArgoCD sẽ đánh dấu **OutOfSync** → phải push Git lại

---

### 🔴 **argocd/apps/backend.yml**
**Tác dụng**: Định nghĩa Backend app cho ArgoCD quản lý

**Làm gì**:
- ArgoCD watch các file trong `k8s/backend/`
- Tự động apply `rollout.yaml` và `analysis-template.yaml`
- Khi bạn push thay đổi lên Git → ArgoCD auto-sync

**Chú ý**:
- `path: k8s/backend/`: ArgoCD sẽ apply tất cả YAML file trong thư mục này
- Nếu add file YAML mới vào `k8s/backend/`, ArgoCD tự động apply

---

### 🔴 **argocd/apps/observability.yaml**
**Tác dụng**: Quản lý monitoring stack (Prometheus, Alertmanager, MailHog)

**Làm gì**:
- Watch `k8s/observability/`
- Apply tất cả monitoring components
- Khi bạn update email alert trong Git → Alertmanager tự reload

**Chú ý**:
- Phải có file `k8s/observability/namespace.yaml` tạo namespace `monitoring`
- ConfigMap trong `alertmanager.yaml` được ArgoCD quản lý → không được sửa trực tiếp trong pod

---

### 🟢 **k8s/backend/rollout.yaml**
**Tác dụng**: Định nghĩa quá trình Canary Deployment cho backend

**Làm gì**:
```yaml
strategy:
  canary:
    steps:
    - setWeight: 20    # 20% traffic → phiên bản mới
    - pause: {duration: 1m}  # Dừng 1 phút để test
    - setWeight: 50    # 50% traffic
    - pause: {duration: 1m}
    - setWeight: 100   # 100% traffic (rollout hoàn tất)
```

**Backend App (Node.js)**:
- Endpoint `/metrics`: Expose Prometheus metrics
- Endpoint `/inject-error`: Bật/tắt chế độ trả error 500
- Endpoint `/health`: Health check

**Chú ý**:
- `readinessProbe` + `livenessProbe`: Kubernetes biết pod sống chết
- Nếu metric xấu → `AnalysisTemplate` sẽ tự abort rollout
- Khi abort → quay lại replica set cũ (tự động rollback)

---

### 🟢 **k8s/backend/analysis-template.yaml**
**Tác dụng**: Định nghĩa tiêu chí đánh giá chất lượng canary deployment

**Làm gì**:
```yaml
metrics:
- name: success-rate
  interval: 10s                    # Kiểm tra mỗi 10 giây
  failureLimit: 1                  # Fail 1 lần = abort
  successCondition: result[0] >= 0.95  # Yêu cầu 95% thành công
  provider:
    prometheus:
      query: (sum(rate(...)) / ...)  # Lấy success rate từ Prometheus
```

**Luồng hoạt động**:
1. Backend deploy phiên bản mới (20% traffic)
2. AnalysisTemplate query Prometheus mỗi 10s
3. Nếu success rate < 95% → tương đương fail → abort after 1 fail
4. Rollout tự động quay về phiên bản cũ (undo)

**Chú ý**:
- `failureLimit: 1`: Chỉ cần 1 lần metric xấu là abort (có thể tăng để tolerant hơn)
- `interval: 10s`: Quá nhanh có thể false alarm, quá chậm không phát hiện nhanh
- Query Prometheus phải chính xác

---

### 🔵 **k8s/observability/prometheus.yaml**
**Tác dụng**: Triển khai Prometheus server để thu thập metrics

**Làm gì**:
```yaml
scrape_configs:
- job_name: 'backend-pods'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_pod_label_app]
    action: keep
    regex: demo;backend    # Chỉ scrape pod label app=backend ở namespace demo
```

**Hoạt động**:
- Mỗi 5 giây, Prometheus scrape endpoint `/metrics` của backend pods
- Lưu metrics vào time-series database
- Evaluates alert rules mỗi 5 giây

**Chú ý**:
- `scrape_interval: 5s`: Quá ngắn = load cao, quá dài = detect chậm
- Backend pods phải expose `/metrics` endpoint
- `relabel_configs` phải match pod đúng (namespace, label)

---

### 🔵 **k8s/observability/prometheus-rule.yaml**
**Tác dụng**: Định nghĩa alert rules cho Prometheus

**Alert Rule**:
```yaml
- alert: HighErrorRate
  expr: (sum(rate(http_requests_total{app="backend", status="500"}[30s])) or vector(0)) / 
        (sum(rate(http_requests_total{app="backend"}[30s])) or vector(1)) > 0.05
  for: 10s
```

**Nghĩa**:
- Tính error rate trong cửa sổ 30 giây
- Nếu lỗi > 5% **liên tiếp 10 giây** → alert FIRING
- Severity: `critical`

**Chú ý**:
- `for: 10s`: Phải xấu 10s liên tiếp mới alert (tránh false alarm)
- `[30s]`: Cửa sổ tính toán (có thể adjust tuỳ tolerance)
- Threshold `0.05` (5%) có thể tăng/giảm

---

### 🔵 **k8s/observability/alertmanager.yaml**
**Tác dụng**: Quản lý alert routing và gửi email

**Cấu hình SMTP Gmail**:
```yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'
  smtp_auth_username: 'hoangnhan912004dn@gmail.com'
  smtp_auth_password: 'zpfi rzpx yarh fvlq'     # App password
  smtp_from: 'hoangnhan912004dn@gmail.com'
  smtp_require_tls: true

receivers:
- name: 'email-notifications'
  email_configs:
  - to: 'hoangnhan912004dn@gmail.com'           # Nơi nhận alert
```

**Hoạt động**:
- Khi Prometheus alert FIRING → gửi tới Alertmanager
- Alertmanager routing theo rules → gửi email tới Gmail

**Chú ý**:
- **App Password**: Phải tạo từ Gmail Security settings (không dùng password thường)
- `smtp_require_tls: true`: Bắt buộc với Gmail
- ConfigMap này được ArgoCD quản lý → sửa phải push Git

---

### 🔵 **k8s/observability/mailhog.yaml**
**Tác dụng**: Email testing server (không gửi thật ra internet)

**Cách dùng khi muốn test không dùng Gmail thật**:
```yaml
# Đổi trong alertmanager.yaml:
smtp_smarthost: 'mailhog.monitoring.svc.cluster.local:1025'
```

Rồi mở MailHog UI:
```bash
kubectl port-forward -n monitoring svc/mailhog 8025:8025
# Mở http://localhost:8025
```

**Chú ý**: Hiện tại lab dùng Gmail thật, nên MailHog chỉ tham khảo

---

## 🚀 Quy trình làm việc

### 1️⃣ **Khi bạn update backend version**

```bash
# Sửa image version trong k8s/backend/rollout.yaml
# VD: image: node:20-alpine → node:21-alpine

git add k8s/backend/rollout.yaml
git commit -m "Update backend image to v21"
git push origin main
```

**Kết quả**:
- ArgoCD phát hiện thay đổi → sync
- Rollout tạo ReplicaSet mới (phiên bản 21)
- Canary: 20% traffic → 50% → 100%
- AnalysisTemplate monitor mỗi 10s
- Nếu xấu → auto-abort + rollback
- Alert fire nếu lỗi > 5%

---

### 2️⃣ **Khi canary bị abort (phát hiện lỗi)**

```bash
# Xem trạng thái
kubectl get rollout backend -n demo
kubectl argo rollouts get rollout backend -n demo --watch
```

**Tự động**:
- ReplicaSet cũ scale up
- ReplicaSet mới scale down
- Traffic quay lại 100% phiên bản cũ

---

### 3️⃣ **Khi phát hiện lỗi sau deploy (5 phút)**

```bash
# Revert commit
git revert HEAD
git push origin main
```

**Kết quả**:
- ArgoCD sync → Rollout config quay lại
- Canary deploy phiên bản cũ
- 5 phút là SLA (Service Level Objective)

---

## 🧪 Cách test end-to-end

### **Test Alert + Email**:

```bash
# 1. Port-forward backend (terminal riêng)
kubectl port-forward -n demo svc/backend-service 8081:8080

# 2. Bật inject-error
curl -s http://localhost:8081/inject-error
# Response: {"message":"Error injection toggled. Current state: true"}

# 3. Tạo traffic lỗi (CMD)
for /L %i in (1,1,50) do curl -s http://localhost:8081/ >nul

# 4. Kiểm tra metrics cập nhật
curl -s http://localhost:8081/metrics | findstr http_requests_total
# Sẽ thấy status="500" > 0

# 5. Đợi 40 giây để alert fire
# 6. Kiểm tra Gmail (email phải tới vài phút)
```

---

### **Test Canary Rollback**:

```bash
# 1. Deploy phiên bản mới có lỗi
# (sửa k8s/backend/rollout.yaml, git push)

# 2. Watch rollout
kubectl argo rollouts get rollout backend -n demo --watch

# 3. Khi auto-abort → xem ReplicaSet quay lại
kubectl get rs -n demo
```

---

## 🧱 Lab 1-4 Overview

### Lab 1 · Nền tảng
**Mục tiêu**: Cài Prometheus và Argo Rollouts qua GitOps, không dùng `kubectl apply` trực tiếp.

**Làm bằng cách**:
- Tạo 2 Application mới trong `argocd/apps/`
  - `kube-prometheus-stack.yaml`
  - `argo-rollouts.yaml`
- Mỗi file `Application` dùng Helm chart từ repo chính thức
- Push lên Git, ArgoCD root app tự deploy app-of-apps

**Ví dụ cấu hình**:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
spec:
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 65.1.1
    helm:
      values: |
        prometheus:
          prometheusSpec:
            serviceMonitorSelectorNilUsesHelmValues: false
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

**Với argo-rollouts** đổi chỉ `chart: argo-rollouts`, `targetRevision: 2.37.7`, destination namespace `argo-rollouts`.

**Ví dụ file thực tế**:
- `argocd/apps/kube-prometheus-stack.yaml`
- `argocd/apps/argo-rollouts.yaml`

**Kiểm tra**:
```bash
git add argocd/apps/
git commit -m "obs+rollouts"
git push
kubectl -n argocd get applications
kubectl -n monitoring get pods
kubectl -n argo-rollouts get pods
```

**Kết quả đúng**:
- 2 app mới `Synced`
- Pods `monitoring` và `argo-rollouts` `Running`

**Chú ý**:
- Không dùng `kubectl apply` cho Helm apps trong lab này.
- Root `Application` phải là app-of-apps để ArgoCD tự quản lý.

---

### Lab 2 · Viết app API
**Mục tiêu**: Tạo app Flask có `/metrics`, build image, load vào Minikube.

**Files**:
- `app/app.py`
- `app/Dockerfile`

**Nội dung**:
```python
import os, random
from flask import Flask, jsonify
from prometheus_flask_exporter import PrometheusMetrics

app = Flask(__name__)
PrometheusMetrics(app)
ERR = float(os.getenv("ERROR_RATE", "0"))
VER = os.getenv("VERSION", "v1")

@app.get("/")
def index():
    if random.random() < ERR:
        return jsonify(error="injected", version=VER), 500
    return jsonify(ok=True, version=VER)

@app.get("/healthz")
def healthz():
    return "ok", 200
```

**Dockerfile**:
```dockerfile
FROM python:3.12-slim
RUN pip install flask prometheus-flask-exporter
COPY app.py /app/app.py
WORKDIR /app
ENV FLASK_APP=app.py
EXPOSE 8080
CMD ["flask", "run", "--host=0.0.0.0", "--port=8080"]
```

**Build & load image**:
```bash
docker build -t w9-api:1 app/
minikube image load w9-api:1 -p w9
```

**Hoàn thành khi**:
- `minikube image ls -p w9 | grep w9-api` ra `w9-api:1`

---

### Lab 3 · Viết manifest + metric
**Mục tiêu**: Tạo Rollout + Service + ServiceMonitor, deploy qua ArgoCD, để Prometheus thấy metric.

**Files**:
- `k8s-api/api.yaml`
- `k8s-api/servicemonitor.yaml`
- `argocd/apps/api.yaml`

**Nội dung**:
- `api.yaml` chứa `Rollout` resource và `Service` port 8080
- `servicemonitor.yaml` chứa `ServiceMonitor` để Prometheus scrape `/metrics`
- `argocd/apps/api.yaml` là ArgoCD Application cho `path: k8s-api`, namespace `demo`

**Ví dụ file**:
```yaml
# argocd/apps/api.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-repo>.git
    path: k8s-api
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

```yaml
# k8s-api/api.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api
  namespace: demo
  labels:
    app: api
spec:
  replicas: 4
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: w9-api:1
        imagePullPolicy: IfNotPresent
        ports:
        - name: http
          containerPort: 8080
        env:
        - name: ERROR_RATE
          value: "0"
        - name: VERSION
          value: "v1"
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
  strategy:
    canary:
      steps:
      - setWeight: 25
      - pause: {}
      - setWeight: 50
      - pause:
          duration: 30s
      - setWeight: 100
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: demo
  labels:
    app: api
spec:
  selector:
    app: api
  ports:
  - name: http
    port: 8080
    targetPort: 8080
```

```yaml
# k8s-api/servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: api-servicemonitor
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app: api
  namespaceSelector:
    matchNames:
      - demo
  endpoints:
  - port: http
    path: /metrics
    interval: 15s
```

**Điểm quan trọng**:
- `Rollout` dùng `image: w9-api:1`
- ServiceMonitor chọn `app=api`
- Prometheus phải thấy `api` target UP

**Kiểm tra**:
```bash
git add app/ k8s-api/ argocd/apps/api.yaml
git commit -m "api"
git push
kubectl -n demo run load --image=busybox --restart=Never -- sh -c "while true; do wget -qO- api:8080/; done"
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:
```

**Xong khi**:
- Prometheus Targets thấy `api` UP
- Query `flask_http_request_total{namespace="demo"}` tăng dần

---

### Lab 4 · Canary tay
**Mục tiêu**: Quan sát rollout canary dừng chờ người quyết định.

**Làm gì**:
- Sửa `k8s-api/api.yaml` version `v1 -> v2`
- Push Git
- ArgoCD sync → Rollout bắt đầu
- Rollout dừng ở step `pause: {}`

**Theo dõi**:
```bash
kubectl argo rollouts get rollout api -n demo --watch
```

**Quyết định bằng tay**:
- `promote` nếu tốt:
  ```bash
  kubectl argo rollouts promote api -n demo
  ```
- `abort` nếu xấu:
  ```bash
  kubectl argo rollouts abort api -n demo
  ```
```

**Chú ý**:
- Manual canary chỉ dừng ở 25% và chờ người
- `promote` lên tiếp 50% → 100%
- `abort` về bản cũ ngay

**Challenge**: Thay `pause` tay bằng `AnalysisTemplate` để máy tự abort khi metric xấu.
- Bạn đã làm phần này sớm trong lab backend
- Điều quan trọng là phân biệt:
  - Lab 4: **manual canary** (human decision)
  - Challenge: **automated canary** (machine decision bằng Prometheus)

---

## 🎯 Ghi chú cho challenge
Nếu bạn đã làm phần `AnalysisTemplate` cho backend thì bạn đã thực hiện phần challenge rồi.

Điểm cần nêu khi giải thích:
- `pause: {}` là cách dừng tay trong Lab 4
- `AnalysisTemplate` là cách cho máy tự đánh giá và abort
- `failureLimit: 1` + `successCondition` = rollback tự động khi metric tệ

---

## ⚠️ Các lỗi thường gặp

| Vấn đề | Nguyên nhân | Cách sửa |
|--------|-----------|---------|
| ArgoCD không sync | Thay đổi cluster trực tiếp bằng kubectl | Push Git lại, ArgoCD sẽ sync |
| Alert không fire | Prometheus không scrape metrics | Kiểm tra `relabel_configs` trong prometheus.yaml |
| Email không tới | SMTP config sai | Kiểm tra app password, TLS setting |
| Canary không abort | AnalysisTemplate query sai | Verify Prometheus query trả metrics đúng |
| Metrics không update | Backend `/metrics` không expose | Test `curl http://localhost:8081/metrics` |

---

## 📝 Query Prometheus quan trọng

### **Error Rate** (dùng trong alert rule):
```promql
(sum(rate(http_requests_total{app="backend", status="500"}[30s])) or vector(0)) / 
(sum(rate(http_requests_total{app="backend"}[30s])) or vector(1))
```

### **Success Rate** (dùng trong analysis-template):
```promql
(sum(rate(http_requests_total{app="backend", status!="500"}[1m])) or vector(1)) / 
(sum(rate(http_requests_total{app="backend"}[1m])) or vector(1))
```

### **Request Count**:
```promql
sum(rate(http_requests_total{app="backend"}[1m]))
```

---

## ✅ Checklist khi submit

- [ ] Tất cả file YAML đang chạy (ArgoCD Synced)
- [ ] Backend expose `/metrics` endpoint
- [ ] Prometheus scrape backend targets (Status → Targets)
- [ ] Alert rule fire khi lỗi > 5% (Prometheus → Alerts)
- [ ] Email alert tới Gmail
- [ ] Canary auto-abort khi lỗi cao (kubectl get rollout)
- [ ] Git revert rollback hoạt động (ArgoCD re-sync)
- [ ] README giải thích cách test

---

## 🔗 Tài liệu tham khảo

- [Argo Rollouts - Progressive Delivery](https://argoproj.io/argo-rollouts/)
- [Prometheus Docs](https://prometheus.io/docs/)
- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/)

