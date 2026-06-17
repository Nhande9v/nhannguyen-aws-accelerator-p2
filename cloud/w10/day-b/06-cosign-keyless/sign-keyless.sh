#!/bin/bash
# Script chạy keyless dưới máy local

IMAGE_NAME="localhost:5005/azurahaven-backend:v1.0.0"

echo "=== KÝ IMAGE BẰNG PHƯƠNG THỨC KEYLESS ==="
# Bật chế độ Experimental để Cosign chấp nhận ký Keyless
export COSIGN_EXPERIMENTAL=1

./cosign.exe sign --allow-insecure-registry $IMAGE_NAME