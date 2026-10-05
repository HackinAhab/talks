#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAMES=(bhk-demo bhk-demo-2)
KIND_CONFIGS=(kind.yaml kind-2.yaml)
MANIFESTS=(node-path.yaml secret-path.yaml)
HOST_PORTS=(8081 8082)
OUTPUT_DIR="${ROOT}/output"
BHK_BIN="${BHK_BIN:-bloodhound-kube}"
BLOODHOUND_TOKEN_ID='dd7ac1e1-57b4-4038-83fb-8db56d7f7429'
BLOODHOUND_TOKEN_KEY='5GSp+1w1laCsoHj6U95WqK8flZ6Z/29cc/t2kFEWbnp+yd1WlkTfhg=='

need() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Required command not found: %s\n' "$1" >&2
    exit 1
  }
}

up() {
  need kind
  need kubectl
  local i cluster existing
  existing="$(kind get clusters)"
  for i in "${!CLUSTER_NAMES[@]}"; do
    cluster="${CLUSTER_NAMES[$i]}"
    if [[ $'\n'"${existing}"$'\n' != *$'\n'"${cluster}"$'\n'* ]]; then
      kind create cluster --name "${cluster}" --config "${ROOT}/${KIND_CONFIGS[$i]}" --wait 120s
    fi
    if [[ "${cluster}" == bhk-demo ]]; then
      # Clear the Secret path left by earlier versions of this lab on reused clusters.
      kubectl --context "kind-${cluster}" -n bhk-demo delete \
        rolebinding/public-web-reads-synthetic-secret role/read-synthetic-secret \
        secret/synthetic-api-credential serviceaccount/public-web --ignore-not-found
    fi
    kubectl --context "kind-${cluster}" apply -f "${ROOT}/manifests/${MANIFESTS[$i]}"
    kubectl --context "kind-${cluster}" -n bhk-demo rollout status deployment/public-web --timeout=120s
    printf 'Lab ready (%s): http://127.0.0.1:%s\n' "${cluster}" "${HOST_PORTS[$i]}"
  done
  export_kubeconfigs
}

export_kubeconfigs() {
  umask 077
  mkdir -p "${OUTPUT_DIR}"
  local cluster
  for cluster in "${CLUSTER_NAMES[@]}"; do
    kubectl config view --raw --flatten --minify --context "kind-${cluster}" > "${OUTPUT_DIR}/${cluster}.kubeconfig"
  done
}

verify() {
  need kubectl
  need curl
  local i cluster
  for i in "${!CLUSTER_NAMES[@]}"; do
    cluster="${CLUSTER_NAMES[$i]}"
    kubectl --context "kind-${cluster}" -n bhk-demo get deployment,pod,service
    if [[ "${cluster}" == bhk-demo-2 ]]; then
      kubectl --context "kind-${cluster}" -n bhk-demo get serviceaccount,role,rolebinding,secret
      [[ "$(kubectl --context "kind-${cluster}" auth can-i get secrets/synthetic-api-credential --as system:serviceaccount:bhk-demo:public-web -n bhk-demo)" == yes ]] || {
        printf 'ServiceAccount cannot read the synthetic Secret in %s\n' "${cluster}" >&2
        exit 1
      }
    fi
    curl --fail --silent --show-error "http://127.0.0.1:${HOST_PORTS[$i]}" >/dev/null
  done
  printf 'Lab verification passed.\n'
}

collect() {
  need kubectl
  need "${BHK_BIN}"
  export_kubeconfigs
  # Config paths are relative to demo/, including when this script is called elsewhere.
  (
    cd "${ROOT}"
    "${BHK_BIN}" collect --clusters-config "${ROOT}/clusters.yml"
  )
  local cluster
  for cluster in "${CLUSTER_NAMES[@]}"; do
    printf 'OpenGraph JSON (%s): %s\n' "${cluster}" "${OUTPUT_DIR}/${cluster}.json"
  done
}

upload() {
  need "${BHK_BIN}"
  : "${BLOODHOUND_TOKEN_ID:?Set BLOODHOUND_TOKEN_ID to an API token ID}"
  : "${BLOODHOUND_TOKEN_KEY:?Set BLOODHOUND_TOKEN_KEY to an API token key}"
  local cluster
  for cluster in "${CLUSTER_NAMES[@]}"; do
    if [[ ! -s "${OUTPUT_DIR}/${cluster}.json" ]]; then
      printf 'Missing collection for %s; run %s collect first.\n' "${cluster}" "$0" >&2
      exit 1
    fi
  done
  "${BHK_BIN}" upload \
    --url "${BLOODHOUND_URL:-http://127.0.0.1:8080}" \
    --enable-extension \
    --reset \
    --token-id "${BLOODHOUND_TOKEN_ID}" \
    --token-key "${BLOODHOUND_TOKEN_KEY}"
  "${BHK_BIN}" upload \
    --url "${BLOODHOUND_URL:-http://127.0.0.1:8080}" \
    --schema-file "${ROOT}/schema.json" \
    --queries-file "${ROOT}/queries.json" \
    --cluster "${CLUSTER_NAMES[0]}" \
    --token-id "${BLOODHOUND_TOKEN_ID}" \
    --token-key "${BLOODHOUND_TOKEN_KEY}"
  for cluster in "${CLUSTER_NAMES[@]}"; do
    "${BHK_BIN}" upload \
      --url "${BLOODHOUND_URL:-http://127.0.0.1:8080}" \
      --upload-file "${OUTPUT_DIR}/${cluster}.json" \
      --cluster "${cluster}" \
      --token-id "${BLOODHOUND_TOKEN_ID}" \
      --token-key "${BLOODHOUND_TOKEN_KEY}"
  done
}

down() {
  need kind
  local cluster
  for cluster in "${CLUSTER_NAMES[@]}"; do
    kind delete cluster --name "${cluster}"
  done
}

case "${1:-}" in
  up) up ;;
  verify) verify ;;
  collect) collect ;;
  upload) upload ;;
  down) down ;;
  *)
    printf 'Usage: %s {up|verify|collect|upload|down}\n' "$0" >&2
    exit 2
    ;;
esac
