# Lab 1 – Install Prometheus Stack & Argo Rollouts via GitOps

## Goal

Deploy the **Prometheus monitoring stack** and the **Argo Rollouts controller** **entirely through GitOps** so that the cluster state is always a direct reflection of the files stored in this repository.  This gives us:

- **Traceability** – every change is version‑controlled and can be audited.
- **Drift‑prevention** – Argo CD continuously reconciles the live cluster with the Git‑defined desired state.
- **Instant rollback** – `git revert` restores the previous manifest and Argo CD syncs it automatically (within minutes).

If we applied the manifests manually with `kubectl apply`, we would lose these guarantees and would have to manually track versions.

---

## 1. Create the two Argo CD `Application` resources

### a) `kube‑prometheus‑stack.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
spec:
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: 65.1.1
    helm:
      values: |
        prometheus:
          prometheusSpec:
            serviceMonitorSelectorNilUsesHelmValues: false
  destination:
    server: https://kubernetes.default.svc
    namespace: monitoring
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```
**What it does**
- Pulls the Helm chart from the public **prometheus‑community** repo.
- Deploys the entire Prometheus‑Operator stack into the `monitoring` namespace.
- `automated` sync ensures Argo CD keeps the stack up‑to‑date and removes resources that are no longer defined (`prune`).
- `CreateNamespace=true` lets Argo CD create the `monitoring` namespace if it does not exist.
- `ServerSideApply=true` uses the server‑side apply feature for a smoother drift‑check.

### b) `argo‑rollouts.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-rollouts
  namespace: argocd
spec:
  source:
    repoURL: https://argoproj.github.io/argo-helm
    chart: argo-rollouts
    targetRevision: 2.37.7
    helm: {}
  destination:
    server: https://kubernetes.default.svc
    namespace: argo-rollouts
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```
**What it does**
- Installs the **Argo Rollouts controller** (the CRD that provides the `Rollout` kind).
- Deploys it into its own `argo‑rollouts` namespace.
- The same automated sync policy guarantees the controller is always present and up‑to‑date.

---

## 2. Add the files to the repo & push
```bash
# 1. Create the files under argocd/apps/
mkdir -p argocd/apps
cat > argocd/apps/kube-prometheus-stack.yaml <<'EOF'
<copy the yaml from section a) above>
EOF

cat > argocd/apps/argo-rollouts.yaml <<'EOF'
<copy the yaml from section b) above>
EOF

# 2. Commit & push – this triggers the GitOps pipeline
git add argocd/apps/kube-prometheus-stack.yaml argocd/apps/argo-rollouts.yaml
git commit -m "obs+rollouts – add Prometheus stack and Argo Rollouts via GitOps"
git push origin main
```
**Why this matters**
- The **root `Application`** (defined elsewhere in `argocd/root.yaml`) watches the `argocd/apps/` directory. Adding files there makes Argo CD automatically create the two sub‑applications.
- No manual `kubectl apply` is required; Argo CD handles the creation, ensuring the manifest source is immutable.

---

## 3. Verify the deployment
```bash
# Verify Argo CD sees the new Applications
kubectl -n argocd get applications
# Expected output includes:
#   kube-prometheus-stack   Sync: Synced   Health: Healthy
#   argo-rollouts           Sync: Synced   Health: Healthy

# Verify the pods are running
kubectl -n monitoring get pods   # Prometheus, Alertmanager, Grafana, etc.
kubectl -n argo-rollouts get pods   # rollout controller
```
**What to look for**
- Each pod should be in the `Running` state.
- The `STATUS` column for the Applications should read **Synced** and **Healthy**. If not, inspect the `Application` resource (`kubectl -n argocd describe application <name>`) to see error details.

---

## 4. What happens if we skip GitOps?
If we were to install the stack manually with `kubectl apply -f <url>`, we would:
- Lose the **single source of truth** – the live cluster would diverge from the repository.
- Have **no automatic rollback**; a failed change would require manual `kubectl delete` or re‑apply of older manifests.
- Miss out on **self‑heal** – Argo CD would not detect and correct drift.
- Reduce **auditability** – no commit history for who changed what and when.

Using GitOps solves all of these issues by treating the repository as the definitive configuration.

---

## 5. Clean‑up (optional)
If you ever need to remove the stack:
```bash
# Remove the Application files
git rm argocd/apps/kube-prometheus-stack.yaml argocd/apps/argo-rollouts.yaml
git commit -m "remove monitoring & rollouts"
git push origin main
```
Argo CD will detect the deletion, prune the resources, and the cluster will return to a clean state.

---

**End of Lab 1** – you now have a fully Git‑Ops‑driven Prometheus monitoring stack and Argo Rollouts controller ready for the subsequent canary deployment labs.
