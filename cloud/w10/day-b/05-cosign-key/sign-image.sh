#!/bin/bash
# Script ký image sử dụng cặp khóa cấu hình thủ công

export COSIGN_PASSWORD="nhan912004-"
IMAGE_NAME="localhost:5005/azurahaven-backend:v1.0.0"

echo "=== ĐANG KÝ IMAGE BẰNG PRIVATE KEY ==="
# Ép cosign tương tác với local docker daemon thay vì remote registry
export COSIGN_EXPERIMENTAL=1

./cosign.exe sign --key ./05-cosign-key/public-key/cosign.key --allow-insecure-registry $IMAGE_NAME