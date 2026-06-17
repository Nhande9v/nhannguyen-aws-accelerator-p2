### 01-prerequisites/ (Thiết lập nền tảng)
Trước khi cấu hình bất kỳ ứng dụng hay policy nào, Kubernetes Cluster cần phải có sẵn các Namespace chuyên biệt để phân ranh giới cô lập (Isolation) và các công cụ bổ trợ (Operator/Controller) được cài đặt thành công.
B1: 01-prerequisites/namespace.yaml
- Namespace là ranh giới logic trong K8s. Bạn không thể deploy SecretStore hay App nếu các Namespace đích chưa tồn tại. Tạo file này đầu tiên để định hình không gian làm việc.

B2: 01-prerequisites/install-tools.md
- File này lưu trữ runbook cài đặt Helm Charts cho External Secrets Operator (ESO) và Kyverno. Không có hai Controller này, các Custom Resource Definitions (CRDs) ở các bước sau sẽ bị lỗi no matches for kind.

### 02-secrets-manager/ (AWS Secrets Manager + ESO)
Sau khi có ESO, ta cấu hình luồng đồng bộ Secret từ AWS về K8s. Thứ tự tạo file cực kỳ quan trọng: AWS (Nguồn) -> SecretStore (Kênh kết nối) -> ExternalSecret (Yêu cầu đồng bộ).
B1: 02-secrets-manager/aws-secret-example.json
Bạn cần xác định cấu trúc dữ liệu lưu trên AWS Secrets Manager trước khi viết file map dữ liệu ở K8s.
Lưu ý thực tế: Giả sử Secret này được lưu trên AWS Secrets Manager với tên (Secret Name) là production/azurahaven/backend

B2: 02-secrets-manager/secretstore.yaml
SecretStore = “đường ống + cách kết nối”
Nó trả lời câu hỏi:
Kubernetes sẽ connect tới đâu? bằng cách nào? quyền gì?
Tại sao tạo trước externalsecret.yaml? SecretStore định nghĩa cách thức và quyền hạn (Authentication) để Cluster kết nối tới AWS. Bạn phải thông đường ống trước rồi mới yêu cầu kéo nước về sau.
serviceAccountRef:
  name: eso-updater-sa
nghĩa là:
- External Secrets Operator hãy dùng cái ServiceAccount tên eso-updater-sa để chạy và đi lấy secret

B3: 02-secrets-manager/externalsecret.yaml
Vì nó cần tham chiếu đến SecretStore đã tạo ở trên thông qua storeRef.
refreshInterval: "1h": Đây chính là cơ chế tự động đồng bộ hỗ trợ Secrets Rotation. Cứ mỗi 1 tiếng, ESO sẽ check AWS xem secret có đổi pass không để cập nhật vào K8s Secret mà không cần restart app thủ công.
target.name: Tên của K8s Secret sinh ra sau khi đồng bộ thành công.
- secretStoreRef: dùng cái đường ống tên aws-secretsmanager-store

B4: 02-secrets-manager/verify.md
Tại sao tạo cuối cùng của mục này? Để kỹ sư vận hành chạy kiểm tra xem luồng đi của Secret từ AWS về Cluster có thông suốt hay không trước khi nhảy sang phần App.
## chạy bài số 2 trước khi chạy phải
# 1. Tạo Secret trên AWS Secrets Manager thật
aws secretsmanager create-secret --name "production/azurahaven/backend" \
  --description "Secret cho ung dung AzuraHaven" \
  --secret-string '{"DB_HOST":"aurora-cluster.cluster-c1234.ap-southeast-1.rds.amazonaws.com","DB_USER":"azura_admin","DB_PASS":"SuperSecurePassword2026@","JWT_SECRET":"d38bd62b719463c1a3b9090c2a8f89db8e1"}' \
  --region ap-southeast-1
- Bạn đang lưu thông tin nhạy cảm lên AWS Secrets Manager

