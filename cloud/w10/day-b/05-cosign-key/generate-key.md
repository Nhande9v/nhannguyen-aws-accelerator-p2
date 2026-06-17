# Hướng dẫn tạo cặp khóa Cosign
Chạy lệnh sau để sinh khóa, hệ thống sẽ yêu cầu nhập mật khẩu (passphrase) để bảo vệ Private Key:
```bash
# 1. Tạo cặp key (mặc định ra file cosign.key và cosign.pub)
./cosign.exe generate-key-pair

# 2. Tạo thư mục nếu chưa có
mkdir -p ./public-key

# 3. Di chuyển cả 2 file vào thư mục public-key
mv cosign.key cosign.pub ./public-key/