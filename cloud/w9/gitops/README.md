# GitOps + Canary + Observability Lab

## Mục tiêu chính
- Triển khai ứng dụng theo nguyên tắc **GitOps**: Git là nguồn sự thật duy nhất.
- Sử dụng **ArgoCD** để đồng bộ manifest từ Git vào cluster.
- Dùng **Argo Rollouts** để deploy canary an toàn.
- Dùng **Prometheus + Alertmanager** để giám sát và gửi alert email.

---

## Cấu trúc thư mục quan trọng
```
gitops/
├── README.md
├── process.md
├── .github/
│   └── workflows/
│       └── validate.yml
├── app/
│   ├── app.py
│   └── Dockerfile
├── argocd/
│   ├── root.yaml
│   └── apps/
│       ├── api.yaml
│       ├── argo-rollouts.yaml
│       ├── backend.yml
│       ├── frontend.yaml
│       ├── kube-prometheus-stack.yaml
│       ├── observability.yaml
│       └── web.yaml
├── k8s-api/
│   ├── api.yaml
│   └── servicemonitor.yaml
└── k8s/
    ├── backend/
    │   ├── rollout.yaml
    │   └── analysis-template.yaml
    ├── frontend/
    │   └── deployment.yaml
    ├── observability/
    │   ├── namespace.yaml
    │   ├── prometheus.yaml
    │   ├── prometheus-rule.yaml
    │   ├── alertmanager.yaml
    │   └── mailhog.yaml
    └── web/
        ├── namespace.yaml
        └── web.yaml
```

---

## Tại sao dùng GitOps ở đây?
- **Git là nguồn duy nhất**: mọi thay đổi được lưu trong repo.
- **Cluster không dùng `kubectl apply` thủ công** khi không cần thiết.
- **ArgoCD tự động đồng bộ** trạng thái Git với Kubernetes.
- **Nếu cluster bị sửa tay**, ArgoCD sẽ cảnh báo hoặc tự phục hồi nếu bật `selfHeal`.

### GitOps trong repo này có nghĩa là:
- `argocd/root.yaml` quản lý toàn bộ các app con.
- `argocd/apps/*.yaml` định nghĩa từng app con.
- `k8s-api/` và `k8s/` chứa manifest thật của ứng dụng.
- Các Helm app như `argo-rollouts` và `kube-prometheus-stack` được deploy từ chart repo.

---

## Luồng chạy GitOps chi tiết

### 1) Root Application: `argocd/root.yaml`
Đây là ứng dụng gốc của ArgoCD.

- `repoURL` trỏ tới repo chứa tất cả manifest.
- `targetRevision: main` đồng bộ từ branch `main`.
- `path: cloud/w9/gitops/argocd/apps` chỉ nơi chứa các app con.

**Tại sao dùng root app?**
- Root app là mô hình `app-of-apps`.
- Nó không deploy workloads trực tiếp.
- Nó quản lý những app con khác.

### 2) Các Application con trong `argocd/apps/`
Mỗi file ở đây là một app độc lập được ArgoCD quản lý.

- `api.yaml`: deploy manifest trong `cloud/w9/gitops/k8s-api` vào namespace `demo`.
- `argo-rollouts.yaml`: cài Argo Rollouts controller từ Helm chart.
- `kube-prometheus-stack.yaml`: cài Prometheus + Alertmanager từ Helm chart.
- `backend.yml`: deploy backend canary ở `k8s/backend`.
- `frontend.yaml`: deploy frontend ở `k8s/frontend`.
- `web.yaml`: deploy web service ở `k8s/web`.
- `observability.yaml`: quản lý cấu hình monitoring bổ sung nếu cần.

**Tại sao sắp xếp như vậy?**
- Phân tách rõ ràng giữa metadata ArgoCD và nội dung deploy.
- Mỗi app con có nguồn và namespace riêng.
- Dễ mở rộng, dễ debug.

### 3) Khi ArgoCD root app chạy
- Root app đọc `argocd/apps/` từ Git.
- ArgoCD tạo hoặc cập nhật từng Application con.
- Mỗi app con sync manifest riêng với cluster.

### 4) Luồng chạy tới manifest cụ thể
Ví dụ với app `api`:
- Root app load `argocd/apps/api.yaml`.
- App `api` dùng `repoURL` và `path: cloud/w9/gitops/k8s-api`.
- ArgoCD tải manifest trong `k8s-api/` và apply vào namespace `demo`.

Ví dụ với app `backend`:
- App `backend` dùng `path: cloud/w9/gitops/k8s/backend`.
- ArgoCD apply `rollout.yaml` và `analysis-template.yaml`.
- Backend được deploy như một `Rollout` với canary strategy.

Ví dụ với Helm app `kube-prometheus-stack`:
- ArgoCD tải chart từ `https://prometheus-community.github.io/helm-charts`.
- Render manifest bằng Helm values trong file.
- Deploy monitoring stack vào namespace `monitoring`.

---

## Giải thích các file quan trọng

### `argocd/root.yaml`
**Mục đích:** khởi tạo app-of-apps.

**Giải thích:**
- Root app không deploy dịch vụ.
- Nó chỉ cho ArgoCD biết nơi tìm các `Application` con.
- Khi có thay đổi trong `argocd/apps/`, ArgoCD sẽ cập nhật app con.

### `argocd/apps/api.yaml`
**Mục đích:** deploy API app và ServiceMonitor.

**Tại sao viết như vậy:**
- `repoURL` trỏ tới repo chứa manifest.
- `path` phải là đường dẫn repo-relative.
- `targetRevision: main` dùng nhánh chính.
- `destination.namespace: demo` deploy vào namespace demo.
- `CreateNamespace=true` tạo namespace nếu chưa tồn tại.
- `ServerSideApply=true` giúp apply theo state server.

