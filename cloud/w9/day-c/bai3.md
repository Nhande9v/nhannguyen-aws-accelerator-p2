# 1. Argo Rollouts
- Argo Rollouts kết hợp nhiều thành phần lại với nhau để đưa ra quyết định tự động: đi tiếp hoặc hủy bỏ(abort)
# 2. Rollout CRD
- Thay vì dùng deployment tiêu chuẩn của K8s, Argo Rollouts giới thiệu một Custom Resource Definition (CRD) tên là Rollout. Nó thừa hưởng cấu hình của deployment nhưng thêm vùng strategy để đ/n cách thức deploy với các bước tăng dần traffic
# 3. AnalysisTemplate & Prometheus Query
- AnalysisTemplate: Giống như một cái "khuôn" định nghĩa đo sức khỏe hệ thống. Nó quy định lấy dữ liệu từ đâu (Prometheus) và dùng câu lệnh PromQL để check
- AnalysisRun : Là một thực thể (instance) cụ thể được sinh ra từ AnalysisTemplate khi bạn tiến hành deploy. Nó sẽ chạy ngầm liên tục trong quá trình Canary để "bắn" query tới Prometheus

# 4. Abort Criteria (Tiêu chí hủy bỏ)
- Trong AnalysisTemplate