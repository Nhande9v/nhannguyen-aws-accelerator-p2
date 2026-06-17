# Kiểm tra đồng bộ Secret từ AWS

### 1. Kiểm tra trạng thái ExternalSecret
```bash
kubectl get externalsecret azurahaven-backend-es -n demo-app
### 2. Kiểm tra K8s Secret được sinh tự động
Bash
kubectl get secret azurahaven-prod-secret -n demo-app -o yaml

### 3. Giải mã kiểm tra data (Base64)
Bash
kubectl get secret azurahaven-prod-secret -n demo-app -o jsonpath='{.data.DB_USER}' | base64 --decode