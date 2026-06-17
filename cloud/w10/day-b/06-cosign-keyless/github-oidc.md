# Luồng hoạt động của Cosign Keyless (OIDC)

Thay vì lưu trữ file Key, GitHub Actions sẽ yêu cầu một Token OIDC ngắn hạn (thời hạn 10 phút) đại diện cho danh tính Repo của bạn.

### Quyền bắt buộc trong Workflow GitHub Actions:
```yaml
permissions:
  id-token: write   # Bắt buộc để lấy OIDC Token từ GitHub
  contents: read
  packages: write   # Để push chữ ký lên Registry