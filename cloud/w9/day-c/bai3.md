# 1. Argo Rollouts
- Argo Rollouts kết hợp nhiều thành phần lại với nhau để đưa ra quyết định tự động: đi tiếp hoặc hủy bỏ(abort)
# 2. Rollout CRD
- Thay vì dùng deployment tiêu chuẩn của K8s, Argo Rollouts giới thiệu một Custom Resource Definition (CRD) tên là Rollout. Nó thừa hưởng cấu hình của deployment nhưng thêm vùng strategy để đ/n cách thức deploy với các bước tăng dần traffic
# 3. AnalysisTemplate & Prometheus Query
- AnalysisTemplate: Giống như một cái "khuôn" định nghĩa đo sức khỏe hệ thống. Nó quy định lấy dữ liệu từ đâu (Prometheus) và dùng câu lệnh PromQL để check
- AnalysisRun : Là một thực thể (instance) cụ thể được sinh ra từ AnalysisTemplate khi bạn tiến hành deploy. Nó sẽ chạy ngầm liên tục trong quá trình Canary để "bắn" query tới Prometheus

# 4. Abort Criteria (Tiêu chí hủy bỏ)
- Trong AnalysisTemplate, bạn định nghĩa các ngưỡng thế nào là "lỗi" Ví dụ: 
+ successCondition: Kết quả trả về từ PromQL phải thỏa mãn điều kiện này (ví dụ: Tỷ lệ lỗi < 1%)

# 5. Integration với Burn Rate
- Thay vì chỉ đo các chỉ số cơ bản như CPU/RAM hay Error Rate tức thời, hệ thống nâng cao sử dụng Burn Rate dựa trên phương pháp SLO

Burn Rate đo tốc độ hệ thống đang "tiêu thụ" tài khoản lỗi (Error Budget) của bạn nhanh bấy nhiêu.

Ví dụ: Nếu Burn Rate = 1, bạn sẽ tiêu hết Error Budget vừa vặn trong 30 ngày. Nếu Burn Rate = 14.4, hệ thống đang lỗi rất nặng, bạn sẽ sạch bách Error Budget chỉ trong 2 ngày!

Tích hợp vào Argo Rollouts: Rollout sẽ gọi Prometheus để check Burn Rate của phiên bản mới. Nếu Burn Rate vượt ngưỡng an toàn (ví dụ > 2), hệ thống sẽ kích hoạt Abort Criteria để rollback ngay lập tức.