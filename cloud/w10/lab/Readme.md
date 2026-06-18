# W10 Lab 1 - RBAC + Gatekeeper

Huong dan nay tiep noi repo GitOps W9/W10 trong `w10/lab/temp`. Muc tieu la tao RBAC cho 3 user va bat Gatekeeper enforce policy bang GitOps, khong `kubectl apply` truc tiep cac manifest RBAC/policy.

> Ghi chu: thay `https://github.com/Vuong-Bach/temp.git` bang repo fork cua ban neu repoURL khac.

## 0. Kiem tra nen tang W9/W10

```bash
cd w10/lab/temp

kubectl config current-context
kubectl get app -n argocd
kubectl get app root -n argocd
```

Neu `root` chua tro ve repo cua ban, sua `argocd/root.yaml`:

```yaml
spec:
  source:
    repoURL: https://github.com/<github-user>/<repo>.git
    path: argocd/apps
    targetRevision: main
```

Commit va push:

```bash
git add argocd/root.yaml
git commit -m "chore: point argocd root to my fork"
git push origin main
```

Sync root app:

```bash
argocd app sync root
argocd app wait root --health --sync --timeout 300
```

Neu khong dung ArgoCD CLI:

```bash
kubectl -n argocd annotate app root argocd.argoproj.io/refresh=hard --overwrite
kubectl get app -n argocd -w
```

## 1. Lab 1.1 - RBAC qua GitOps

Tao cau truc file:

```bash
mkdir -p rbac
```

### 1.1 Tao `rbac/roles.yaml`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: developer
  namespace: demo
rules:
  - apiGroups: ["", "apps"]
    resources:
      - pods
      - services
      - deployments
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sre-pod-operator
rules:
  - apiGroups: [""]
    resources:
      - pods
      - pods/log
      - pods/exec
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: platform-viewer
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
```

### 1.2 Tao `rbac/rolebindings.yaml`

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: alice-developer
  namespace: demo
subjects:
  - kind: User
    name: alice
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: developer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: bob-sre-pod-operator
subjects:
  - kind: User
    name: bob
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: sre-pod-operator
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: carol-platform-viewer
subjects:
  - kind: User
    name: carol
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: platform-viewer
  apiGroup: rbac.authorization.k8s.io
```

### 1.3 Tao ArgoCD app `argocd/apps/rbac.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rbac
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  project: default
  source:
    repoURL: https://github.com/<github-user>/<repo>.git
    path: rbac
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: demo
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Commit va sync:

```bash
git add rbac argocd/apps/rbac.yaml
git commit -m "feat: add lab rbac roles"
git push origin main

argocd app sync root
argocd app sync rbac
argocd app wait rbac --health --sync --timeout 300
```

Nghiem thu RBAC:

```bash
kubectl auth can-i create deploy -n demo --as alice
kubectl auth can-i create deploy -n kube-system --as alice
kubectl auth can-i get pods -A --as bob
kubectl auth can-i delete nodes --as carol
```

Ket qua dung:

```text
yes
no
yes
no
```

## 2. Lab 1.2 - Gatekeeper qua GitOps

Tao cau truc:

```bash
mkdir -p gatekeeper/templates gatekeeper/constraints gatekeeper/test
```

### 2.1 Cai Gatekeeper controller bang ArgoCD

Tao `argocd/apps/gatekeeper.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gatekeeper
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-2"
spec:
  project: default
  source:
    repoURL: https://open-policy-agent.github.io/gatekeeper/charts
    chart: gatekeeper
    targetRevision: 3.16.3
    helm:
      releaseName: gatekeeper
  destination:
    server: https://kubernetes.default.svc
    namespace: gatekeeper-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

### 2.2 ConstraintTemplate: cam image `:latest`

Tao `gatekeeper/templates/k8sdisallowedtags-template.yaml`:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowedtags
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowedTags
      validation:
        openAPIV3Schema:
          type: object
          properties:
            tags:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowedtags

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          tags := input.parameters.tags
          endswith(container.image, concat("", [":", tags[_]]))
          msg := sprintf("container <%v> uses disallowed image tag in image <%v>", [container.name, container.image])
        }
```

### 2.3 ConstraintTemplate: bat buoc `resources.limits`

Tao `gatekeeper/templates/k8srequiredresources-template.yaml`:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredresources
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredResources
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredresources

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not container.resources.limits
          msg := sprintf("container <%v> must define resources.limits", [container.name])
        }
```

### 2.4 ConstraintTemplate: cam `runAsUser: 0`

Tao `gatekeeper/templates/k8sdisallowrootuser-template.yaml`:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowrootuser
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowRootUser
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowrootuser

        violation[{"msg": msg}] {
          input.review.object.spec.securityContext.runAsUser == 0
          msg := "pod must not run as root user"
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          container.securityContext.runAsUser == 0
          msg := sprintf("container <%v> must not run as root user", [container.name])
        }
```

