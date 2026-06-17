# Cài đặt các công cụ nền tảng qua Helm

### 1. Cài đặt External Secrets Operator (ESO)
```bash
helm repo add external-secrets [https://charts.external-secrets.io](https://charts.external-secrets.io)
helm repo update
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --set installCRDs=true

  # installCRDs=true để K8s hiểu được SecretStore và ExternalSecret 
Cài đặt Kyverno
```bash
helm repo add kyverno [https://kyverno.github.io/kyverno/](https://kyverno.github.io/kyverno/)
helm repo update
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --set admissionController.replicas=1 

