# CDO08 — Event Trigger Security Input
**Task Force 4 · CDO08**
**Scope:** EventBridge Scheduler → Prediction Lambda → AI endpoint + Fallback Lambda

> **Status:** Draft (W11) — Chờ PM review & AI API/Deployment Contract xác nhận TLS/auth.
> **Last updated:** 2026-06-24
> **Liên quan:** Merge vào `docs/03_security_design.md` sau khi PM tag/approve.

---

## Vị trí trong kiến trúc (Placement Rationale)

Trigger tự động nằm trong layer **Model Training & Lifecycle** của `02_infra_design.md` (phần `ModelTraining` subgraph), nhưng **tách biệt với luồng training hàng tuần** — đây là một scheduler riêng gọi Prediction Lambda theo lịch định kỳ (ví dụ: mỗi 15 phút) để tạo rolling baseline prediction. Vị trí gợi ý trong kiến trúc:

```
EventBridge Scheduler (CDO08)
  └──► SQS Scheduler Queue (buffer + DLQ)
         └──► Lambda Prediction (scheduled)
                ├──► Amazon Managed Prometheus (AMP) — query lookback metrics
                ├──► AI Endpoint (ECS Fargate / external API)
                ├──► DynamoDB Audit Logs — ghi kết quả + idempotency key
                └──► Grafana Annotation — (nếu score vượt threshold)
                       [Fallback path nếu AI timeout/429/503]
                └──► Lambda Fallback Evaluator
                       └──► Grafana Annotation tagged [Fallback]
```

> **Ghi chú vị trí file:** Thêm subgraph `ScheduledPrediction` vào `02_infra_design.md §1` và mở rộng bảo mật tại `03_security_design.md §4-§6`.

---

## 1. IAM Boundaries

### 1.1 EventBridge Scheduler Role (`role/cdo08-scheduler-invoke`)

| Permission | Resource | Ghi chú |
| :--- | :--- | :--- |
| `lambda:InvokeFunction` | ARN của **Prediction Lambda** (duy nhất) | Không có quyền invoke bất kỳ Lambda nào khác |
| Không có quyền | DynamoDB, S3, SQS | Scheduler không được phép đọc/ghi dữ liệu trực tiếp |

**Trust Policy:** Chỉ tin tưởng `scheduler.amazonaws.com` với điều kiện `aws:SourceAccount` khớp với account ID của dự án.

```json
{
  "Effect": "Allow",
  "Principal": { "Service": "scheduler.amazonaws.com" },
  "Action": "sts:AssumeRole",
  "Condition": {
    "StringEquals": { "aws:SourceAccount": "<ACCOUNT_ID>" }
  }
}
```

---

### 1.2 Prediction Lambda Role (`role/cdo08-prediction-lambda`)

| Permission | Resource | Ghi chú |
| :--- | :--- | :--- |
| `aps:QueryMetrics` | AMP Workspace ARN | Query lookback metrics (chỉ read) |
| `dynamodb:PutItem`, `dynamodb:GetItem` | Table `PredictionAuditLog` | Ghi audit + check idempotency key |
| `dynamodb:GetItem` | Table `TenantMetadata` | Đọc static threshold cấu hình sẵn |
| `kms:GenerateDataKey`, `kms:Decrypt` | KMS key CMK audit log | Mã hóa audit log at rest |
| `secretsmanager:GetSecretValue` | Secret ARN của AI API credential | Chỉ đọc credential AI (không có quyền update) |
| `sqs:SendMessage` | ARN của **Lambda on-failure DLQ** | Để Lambda runtime gửi execution failure event |
| `cloudwatch:PutMetricData` | Namespace `CDO08/Prediction` | Emit custom metric cho circuit breaker monitor |

**Không được phép:** invoke Lambda Fallback trực tiếp (Fallback được kích hoạt bởi logic trong Prediction Lambda code hoặc EventBridge rule on-failure), không có quyền ghi S3 model registry, không có quyền gọi API Gateway public.

---

### 1.3 Fallback Lambda Role (`role/cdo08-fallback-lambda`)

| Permission | Resource | Ghi chú |
| :--- | :--- | :--- |
| `aps:QueryMetrics` | AMP Workspace ARN | Query metric history cho threshold evaluation (Timestream đã bị loại khỏi account, xem `02_infra_design.md §5.5`) |
| `dynamodb:GetItem` | Table `TenantMetadata` (Static Thresholds) | Đọc ngưỡng tĩnh |
| `dynamodb:PutItem` | Table `PredictionAuditLog` | Ghi audit log [Fallback] |
| `kms:GenerateDataKey`, `kms:Decrypt` | KMS key CMK audit log | Mã hóa fallback audit log |
| `cloudwatch:PutMetricData` | Namespace `CDO08/Fallback` | Emit metric fallback activation rate |

**Không được phép:** gọi AI endpoint, gọi Scheduler, ghi S3.

---

### 1.4 AI Credential Access (Secret Manager Pattern)

