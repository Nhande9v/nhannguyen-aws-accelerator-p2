# Giải thích chi tiết kiến trúc — Task Force 4 · CDO Group 1

---

## 1. Lambda Serving Adapter — Wrapper Pattern kết hợp ECS Fargate AI Engine

**Lambda Serving Adapter** đóng vai trò **boundary wrapper** (ranh giới bảo vệ) đứng trước **AI Serving Engine chạy trên ECS Fargate**. Đây là một trong những thiết kế trọng tâm của kiến trúc, giải quyết đồng thời ba vấn đề: cô lập API contract, triệt tiêu rủi ro runtime, và đảm bảo bảo mật sâu.

### Lý do lựa chọn & Cơ chế hoạt động

**1. Cô lập API Contract**

Lý do chọn: Trong phát triển hệ thống, các mô hình AI thường xuyên được cập nhật, tinh chỉnh (fine-tune) hoặc thay đổi hoàn toàn kiến trúc thuật toán (ví dụ: chuyển từ mô hình thống kê cũ sang các mô hình học máy hiện đại). Nếu để Client gọi trực tiếp vào AI Engine, mỗi lần thay đổi code AI hoặc cấu trúc dữ liệu đầu vào, phía Client (Grafana Dashboard) sẽ bị vỡ cấu trúc hiển thị (Break Contract).

**2. Triệt tiêu rủi ro Cold Start & Timeout**

Các mô hình AI và thư viện inference nặng (numpy, pandas, scikit-learn) mất nhiều thời gian khởi động và tải baseline weights từ S3. Nếu chạy thuần Lambda sẽ bị **Cold Start lên đến vài giây** và nguy cơ sập do giới hạn **15 phút runtime**. Việc đẩy lõi tính toán sang **ECS Fargate** (container trực chiến, không có cold start sau khi khởi động) giúp đảm bảo **P99 Latency < 100ms** ổn định trong suốt phiên test/demo.

**3. Bảo mật & Audit chuyên sâu**

Trước khi gọi ECS Fargate, Lambda Adapter thực hiện:
- Xác thực quyền qua **IAM Role** (least-privilege — chỉ Adapter mới có quyền invoke AI Engine)
- Ghi **nhật ký gọi được mã hóa KMS** vào **DynamoDB Audit Logs** kèm `correlation_id`, `tenant_id`, `timestamp`, và kết quả trả về

Audit log này phục vụ công tác **hậu kiểm (post-mortem)** và đảm bảo tính truy vết E2E (End-to-End Traceability).

### Luồng xử lý

```
POST /v1/predict
      │
      ▼
[Lambda Serving Adapter]
  ├─ IAM Auth check
  ├─ Call ECS Fargate AI Engine (HTTP internal)
  │      └─ Query Timestream (historical metrics)
  │      └─ Load baseline weights from S3
  │      └─ Return: actionable recommendation
  ├─ Write KMS-encrypted Audit Log → DynamoDB
  └─ Return recommendation to Grafana
```

---

## 2. Lambda Fallback Evaluator — Circuit Breaker Pattern (Ngắt Mạch Tự Động)

**Lambda Fallback Evaluator** hoạt động **hoàn toàn độc lập** với luồng xử lý AI chính, được kích hoạt khi Circuit Breaker tại Lambda Adapter phát hiện AI Engine gặp sự cố. Đây là thành phần then chốt đảm bảo **tính liên tục của hệ thống giám sát** trong mọi tình huống.

### Lý do lựa chọn & Cơ chế hoạt động

**1. Đảm bảo tính liên tục của hệ thống (High Availability — Fail-Open)**

Trong môi trường Production hoặc Demo tải cao, nếu cụm AI Serving Engine gặp sự cố (Timeout, Lỗi 503, hoặc cạn kiệt Retry Budget), hệ thống **tuyệt đối không được phép "chết đứng" (Fail-Closed)** làm mất toàn bộ luồng giám sát. Thiết kế **Fail-Open** đảm bảo SRE luôn nhận được cảnh báo, dù là từ AI hay từ bộ lọc dự phòng.

