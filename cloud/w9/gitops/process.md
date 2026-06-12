cloud/w9/gitops/
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
B2: prometheus-rule.yaml : đây là luật để Prometheus biết khi bắn lỗi 
B3: k8s/backend/rollout.yaml: đây là bộ khung để hệ thống tự ddoonjg kiểm tra sức khỏe mỗi khi bạn cập nhật phần mềm, giảm rủi ro khi deploy version mới
B4: k8s/backend/analysis-template.yaml: để rollout bk kiểm tra gì
Rollout = quy trình deploy canary.
AnalysisTemplate = bộ tiêu chí đánh giá.
Canarry = chiến lược deploy dần dần
B5: observability.yaml: Kết nối mọi thứ vào ArgoCD
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
nhớ cài

Bạn không nhất thiết phải dùng helm, bạn có thể áp dụng trực tiếp các file YAML định nghĩa CRD từ trang chủ của Prometheus-Operator.

Hãy chạy lệnh này để cài đặt "bộ khung" của Prometheus vào cluster mà không cần cài Helm:

Bash
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml