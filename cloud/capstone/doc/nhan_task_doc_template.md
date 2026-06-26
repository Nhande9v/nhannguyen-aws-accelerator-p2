# Nhan Task Doc Template

## 1. Requirement

- Mô tả phần việc: xây dựng AI Integration Adapter, đảm bảo fail-open static threshold và bảo mật cho EventBridge Scheduler.
- Requirement chính:
  - EventBridge Scheduler chỉ trigger prediction; không quyết định telemetry data point interval.
  - Prediction Lambda phải query AMP với window ≥120 phút để build `signal_window`.
  - Prediction Lambda gọi `POST /v1/predict` và xử lý lỗi 400/401/429/503.
  - Khi AI timeout/429/503/exhausted retry, hệ thống phải chuyển sang fail-open static threshold.
- Mục tiêu: người đọc PM/TL hiểu rõ requirement, current design, alternatives, recommendation, security, observability/evidence và cost impact.

## 2. Current Design

### 2.1 Kiến trúc tổng quan

- `EventBridge Scheduler` chạy theo lịch đã định và gửi payload prediction đến `Prediction Integration Lambda`.
- Scheduler chỉ chịu trách nhiệm trigger prediction, không chịu trách nhiệm điều chỉnh tần suất hoặc interval của dữ liệu telemetry.
- `Prediction Lambda` query AMP bằng PromQL trong window tối thiểu 120 phút, xây dựng `signal_window` từ kết quả query.
- Lambda gọi AI endpoint `POST /v1/predict` với payload chứa `signal_window`, `tenant_id`, `service_id`, và metadata.
- Nếu AI trả về thành công, Lambda tạo Grafana annotation và ghi audit record.
- Nếu AI timeout, nhận lỗi 429/503 hoặc đã hết retry budget, Lambda kích hoạt `Fallback evaluator Lambda` sử dụng static threshold và tạo annotation/fallback audit.

### 2.2 Luồng dữ liệu prediction

1. Scheduler invoke Prediction Lambda với payload: `tenant_id`, `service_id`, `lookback_minutes`, `scheduled_at`, `idempotency_key`.
2. Prediction Lambda xác thực payload và use-case.
3. Lambda query AMP bằng PromQL để lấy telemetry window `>= 120 phút`.
4. Lambda build `signal_window` (chuỗi số liệu thời gian đã chuẩn hóa theo service/tenant) và gửi lên `/v1/predict`.
5. Lambda xử lý response AI:
   - 200 OK → ghi annotation + audit.
   - 400 Bad Request / 401 Unauthorized → fail fast, audit error; không retry nhiều.
   - 429 Too Many Requests / 503 Service Unavailable → retry budget hạn chế, sau đó fail-open static threshold.
   - timeout → chuyển sang fallback.
6. Nếu fallback, `Fallback evaluator Lambda` query AMP gần nhất, dùng static threshold đúng service và tạo annotation/fallback audit.

## 3. Alternatives Considered

### 3.1 SQS-trigger prediction

- Luồng: telemetry event vào SQS, trigger Prediction Lambda trực tiếp từ SQS.
- Ưu điểm:
  - Gần real-time prediction.
  - Loại bỏ scheduler external.
- Nhược điểm:
  - Prediction rate bị ràng buộc theo ingest rate.
  - Dễ gây overload AI khi telemetry burst.
  - Khó kiểm soát cadence và cost.
- Kết luận: không phù hợp vì requirement cần tách rõ prediction cadence khỏi telemetry ingestion.

### 3.2 ECS integration service

- Luồng: chạy service trên ECS/Fargate để gọi AI, giữ connection pooling.
- Ưu điểm:
  - Thích hợp cho QPS cao, giữ kết nối lâu dài.
  - Deployment deployable theo container image.
- Nhược điểm:
  - Always-on cost và vận hành service.
  - Không phải ưu tiên cho capstone nếu prediction cadence chỉ ổn định.
- Kết luận: phù hợp nếu AI QPS lớn, nhưng hiện tại Lambda adapter giữ scope nhẹ hơn và dễ kiểm thử.

### 3.3 Step Functions orchestration

- Luồng: orchestrate query AMP → call AI → fallback logic.
- Ưu điểm:
  - Visual workflow, retry/state đầy đủ.
  - Dễ follow trạng thái lỗi.
- Nhược điểm:
  - Thêm chi phí Step Functions.
  - Tăng độ phức tạp cho flow đơn giản.
  - Không cần thiết khi Lambda đã đủ xử lý logic retry/fallback.
- Kết luận: không chọn cho capstone; có thể cân nhắc nếu cần audit workflow hoặc phức tạp hơn.

## 4. Recommendation

