#!/usr/bin/env bash

set -euo pipefail

kubectl_bin="${KUBECTL:-kubectl}"

client_id="${OIDC_CLIENT_ID:-aml}"
oauth2client_name="${OAUTH2CLIENT_NAME:-mfwwzs7sttsiiirdeu}"
client_name="${OIDC_CLIENT_NAME:-Alauda AI}"
client_secret="${OIDC_CLIENT_SECRET:-TjA3xK9mP2vR8wL5nQ6sF1hG4dY7uB0c}"
client_secret_name="${OIDC_CLIENT_SECRET_NAME:-aml-oidc-secret}"
namespace="${OIDC_NAMESPACE:-cpaas-system}"

dry_run="${DRY_RUN:-false}"
kubectl_apply=("${kubectl_bin}" apply -f -)
if [[ "${dry_run}" == "true" ]]; then
  kubectl_apply=(cat)
fi

cluster_name="${CLUSTER_NAME:-}"

logo="${LOGO:-data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNjEiIGhlaWdodD0iMTU2Ij48ZyBmaWxsPSJub25lIiBmaWxsLXJ1bGU9ImV2ZW5vZGQiPjxwYXRoIGZpbGw9IiNCM0Q3RkMiIGQ9Ik01OS40NTYgNjEuMDU2YzguODM2IDAgMTYgNy4xNjMgMTYgMTZzLTcuMTY0IDE2LTE2IDE2LTE2LTcuMTY0LTE2LTE2IDcuMTYzLTE2IDE2LTE2TTE3LjUgNjUuODU2YzYuMzgyIDAgMTEuNTU2IDUuMTczIDExLjU1NiAxMS41NTVTMjMuODgyIDg4Ljk2NyAxNy41IDg4Ljk2NyA1Ljk0NCA4My43OTMgNS45NDQgNzcuNDEgMTEuMTE4IDY1Ljg1NiAxNy41IDY1Ljg1NiIvPjxwYXRoIGZpbGw9IiNGRkYiIGQ9Ik0xNy41IDcwLjE4OWE3LjIyMiA3LjIyMiAwIDEgMSAwIDE0LjQ0NCA3LjIyMiA3LjIyMiAwIDAgMSAwLTE0LjQ0NCIvPjxwYXRoIGZpbGw9IiNCM0Q3RkMiIGQ9Ik0yNS45MjcgNjkuNTQycTUuNjUyIDUuNDk2IDEwLjIxMyA1LjQ5NnQxMS44NTMtOS4xNDV2MjIuMzM0cS04LjI2LTcuODU1LTExLjg1My03Ljg1NXQtMTAuMjEzIDQuOTM2ek01MiAxMDBhOSA5IDAgMSAxLTE4IDAgOSA5IDAgMCAxIDE4IDBNNTIgNTRhOSA5IDAgMSAxLTE4IDAgOSA5IDAgMCAxIDE4IDBNMzguMjIyIDIxYTYgNiAwIDEgMS0xMiAwIDYgNiAwIDAgMSAxMiAwTTM4LjIyMiAxMzNhNiA2IDAgMSAxLTEyIDAgNiA2IDAgMCAxIDEyIDBNNzUgMTFhNyA3IDAgMSAxLTE0IDAgNyA3IDAgMCAxIDE0IDBNNzUgNDlhNyA3IDAgMSAxLTE0IDAgNyA3IDAgMCAxIDE0IDBNNzUgMTQzYTcgNyAwIDEgMS0xNCAwIDcgNyAwIDAgMSAxNCAwTTc1IDEwNGE3IDcgMCAxIDEtMTQgMCA3IDcgMCAwIDEgMTQgME0xMi45MSAzMC45NThDNS45MDIgMzQuMjI2IDIuODcgNDIuNTU2IDYuMTM4IDQ5LjU2M2MzLjI2OCA3LjAwOCAxMS41OTggMTAuMDQgMTguNjA1IDYuNzcyIDcuMDA4LTMuMjY4IDEwLjA0LTExLjU5NyA2Ljc3Mi0xOC42MDUtMy4yNjgtNy4wMDctMTEuNTk4LTEwLjA0LTE4LjYwNS02Ljc3Mk00Ny45NTYgMTkuMjVjLTUuMDYgMi4zNi03LjI1IDguMzc2LTQuODkgMTMuNDM3czguMzc2IDcuMjUgMTMuNDM3IDQuODljNS4wNi0yLjM2IDcuMjUtOC4zNzUgNC44OS0xMy40MzZzLTguMzc2LTcuMjUtMTMuNDM3LTQuODkiLz48cGF0aCBmaWxsPSIjRkZGIiBkPSJNNDkuNTU5IDIyLjY4N0E2LjMyIDYuMzIgMCAxIDAgNTQuOSAzNC4xNGE2LjMyIDYuMzIgMCAwIDAtNS4zNDEtMTEuNDU0Ii8+PHBhdGggZmlsbD0iI0IzRDdGQyIgZD0iTTQyLjYzNyAyNS4yOXEtMi40NSA2LjQ0OC02LjA2NyA4LjEzNS0zLjYxNSAxLjY4Ny0xMi43ODEtMi44N2w4LjI1OSAxNy43MTJxMy42NDUtOS4yODQgNi40OTUtMTAuNjEzIDIuODUtMS4zMyA5LjkyNC4xMzl6TTEyLjkxIDEyMi40NjRjLTcuMDA4LTMuMjY4LTEwLjA0LTExLjU5OC02Ljc3Mi0xOC42MDUgMy4yNjgtNy4wMDggMTEuNTk4LTEwLjA0IDE4LjYwNS02Ljc3MiA3LjAwOCAzLjI2OCAxMC4wNCAxMS41OTggNi43NzIgMTguNjA1LTMuMjY4IDcuMDA4LTExLjU5OCAxMC4wNC0xOC42MDUgNi43NzJNNDcuOTU2IDEzNC4xNzJjLTUuMDYtMi4zNi03LjI1LTguMzc2LTQuODktMTMuNDM3IDIuMzYtNS4wNiA4LjM3Ni03LjI1IDEzLjQzNy00Ljg5IDUuMDYgMi4zNiA3LjI1IDguMzc1IDQuODkgMTMuNDM2cy04LjM3NiA3LjI1MS0xMy40MzcgNC44OTEiLz48cGF0aCBmaWxsPSIjRkZGIiBkPSJNNDkuNTU5IDEzMC43MzZBNi4zMiA2LjMyIDAgMSAxIDU0LjkgMTE5LjI4YTYuMzIgNi4zMiAwIDAgMS01LjM0MSAxMS40NTUiLz48cGF0aCBmaWxsPSIjQjNEN0ZDIiBkPSJNNDIuNjM3IDEyOC4xMzJxLTIuNDUtNi40NDgtNi4wNjctOC4xMzUtMy42MTUtMS42ODYtMTIuNzgxIDIuODdsOC4yNTktMTcuNzEycTMuNjQ1IDkuMjg0IDYuNDk1IDEwLjYxM3Q5LjkyNC0uMTM4eiIvPjxwYXRoIHN0cm9rZT0iIzAwN0FGNSIgc3Ryb2tlLXdpZHRoPSI3IiBkPSJtMTI5IDMwLjU2LTEuMjA3LTYuNDE0QzEyNS41OTMgMTIuNDYzIDExNS4zODkgNCAxMDMuNSA0IDkyLjE3OCA0IDgzIDEzLjE3OCA4MyAyNC41djEwN2MwIDExLjMyMiA5LjE3OCAyMC41IDIwLjUgMjAuNSAxMS40NTYgMCAyMC44NzItOS4wMzcgMjEuMzQzLTIwLjQ4MyIvPjxwYXRoIHN0cm9rZT0iIzAwN0FGNSIgc3Ryb2tlLXdpZHRoPSI3IiBkPSJNMTQ3LjMxIDg1LjA4OWM1Ljk0IDUuMjIzIDkuNjkgMTIuODc5IDkuNjkgMjEuNDExIDAgMTUuNzQtMTIuNzYgMjguNS0yOC41IDI4LjVxLTE1Ljc0IDAtMTkuNjA4LTEwLjE0MSIvPjxwYXRoIHN0cm9rZT0iIzAwN0FGNSIgc3Ryb2tlLXdpZHRoPSI3IiBkPSJNMTI4LjUgMzRjMTUuNzQgMCAyOC41IDEyLjc2IDI4LjUgMjguNVMxNDQuMjQgOTEgMTI4LjUgOTFxLTE1Ljc0IDAtMTkuNjA4LTIuNSIvPjxwYXRoIHN0cm9rZT0iIzAwN0FGNSIgc3Ryb2tlLXdpZHRoPSI3IiBkPSJNMTA3LjQyIDQuMjkyYzEzLjMgMi40MSAyMS41OCAxNC4xOTYgMjEuNTggMjguMTkgMCA3LjgzLTMuMTU3IDE0Ljk0LTguMjY4IDIwLjA5Ii8+PHBhdGggZmlsbD0iIzAwN0FGNSIgc3Ryb2tlPSIjMDA3QUY1IiBzdHJva2Utd2lkdGg9IjciIGQ9Ik05OCAxMjZjMC01LjUyMyA0LjQ3Ny0xMCAxMC0xMHMxMCA0LjQ3NyAxMCAxMC00LjQ3NyAxMC0xMCAxMC0xMC00LjQ3Ny0xMC0xMFpNMTA1IDg5YzAtNS41MjMgNC40NzctMTAgMTAtMTBzMTAgNC40NzcgMTAgMTAtNC40NzcgMTAtMTAgMTAtMTAtNC40NzctMTAtMTBaTTEwOSA1M2MwLTUuNTIzIDQuNDc3LTEwIDEwLTEwczEwIDQuNDc3IDEwIDEwLTQuNDc3IDEwLTEwIDEwLTEwLTQuNDc3LTEwLTEwWiIvPjwvZz48L3N2Zz4=}"

