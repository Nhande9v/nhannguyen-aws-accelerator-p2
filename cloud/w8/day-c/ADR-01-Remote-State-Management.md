# ADR 01: Quản lý State tập trung bằng AWS S3 và DynamoDB

## 1. Bối cảnh (Context)
Hiện tại, dự án đang lưu trữ file `terraform.tfstate` ở máy cục bộ (Local). Điều này gây ra rủi ro lớn khi làm việc nhóm (dễ bị xung đột đè code lên nhau) và không đảm bảo an toàn bảo mật khi file chứa thông tin nhạy cảm ở dạng text thuần.

## 2. Quyết định (Decision)
Chúng tôi quyết định di chuyển toàn bộ Terraform State lên lưu trữ tập trung trên Cloud:
- **Lưu trữ:** Sử dụng **AWS S3 Bucket** có bật tính năng `Versioning` để lưu file State tập trung và có khả năng khôi phục phiên bản cũ khi lỗi.
- **Khóa State (Locking):** Sử dụng **AWS DynamoDB Table** với Hash Key là `LockID` để tự động khóa State khi có người đang thực thi lệnh `apply`, tránh xung đột đồng thời.

## 3. Trạng thái (Status)
- **Đã chấp thuận (Approved)** và triển khai thành công tại thư mục `day-c`.

## 4. Hệ quả (Consequences)
- **Tích cực:** Thành viên trong nhóm có thể đồng bộ hạ tầng mượt mà, không sợ ghi đè dữ liệu, tăng tính an toàn cho hệ thống.
- **Tiêu cực:** Phải tốn thêm chi phí quản lý tài nguyên thô (S3, DynamoDB) trên AWS (tuy nhiên chi phí này ở mức cực kỳ thấp/Free Tier).