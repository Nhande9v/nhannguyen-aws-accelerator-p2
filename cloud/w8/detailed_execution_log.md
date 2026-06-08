
## 1. TỔNG HỢP KIẾN THỨC ÔN TẬP (SELF-STUDY NOTES)

Phần này tóm tắt các khái niệm cốt lõi bạn đã tự học để phục vụ việc ôn tập nhanh.

### 1.1. Terraform & IaC (Infrastructure as Code)
- **IaC là gì?** Là việc quản lý hạ tầng bằng mã nguồn thay vì thao tác tay trên giao diện web. Giúp hạ tầng có khả năng: *Tái sử dụng (Reusability)*, *Định danh phiên bản (Versioning)* và *Độ chính xác cao*.
- **Ngôn ngữ HCL (HashiCorp Configuration Language):**
    - Là ngôn ngữ **Khai báo (Declarative)**: Bạn chỉ cần viết ra "Trạng thái mong muốn" (ví dụ: Tôi muốn 1 container Nginx), Terraform sẽ tự tìm cách thực hiện. Khác với ngôn ngữ *Mệnh lệnh (Imperative)* phải chỉ rõ từng bước `pull`, `run`.
    - Cấu trúc: `resource "loại_tài_nguyên" "tên_định_danh_local" { ... }`.
- **Terraform Workflow (Vòng đời cơ bản):**
    1.  **Init:** Khởi tạo thư mục, tải các Plugin (Provider) cần thiết (như Docker, AWS, Azure).
    2.  **Plan:** "Bản nháp" so sánh giữa code và hạ tầng thực tế. Cho bạn biết cái gì sẽ được *Thêm (+)*, *Sửa (~)*, hoặc *Xóa (-)*.
    3.  **Apply:** Thực thi các thay đổi đã lên kế hoạch.
    4.  **Destroy:** Thu hồi/Xóa bỏ toàn bộ hạ tầng đã tạo.

### 1.2. Kubernetes (K8s) - Hệ điều hành của Cloud
- **Pod:** Đơn vị nhỏ nhất mà K8s quản lý. Một Pod có thể chứa một hoặc nhiều container dùng chung mạng (IP) và ổ đĩa (Volume). 
    - *Tư duy:* Đừng coi Pod là một máy chủ ảo, hãy coi nó là một "tiến trình" đang chạy ứng dụng.
- **Service:** Là "biển chỉ dẫn" mạng. Vì Pod có thể bị xóa và tạo mới với IP khác, Service cung cấp một IP hoặc Port cố định để bên ngoài truy cập vào ứng dụng.
    - **NodePort:** Mở một cổng trên máy vật lý (Node) để truy cập từ ngoài vào (Ví dụ: 30080).
- **Probes (Cơ chế tự chữa lành):**
    - **Liveness Probe:** "Mày còn sống không?". Nếu không phản hồi, K8s sẽ giết và khởi tạo lại Pod.
    - **Readiness Probe:** "Mày đã sẵn sàng phục vụ chưa?". Nếu chưa (đang khởi động), K8s sẽ không cho traffic đi vào Pod này.
- **ConfigMap & Secret:**
    - **ConfigMap:** Lưu cấu hình không nhạy cảm (file config, environment variables).
    - **Secret:** Lưu thông tin nhạy cảm (mật khẩu, token). 
    - *Lưu ý:* Secret mặc định chỉ mã hóa Base64 (dễ giải mã), trong thực tế cần kết hợp với các công cụ như Vault hoặc KMS.
- **NetworkPolicy:** "Bức tường lửa" nội bộ. Nó định nghĩa Pod nào được phép nói chuyện với Pod nào. 
    - *Tư duy:* Mặc định trong K8s mọi thứ đều thông suốt, NetworkPolicy giúp chúng ta thực hiện nguyên tắc **Zero Trust**.

### 1.3. Công cụ hỗ trợ
- **Docker Desktop:** Cung cấp môi trường chạy container.
- **Minikube:** Giả lập một cụm Kubernetes (Cluster) nhỏ ngay trên laptop cá nhân.
- **Kubectl:** "Cây gậy điều khiển" - công cụ dòng lệnh để gửi yêu cầu tới Kubernetes API.