```
AI API Key/Token
  └── AWS Secrets Manager (Secret: cdo08/ai-endpoint-credential)
        ├── Rotation: Manual (chờ AI API contract xác nhận rotation policy)
        ├── KMS Encryption: CMK (cdo08-secrets-cmk)
        └── Resource Policy: Chỉ cho phép role/cdo08-prediction-lambda GetSecretValue
```

> ⚠️ **Ranh giới quan trọng:** Fallback Lambda **không** được phép đọc AI credential — fallback chỉ dùng static threshold, không gọi AI.

---

## 2. Scheduler DLQ vs Lambda Execution Failure — Phân biệt rõ 2 loại

Đây là điểm **dễ nhầm lẫn nhất** trong thiết kế trigger tự động:

| Khía cạnh | EventBridge Scheduler DLQ | Lambda Execution on-failure / DLQ |
| :--- | :--- | :--- |
| **Trigger khi nào** | Scheduler **không thể invoke** được Lambda (ví dụ: Lambda ARN sai, thiếu permission, throttle invoke-level) | Lambda **đã được invoke** nhưng **function execution thất bại** (exception, timeout, OOM) |
| **Ai ghi event vào DLQ** | EventBridge Scheduler service (không phải Lambda runtime) | Lambda runtime hoặc SQS trigger |
| **DLQ nhận gì** | Payload gốc từ Scheduler (`tenant_id`, `service_id`, `lookback_minutes`, `scheduled_at`) + error metadata của Scheduler | Lambda execution failure event + partial context |
| **DLQ target** | SQS Queue `cdo08-scheduler-dlq` (cấu hình trong Scheduler group) | SQS Queue `cdo08-prediction-execution-dlq` (cấu hình trong Lambda event source mapping hoặc Lambda destination) |
| **Ai xử lý** | Ops team alert + replay thủ công / automation | Circuit Breaker logic → Fallback Lambda kích hoạt |
| **Giám sát** | CloudWatch Alarm `cdo08-scheduler-dlq-depth > 0` | CloudWatch Alarm `Lambda Errors + Throttles metric` |

### Tóm tắt luồng phân kỳ:

```
EventBridge Scheduler
  │
  ├── [Invoke OK] ──────────────────► Prediction Lambda executes
  │                                        ├── [Success] → ghi audit, annotation
  │                                        └── [Failure/Timeout] → Lambda on-failure path
  │                                                  └── [SQS on-failure DLQ] → Fallback Lambda
  │
  └── [Invoke FAIL — throttle/ARN error] ──► EventBridge Scheduler DLQ (SQS)
                                                └── Ops alert → manual investigation
```

---

## 3. Idempotency Key, Retry Limit & Audit Handling

### 3.1 Idempotency Key Design

**Key pattern:** `{tenant_id}#{service_id}#{scheduled_at_epoch_truncated_to_window}`

Ví dụ: `tenant-uuid-abc#payment-api#1750730400` (truncate về bội số 15 phút để tránh drift)

**Cơ chế kiểm tra:**
1. Khi Prediction Lambda bắt đầu, nó **GetItem** từ DynamoDB table `PredictionAuditLog` với idempotency key.
2. Nếu item **đã tồn tại** với `status = COMPLETED` hoặc `status = PENDING` (trong vòng TTL an toàn, ví dụ: 30 phút) → **return sớm, không tạo prediction mới**, log `SKIPPED_DUPLICATE`.
3. Nếu **chưa tồn tại** → PutItem với `status = PENDING`, `ttl = now + 30 phút` → thực hiện prediction → update `status = COMPLETED` hoặc `status = FAILED`.

**DynamoDB conditional write:**
```python
table.put_item(
    Item={"pk": idempotency_key, "status": "PENDING", "ttl": now + 1800},
    ConditionExpression="attribute_not_exists(pk)"
)
# Nếu raise ConditionalCheckFailedException → return SKIPPED_DUPLICATE
```

### 3.2 Retry Limit

| Retry Layer | Config | Ghi chú |
| :--- | :--- | :--- |
| **EventBridge Scheduler** | `MaxRetryAttempts = 2`, `MaxEventAgeSeconds = 600` | Sau 2 lần retry invoke thất bại, event vào Scheduler DLQ |
| **Prediction Lambda (AI call)** | Max 2 retries với exponential backoff (1s → 2s), timeout per attempt 8s | Tổng tối đa ~21s trước khi chuyển sang Fallback path |
| **Lambda Fallback** | 0 retry (fail-open: nếu fallback cũng fail, chỉ log ERROR, không tạo annotation) | Tránh cascade failure làm nghẽn queue |

### 3.3 Audit Handling — Chống duplicate annotation/prediction

**Rule:** Một annotation trên Grafana chỉ được tạo khi:
- `prediction_run_id` (UUID v4, sinh tại Prediction Lambda) chưa xuất hiện trong DynamoDB trong window hiện tại, **VÀ**
- `idempotency_key` không ở trạng thái `COMPLETED`.

**Audit record schema** (DynamoDB `PredictionAuditLog`):