usage() {
  cat <<'EOF'
Usage:
  global-install.sh <cluster-name>

Creates global resources for Alauda AI:
  Secret, OAuth2Client, ProductEntry.

Platform URLs are read from ProductBase/base spec.platformURL and spec.alternativeURLs.
EOF
}

setup_oauth2client() {
  local major
  local minor
  local redirect_uris
  local use_secret_ref
  local urls
  local version
  local exist

  exist="$("${kubectl_bin}" get oauth2client.dex.coreos.com "${oauth2client_name}" -n "${namespace}" -o jsonpath='{.metadata.name}' --ignore-not-found)"
  if [[ -n "${exist}" ]]; then
    echo "OAuth2Client ${oauth2client_name} already exists" >&2
    return 0
  fi

  platform_urls="$("${kubectl_bin}" get productbase.product.alauda.io base -o 'jsonpath={.spec.platformURL}{" "}{.spec.alternativeURLs[*]}' | tr ' ' '\n')"
  prdb_version="$("${kubectl_bin}" get productbase.product.alauda.io base -o 'jsonpath={.spec.version}')"

  urls="$(printf '%s\n' "${platform_urls}" | awk 'NF { sub(/\/+$/, ""); if (!seen[$0]++) print }')"
  redirect_uris="$(printf '%s\n' "${urls}" | awk -v cluster="${cluster_name}" '{ printf "  - \"%s/*\"\n", $0, cluster }')"
  version="${prdb_version#v}"
  major="${version%%.*}"
  minor="${version#*.}"
  minor="${minor%%.*}"
  use_secret_ref=false
  if [[ "${major}" =~ ^[0-9]+$ && "${minor}" =~ ^[0-9]+$ ]] && ((major > 4 || (major == 4 && minor >= 3))); then
    use_secret_ref=true
  fi

  cat <<EOF | "${kubectl_apply[@]}"
apiVersion: "v1"
kind: "Secret"
metadata:
  name: "${client_secret_name}"
  namespace: "${namespace}"
type: "Opaque"
data:
  client-secret: $(echo -n "${client_secret}" | base64)
---
apiVersion: "dex.coreos.com/v1"
kind: "OAuth2Client"
metadata:
  name: "${oauth2client_name}"
  namespace: "${namespace}"
id: "${client_id}"
name: "${client_name}"
secret: "$([[ "${use_secret_ref}" == "true" ]] || printf '%s' "${client_secret}")"
$([[ "${use_secret_ref}" == "true" ]] && printf 'secretRef:\n  name: "%s"\n  key: client-secret\n' "${client_secret_name}")
redirectURIs:
${redirect_uris}
EOF
}

setup_product_entry() {
  cat <<EOF | "${kubectl_apply[@]}"
---
apiVersion: "alauda.io/v1alpha1"
kind: "ProductEntry"
metadata:
  labels:
    cpaas.io/image-fields: "spec.logo"
  name: aml-${cluster_name}
  annotations:
    original-name: '{"zh":"Alauda AI","en":"Alauda AI"}'
spec:
  catalog:
    en: "AI Big Data"
    zh: "AI 大数据"
  description:
    en: "alauda ai"
    zh: "alauda ai"
  displayName:
    en: "Alauda AI"
    zh: "Alauda AI"
  entryTarget: "blank"
  entrypoint: "/clusters/${cluster_name}/aml"
  logo: "${logo}"
  packType: "Integrated"
EOF
}

main() {
  if ! command -v "${kubectl_bin}" >/dev/null 2>&1; then
    echo "${kubectl_bin} is required" >&2
    exit 1
  fi

  cluster_name="${1:-}"
  if [[ -z "${cluster_name}" ]]; then
    echo "cluster-name is required" >&2
    usage >&2
    exit 1
  fi

  setup_oauth2client
  setup_product_entry
}

main "$@"
