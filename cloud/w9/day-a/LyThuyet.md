# 1. CI/CD Pipeline với GitHub Actions: Plan-on-PR & Apply-on-Merge
[Người phát triển] ──(Tạo PR)──> [GitHub Actions: Plan] ──(Hiển thị kết quả trên PR)
                                         │
                                  (Merge vào main)
                                         │
                                         ▼
                                [GitHub Actions: Apply]

## 1.1 Plan-on-PR (Chạy khi tạo/cập nhật Pull Request)
- Mục đích: Kiểm tra trước xem thay đổi tác động đến hệ thống như nào
- Cách hoạt động : Khi bạn mở PR từ feature vào main, GitHub actions sẽ kích hoạt flow, chạt lệnh kiểm tra và tự động comment kết quả để review

vì k8s ko giống terraform nên ko lệnh plan, chỉ có apply nên dùng apply --dry-run=client

Đọc YAML
↓
Parse YAML
↓
Kiểm tra syntax
↓
Kiểm tra schema
↓
Mô phỏng apply
↓
Dừng lại
## 1.2 Apply-on-Merge (Chạy khi PR được Merge vào nhánh chính)
- Mục đích : Hiện thực hóa các thay đổi lên mt thật sau khi phê duyệt
- Cách hoạt động: Khi PR đc merge vào nhánh chính, workflow đc kích hoạt. Lúc này lệnh thực thi đẩy file để chạy

# 2. So sánh GitOps Controller: ArgoCD vs Flux CD
-  là một công cụ mã nguồn mở chuyên dùng để tự động hóa việc triển khai và quản lý ứng dụng trên nền tảng Kubernetes
- ArgoCD:  Có UI cực kỳ trực quan, mạnh mẽ, xem được trạng thái. Quản lý tập trung thông qua các Custom Resource Definition (CRD) như Application, một instance ArgoCD ở cụm trung tâm có thể quản lý hàng trăm cụm vệ tinh dễ dàng qua UI. Phù hợp cả đội ngủ vận hành
- Flux CD: UI có bên thứ 3, Flux tập trung hoàn toàn vào CLI và triết lý Git-native. Microservices: chia nhỏ các controller, phần nào làm phần nấy, Hỗ trợ tốt qua mô hình Git Repo cấu trúc phân cấp. Thường được các kỹ sư Platform/Ops ưu chuộng vì nó chạy ngầm nhẹ nhàng

# 3. Kiến trúc Nâng cao: App-of-Apps & Sync Waves trong ArgoCD
- Khi số lượng Microservices tăng lên, vào UI click tạo từng ứng dụng (Application) là điều bất khả thi. ArgoCD giải quyết bằng hai khái niệm:
+ App-of-Apps Pattern: Mô hình thiết kế mẫu. Bạn tạo ứng dụng gọi là Root App, cái này không trỏ đến mã nguồn mà nó trỏ đến thư mục chứa các manifest khai báo các ứng dụng khác
VD : Bạn chỉ deploy rootapp. Sau đó bất cứ khi nào bạn thêm một file định nghĩa App, Root tự động nhận biết và sinh ra app đó
+ Sync Waves: ứng dụng của bạn ko thể chạy nếu db chưa sẵn sàng. Sync Waves sinh ra để sắp xếp thứ tự này bằng cách sử dụng annotation
Nó chạy từ waves thấp đến cao, chỉ chạy khi ở trạng thái healthy

# 4. Chiến lược Rollback: Git Revert vs Kubectl Rollout Undo
- Git Revert (ưu tiên): Revert commit lỗi trên Git → ArgoCD/Flux tự sync về bản ổn định. Chậm hơn nhưng giữ đúng nguyên tắc Git = Source of Truth.
- kubectl rollout undo (khẩn cấp): Rollback trực tiếp trên cluster, rất nhanh nhưng gây Out of Sync giữa Git và cluster. Nếu bật Self-Heal, ArgoCD có thể deploy lại bản lỗi.

# Lệnh chạy day-a: mở docker
- minikube status: stop thì : minikube start
- kubectl apply -R -f k8s-manifests/ --dry-run=client
- kubectl get nodes
- kubectl get ns
- kubectl create namespace apps
- kubectl apply -R -f k8s-manifests/ 
- kubectl get deployments -n apps: xác nhận deployment tồn tại
- kubectl get pods -n apps
 *** Tổng kết lại thì làm sao kiểm tra deployment thành công?
 Tôi dùng:

kubectl get deployments -n apps

để kiểm tra số replica READY.

Sau đó dùng:

kubectl get pods -n apps

để xác nhận Pod đã ở trạng thái Running.

Nếu cần debug tiếp:

kubectl describe pod <pod-name>
kubectl logs <pod-name>

## 
Hiện tại: Bạn đang đóng vai là ArgoCD bằng cách gõ tay lệnh kubectl apply. Bạn tự đọc file manifests rồi tự ra lệnh cho K8s chạy.

Mục tiêu GitOps: Bạn sẽ cài ArgoCD vào cụm. Sau đó, bạn nạp file root-app.yaml vào ArgoCD. Kể từ lúc đó, bạn không bao giờ gõ lệnh kubectl apply nữa. ArgoCD sẽ tự động lên GitHub nhặt file, tự động chạy và tự động đồng bộ (Sync) về cụm Minikube của bạn.

B1: kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
B2 : 1-2 phút để các container của ArgoCD tải xong và chạy. Kiểm tra bằng lệnh:
kubectl get pods -n argocd
B3: Lấy mật khẩu đăng nhập Admin của ArgoCD
Mật khẩu mặc định được ArgoCD tự sinh ra và mã hóa trong Kubernetes Secret. Hãy chạy lệnh này để giải mã và lấy mật khẩu dạng chữ thường:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode; echo
pass của tôi: c-PTqrhmUIyR-uWo
B4: Mở cổng kết nối (Port-forward) vào giao diện Web
kubectl port-forward svc/argocd-server -n argocd 8080:443
B5: Để biến toàn bộ đống file lý thuyết trong folder gitops-root/ của bạn thành thực tế, ở tab Terminal mới, bạn chỉ cần chạy đúng một lệnh duy nhất này để nạp "Thuyền trưởng" root-app.yaml:
kubectl apply -f w9/day-a/gitops-root/root-app.yaml

làm thêm cái này:
Ép Minikube đồng bộ lại DNS từ máy Host:

Bash
minikube ssh "sudo sh -c 'echo \"nameserver 8.8.8.8\" > /etc/resolv.conf'"
(Lệnh này giúp nạp DNS của Google thẳng vào trong lòng cụm CoreDNS nội bộ của Minikube để nó biết đường tìm đến github.com).