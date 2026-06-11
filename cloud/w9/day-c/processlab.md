# B1: tạo argo-rollouts
- Thành phần này quản lý Controller của Argo Rollouts. (File rollout.yaml thực chất sẽ nằm ở thư mục app hoặc analysis tùy cách quản lý, nhưng đặt ở đây làm mẫu cấu hình gốc cũng rất tốt).
# B2: tạo demo-app
- Để test được Canary, ta cần 2 Service: một trỏ vào bản cũ (Stable) và một trỏ vào bản mới (Canary).
Bạn không cần file deployment-v1.yaml hay v2.yaml nữa, vì Rollout CRD sẽ thay thế hoàn toàn Deployment để quản lý việc nâng version bằng cách thay đổi thuộc tính image

+ Rollout (Bộ điều khiển chính): Thay vì dùng Deployment thông thường, bạn dùng Rollout của Argo. Nó là "bộ não" điều khiển việc tăng dần traffic.
+ Hai Service (Stable & Canary):
demo-app-stable: Luôn trỏ vào phiên bản cũ đang chạy ổn định.
demo-app-canary: Trỏ vào phiên bản mới (vừa deploy).
nếu ko có service.yaml của argo-rollouts thì Prometheus không có dữ liệu tổng quan về trạng thái đợt Rollout 

Prometheus đi qua Service $\rightarrow$ Thu thập được thông tin sức khỏe của Argo Rollouts $\rightarrow$ Giúp bạn vẽ được biểu đồ Grafana để quản lý tổng quan toàn bộ hệ thống Deploy của công ty.

DgMuLtz9gr-pkgUZ
