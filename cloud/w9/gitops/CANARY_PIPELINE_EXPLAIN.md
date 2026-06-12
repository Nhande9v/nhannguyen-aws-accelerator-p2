**Canary Pipeline — Giải thích & Lý do chia bước**

**Mục tiêu (4 yêu cầu gốc)**
- **GitOps**: Mọi thay đổi đi qua Git, ArgoCD tự sync, không có drift.
- **Canary tự động**: Thay `pause` tay bằng `AnalysisTemplate` để tự quyết định tiếp/abort.
- **Observability / SLO**: Prometheus trả metric/SLO để phân biệt bản tốt/bản lỗi.
- **Rollback reproducible + Evidence**: Có thể `git revert` để rollback và có bằng chứng (ảnh/clip) canary auto-abort.

**Tại sao tôi chia thành 8 bước cụ thể**
Để thực hiện an toàn 4 yêu cầu trên cần một số phần độc lập, mỗi phần giải quyết một rủi ro vận hành hoặc kỹ thuật:
- **1) Commit & ArgoCD app**: đảm bảo thay đổi cấu hình (image/version/AnalysisTemplate refs) được quản lý bởi Git — bước deploy cơ bản.
- **2) Rollout manifest**: `Rollout` (thay cho `Deployment`) khai báo chiến lược canary và tham chiếu `AnalysisTemplate` — cơ chế dịch vụ thực tế sẽ chạy.
- **3) AnalysisTemplate**: định nghĩa các bước phân tích (PromQL queries, interval, failureConditions) để thay thế `pause` tay bằng logic tự động.
- **4) Prometheus SLO / PromQL**: viết query/SLO cụ thể (ví dụ: success rate, latency) và ngưỡng (ví dụ <99% trong 5m là fail).
- **5) ServiceMonitor / PrometheusRule**: đảm bảo Prometheus có thể scrape `api` và có rule để tính SLO/alert.
- **6) Alertmanager + Receiver (email)**: cấu hình receiver/email để gửi alert khi SLO bị breach — dùng cho chứng minh và vận hành.
- **7) Argo Rollouts Analysis wiring**: liên kết `AnalysisTemplate` với `Rollout` để khi metric vượt ngưỡng thì Rollout **auto-abort/rollback**.
- **8) README + Steps reproducible**: tài liệu (README) mô tả query, ngưỡng, cách reproduce, và cách `git revert` để rollback; cần để đạt mục yêu cầu chứng minh reproducible từ Git.

Mỗi yêu cầu gốc thường cần nhiều hoạt động nhỏ (ví dụ: để có Observability cần cả ServiceMonitor + query + PrometheusRule), nên tổng lên thành ~8 mục rõ ràng để thực thi an toàn.

**Map ngược: 8 → 4**
- GitOps: (1) Commit & ArgoCD app  + (8) README (để reproduce từ Git)
- Canary tự động: (2) Rollout manifest + (3) AnalysisTemplate + (7) Rollouts wiring
- Observability/SLO: (4) PromQL + (5) ServiceMonitor/PrometheusRule
- Rollback & Evidence: (6) Alertmanager/email + (8) README/screenshot steps

**Ví dụ ngắn — cách chứng minh (quick recipe)**
- Tạo branch: `git checkout -b feature/api-canary`
- Bump image trong [w9/gitops/k8s-api/api.yaml](w9/gitops/k8s-api/api.yaml) -> `image: myuser/w9-api:v2` và/hoặc thay env để gây lỗi tạm thời (ví dụ `ERROR_RATE=0.5`).
- Commit & push → ArgoCD sẽ sync (nếu không tự động, refresh app):
  ```bash
  git add -A && git commit -m "canary: v2" && git push origin HEAD
  kubectl -n argocd annotate application api argocd.argoproj.io/refresh='hard' --overwrite
  ```
- Quan sát canary: `kubectl -n demo get rollout api` và check analysis status.
- Nếu AnalysisTemplate phát hiện SLO fail, Argo Rollouts sẽ `abort` và giữ bản cũ; chụp ảnh/clip màn hình timeline này.
- Để rollback cấu hình Git (nếu muốn revert manifest):
  ```bash
  git revert <commit-hash>
  git push origin HEAD
  ```

**Gợi ý cho query SLO (ví dụ)**
- **Availability (success rate)**:
  ```promql
  sum(rate(http_requests_total{job="api",status=~"2.."}[5m]))
  /
  sum(rate(http_requests_total{job="api"}[5m]))
  ```
- Threshold (example): **< 0.99** trong cửa sổ 5m → fail.

**Kết luận ngắn**
Việc mở rộng từ 4 thành ~8 bước là hợp lý vì mỗi mục tiêu lớn chứa nhiều thành phần kỹ thuật độc lập (deploy, đo lường, alerting, wiring). File này là checklist lý thuyết — nếu bạn muốn, tôi có thể:
- tạo `AnalysisTemplate` + mẫu `PrometheusRule` và `Alertmanager` receiver (email),
- chỉnh `Rollout` để tham chiếu `AnalysisTemplate`,
- rồi demo bằng một commit tạo lỗi để show auto-abort và ghi ảnh/clip.

---
File này đã tạo tại: `w9/gitops/CANARY_PIPELINE_EXPLAIN.md`