**2. Cơ chế ngắt mạch tự động (Circuit Breaker)**

Lambda Adapter tích hợp **Circuit Breaker** theo dõi tỷ lệ lỗi từ AI Engine. Khi số lỗi liên tiếp vượt ngưỡng cấu hình (ví dụ: 3 lần timeout trong 30 giây), mạch chuyển sang trạng thái **Open**: toàn bộ request tiếp theo được định tuyến thẳng sang **Lambda Fallback Evaluator** mà không tốn thời gian chờ AI phản hồi, giữ cho hệ thống luôn phản hồi nhanh. Sau một khoảng thời gian cooldown, mạch thử chuyển sang **Half-Open** để kiểm tra xem AI Engine đã phục hồi chưa.

| Trạng thái mạch | Điều kiện | Hành vi |
| :--- | :--- | :--- |
| **Closed** (Bình thường) | Tỷ lệ lỗi < ngưỡng | Request đi vào AI Engine bình thường |
| **Open** (Ngắt mạch) | Lỗi liên tiếp vượt ngưỡng | Toàn bộ request route thẳng sang Fallback, không chờ AI |
| **Half-Open** (Thử nghiệm) | Sau cooldown period | Cho 1 request thử vào AI — nếu thành công → Closed; nếu lỗi → Open lại |

**3. Logic xử lý ngưỡng tĩnh (Static Threshold Evaluation)**

Lambda Fallback Evaluator khi được kích hoạt sẽ:
1. **Bỏ qua luồng AI** hoàn toàn
2. Trực tiếp **query dữ liệu metric lịch sử từ Amazon Timestream** bằng cú pháp SQL với filter `tenant_id` + `service_id`
3. **Đối chiếu số liệu với Static Thresholds** (CPU %, queue depth, connection count) được cấu hình sẵn trong DynamoDB
4. Đưa ra **khuyến nghị xử lý kịp thời** dựa trên ngưỡng cấu hình

**4. Trải nghiệm vận hành minh bạch (Operational Trust)**

Hệ thống vẫn tạo ra **annotation bình thường lên Grafana** để SRE không bị mất dấu vết hệ thống. Tuy nhiên, mọi cảnh báo từ luồng Fallback **bắt buộc phải gắn nhãn `[Fallback]`**. Điều này giúp SRE nhận biết ngay:

> *"Hệ thống AI đang gặp sự cố — cảnh báo này hiện đang chạy bằng bộ lọc ngưỡng tĩnh dự phòng."*

Tránh nhầm lẫn giữa kết quả dự đoán từ AI và kết quả đánh giá từ ngưỡng tĩnh.

### Luồng xử lý

```
[Lambda Serving Adapter]
  │
  ├─ (AI Engine OK — Circuit Breaker CLOSED) ──► ECS Fargate AI Engine
  │                                                      └─ Return AI Recommendation
  │
  └─ (Circuit Breaker OPEN / AI timeout / 503)
           │
           ▼
  [Lambda Fallback Evaluator]
    ├─ Query Timestream (metric history, filter by tenant_id + service_id)
    ├─ Load Static Thresholds from DynamoDB
    ├─ Evaluate: metric > threshold?
    └─ Push Grafana Annotation tagged [Fallback] + Recommendation
```

---

## Tóm tắt so sánh vai trò hai thành phần

| Thành phần | Vai trò chính | Kích hoạt khi | Output |
| :--- | :--- | :--- | :--- |
| **Lambda Serving Adapter** | Boundary Wrapper — cô lập API contract, audit, bảo mật | Mọi request `POST /v1/predict` | Gọi AI Engine → trả kết quả AI + ghi Audit Log |
| **Lambda Fallback Evaluator** | Circuit Breaker Fallback — dự phòng khi AI sập | Circuit Breaker chuyển sang trạng thái Open | Cảnh báo `[Fallback]` dựa trên Static Threshold lên Grafana |


# sài PULL hay PUSH Pipeline