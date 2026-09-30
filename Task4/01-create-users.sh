#!/usr/bin/env bash
set -euo pipefail

certificate_dir="./certs"
mkdir -p "$certificate_dir"

users=(
  "admin-user:cluster-admins"
  "operator-user:application-operators"
  "viewer-user:cluster-viewers"
)

for item in "${users[@]}"; do
    IFS=: read -r username group <<< "$item"
    csr_name="${username}-csr"
    echo "Пользователь: ${username}, Группа: ${group}"

    openssl genrsa \
        -out "$certificate_dir/${username}.key" 2048
    
    MSYS_NO_PATHCONV=1 openssl req \
        -new \
        -key "$certificate_dir/${username}.key" \
        -out "$certificate_dir/${username}.csr" \
        -subj "/CN=${username}/O=${group}"

    
    csr_data=$(base64 -w 0 "$certificate_dir/${username}.csr")

    echo "Подготовлен запрос Kubernetes: ${csr_name}"

    minikube kubectl -- delete certificatesigningrequest \
        "$csr_name" \
        --ignore-not-found
    
    minikube kubectl -- apply -f - <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${csr_name}
spec:
  request: ${csr_data}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 31536000
  usages:
    - client auth
EOF

    minikube kubectl -- certificate approve "$csr_name"

    certificate_data=""

    for attempt in {1..10}; do
        certificate_data=$( 
            minikube kubectl -- get certificatesigningrequest \
                "$csr_name" \
                -o jsonpath='{.status.certificate}'
        )

        if [[ -n "$certificate_data" ]]; then
            break
        fi

        sleep 1
    done

    if [[ -z "$certificate_data" ]]; then 
        echo "Не удалось получить сертификат для ${username}"
        exit 1
    fi

    printf '%s' "$certificate_data" |
        base64 -d > "$certificate_dir/${username}.crt"

minikube kubectl -- config set-credentials "$username" \
    --client-key="$certificate_dir/${username}.key" \
    --client-certificate="$certificate_dir/${username}.crt" \
    --embed-certs=true

minikube kubectl -- config set-context "${username}-context" \
    --cluster=minikube \
    --user="$username" \
    --namespace=propdevelopment

done
echo "Пользователи и контексты созданы"
