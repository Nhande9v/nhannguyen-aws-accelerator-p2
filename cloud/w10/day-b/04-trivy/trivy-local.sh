#!/bin/bash
# Script quét image local trước khi push

IMAGE_NAME="nginx:1.23"

echo "=== ĐANG QUÉT BẢO MẬT IMAGE: $IMAGE_NAME ==="

trivy image \
  --exit-code 1 \
  --severity CRITICAL \
  --ignore-unfixed \
  --ignorefile ./04-trivy/trivyignore \
  $IMAGE_NAME