# Quy trình chuẩn (Happy Path) từ Code đến Cluster

Khi một tính năng mới của ứng dụng AzuraHaven được Deploy, luồng đi chuẩn sẽ như sau:

1. **Bước 1**: Lập trình viên hoàn thành code, đẩy tag mới lên Git: `git tag v1.0.0 && git push origin v1.0.0`
2. **Bước 2**: GitHub Actions kích hoạt:
   * Chạy Trivy quét base image -> Trạng thái: **PASS** (Không có lỗi CRITICAL unpatched).
   * Kích hoạt Cosign đóng dấu chữ ký số vào Image trên Registry.
3. **Bước 3**: Cập nhật file manifest ứng dụng bằng GitOps hoặc chạy lệnh thủ công:
   ```bash
   kubectl apply -f cloud/w10/day-b/03-demo-app/deployment.yaml
4. **Bước 4**: Kyverno bắt được tín hiệu triển khai Pod, đối chiếu chữ ký số trên Registry với Public Key trong Cluster -> Trạng thái: Hợp lệ (Allowed).

5. **Bước 5**: Pod chuyển sang trạng thái Running. Kết thúc chu trình an toàn.