### 2.5 ConstraintTemplate: cam `hostNetwork: true`

Tao `gatekeeper/templates/k8sdisallowhostnetwork-template.yaml`:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowhostnetwork
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowHostNetwork
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowhostnetwork

        violation[{"msg": msg}] {
          input.review.object.spec.hostNetwork == true
          msg := "pod must not use hostNetwork"
        }
```

### 2.6 Tao 4 Constraint enforce

Tao `gatekeeper/constraints/01-disallow-latest.yaml`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowedTags
metadata:
  name: disallow-latest-tag
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
  parameters:
    tags: ["latest"]
```

Tao `gatekeeper/constraints/02-require-limits.yaml`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredResources
metadata:
  name: require-resource-limits
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

Tao `gatekeeper/constraints/03-disallow-root.yaml`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowRootUser
metadata:
  name: disallow-root-user
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

Tao `gatekeeper/constraints/04-disallow-hostnetwork.yaml`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowHostNetwork
metadata:
  name: disallow-hostnetwork
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
```

### 2.7 Tao ArgoCD app `argocd/apps/gatekeeper-policies.yaml`

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gatekeeper-policies
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
spec:
  project: default
  source:
    repoURL: https://github.com/<github-user>/<repo>.git
    path: gatekeeper
    targetRevision: main
    directory:
      recurse: true
  destination:
    server: https://kubernetes.default.svc
    namespace: gatekeeper-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
```

Commit va sync:

```bash
git add gatekeeper argocd/apps/gatekeeper.yaml argocd/apps/gatekeeper-policies.yaml
git commit -m "feat: add gatekeeper admission policies"
git push origin main

argocd app sync root
argocd app sync gatekeeper
argocd app wait gatekeeper --health --sync --timeout 300
argocd app sync gatekeeper-policies
argocd app wait gatekeeper-policies --health --sync --timeout 300
```

Kiem tra controller va CRD:

```bash
kubectl get pods -n gatekeeper-system
kubectl get constrainttemplates
kubectl get constraints
```

## 3. Lab 1.2 - Manifest test reject/pass

Tao `gatekeeper/test/pod-latest.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-latest
  namespace: demo
spec:
  containers:
    - name: app
      image: nginx:latest
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
      securityContext:
        runAsUser: 1000
```

Tao `gatekeeper/test/pod-no-limits.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-no-limits
  namespace: demo
spec:
  containers:
    - name: app
      image: nginx:1.27.0
      securityContext:
        runAsUser: 1000
```

Tao `gatekeeper/test/pod-root.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-root
  namespace: demo
spec:
  securityContext:
    runAsUser: 0
  containers:
    - name: app
      image: nginx:1.27.0
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
```

Tao `gatekeeper/test/pod-hostnetwork.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: bad-hostnetwork
  namespace: demo
spec:
  hostNetwork: true
  containers:
    - name: app
      image: nginx:1.27.0
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
      securityContext:
        runAsUser: 1000
```

Tao `gatekeeper/test/pod-good.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: good-pod
  namespace: demo
  labels:
    owner: platform-team
spec:
  containers:
    - name: app
      image: nginx:1.27.0
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
      securityContext:
        runAsUser: 1000
```

Chay nghiem thu:

```bash
kubectl apply -f gatekeeper/test/pod-latest.yaml
kubectl apply -f gatekeeper/test/pod-no-limits.yaml
kubectl apply -f gatekeeper/test/pod-root.yaml
kubectl apply -f gatekeeper/test/pod-hostnetwork.yaml
kubectl apply -f gatekeeper/test/pod-good.yaml
```

Ky vong:

```text
pod-latest.yaml       reject
pod-no-limits.yaml    reject
pod-root.yaml         reject
pod-hostnetwork.yaml  reject
pod-good.yaml         pass
```

Xoa pod hop le sau khi test:

```bash
kubectl delete pod good-pod -n demo
```

## 4. Lab 1.3 - Custom Policy: reject Deployment neu replicas > 5

Chon policy nay vi de test ro rang va khong anh huong cac Pod system.

Tao `gatekeeper/templates/k8smaxreplicas-template.yaml`:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8smaxreplicas
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  crd:
    spec:
      names:
        kind: K8sMaxReplicas
      validation:
        openAPIV3Schema:
          type: object
          properties:
            maxReplicas:
              type: integer
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8smaxreplicas

        violation[{"msg": msg}] {
          replicas := input.review.object.spec.replicas
          max := input.parameters.maxReplicas
          replicas > max
          msg := sprintf("deployment <%v> has %v replicas; max allowed is %v", [input.review.object.metadata.name, replicas, max])
        }
```

Tao `gatekeeper/constraints/05-max-deployment-replicas.yaml`:

```yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sMaxReplicas
metadata:
  name: max-deployment-replicas
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
  parameters:
    maxReplicas: 5
