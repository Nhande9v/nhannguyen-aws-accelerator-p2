### Tổng quát
Developer
    |
    v
Build Image
    |
    +--> Trivy Scan (CVE?)
    |
    +--> Cosign Sign
    |
    v
Container Registry
    |
    v
Kubernetes Admission Controller
    |
    +--> Verify Signature?
    +--> CVE Policy?
    |
    v
Deploy

Secret Flow
AWS Secrets Manager
        |
        v
External Secrets Operator
        |
        v
Kubernetes Secret
        |
        v
Pod

## 1. Secrets Rotation
VD: DB_USER=admin
DB_PASSWORD=123456
- Bị lộ => Nhân viên nghỉ việc
=> cho nên cần 90 ngày đổi 1 lần, or 30 ngày hoặc tự động
- Secret Rotation = xoay vòng secret định kỳ.
Vấn đề khi dùng Kubernetes Secret
Nhiều người làm kiểu base64 chứ ko mã hóa rồi commit rất nguy hiểm giải pháp ko lưu secret trong git lưu AWS Secret manager, Azure Key Vault
AWS Secrets Manager
      |
      v
External Secrets Operator
      |
      v
K8s Secret
      |
      v
Pod

## 2. AWS Secrets Manager
- Là dịch vụ lưu secret của AWS.
- Ưu điểm :
+ AWS mã hóa bằng KMS.
Secret
   |
   v
KMS Key

+ Audit
Biết ai đọc secret.
Ví dụ:
Dev A đọc lúc 10:00
Pod B đọc lúc 10:01

+ Rotation
AWS tự đổi password.
Ví dụ:
RDS Password
AWS:
old-pass
   ->
new-pass

## 3. External Secrets Operator (ESO)
- Câu hỏi làm sao pod k8s lấy secret từ bên ngoài
ESO sẽ giải quyết việc đó
- ESO là một kubernetes operator

Nó chạy:
Loop:
  đọc AWS Secret
  tạo Kubernetes Secret

VD : AWS { "password":"super-secret"}
ESO 
 kind: ExternalSecret
 sẽ tạo:
kind: Secret
metadata:
  name: db-secret 
  AWS Secrets Manager
        |
        v
ExternalSecret
        |
        v
K8s Secret
        |
        v
Pod

Rotation với ESO
khi đổi password thì ESO sync lại

## 4. Supply Chain Security là gì?  ******** 
Mục tiêu:
- là việc bảo vệ toàn bộ quá trình từ lúc viết code cho đến khi ứng dụng chạy trong cluster, nhằm đảm bảo không ai chèn mã độc,
Ví dụ:
my-app:v1
Ai đó push image giả:
my-app:v1
có malware.
Nếu cluster deploy luôn:
Production bị hack

- Cho nên cần 
+ Scan
+ Sign
+ Verify

## 5. Trivy Image Scan
- Trivy là scanner nổi tiếng của Aqua.
- Nó scan:
Docker Image, Filesystem, Repo, Kubernetes, SBOM
+ Tìm lỗ hổng (CVE)
+ Tìm Secret bị lộ
+ Tìm cấu hình sai (Misconfiguration)

## 6.CVE
- Common Vulnerabilities and Exposures.
- VD: 
Log4Shell
Heartbleed
=> đều là CVE

Severity:
CRITICAL
HIGH
MEDIUM
LOW

Thông thường policy:
CRITICAL = fail
HIGH = fail
MEDIUM = warning

## 7. Cosign
Sau khi scan xong.
Làm sao biết image là của công ty?
Cần ký image.
Cosign sinh ra để giải quyết.
- VD:
Image:
my-app:v1
Cosign:
cosign sign my-app:v1
Nó tạo chữ ký:
Signature

Flow: 
Build->Scan->Sign->Push Registry
ko có Làm sao biết:
Image này do team của bạn build?
Có ai thay thế image trong registry không?
## 8. Key-based Signing
Kiểu truyền thống.
- Tạo key:
cosign generate-key-pair
- Sinh:
cosign.key
cosign.pub
- Ưu điểm:
Đơn giản
Offline được
- Nhược điểm:
Mất private key = toang

Cosign dùng:

Image Digest
     +
Private Key
     |
     v
Signature
Tạo key trước → dùng private key để ký → dùng public key để xác minh.
## 9. Keyless Signing (OIDC)
Đây là cách hiện đại.   
Không cần giữ private key.
flow 
GitHub Actions
      |
OIDC Identity
      |
Fulcio
      |
Temporary Cert
      |
Cosign Sign
1. CI/CD chạy pipeline (GitHub Actions)
2. Hệ thống cấp OIDC token (identity tạm thời)
3. Cosign dùng token đó để ký image
4. Signature được lưu kèm identity của pipeline

Ưu điểm:
Không phải giữ private key

## 10. Admission Webhook
khi deploy bằng kubectl apply thì request đi vào api
User
  |
  v
API Server
  |
  v
Admission Webhook
  |
  v
etcd

Webhook có quyền:
ALLOW
DENY

Verify Signature bằng Admission Controller
VD: Image phải có Cosign Signature
Deploy:
image: my-app:v1
Webhook:
Có signature?
nếu trả lời là yes thì deploy
- flow:
Developer
     |
Deploy
     |
Admission
     |
Verify Signature
     |
Allow/Deny

## 11. Exception Policy CVE
Exception Policy CVE (hay còn gọi là CVE exception / vulnerability exception policy) là cơ chế cho phép bạn “bỏ qua có kiểm soát” một số lỗ hổng CVE khi scan (ví dụ bằng Trivy) thay vì chặn luôn pipeline.
Vì sao cần Exception Policy?

Nếu không có nó:
Pipeline sẽ fail liên tục
→ không deploy được
→ team bị “kẹt” vì CVE không fix được ngay
Khi scan image, bạn có thể gặp:

CRITICAL: 1
HIGH: 5

- Theo policy bình thường:
Có CRITICAL → FAIL pipeline → không deploy
- Nhưng có trường hợp:
CVE đó không ảnh hưởng thực tế
Hoặc chưa có bản fix
Hoặc đã được chấp nhận rủi ro tạm thời
→ bạn tạo Exception Policy để loại trừ CVE đó khỏi việc chặn deploy.