# 2. Tạo Kubernetes Secret chứa AWS credentials
kubectl create secret generic aws-credentials \
  --from-literal=access-key-id=AKIA2JF7BTH6LSSPQHXC \
  --from-literal=secret-access-key='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' \
  -n demo-app
- Bạn đang tạo Kubernetes Secret

để chứa AWS credentials:

Access Key ID
Secret Access Key
### 03-demo-app/ (Triển khai Ứng dụng Demo)
Sau khi hạ tầng và Secret đã sẵn sàng, ta tiến hành viết Manifest deploy ứng dụng. Ứng dụng này sẽ "tiêu thụ" Secret do ESO sinh ra.
B1: 03-demo-app/namespace.yam
Tại sao cần? Mặc dù đã khai báo ở file prerequisites, việc giữ một file namespace tại đây giúp thư mục ứng dụng độc lập, có thể deploy riêng biệt khi cần (ví dụ thông qua ArgoCD).

B2: 03-demo-app/deployment.yaml
Pods/Deployments định hình cấu trúc cổng (containerPort) và các biến môi trường mà ứng dụng cần
Trích xuất trực tiếp các key từ azurahaven-prod-secret (do ESO quản lý) nạp vào biến môi trường của Container.

B3: 03-demo-app/service.yaml
Dùng để mở cổng kết nối (Expose) cho Deployment phía trên dựa trên bộ Selector app: azurahaven-backend

03-demo-app/ (Triển khai Ứng dụng tiêu thụ Secret)
Ứng dụng azurahaven-backend sẽ lấy trực tiếp các thông tin Database (User, Pass, Host) từ K8s Secret mà ESO vừa kéo về từ AWS thật.

- Apply file Deployment và Service của ứng dụng
kubectl apply -f 03-demo-app/deployment.yaml
kubectl apply -f 03-demo-app/service.yaml

- Kiểm tra xem Pod của ứng dụng đã lên chưa
kubectl get pods -n demo-app

### 04-trivy/ (Quét lỗ hổng Image trong CI/CD)
Trước khi một Image được ký và đẩy lên Cluster, nó bắt buộc phải được quét để tìm lỗ hổng bảo mật (CVE). Nếu Image có quá nhiều lỗi nghiêm trọng (CRITICAL), pipeline phải dừng lại ngay lập tức.
B1: 04-trivy/trivyignore
Trong thực tế đi làm, luôn có những CVE chưa có bản vá (unpatched) hoặc không ảnh hưởng trực tiếp đến hệ thống của bạn. Bạn cần file này để bỏ qua các CVE đã được kiểm duyệt (Exception), tránh việc Pipeline bị block vô lý.

B2: 04-trivy/trivy-local.sh
Script này giả lập cách Trivy quét image ở máy local của lập trình viên hoặc runner trước khi đẩy lên Docker Registry.
--exit-code 1: Ép script trả về lỗi (fail pipeline) nếu phát hiện lỗi CRITICAL.

--ignore-unfixed: Bỏ qua các lỗi chưa có bản vá từ chính nhà sản xuất để tránh làm phiền lập trình viên.

###  05-cosign-key/ (Ký Image bằng Key cá nhân)
Sau khi Image vượt qua vòng gửi xe của Trivy, ta tiến hành "đóng dấu" (Sign) để xác thực Image này trích xuất từ nguồn uy tín. Cách đầu tiên là dùng cặp Key (Public/Private)
B1: 05-cosign-key/generate-key.md
Phải có hướng dẫn sinh khóa an toàn trước khi viết script ký/xác thực.
trong thư mục public-key/ sẽ có:
cosign.key: Khóa bí mật (Tuyệt đối không đẩy lên Git, đưa vào CI/CD Secret).
cosign.pub: Khóa công khai (Dùng để nạp vào Kyverno Cluster Policy).

