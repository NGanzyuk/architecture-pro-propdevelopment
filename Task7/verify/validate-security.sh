#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
task_dir=$(cd "${script_dir}/.." && pwd)
profile=${MINIKUBE_PROFILE:-task7}
test_namespace=gatekeeper-test
minikube_bin=${MINIKUBE_BIN:-minikube}

if ! command -v "${minikube_bin}" >/dev/null 2>&1; then
  windows_minikube='/c/Program Files/Kubernetes/Minikube/minikube.exe'
  if [[ -x "${windows_minikube}" ]]; then
    minikube_bin=${windows_minikube}
  else
    echo "ОШИБКА: minikube не найден" >&2
    exit 1
  fi
fi

kube() {
  "${minikube_bin}" -p "${profile}" kubectl -- "$@"
}

cleanup() {
  kube delete namespace "${test_namespace}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
}
trap cleanup EXIT

kube wait -n gatekeeper-system \
  --for=condition=Available deployment/gatekeeper-controller-manager \
  --timeout=180s

kube apply -f "${task_dir}/gatekeeper/constraint-templates"

for crd in \
  k8sdenyprivileged.constraints.gatekeeper.sh \
  k8sdenyhostpath.constraints.gatekeeper.sh \
  k8srequirecontainersecurity.constraints.gatekeeper.sh; do
  for attempt in {1..30}; do
    if kube get crd "${crd}" >/dev/null 2>&1; then
      break
    fi
    if (( attempt == 30 )); then
      echo "ОШИБКА: CRD ${crd} не создан"
      exit 1
    fi
    sleep 2
  done
  kube wait --for=condition=Established "crd/${crd}" --timeout=120s
done

kube apply -f "${task_dir}/gatekeeper/constraints"
sleep 5

kube create namespace "${test_namespace}" --dry-run=client -o yaml | kube apply -f -
kube label namespace "${test_namespace}" \
  pod-security.kubernetes.io/enforce=privileged \
  --overwrite >/dev/null

failures=0

for manifest in "${task_dir}"/insecure-manifests/*.yaml; do
  if output=$(sed "s/namespace: audit-zone/namespace: ${test_namespace}/" "${manifest}" | kube apply -f - 2>&1); then
    echo "ОШИБКА: ${manifest##*/} был принят Gatekeeper"
    failures=$((failures + 1))
  elif grep -qi 'gatekeeper' <<<"${output}"; then
    echo "OK: ${manifest##*/} отклонён Gatekeeper"
  else
    echo "ОШИБКА: ${manifest##*/} отклонён по другой причине"
    echo "${output}"
    failures=$((failures + 1))
  fi
done

for manifest in "${task_dir}"/secure-manifests/*.yaml; do
  sed "s/namespace: audit-zone/namespace: ${test_namespace}/" "${manifest}" | kube apply -f -
done

kube wait -n "${test_namespace}" --for=condition=Ready pod -l task7=secure --timeout=120s

if (( failures > 0 )); then
  echo "Проверка Gatekeeper завершилась с ошибками: ${failures}"
  exit 1
fi

echo "Gatekeeper: небезопасные Pod отклонены, безопасные Pod приняты"
