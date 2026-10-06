#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STACK_DIR="${ROOT}/bloodhound"

command -v podman >/dev/null 2>&1 || {
  printf 'Required command not found: podman\n' >&2
  exit 1
}

case "${1:-}" in
  up)
    test -f "${STACK_DIR}/.env" || cp "${STACK_DIR}/.env.example" "${STACK_DIR}/.env"
    podman compose -f "${STACK_DIR}/docker-compose.yml" up -d
    printf 'BloodHound CE is starting at http://127.0.0.1:8080/ui/login\n'
    printf 'Retrieve the initial password with: %s logs bloodhound\n' "$0"
    ;;
  logs)
    podman compose -f "${STACK_DIR}/docker-compose.yml" logs bloodhound | grep 'Initial'
    ;;
  down)
    podman compose -f "${STACK_DIR}/docker-compose.yml" down
    ;;
  reset)
    podman compose -f "${STACK_DIR}/docker-compose.yml" down --volumes
    ;;
  *)
    printf 'Usage: %s {up|logs|down|reset}\n' "$0" >&2
    exit 2
    ;;
esac
