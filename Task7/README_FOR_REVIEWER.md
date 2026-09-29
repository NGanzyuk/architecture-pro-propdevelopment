# Task 7 — безопасность контейнеров

Решение использует два независимых механизма:

- Pod Security Admission с профилем `restricted` в namespace `audit-zone`;
- OPA Gatekeeper с запретом `privileged`, `hostPath`, запуска от root и файловой системы контейнера в режиме записи.

## Запуск кластера

```bash
minikube start -p task7 \
  --driver=docker \
  --mount \
  --mount-string="$(pwd):/etc/ssl/certs/task7" \
  --extra-config=apiserver.audit-policy-file=/etc/ssl/certs/task7/audit-policy.yaml \
  --extra-config=apiserver.audit-log-path=/etc/ssl/certs/task7/audit.log \
  --extra-config=apiserver.audit-log-maxage=7 \
  --extra-config=apiserver.audit-log-maxbackup=2 \
  --extra-config=apiserver.audit-log-maxsize=50
```

## Проверка Pod Security Admission

```bash
bash verify/verify-admission.sh
```

Скрипт подтверждает, что три файла из `insecure-manifests/` отклоняются, а три файла из `secure-manifests/` успешно запускаются.

## Установка и проверка Gatekeeper

```bash
minikube -p task7 kubectl -- apply -f \
  https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.23.1/deploy/gatekeeper.yaml

bash verify/validate-security.sh
```

Для независимой проверки Gatekeeper скрипт создаёт временный namespace `gatekeeper-test` с уровнем PSA `privileged`. Поэтому отказы в этой проверке формирует именно Gatekeeper, а не Pod Security Admission. Временный namespace удаляется после проверки.

Шаблон `runasnonroot.yaml` проверяет два связанных требования: `runAsNonRoot: true` и `readOnlyRootFilesystem: true`.

## Ожидаемый результат

| Проверка | Результат |
|---|---|
| Небезопасные Pod в `audit-zone` | Отклонены Pod Security Admission |
| Безопасные Pod в `audit-zone` | Запущены |
| Небезопасные Pod в `gatekeeper-test` | Отклонены Gatekeeper |
| Безопасные Pod в `gatekeeper-test` | Запущены |