### `argocd/apps/argo-rollouts.yaml`
**Mục đích:** cài Argo Rollouts controller.

**Giải thích:**
- Đây là Helm Application.
- `repoURL` là chart repo của Argo Helm.
- `chart: argo-rollouts` và `targetRevision: 2.37.7` chỉ định chart.
- Namespace đích là `argo-rollouts`.

### `argocd/apps/kube-prometheus-stack.yaml`
**Mục đích:** cài monitoring stack.

**Giải thích:**
- Dùng Helm chart `kube-prometheus-stack`.
- `helm.values` cấu hình Prometheus để hỗ trợ ServiceMonitor.
- Namespace đích là `monitoring`.

### `k8s-api/api.yaml`
**Mục đích:** định nghĩa Deployment/Service cho API.

**Giải thích:**
- File này chứa manifest thật cho API.
- Nếu muốn thay đổi API, sửa ở đây.
- ArgoCD sync lại khi file được commit.

### `k8s-api/servicemonitor.yaml`
**Mục đích:** cho Prometheus biết cách scrape API.

**Giải thích:**
- ServiceMonitor dùng label selector để tìm service.
- Nếu ServiceMonitor không đúng, Prometheus sẽ không scrape.

### `k8s/backend/rollout.yaml`
**Mục đích:** định nghĩa chiến lược canary cho backend.

**Giải thích:**
- Dùng `Rollout` thay vì `Deployment` để có canary.
- Các bước `setWeight` và `pause` điều phối traffic.
- Rollout tăng từ 20% lên 50% rồi 100%.
- Nếu metric xấu, Rollout abort và rollback.

### `k8s/backend/analysis-template.yaml`
**Mục đích:** định nghĩa cách đo chất lượng canary.

**Giải thích:**
- `AnalysisTemplate` kiểm tra metric từ Prometheus.
- Nếu metric không đạt, rollout sẽ abort.
- Đây là bản chất của canary tự động.

### `k8s/observability/prometheus-rule.yaml`
**Mục đích:** định nghĩa alert rule cho Prometheus.

**Giải thích:**
- Rule tính error rate.
- Nếu lỗi > 5% liên tiếp 10s, alert firing.
- `for: 10s` giúp tránh cảnh báo giả.

### `k8s/observability/alertmanager.yaml`
**Mục đích:** cấu hình gửi email alert.

**Giải thích:**
- Dùng Gmail SMTP.
- `smtp_auth_password` phải là app password.
- Receiver email nhận alert.

### `k8s/observability/mailhog.yaml`
**Mục đích:** email testing server nội bộ.

**Giải thích:**
- Dùng khi không muốn gửi email thật.
- Nếu dùng MailHog, alert gửi vào UI nội bộ.

---

## Tại sao ghi mỗi phần như vậy?

### `repoURL` + `path`
- `repoURL` xác định repo chứa manifest.
- `path` xác định thư mục trong repo.
- `path` phải là repo-relative.
- Nếu sai, ArgoCD sẽ báo `app path does not exist`.

### `CreateNamespace=true`
- Tự tạo namespace khi chưa có.
- Giảm bước tạo namespace thủ công.

### `ServerSideApply=true`
- Dùng apply của API server.
- Giúp ArgoCD xử lý tốt hơn khi sync lại.

### `prune: true`
- Xóa resource đã bị xóa khỏi Git.
- Giữ cluster sạch.

### `selfHeal: true`
- Tự phục hồi nếu cluster bị thay đổi ngoài Git.
- Giữ cluster luôn đúng với Git.

---

## Luồng root → app → k8s cụ thể

1. `argocd/root.yaml` load từ Git và đọc thư mục `argocd/apps`.
2. Root app tạo các Application con.
3. Mỗi app con sync manifest riêng với cluster.
4. App `api` sync `k8s-api/`.
5. App `backend` sync `k8s/backend/`.
6. App `kube-prometheus-stack` render Helm chart.
7. Cluster nhận manifest và tạo resources.

---

## Những thứ cần thiết nhất
- `argocd/root.yaml`: root app.
- `argocd/apps/*.yaml`: app con.
- `k8s-api/` và `k8s/`: manifest thật.
- `prometheus-rule.yaml`: alert rule.
- `alertmanager.yaml`: email config.
- `servicemonitor.yaml`: kết nối Prometheus.

---

## Câu hỏi ôn tập hay ho
- Root app trong ArgoCD dùng để làm gì?
- `path` trong app con nên viết như thế nào?
- App `api` lấy manifest từ thư mục nào?
- `kube-prometheus-stack` là app Git hay Helm?
- Nếu `Application` báo `ComparisonError`, cách debug ra sao?
- `prune: true` và `selfHeal: true` khác nhau như thế nào?
- Nếu muốn rollback, bạn sửa gì trong Git?
- Alert được gửi khi rule nào firing?
- Tại sao `ServerSideApply=true` quan trọng với ArgoCD?
- Nếu `api` app không sync, bước đầu bạn kiểm tra gì?

---

## Cách kiểm tra nhanh
```bash
kubectl -n argocd get applications
kubectl -n argocd describe application api
kubectl -n argocd describe application argo-rollouts
kubectl -n monitoring get pods
kubectl -n demo get pods
kubectl argo rollouts get rollout backend -n demo
kubectl -n monitoring get alerts
```

## Gợi ý debug nhanh
- Sai `path` repo-relative → `app path does not exist`.
- YAML lỗi/kém indent → `ComparisonError`.
- Resource cũ với selector immutable → xóa resource cũ và sync lại.
- App `Healthy` nhưng `OutOfSync` → cluster khác với Git.
