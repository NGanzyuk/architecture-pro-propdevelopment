#!/usr/bin/env bash
set -euo pipefail

namespace="propdevelopment"

minikube kubectl -- create namespace "$namespace" \
    --dry-run=client \
    -o yaml |
    minikube kubectl -- apply -f -

minikube kubectl -- apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: application-operator
  namespace: ${namespace}
rules:
  - apiGroups:
      - ""
    resources:
      - pods
      - services
      - endpoints
      - configmaps
      - persistentvolumeclaims
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

  - apiGroups:
      - ""
    resources:
      - pods/log
      - events
    verbs:
      - get
      - list
      - watch

  - apiGroups:
      - apps
    resources:
      - deployments
      - statefulsets
      - daemonsets
      - replicasets
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

  - apiGroups:
      - batch
    resources:
      - jobs
      - cronjobs
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete

  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
      - create
      - update
      - patch
      - delete
EOF

minikube kubectl -- apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cluster-viewer
rules:
  - apiGroups:
      - ""
    resources:
      - pods
      - services
      - endpoints
      - configmaps
      - persistentvolumeclaims
      - persistentvolumes
      - namespaces
      - nodes
      - events
    verbs:
      - get
      - list
      - watch

  - apiGroups:
      - ""
    resources:
      - pods/log
    verbs:
      - get

  - apiGroups:
      - apps
    resources:
      - deployments
      - statefulsets
      - daemonsets
      - replicasets
    verbs:
      - get
      - list
      - watch

  - apiGroups:
      - batch
    resources:
      - jobs
      - cronjobs
    verbs:
      - get
      - list
      - watch

  - apiGroups:
      - networking.k8s.io
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch

  - apiGroups:
      - storage.k8s.io
    resources:
      - storageclasses
    verbs:
      - get
      - list
      - watch
EOF
