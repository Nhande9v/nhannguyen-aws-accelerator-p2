# Requirements Analysis - Task Force 4 · CDO Group 1

## 1. Đề tài Context
* **Client**: Head of SRE tại một Fintech quy mô trung bình (mid-size).
* **Quy mô hệ thống**: 
  * ~3.5 triệu active users.
  * ~2.8k RPS peak ngày thường, ~9k RPS peak dịp Black Friday.
  * Vận hành ~120 microservices production trên nền tảng AWS (ECS Fargate + RDS Aurora MySQL + DynamoDB + SQS).
* **Vấn đề cốt lõi (Pain Points)**:
  * Miss SLO liên tục 7 lần trong 3 tháng qua (target monthly availability 99.9%) do sự cố nghẽn tài nguyên ngầm (silent capacity exhaustion): CPU RDS tăng vọt lên 100% trong 90 phút trước khi connection pool bị cạn kiệt, queue backlog tăng 6 lần gây timeout, ALB connection limit chạm ngưỡng tối đa.
  * Các sự cố chỉ được phát hiện khi có phản hồi tiêu cực từ người dùng qua support ticket (18-25 tickets trước khi hệ thống alert nội bộ kích hoạt).
  * Đã có sẵn công cụ giám sát (Grafana, CloudWatch, DataDog trial) nhưng thiếu tính chủ động (proactive detection) do cảnh báo ngưỡng tĩnh (static threshold) quá nhạy gây alert fatigue hoặc quá trễ khi hệ thống drift chậm.
* **Mục tiêu dự án (Foresight Lens)**:
  * Xây dựng hệ thống giám sát chủ động (proactive time-series analysis) chạy 24/7 để học baseline bình thường của từng dịch vụ.
  * Cảnh báo sớm trước ít nhất 15 phút (với test window >= 2 tiếng) kèm theo khuyến nghị hành động cụ thể (actionable capacity recommendation) dạng manual approval gate (không auto-remediate).
  * Đảm bảo tính đa thuê (multi-tenant) tối thiểu cho 3 dịch vụ tier-1: `payment-api`, `queue-worker`, và `gateway-api`.

---

## 2. Infra Non-Functional Requirements (NFR)

| NFR | Target | Justification |
| :--- | :--- | :--- |
| **Multi-tenant scale** | $\ge 50$ tenants | Đảm bảo khả năng mở rộng phục vụ toàn bộ subset dịch vụ quan trọng trong 120 microservices của khách hàng khi rollout diện rộng. |
| **Production Target SLO** | $p99 \text{ latency} < 1000\text{ms}$ | Cam kết từ AI API contract nhằm đảm bảo phản hồi dự đoán/phân tích tải gần như tức thời khi có truy vấn từ các luồng kiểm thử hoặc webhook cảnh báo. |
| **Availability** | $\ge 99.5\%$ | Đáp ứng yêu cầu SLA tối thiểu cho môi trường demo/staging chất lượng cao mà không đẩy chi phí vận hành hạ tầng lên quá mức. |
| **Error rate** | $< 0.5\%$ | Giới hạn tỷ lệ lỗi hệ thống hạ tầng để đảm bảo độ tin cậy từ phía SRE và các dịch vụ tích hợp khác. |
| **Cost per tenant/month** | $\approx \$2 - \$3$ | Với budget tối đa \$200/tháng cho môi trường Capstone, chi phí hạ tầng tính trên tenant cần cực kỳ tối ưu để có thể chạy thử nghiệm song song tối thiểu 3-5 tenants tier-1 mà không vượt budget. |
| **Onboarding SLA** | $< 15$ mins | Quy trình onboarding dạng **Config-driven (GitOps)** giúp đăng ký và kích hoạt thu thập telemetry/tạo baseline cho service mới chỉ bằng việc cập nhật Git repository và deploy IaC tự động. |
| **Security baseline** | IAM least-privilege + KMS + CloudTrail audit | Tuân thủ các tiêu chuẩn bảo mật tài chính (Fintech), mã hóa dữ liệu tại chỗ (encryption at rest) cho cả telemetry storage và audit log. |
| **Operational Trust** | Validation & E2E Traceability | Telemetry phải được kiểm tra schema và tenant matching tại ingestion boundary trước khi lưu; hỗ trợ E2E Correlation ID đi từ client telemetry đến prediction log và Grafana annotation. |

---

## 3. Differentiation Angle (KEY)