- Giữ `EventBridge Scheduler` để trigger prediction theo cadence, không dùng nó để quyết định telemetry interval.
- Dùng `Prediction Lambda` để thực hiện toàn bộ logic query AMP, xây dựng `signal_window`, gọi `/v1/predict` và xử lý lỗi.
- Dùng `Fallback evaluator Lambda` cho fail-open khi AI timeout/429/503/exhausted retry.
- Đặt `lookback window >= 120 phút` để đảm bảo dữ liệu đủ dày cho prediction model và giảm sai số do short-term noise.
- Dùng idempotency key (`service_id + scheduled_at`) để tránh duplicate annotation khi Lambda retry hoặc Scheduler invoke lại.

## 5. Security

### 5.1 Scheduler role

- Scheduler chỉ có quyền invoke `Prediction Integration Lambda`.
- Scheduler không có quyền đọc AMP, DynamoDB hay Secrets Manager.
- Scheduler không cần DLQ: if invoke fails, Lambda on-failure destination hoặc alarm giải quyết.

### 5.2 Prediction/Fallback IAM

- `Prediction Lambda` cần quyền:
  - query AMP workspace
  - read Secrets Manager for AI endpoint/token
  - write Grafana annotation
  - write DynamoDB audit record
- `Fallback Lambda` cần quyền:
  - query AMP
  - read static threshold config
  - write Grafana annotation
  - write DynamoDB audit record
- Cả hai Lambda không cần quyền ghi vào SQS ingest queue.

### 5.3 SigV4

- Khi Lambda gọi AMP hoặc annotation API, sử dụng SigV4 signing theo AWS best practice.
- Nếu gọi external AI endpoint, dùng HTTPS với token lưu trong Secrets Manager.

### 5.4 Idempotency key

- Prediction Lambda sử dụng `service_id + scheduled_at` làm idempotency key.
- Key này được dùng để kiểm tra duplicate annotation/audit trong DynamoDB trước khi ghi.
- Mục tiêu: không tạo duplicate annotation nếu Lambda retry hoặc Scheduler invoke nhiều lần.

### 5.5 No Scheduler DLQ

- Scheduler không cần trực tiếp DLQ cho payload prediction.
- Nếu invoke target fail, thiết kế alarm/retry ở Lambda/CloudWatch hoặc on-failure destination để giữ evidence.
- Ưu điểm: giảm complexity và tránh cache duplicate trigger từ DLQ replay.

## 6. Observability / Evidence

- Log `scheduled_at`, `service_id`, `tenant_id`, `idempotency_key`, `signal_window` size và AI response status.
- Metric/Alarm:
  - `PredictionLambdaDuration`
  - `PredictionLambdaErrors`
  - `PredictionFallbackCount`
  - `AIPredict429`
  - `AIPredict503`
- Audit record:
  - `prediction_id`
  - `correlation_id`
  - `service_id`
  - `tenant_id`
  - `scheduled_at`
  - `mode`: `ai` or `fallback`
  - `status`
- Grafana annotation labels:
  - `service_id`
  - `tenant_id`
  - `mode`
  - `fallback=true` khi fail-open.

## 7. Cost Impact

- Lambda: pay-per-invocation, chỉ chạy theo schedule 3 lần/5 phút cho 3 service.
- EventBridge Scheduler: very low cost, few scheduled invocations per day.
- AMP query: cost thêm query volume, nhưng query frequency nhỏ.
- Grafana annotation: small usage cost.
- Alternatives cost trade-offs:
  - SQS-trigger prediction: giảm scheduler cost nhưng tăng AI call volume và khó kiểm soát cost.
  - ECS service: tăng always-on compute cost.
  - Step Functions: tăng orchestration cost.

## 8. W12 Test / Evidence Proposal

- AI success case:
  - Scheduler invoked Prediction Lambda.
  - Prediction Lambda query AMP `>= 120 phút` và build `signal_window`.
  - AI returns 200 and annotation + audit record are created.
- AI 503 fallback case:
  - Simulate AI endpoint returning 503.
  - Ensure Prediction Lambda exhausts retry budget and calls fallback static threshold.
  - Fallback annotation/audit record created with `fallback=true`.
- Duplicate invoke / idempotency case:
  - Force Scheduler or Lambda retry to invoke same `service_id + scheduled_at` twice.
  - Verify no duplicate Grafana annotation and only one audit record for the same idempotency key.
- Fallback annotation/audit case:
  - Validate the fallback path writes the same evidence fields and distinct `mode=fallback`.

## 9. Notes

- EventBridge Scheduler chỉ tạo trigger, không phải data interval controller.
- `signal_window` cần đủ dài để prediction không chỉ dựa vào các điểm dữ liệu rất gần.
- Fail-open static threshold là hard requirement khi AI dependency bị lỗi.
- Scheduler security phải giảm quyền tới mức tối thiểu.
- Document này được dùng làm file riêng trong capstone để team hiểu rõ phần Nhan làm và phục vụ merge nội dung vào docs chính nếu cần.
