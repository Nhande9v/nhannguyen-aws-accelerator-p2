Application
     |
     | (Metrics + Logs)
     v
OpenTelemetry Collector
     |----------------> Prometheus (Metrics)
     |
     +----------------> Loki (Logs)
                              |
                              v
                         Grafana

# 1. Vai trò của từng thành phần
OpenTelemetry Protocol (OTLP)
## 1.1 OpenTelemetry Collector (OTel Collector)
- Đây là trạm trung chuyển dữ liệu
Thay vì gửi nhìu nơi
App --> Prometheus
App --> Loki
App --> Jaeger
thì chỉ cần
App --> OTel Collector
Collector sẽ tự phân phối dữ liệu đi.
## 1.2 Prometheus
- Lưu trữ metrics
## 1.3 Loki
- Lưu trữ logs
## 1.4 Grafana
- Dashboard để xem dữ liệu
Grafana không lưu metric hay log
- Nó chỉ đọc:
Đọc dữ liệu từ Prometheus
Đọc dữ liệu từ Loki
Hiển thị Dashboard

# 2. Luồng metrics
App
 |
 | OTLP
 v
OTel Collector
 |
 | Export
 v
Prometheus Exporter (:8889)
 |
 | Pull
 v
Prometheus
 |
 v
Grafana

- Prometheus hoạt động theo cơ chế:
Prometheus đi lấy dữ liệu

scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8889']
Prometheus sang otel-collector:8889 để lấy metrics
# 3. Luồng logs
App
 |
 | OTLP
 v
OTel Collector
 |
 v
Loki
 |
 v
Grafana

otlp/loki:
  endpoint: "http://loki:3100/otlp"
Collector gửi log sang Loki

Receiver là:
Cổng nhận dữ liệu

# 4. Service Pipeline
YAML: 
service:
  pipelines:
- Nhận dữ liệu từ đâu Xử lý thế nào Gửi đi đâu
Pipeline Metrics
metrics:
  receivers: [otlp]
  processors: [batch]
  exporters: [prometheus]

Pipeline Logs
logs:
  receivers: [otlp]
  processors: [batch]
  exporters: [otlp/loki]

# Chạy dự án
B1: docker compose up -d
B2: Kiểm tra xem các container đã chạy ổn định chưa bằng lệnh:
docker compose ps

# Tích hợp OpenTelemetry SDK vào Ứng dụng để bắt đầu đẩy Metric & Log lên
B1: cài đặt thư viện
npm install @opentelemetry/sdk-node \
            @opentelemetry/auto-instrumentations-node \
            @opentelemetry/exporter-otlp-grpc
Làm dự án trở thành nhà máy sản xuất dữ liệu giám sát
B2: cài npm install express
B3:  Tạo file instrumentation.js
B4: tạo app.js
File này tạo ra 3 endpoint tương ứng với 3 kịch bản: Thành công, Bị lỗi 500, và Chạy chậm (Latency > 500ms).
B5: node -r ./instrumentation.js app.js
B6 : docker logs otel-collector : xem log
### để làm dự án trên thì cần
docker-compose up trước và nó lấy 2 dữ liệu của file
otel-config.yaml cung cấp cái gì? Nó mở sẵn cổng 4317 (gRPC) và giữ cổng 8889 (Prometheus metrics port). Nó cũng lấy luôn tên service loki:3100 từ Docker Compose làm đích đến để sẵn sàng đẩy Log đi.
prometheus.yml lấy cái gì để chạy? Nó lấy cái target ['otel-collector:8889'] (địa chỉ do OTel Collector mở ra ở trên) để biết đường cứ 15 giây lại mò sang đó kéo dữ liệu về


## Phần đã làm đc
# OTel SDK + Collector:

Đã cấu hình thành công instrumentation.js để đẩy metric và log từ ứng dụng Node.js sang Collector thông qua giao thức OTLP.

Đã thiết lập otel-config.yaml với pipeline cho cả Metrics (sang Prometheus) và Logs (sang Loki).

Đã xác nhận Collector chạy ổn định và nhận được dữ liệu (logs Everything is ready và trang /metrics đã hiển thị dữ liệu).

# Prometheus + Grafana + Loki:

Prometheus đã kết nối thành công và scrape được dữ liệu từ Collector (trạng thái UP xanh).

Grafana đã truy vấn được dữ liệu từ Prometheus và hiển thị biểu đồ thành công.

Pipeline cho Loki đã được khai báo trong Collector, sẵn sàng để tiếp nhận logs.

# SLO Methodology (Availability + Latency):

Bạn đã có các endpoint mô phỏng (/api/success, /api/error, /api/slow) để đo đạc các chỉ số này.

Hệ thống đã có khả năng ghi nhận dữ liệu thực tế cho các metric này.
hệ thống nâng cao sử dụng Burn Rate dựa trên phương pháp SLO
SLI là gì?
•	Service Level Indicator. 
•	Chỉ số đo chất lượng dịch vụ. 
SLO là gì?
•	Service Level Objective. 
•	Mục tiêu mong muốn của SLI. 

SLI (Service Level Indicator): Là con số thực tế đang đo được (ví dụ: hiện tại hệ thống uptime 99.98%).
SLO (Service Level Objective): Là ngưỡng mục tiêu mà nhóm bạn đặt ra (ví dụ: chúng ta phải đạt 99.95%).
SLA (Service Level Agreement): Là cam kết tối thiểu với khách hàng (ví dụ: khách hàng chấp nhận mức 99.9%).

## Montoring và observaiblibity
Montoring : CPU cao không, Pod có restart ko, hệ thông có chạy ko
Observability: Tại sao hệ thống bị lỗi, service nào gây lỗi, lỗi xảy ra ở đâu