* **Angle chọn**: **Serverless-First & Event-Driven Hybrid Observability Platform với Operational Trust**
* **Why this angle (Trọng tâm: Chi phí tối giản & Khả năng co giãn cực hạn & Độ tin cậy vận hành)**:
  * **Cost-Efficiency (Tối ưu hóa chi phí chạy nền)**: Với ngân sách capstone cực kỳ ngặt nghèo (\$200/tháng), việc duy trì các cụm máy chủ ảo hoặc Kubernetes control plane hoạt động 24/7 là không khả thi. Hướng đi Serverless-First cho phép hạ tầng tự động scale về 0 khi không có tải kiểm thử, giảm thiểu tối đa hóa đơn AWS khi ở trạng thái rảnh rỗi.
  * **Operational Trust (Tin cậy vận hành)**: Telemetry được kiểm duyệt chặt chẽ (schema validation & tenant match) ở ranh giới đầu vào để ngăn chặn ô nhiễm dữ liệu. Hệ thống đảm bảo không mất mát sự kiện âm thầm nhờ cơ chế retry/DLQ, và tích hợp fallback tự động về static threshold khi AI model serving gặp sự cố.
  * **Event-Driven Metric Ingestion (Xử lý telemetry tải lớn)**: Để giải quyết bài toán telemetry tần suất cao (peak lên tới 50k events/sec), hệ thống sử dụng Kinesis Data Streams / SQS trực tiếp tích hợp từ API Gateway (Service Integration - bỏ qua Lambda trung gian khi ingest để tiết kiệm chi phí invocation tối đa), kết hợp client-side batching từ load generator k6.
  * **Ops-Light (Giảm tải vận hành)**: Onboarding dựa trên GitOps/Config-driven thay vì tự động hoá SaaS quá phức tạp, giúp triển khai nhanh, an toàn và tái lập dễ dàng.
* **Trade-off chấp nhận**:
  * **Cold Start Latency**: Các yêu cầu API dự đoán `/v1/predict` đầu tiên sau thời gian rảnh có thể chịu độ trễ cold start cao hơn bình thường (lên đến 1-2 giây). Tuy nhiên, đối với bài toán dự đoán tải trước 15-90 phút, độ trễ cold start vài giây ở các request đầu là hoàn toàn chấp nhận được.
* **Locked Date**: **T3 W11** (Cam kết hoàn thành thiết kế hạ tầng và đóng băng thông số hợp đồng).

---

## 4. Comparison với 2 nhóm cùng Task Force

| Aspect | My Angle (Serverless-First & Time-Series DB) | Nhóm khác A (K8s-Heavy - EKS + Prometheus) | Nhóm khác B (Managed Services - ECS + Datadog/CloudWatch) |
| :--- | :--- | :--- | :--- |
| **Compute Pattern** | AWS Lambda + API Gateway (Scale-to-zero) | Amazon EKS (Kubernetes managed nodes) | AWS ECS Fargate (Serverless container instances) |
| **Storage** | Amazon Timestream (Time-series optimized) | Self-hosted Prometheus on EKS (EBS backend) | Managed Prometheus (AMP) / CloudWatch Metrics |
| **Cost Profile** | **Cực thấp khi rảnh rỗi ($0 fixed cost)**, thanh toán thuần theo mức độ sử dụng thực tế. | **Cao cố định** (~$73/tháng cho EKS control plane + chi phí EC2 nodes tối thiểu). | **Trung bình** (Chi phí Fargate cố định theo số lượng containers chạy nền). |
| **Ops Complexity** | **Thấp nhất** (AWS quản lý hạ tầng hoàn toàn, chỉ quản lý code Lambda & DB schema). | **Rất cao** (Quản trị cụm K8s, Helm chart, Ingress controller, PV/PVC, node groups). | **Trung bình** (Cấu hình ECS task definition, service scaling, và IAM policies). |
| **Latency Profile** | Có nguy cơ cold start ở các request đầu, nhưng p99 latency ổn định khi ở trạng thái warm. | Latency cực kỳ ổn định và thấp nhờ container luôn trực chiến. | Latency ổn định, không chịu ảnh hưởng của cold start như Lambda. |
| **Win Axis** | **Tối ưu hóa chi phí tuyệt đối (Cost), Tự động co giãn (Scale) & Độ tin cậy vận hành (Operational Trust)**. | Khả năng di động mã nguồn (Portability) & Hệ sinh thái K8s phong phú. | Cân bằng giữa tính sẵn sàng cao và mức độ tự động hóa quản lý hạ tầng. |

---

## 5. Constraints
* **Cloud Provider**: Chỉ sử dụng hạ tầng AWS (AWS Only), không triển khai Multi-Cloud.
* **AWS Region**: Deploy tập trung tại một Region chính (ví dụ: `ap-southeast-1` - Singapore) để giảm thiểu latency truyền dữ liệu.
* **Budget**: Hạn mức ngân sách kiểm thử tối đa \$200 cho 2 tuần chạy thật và demo.
* **Code Freeze**: Thứ Tư Tuần 12 lúc 18h00.

---

## 6. Open Questions
1. **Q1 (Tích hợp AI Engine)**: Liệu Lambda function làm nhiệm vụ model serving có bị giới hạn dung lượng bộ nhớ (10GB) hoặc thời gian chạy (15 phút) khi thực hiện baseline training quy mô lớn hay không? Nếu có, có cần chuyển luồng Train sang AWS Batch / Step Functions hay không?
2. **Q2 (Telemetry Volume)**: Khi mô phỏng tải 50k events/sec trong 2 giờ chạy test scenario, chi phí ingest và storage của Amazon Timestream sẽ tăng vọt như thế nào? Cần thiết kế chiến lược nén dữ liệu hoặc gộp batch (micro-batching) từ phía client giả lập để tối ưu chi phí như thế nào?

