### BƯỚC 1: Khởi tạo Nền tảng (Cơ sở hạ tầng & Ứng dụng)
B1 : manifests/namespace.yaml
- Mọi tài nguyên khác đều cần được deploy vào một Namespace cụ thể để quản lý độc lập và không làm ảnh hưởng đến hệ thống mặc định.
B2: app/backend-v1/app.py & app/backend-v2/app.py
- tạo trước bởi vì chúng ta cần logic để prometheus có thể scrape
và đây là ứng dụng flask tích hợp thư viện prometheus_client
### BƯỚC 2: Mạng lưới và Định tuyến (Networking)
B3 : manifests/service/stable-svc.yaml
-  Rollout cần biết tên chính xác của Stable Service để gán traffic ổn định vào đó.
 Argo Rollouts sẽ quản lý việc cập nhật version mới một cách an toàn hơn Deployment mặc định của Kubernetes. và cần lấy namespace của B1

B4: manifests/service/canary-svc.yaml
- Rollout cần Canary Service để chuyển hướng một phần traffic nhỏ (ví dụ 10%, 20%) sang các Pod mới chạy v2 phục vụ việc phân tích và cần lấy namespace của B1
### BƯỚC 3: Giám sát nâng cao (Monitoring, Prometheus Rule & Burn Rate)
Trước khi cấu hình tự động phân tích (Analysis), Prometheus cần phải nhận diện được Service của chúng ta và cấu hình sẵn các quy tắc tính toán cảnh báo, đặc biệt là Burn Rate (Tốc độ tiêu hao Error Budget dựa trên SLO).
B5: manifests/monitoring/servicemonitor.yaml
- Định nghĩa cho Prometheus Operator biết cần phải crawl (cào) dữ liệu metrics từ endpoint /metrics của các Service trên.
B6: manifests/monitoring/prometheus-rule.yaml

### BƯỚC 4: Phân tích & Tự động hóa Deployment (Argo Rollouts CRD)
Đây là "bộ não" của Progressive Delivery. AnalysisTemplate định nghĩa các tiêu chuẩn đo lường (Metrics & Query) kèm điều kiện hủy bỏ (abortCriteria), còn Rollout định nghĩa các bước đi của Canary step-by-step.
B7:  manifests/rollout/analysis-template.yaml
- Rollout.yaml sẽ gọi tên AnalysisTemplate này trong các step deploy của nó. Do đó mẫu phân tích này phải được khai báo trước.
+ successCondition: Điều kiện xem Canary có an toàn không (ví dụ: Burn rate phải nhỏ hơn 1 hoặc Error rate < 1%).
+ failureLimit: Cho phép truy vấn lỗi tối đa bao nhiêu lần trước khi chính thức Rollback (Hủy bỏ deployment).
+ consecutiveErrorLimit: Số lần lỗi kết nối/lỗi hệ thống liên tiếp từ phía Prometheus (không phải lỗi của code app) thì dừng lại.
- Analysis-template là nơi đ/n Kiểm tra những điều kiện nào để quyết định phiên bản mới có tốt hay không?"
B8: manifests/rollout/rollout.yaml
- Rollout liên kết mọi thành phần lại với nhau: Nó quản lý Pod Template, điều phối Traffic qua backend-stable / backend-canary và trigger việc phân tích dựa trên backend-burn-rate-analysis.
- Strategy: Canary (quan trọng nhất)
strategy:
  canary:
 Nghĩa là deploy theo kiểu:
không update 100% ngay, mà chia traffic từng bước

- giữ trạng thái để:
collect metrics
xem hệ thống có lỗi không

### BƯỚC 5: Kiểm thử gánh tải & Cấu hình phụ trợ
B9: manifests/monitoring/alertmanager-config.yaml
- Khi AnalysisTemplate kích hoạt Abort Criteria và Rollback, Prometheus Alertmanager sẽ bắt được Alert và bắn thông báo (Slack/Webhook) giúp đội ngũ Engineer biết đợt Canary đã thất bại.
+ Abort Criteria = điều kiện để dừng (abort) rollout ngay lập tức
B10: manifests/loadtest/hey.sh
- Đây là Script phía Client để tạo tải giả lập liên tục vào hệ t`hống khi đang diễn ra Canary, từ đó sinh ra metrics cho Prometheus thu thập.

### để chạy bài thì:
b1: minikube start
b2: # Tạo Namespace và Mạng lưới
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/service/stable-svc.yaml
kubectl apply -f manifests/service/canary-svc.yaml