```

Tao test vi pham `gatekeeper/test/deploy-too-many-replicas.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bad-replicas
  namespace: demo
spec:
  replicas: 6
  selector:
    matchLabels:
      app: bad-replicas
  template:
    metadata:
      labels:
        app: bad-replicas
        owner: platform-team
    spec:
      containers:
        - name: app
          image: nginx:1.27.0
          resources:
            limits:
              cpu: "100m"
              memory: "128Mi"
          securityContext:
            runAsUser: 1000
```

Tao test hop le `gatekeeper/test/deploy-good.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: good-replicas
  namespace: demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: good-replicas
  template:
    metadata:
      labels:
        app: good-replicas
        owner: platform-team
    spec:
      containers:
        - name: app
          image: nginx:1.27.0
          resources:
            limits:
              cpu: "100m"
              memory: "128Mi"
          securityContext:
            runAsUser: 1000
```

Commit va sync custom policy:

```bash
git add gatekeeper
git commit -m "feat: add custom max replicas gatekeeper policy"
git push origin main

argocd app sync gatekeeper-policies
argocd app wait gatekeeper-policies --health --sync --timeout 300
```

Test custom policy:

```bash
kubectl apply -f gatekeeper/test/deploy-too-many-replicas.yaml
kubectl apply -f gatekeeper/test/deploy-good.yaml
```

Ky vong:

```text
deploy-too-many-replicas.yaml  reject
deploy-good.yaml               pass
```

Don dep deployment hop le:

```bash
kubectl delete deploy good-replicas -n demo
```

## 5. Checklist nop bai

Kiem tra file trong repo fork:

```bash
tree rbac gatekeeper argocd/apps
```

Kiem tra ArgoCD:

```bash
kubectl get app -n argocd
kubectl get app -n argocd root rbac gatekeeper gatekeeper-policies
```

Kiem tra RBAC:

```bash
kubectl auth can-i create deploy -n demo --as alice
kubectl auth can-i create deploy -n kube-system --as alice
kubectl auth can-i get pods -A --as bob
kubectl auth can-i delete nodes --as carol
```

Kiem tra Gatekeeper:

```bash
kubectl get pods -n gatekeeper-system
kubectl get constrainttemplates
kubectl get constraints
kubectl get k8sdisallowedtags
kubectl get k8srequiredresources
kubectl get k8sdisallowrootuser
kubectl get k8sdisallowhostnetwork
kubectl get k8smaxreplicas
```

Kiem tra platform W9/W10 van xanh:

```bash
kubectl get app -n argocd
kubectl get pods -A
kubectl get rollout -n demo
```

## 6. Loi thuong gap

- `no matches for kind K8sDisallowedTags`: Constraint duoc sync truoc ConstraintTemplate. Chay lai `argocd app sync gatekeeper-policies`, hoac dam bao annotation sync-wave template la `0`, constraint la `1`.
- `admission webhook connection refused`: Gatekeeper controller chua san sang. Chay `kubectl get pods -n gatekeeper-system` va doi pod Ready.
- Platform bi OutOfSync/Degraded sau khi enforce: co resource dang vi pham policy. Tam thoi doi `enforcementAction: warn`, sync lai, sua manifest app cho pin image tag, co `resources.limits`, khong root, khong `hostNetwork`.
- `alice` van tao duoc Deployment o `kube-system`: kiem tra co ClusterRoleBinding admin nao bind den user/group cua alice khong.
- ArgoCD khong thay file moi: dam bao da `git push origin main` va `repoURL/path/targetRevision` trong app dung.

## 7. Tom tat lenh chay nhanh

```bash
cd w10/lab/temp

git add rbac gatekeeper argocd/apps/rbac.yaml argocd/apps/gatekeeper.yaml argocd/apps/gatekeeper-policies.yaml
git commit -m "feat: add rbac and gatekeeper lab"
git push origin main

argocd app sync root
argocd app sync rbac
argocd app sync gatekeeper
argocd app wait gatekeeper --health --sync --timeout 300
argocd app sync gatekeeper-policies
argocd app wait gatekeeper-policies --health --sync --timeout 300

kubectl auth can-i create deploy -n demo --as alice
kubectl auth can-i create deploy -n kube-system --as alice
kubectl auth can-i get pods -A --as bob
kubectl auth can-i delete nodes --as carol

kubectl apply -f gatekeeper/test/pod-latest.yaml
kubectl apply -f gatekeeper/test/pod-no-limits.yaml
kubectl apply -f gatekeeper/test/pod-root.yaml
kubectl apply -f gatekeeper/test/pod-hostnetwork.yaml
kubectl apply -f gatekeeper/test/pod-good.yaml
kubectl apply -f gatekeeper/test/deploy-too-many-replicas.yaml
kubectl apply -f gatekeeper/test/deploy-good.yaml
```
