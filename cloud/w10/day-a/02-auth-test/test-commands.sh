#!/bin/bash
# Script dùng để giả lập (impersonate) ServiceAccount và kiểm tra quyền RBAC

echo "=== Kiểm tra quyền đọc Pod trong namespace lab-rbac-policy ==="
kubectl auth can-i list pods --as=system:serviceaccount:lab-rbac-policy:pod-viewer-sa -n lab-rbac-policy

echo "=== Kiểm tra quyền XÓA Pod (Kỳ vọng: no) ==="
kubectl auth can-i delete pods --as=system:serviceaccount:lab-rbac-policy:pod-viewer-sa -n lab-rbac-policy

echo "=== Kiểm tra quyền đọc Node (ClusterRole) (Kỳ vọng: yes) ==="
kubectl auth can-i list nodes --as=system:serviceaccount:lab-rbac-policy:pod-viewer-sa