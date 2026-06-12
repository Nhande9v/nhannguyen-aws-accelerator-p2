# Tài liệu quy trình
# pass word: RgKQHTVHl2GAyh3R
$ kubectl port-forward -n argocd svc/argocd-server 8080:443
## Tổng quan

Mục tiêu của lab này là **triển khai phiên bản API mới một cách an toàn và tự động bảo vệ nó** bằng một quy trình GitOps với ArgoCD, phân tích canary tự động qua Argo Rollouts, quan sát với Prometheus & Alertmanager, và rollback ngay lập tức bằng Git revert trong vòng 5 phút.

## Cấu trúc kho

```
cloud/w9/gitops/
├── argocd/
│   ├── root.yaml                  # Ứng dụng gốc quản lý tất cả các app
│   └── apps/                      # Ứng dụng thành phần
│       ├── backend.yaml
│       ├── frontend.yaml
│       └── observability.yaml     # Ứng dụng giám sát
├── k8s/
│   ├── backend/
│   │   ├── rollout.yaml
│   │   └── analysis-template.yaml # Tích hợp với backend
│   ├── frontend/
│   │   └── deployment.yaml
│   └── observability/
│       ├── namespace.yaml
│       └── prometheus-rule.yaml
└── process.md                     # Tài liệu này
```

## Ngăn xếp quan sát (Observability Stack)

- **Prometheus** – thu thập metrics từ dịch vụ backend.
- **Alertmanager** – nhận alert từ Prometheus và chuyển tiếp đến MailHog SMTP cục bộ để kiểm tra email.
- **MailHog** – bộ nhận SMTP đơn giản lưu lại email cảnh báo.

Các file liên quan (tạo trong `k8s/observability/`):
- `mailhog.yaml`
- `prometheus.yaml`
- `alertmanager.yaml`

## Canary Rollout cho backend

`k8s/backend/rollout.yaml` định nghĩa một tài nguyên **Rollout** với:
- Một Service để mở lối truy cập backend.
- Một container mở `/metrics` (định dạng Prometheus) và `/inject-error` (khiến ứng dụng lỗi để thử nghiệm).
- Các kiểm tra sức khỏe (`readinessProbe` và `livenessProbe`).

`k8s/backend/analysis-template.yaml` cung cấp một **AnalysisTemplate** mà:
- Truy vấn chỉ số `backend_error_rate` từ Prometheus mỗi **10 giây**.
- Kết luận canary thất bại sau **1** lần thất bại liên tiếp (`failureLimit: 1`).
- Tự động dừng rollout và quay về phiên bản ổn định trước đó.

## Quy trình GitOps

1. **Thực hiện thay đổi** trên bất kỳ file YAML nào (ví dụ: cập nhật thẻ image backend).
2. **Commit** thay đổi:
   ```bash
   git add .
   git commit -m "Update backend image to v2"
   git push origin main
   ```
   ArgoCD sẽ phát hiện commit và đồng bộ cluster.
3. **Rollback** (nếu cần) trong vòng **5 phút** bằng:
   ```bash
   git revert HEAD   # hoặc revert commit SHA cụ thể
   git push origin main
   ```
   ArgoCD sẽ tự động đồng bộ trở lại phiên bản trước đó.

## SLO & Cảnh báo

- **SLO**: 99,9% yêu cầu thành công mỗi phút.
- **Luật cảnh báo** (`prometheus-rule.yaml`): kích hoạt khi tỷ lệ lỗi vượt quá **5%** trong khoảng 1 phút.
- **Alertmanager** gửi cảnh báo tới MailHog, có thể kiểm tra tại `http://localhost:8025`.

## Các bước kiểm tra

1. **Triển khai** canary (ArgoCD sẽ bắt đầu rollout).
2. **Tiêm lỗi** để kiểm tra rollback tự động:
   ```bash
   curl http://<backend-service>/inject-error
   ```
   Lỗi sẽ tăng chỉ số `backend_error_rate`, khiến AnalysisTemplate đánh giá thất bại và rollout sẽ quay lại.
3. **Kiểm tra cảnh báo** trong MailHog để xác nhận email thông báo đã được gửi.
4. Xác nhận phiên bản ổn định đang chạy lại bằng:
   ```bash
   kubectl get rollout backend -n <namespace>
   ```

## Tóm tắt lệnh

```bash
# Namespace cho Argo Rollouts
kubectl create namespace argo-rollouts

# Cài CRD Argo Rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Cài Prometheus Operator (không dùng Helm)
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml

# Áp dụng ngăn xếp quan sát
kubectl apply -f k8s/observability/

# Áp dụng rollout backend
kubectl apply -f k8s/backend/
```

Những bước này hoàn thành tài liệu quy trình yêu cầu cho lab.

├── argocd/
│   ├── root.yaml                  # "Gốc" quản lý tất cả các app
│   └── apps/                      # Các app thành phần
│       ├── backend.yaml
│       ├── frontend.yaml
│       └── observability.yaml     # App quản lý monitoring
├── k8s/
│   ├── backend/
│   │   ├── rollout.yaml
│   │   └── analysis-template.yaml # Tích hợp sẵn vào backend
│   ├── frontend/
│   │   └── deployment.yaml
│   └── observability/             # Nền tảng giám sát
│       ├── namespace.yaml
│       └── prometheus-rule.yaml
└── process.md                     # Hướng dẫn nộp bài
observability.yaml  <-- Tạo file này để ArgoCD quản lý monitor
analysis-template.yaml : Đây là một Argo Rollouts AnalysisTemplate dùng để đánh giá chất lượng của một deployment (thường là canary hoặc blue-green) bằng cách lấy metric từ Prometheus

B1: namespace.yaml: để có nơi chứa toàn bộ hệ thống giám sát
B2: prometheus-rule.yaml: đây là luật để Prometheus biết khi bắn lỗi
B3: k8s/backend/rollout.yaml: đây là bộ khung để hệ thống tự động kiểm tra sức khỏe mỗi khi bạn cập nhật phần mềm, giảm rủi ro khi deploy version mới
B4: k8s/backend/analysis-template.yaml: để rollout biết kiểm tra gì
Rollout = quy trình deploy canary.
AnalysisTemplate = bộ tiêu chí đánh giá.
Canary = chiến lược deploy dần dần
B5: observability.yaml: Kết nối mọi thứ vào ArgoCD
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
nhớ cài

Bạn không nhất thiết phải dùng Helm, bạn có thể áp dụng trực tiếp các file YAML định nghĩa CRD từ trang chủ của Prometheus Operator.

Hãy chạy lệnh này để cài đặt "bộ khung" của Prometheus vào cluster mà không cần cài Helm:

kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml