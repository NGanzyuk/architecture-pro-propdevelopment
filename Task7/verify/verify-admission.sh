#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
task_dir=$(cd "${script_dir}/.." && pwd)
profile=${MINIKUBE_PROFILE:-task7}
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

kube apply -f "${task_dir}/01-create-namespace.yaml"

failures=0

for manifest in "${task_dir}"/insecure-manifests/*.yaml; do
  if output=$(kube apply -f "${manifest}" 2>&1); then
    echo "ОШИБКА: ${manifest##*/} был принят PodSecurity Admission"
    kube delete -f "${manifest}" --ignore-not-found >/dev/null 2>&1 || true
    failures=$((failures + 1))
  elif grep -qi 'violates PodSecurity "restricted' <<<"${output}"; then
    echo "OK: ${manifest##*/} отклонён PodSecurity Admission"
  else
    echo "ОШИБКА: ${manifest##*/} отклонён по другой причине"
    echo "${output}"
    failures=$((failures + 1))
  fi
done

kube apply -f "${task_dir}/secure-manifests"
kube wait -n audit-zone --for=condition=Ready pod -l task7=secure --timeout=120s

if (( failures > 0 )); then
  echo "Проверка PodSecurity Admission завершилась с ошибками: ${failures}"
  exit 1
fi

echo "PodSecurity Admission: небезопасные Pod отклонены, безопасные Pod запущены"
