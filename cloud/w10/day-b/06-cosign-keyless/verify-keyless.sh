#!/bin/bash
# Kiểm tra chữ ký Keyless cá nhân qua GitHub Identity (Chạy Local)

IMAGE_NAME="localhost:5005/azurahaven-backend:v1.0.0"

echo "=== KIỂM TRA CHỮ KÝ KEYLESS ==="

# Thay certificate-identity thành chính xác email của bạn
./cosign.exe verify --allow-insecure-registry \
  --certificate-identity "hoangnhan912004dn@gmail.com" \
  --certificate-oidc-issuer "https://github.com/login/oauth" \
  $IMAGE_NAME