B2: 05-cosign-key/sign-image.sh
Sử dụng Private Key vừa tạo để đóng dấu trực tiếp lên Container Image.
B3: 05-cosign-key/verify-image.sh
Dùng để verify thủ công xem image đã được ký đúng bằng public key tương ứng hay chưa trước khi cấu hình tự động trên Cluster.
B4: chạy dự án thì mở genetate-key chạy trc
sau đó chạy ./05-cosign-key/sign-image.sh và ./05-cosign-key/verify-image.sh

### 06-cosign-keyless/ (Ký Image không dùng Key - OIDC)
Trong môi trường Enterprise hiện đại, việc quản lý file cosign.key rất rủi ro (dễ lộ, phải đổi khóa định kỳ). Keyless Signing giải quyết vấn đề này bằng cách dùng danh tính OIDC (OpenID Connect) từ GitHub Actions cấp qua nhà chứng thực Fulcio & Rekor của Sigstore.
B1: 06-cosign-keyless/github-oidc.md
Giải thích cơ chế hạ tầng liên kết danh tính giữa GitHub và Sigstore. Không có cấu hình này, Keyless không thể hoạt động

B2: 06-cosign-keyless/sign-keyless.sh
Chú ý không có tham số `--key`. Cosign tự hiểu sẽ kích hoạt chế độ Keyless thông qua môi trường CI.
B3: 06-cosign-keyless/verify-keyless.sh
Xác thực danh tính bằng cách chỉ định rõ: Image này phải được ký từ đúng Repo GitHub của bạn (--certificate-identity) và thông qua nhà phát hành GitHub (--certificate-oidc-issuer).

### 07-kyverno/ (Triển khai Chốt chặn Policy)
Dù ai đó cố tình dùng lệnh kubectl apply để triển khai một Image lậu (chưa qua quét, chưa được ký), Kyverno Admission Webhook sẽ lập tức chặn đứng lại ngay tại cửa ngõ API Server. 
B1: 07-kyverno/verify-signature-policy.yaml
Đây là Core Policy bắt buộc mọi Image chạy vào Namespace demo-app phải được ký bằng cặp khóa hợp lệ đã cấu hình ở thư mục 05.
failurePolicy: Fail: Nếu không thỏa mãn policy, từ chối deploy luôn (chế độ Enforce).
nếu mà dùng mục 5 thì dùng key, còn mục 6 thì ùng cert

B2: 07-kyverno/exception-policy.yaml
Đi làm sẽ có trường hợp khẩn cấp (Hotfix/Incident), hệ thống Core gặp lỗi nguy hiểm nhưng Image mới lại dính một CVE chưa có bản vá khiến Kyverno block. Bạn cần một file Policy ngoại lệ (Exception) tạm thời để cứu hệ thống.
Sử dụng PolecyException của Kyverno trỏ đích danh tới Policy verify-image-signature để chừa một lối đi hẹp, an toàn, có kiểm soát.

### 08-ci/github-actions/ (Tự động hóa luồng Bảo mật)
Phần này định hình quy trình tự động hoàn toàn. Không một kỹ sư nào được phép tự ý dùng máy cá nhân để ký ảnh rồi đẩy lên Cluster; tất cả phải đi qua Pipeline.
B1: 08-ci/github-actions/trivy-scan.yaml
Tại sao tạo trước? Theo quy trình an toàn, Quét phải diễn ra trước khi Ký. Nếu bước quét phát hiện lỗ hổng nghiêm trọng, Image sẽ bị hủy bỏ ngay lập tức trước khi nó kịp có chữ ký hợp lệ.
B2: 08-ci/github-actions/sign-image.yaml
Tại sao tạo sau? Vì workflow này chỉ chạy khi bước Quét Bảo Mật ở trên đã thành công hoàn toàn. Tại đây chúng ta sẽ áp dụng song song cả 2 cơ chế (Key-based và Keyless) như bạn đã định hình trong folder.
###### để chạy dự án
#!/bin/bash

# Hiển thị màu cho log
GREEN='\033[0;32m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== BẮT ĐẦU CHẠY TOÀN BỘ LAB SECURE SUPPLY CHAIN ===${NC}"