```json
{
  "pk": "{tenant_id}#{service_id}#{window_epoch}",
  "prediction_run_id": "uuid-v4",
  "scheduled_at": "ISO8601",
  "executed_at": "ISO8601",
  "status": "PENDING | COMPLETED | FAILED | SKIPPED_DUPLICATE",
  "source": "AI | FALLBACK",
  "ai_endpoint_version": "v1.2",
  "lookback_minutes": 120,
  "result_summary": "...",
  "annotation_created": true,
  "ttl": 1750734000,
  "kms_encrypted": true
}
```

**TTL:** 90 ngày (consistent với audit log hiện tại trong `02_infra_design.md`).

---

## 4. TLS / Auth Requirements (Chờ AI API/Deployment Contract)

> **Trạng thái:** Các mục dưới đây là yêu cầu **tối thiểu đề xuất** — cần AI API team xác nhận tại Deployment Contract meeting trước khi finalize.

| Yêu cầu | Đề xuất | Chờ xác nhận |
| :--- | :--- | :--- |
| **TLS version** | TLS 1.2 tối thiểu, TLS 1.3 preferred | AI endpoint có enforce TLS 1.3 không? |
| **Auth scheme** | Bearer token (JWT) hoặc API Key qua `Authorization` header | AI team dùng OAuth2 client credentials, API Key, hay mTLS? |
| **Token rotation** | Rotation 90 ngày tối thiểu (hoặc theo AI team policy) | AI team có cung cấp rotation API/webhook không? |
| **Credential storage** | AWS Secrets Manager `cdo08/ai-endpoint-credential` với CMK | AI team có yêu cầu IP allowlist hay VPC endpoint không? |
| **Request signing** | AWS SigV4 (nếu AI endpoint là AWS-native) hoặc HMAC (nếu external) | Cần AI team xác nhận endpoint type |
| **mTLS (optional)** | Không bắt buộc ở giai đoạn đầu, nhưng recommended nếu AI endpoint chạy trong VPC riêng | AI team có issue client cert không? |
| **Timeout & circuit breaker** | Prediction Lambda: 8s per call, 2 retries; circuit breaker open sau 3 consecutive 429/503/timeout | AI team có SLA latency p99 bao nhiêu? |

---

## 5. PM Review Checklist (Definition of Done)

> PM cần tag vào mục này sau khi review. Khi tất cả checkbox được tick, nội dung được merge vào `docs/03_security_design.md`.

- [ ] **Jira link đính kèm:** Google Docs link đã được đính kèm vào Jira ticket CDO08; PM có quyền xem (`View` permission).
- [ ] **IAM boundaries xác nhận:** PM review và đồng ý với IAM role scope của §1.1, §1.2, §1.3 (đặc biệt là AI credential chỉ Prediction Lambda được đọc).
- [ ] **Scheduler DLQ vs Lambda failure phân biệt rõ:** PM hiểu sự khác nhau giữa Scheduler DLQ (§2) và Lambda execution on-failure path; diagram luồng phân kỳ được approve.
- [ ] **Idempotency & retry policy xác nhận:** PM đồng ý với idempotency key pattern, retry limit (§3.2) và audit record schema (§3.3) để tránh duplicate annotation/prediction.
- [ ] **TLS/auth chờ AI contract:** PM đã tag AI API team vào §4; deadline xác nhận TLS/auth requirement được ghi nhận trong Jira.
- [ ] **PM tag/link để merge:** PM được tag vào PR merge nội dung này vào `docs/03_security_design.md`; link PR/branch được ghi rõ trong Jira comment.

---

## 6. Open Questions

| # | Câu hỏi | Cần trả lời từ | Deadline gợi ý |
| :--- | :--- | :--- | :--- |
| Q1 | AI endpoint enforce TLS 1.2 hay 1.3? Có yêu cầu mTLS không? | AI API team | Trước Code Freeze T3 W12 |
| Q2 | AI team auth scheme là gì? Bearer JWT / API Key / OAuth2 client credentials? | AI API team | Trước Code Freeze T3 W12 |
| Q3 | Token rotation policy của AI credential là bao lâu? Có API rotation hook không? | AI API team | Trước Code Freeze T3 W12 |
| Q4 | AI endpoint có SLA latency p99 chính thức không? (để calibrate 8s timeout trong §3.2) | AI API team / Deployment Contract | Trước Code Freeze T3 W12 |
| Q5 | PM xác nhận: Scheduler chạy mỗi bao nhiêu phút? (ảnh hưởng đến idempotency window size trong §3.1) | PM | Trong sprint hiện tại |
| Q6 | Fallback Lambda có cần tạo Grafana annotation không, hay chỉ log CloudWatch? | PM / SRE | Trong sprint hiện tại |

---

## 7. Related Documents

- [`02_infra_design.md`](./02_infra_design.md) — Architecture diagram & component table (thêm subgraph `ScheduledPrediction` tại §1)
- `docs/03_security_design.md` — Đích merge cuối cùng của tài liệu này
- `01_requirements_analysis.md` — NFR: IAM least-privilege + KMS + CloudTrail audit (§2)
- `08_adrs.md` — ADR liên quan: lý do chọn Secrets Manager thay vì env variable cho AI credential
