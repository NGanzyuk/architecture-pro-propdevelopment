#!/usr/bin/env bash
set -euo pipefail

input_file="${1:-audit.log}"
output_file="${2:-audit-extract.json}"

if [[ ! -f "$input_file" ]]; then
  echo "Файл ${input_file} не найден" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Для выполнения скрипта требуется jq" >&2
  exit 1
fi

echo "Исходный лог: ${input_file}"
echo "Результат: ${output_file}"

jq -s '
  [
    .[]
    | select(.stage == "ResponseComplete")
    | select(
        (
          .objectRef.resource == "secrets"
          and .verb == "get"
          and (
            .impersonatedUser.username
              == "system:serviceaccount:secure-ops:monitoring"
            or
            .user.username
              == "system:serviceaccount:secure-ops:monitoring"
          )
        )
        or
        (
  .objectRef.resource == "pods"
  and .objectRef.namespace == "secure-ops"
  and .objectRef.name == "privileged-pod"
  and .verb == "create"
  and (
    (.requestObject.spec.containers // [])
    | any(.securityContext.privileged == true)
  )
)
        or
        (
          .objectRef.resource == "pods"
          and .objectRef.subresource == "exec"
        )
        or
        (
          .objectRef.resource == "rolebindings"
          and .objectRef.name == "escalate-binding"
          and .verb == "create"
        )
        or
        (
          .verb == "delete"
          and (
            (.requestURI // "")
            | test("audit-policy"; "i")
          )
        )
      )
  ]
' "$input_file" > "$output_file"

event_count=$(jq 'length' "$output_file")

echo "Найдено подозрительных событий: ${event_count}"