# ==========================================
# PHẦN 01: PREREQUISITES (Hạ tầng nền móng)
# ==========================================
echo -e "${GREEN}--> [Step 1/9] Khởi tạo các Namespace...${NC}"
kubectl apply -f 01-prerequisites/namespace.yaml

echo -e "${GREEN}--> [Step 1/9] Cài đặt ESO và Kyverno qua Helm...${NC}"
helm repo add external-secrets https://charts.external-secrets.io
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --set installCRDs=true

helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --set admissionController.replicas=1

echo "Đợi 30s cho các Operator khởi động hoàn toàn..."
sleep 30

# ==========================================
# PHẦN 02: SECRETS MANAGER (Kết nối AWS thật)
# ==========================================
echo -e "${GREEN}--> [Step 2/9] Triển khai cấu hình kết nối AWS Secrets Manager...${NC}"
# *Lưu ý: Bạn phải chạy các lệnh tạo secret trên AWS và tạo 'aws-credentials' trong k8s trước bước này.
kubectl apply -f 02-secrets-manager/secretstore.yaml
kubectl apply -f 02-secrets-manager/externalsecret.yaml

echo "Kiểm tra trạng thái đồng bộ secret từ AWS:"
kubectl get externalsecret azurahaven-backend-es -n demo-app

# ==========================================
# PHẦN 04 & 05: TRIVY & COSIGN KEY (Bảo mật Artifact)
# ==========================================
echo -e "${GREEN}--> [Step 3/9] Giả lập quét ảnh bằng Trivy nội bộ...${NC}"
# Yêu cầu máy đã cài trivy. Có thể chạy file test local:
# chmod +x 04-trivy/trivy-local.sh && ./04-trivy/trivy-local.sh

echo -e "${GREEN}--> [Step 4/9] Khởi tạo cặp khóa cho Cosign...${NC}"
# Chạy lệnh này thủ công nếu chưa có khóa (bỏ comment nếu cần):
# cosign generate-key-pair --output-dir ./05-cosign-key/public-key

# ==========================================
# PHẦN 07: KYVERNO (Triển khai Chốt chặn Policy)
# ==========================================
echo -e "${GREEN}--> [Step 5/9] Áp dụng Kyverno ClusterPolicy kiểm tra chữ ký...${NC}"
# Lưu ý: Cần đảm bảo file verify-signature-policy.yaml đã điền đúng public key vừa tạo
kubectl apply -f 07-kyverno/verify-signature-policy.yaml

# ==========================================
# PHẦN 03 & 09: END-TO-END DEMO APP (Kiểm thử thực tế)
# ==========================================
echo -e "${GREEN}--> [Step 6/9] Thử nghiệm Kịch bản tấn công (Deploy Image lậu không có chữ ký)...${NC}"
echo "Kỳ vọng: Hệ thống SẼ CHẶN lệnh sau đây:"
kubectl run độc-hại --image=nginx:latest -n demo-app

echo -e "${GREEN}--> [Step 7/9] Ký Image chuẩn bằng Cosign Key...${NC}"
# Giả lập việc ký ảnh bằng private key local trước khi đẩy (Thay image bằng image registry thật của bạn)
# chmod +x 05-cosign-key/sign-image.sh && ./05-cosign-key/sign-image.sh

echo -e "${GREEN}--> [Step 8/9] Triển khai Ứng dụng Demo hợp lệ (Happy Path)...${NC}"
echo "Kỳ vọng: Hệ thống CHO PHÉP deploy vì image đã có chữ ký khớp với Policy:"
kubectl apply -f 03-demo-app/deployment.yaml
kubectl apply -f 03-demo-app/service.yaml

echo -e "${GREEN}--> [Step 9/9] Kiểm tra trạng thái ứng dụng sau khi vượt qua tất cả chốt chặn...${NC}"
kubectl get pods -n demo-app -l app=azurahaven-backend

echo -e "${GREEN}=== HOÀN THÀNH TOÀN BỘ QUY TRÌNH DIỄN TẬP BẢO MẬT ===${NC}"