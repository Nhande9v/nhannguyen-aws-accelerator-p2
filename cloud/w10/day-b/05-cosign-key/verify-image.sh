#!/bin/bash
IMAGE_NAME="localhost:5005/azurahaven-backend:v1.0.0"

echo "=== KIỂM TRA CHỮ KÝ IMAGE ==="
./cosign.exe verify --key ./05-cosign-key/public-key/cosign.pub --allow-insecure-registry $IMAGE_NAME