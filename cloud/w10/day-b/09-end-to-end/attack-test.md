# Kịch bản Diễn tập Tấn công (Supply Chain Attack)

Giả lập trường hợp Hacker chiếm quyền điều khiển Registry nội bộ và chèn một mã độc vào Image rồi tìm cách phân phối nó vào hệ thống K8s production.

### 1. Kịch bản 1: Đẩy Image lậu hoàn toàn không có chữ ký
```bash
kubectl run backdoor-pod --image=my-registry.internal/attacker/malicious:latest -n demo-app