---
*Cập nhật lần cuối: Theo dõi tiến độ Lab Tuần 8.*
### 1.4 Những câu lệnh 
minikube start --driver=docker : Khởi động một cụm máy chủ Kubernetes mini ảo (Cluster) ngay trên laptop của bạn. Tham số --driver=docker ép nó tận dụng chính Docker Desktop làm nền tảng chạy ngầm cho tiết kiệm tài nguyên.
kubectl apply -f pod-service.yaml : Gửi toàn bộ file cấu hình YAML của bạn lên cho trung tâm điều khiển của K8s. Hệ thống sẽ đọc file và tạo ra đúng 3 thực thể: ConfigMap (chứa file HTML), Pod (chạy container Nginx), và Service (mở cổng mạng).
kubectl describe pod my-nginx-pod : In ra toàn bộ hồ sơ bệnh án chi tiết của cái Pod tên là my-nginx-pod: Trạng thái chạy (Running), tính năng tự sửa lỗi (Liveness Probe) hoạt động ra sao, ổ đĩa gắn vào thế nào, và nhật ký sự kiện (Events) lúc kéo image mất bao nhiêu giây.
minikube service nginx-service --url : Đục một đường ống kết nối (tunnel) từ môi trường máy ảo Minikube thông ra ngoài máy Windows thật của bạn và trả về một đường link URL (Ví dụ: http://127.0.0.1:30080).

### 1.5 Nhưng kiến thức cơ bản 
- resource (Tài nguyên): Nó dùng để khai báo bất kỳ cái gì bạn muốn Terraform tạo ra (như 1 cái máy ảo, 1 cái ổ đĩa, hay ở đây là 1 cái Docker Image và 1 cái Docker Container).
- arg (Argument / Tham số): Là các dòng thuộc tính nằm bên trong dấu ngoặc nhọn {} của resource để cấu hình cho tài nguyên đó.
resource "docker_container" "nginx_server" {
  image = docker_image.nginx.image_id  # <--- Đây là 1 argument (tên là image)
  name  = "terraform-demo-nginx"       # <--- Đây là 1 argument (tên là name)
}
- CrashLoopBackOff (loop cook): Là lỗi Pod bị chết đi sống lại liên tục do lỗi code/cấu hình bên trong container. Bên K8s thì nó sẽ tự cứu, tự bật lại liên tục dẫn đến lỗi CrashLoopBackOff

### 1.6 kiến thức về pod
ReplicationControllers:đóng vai trò như một "người giám sát" để đảm bảo một số lượng bản sao (Replicas) của Pod luôn luôn chạy ổn định ở bất kỳ thời điểm nào.

Desired Replica Count: số lượng Pod ta muốn duy trì, RC đảm bảo số lượng Pod hiện tại luôn bằng với số lượng ta mong muốn
Pod Template
Selector: RC sử dụng một selector để xác định các pods mà nó quản lý
Self-healing: RC tự động thay thế các Pod bị lỗi hoặc tắt để đảm bảo số lượng Pod mong muốn luôn được duy trì

- RC : Chỉ cần ghi thẳng app: web-app
- RS : Phải bọc qua matchLabels hoặc matchExpressions, Hãy quản lý tất cả các Pod miễn là cái nhãn env của tụi nó nằm trong nhóm production hoặc staging
- DaemonSet này không dùng để chạy các trang Web App thông thường (như app đặt phòng hay web Nginx của bạn), mà nó sinh ra để chạy các ứng dụng Hạ tầng / Giám sát ngầm: thu thập logs

### 1.7 các thành phần kubernets
- Service là một đối tượng cung cấp địa chỉ mạng ổn định để truy cập một hoặc nhiều Pod.
+ Khi Pod được tạo lại, IP thường thay đổi, Service giải quyết vấn đề này bằng cách tạo một điểm truy cập cố định phía trước các Pod.
- ConfigMap là đối tượng dùng để lưu trữ cấu hình dưới dạng key-value và cung cấp cấu hình đó cho Pod/Container.
+ Tách cấu hình khỏi code và image Docker.
- Secret trong Kubernetes là đối tượng dùng để lưu trữ dữ liệu nhạy cảm
+ Mật khẩu database, API keys
### Volume
+ Volume là cơ chế cung cấp lưu trữ (storage) cho Pod.
+ Giúp dữ liệu tồn tại ngoài vòng đời của container và có thể được chia sẻ giữa các container trong cùng Pod.
### Deployment & StatefulSet
-  Deployment là controller quản lý Pod.
-  StatefulSet: Mỗi Pod có danh tính riêng và dữ liệu riêng, không được thay thế tùy tiện.=> stateful
### NodePort là gì?
- Expose ra ngoài node.
### Startup Probe là gì?
- Cho ứng dụng thời gian khởi động lâu.
### Minikube tunnel dùng để làm gì?
- Giúp Service hoạt động trên môi trường local.
### etcd
- Cơ sở dữ liệu key-value của Kubernetes.
### Scheduler làm gì?
- quyết định Pod sẽ chạy trên node nào
### Rolling Update là gì?
- Triển khai phiên bản mới mà không downtime.
## 2. Đây là lab đã xây dựng 
### Bước 1: 
- Thư mục modules/: chứa các khuôn đúc thô (S3, EC2, RDS...)
- Thư mục root: Chứa các file điều phối chính( main.tf, provider.tf, backend.tf, variables.tf, outputs.tf, terraform.tfvars)
### Bước 2: Viết cho modules
- variables.tf : khai báo biến và dựng khuôn, 
variable "bucket_name" {
  description = "Ten cua S3 bucket duoc truyen tu ngoai root vao"
  type        = string
}

- main.tf : định nghĩa tài nguyên
resource "aws_s3_bucket" "artifact" {
  bucket        = var.bucket_name
  force_destroy = true

  tags = {
    Name        = var.bucket_name
    Environment = var.environment
    ManagedBy   = "terraform-module"
  }
}
- outputs.tf: xuất các thông tin để dùng
### Bước 3: Viết cho root
- provider.tf: Khai báo provider AWS và vùng (region)
- variables.tf: Khai báo biến
variable "artifact_bucket_name" {
  description = "Ten cua S3 Bucket dung de chua san pham/artifact"
  type        = string
}
- s3.tf & dynamodb.tf: Viết code cứng để tạo S3 Bucket chứa State và bảng DynamoDB để khóa State (Phục vụ cho Backend)

### data resource là lấy trong aws đã có dữ liệu