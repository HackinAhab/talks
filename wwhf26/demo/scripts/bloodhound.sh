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
    podman compose --project-directory "${STACK_DIR}" up -d
    printf 'BloodHound CE is starting at http://127.0.0.1:8080/ui/login\n'
    printf 'Retrieve the initial password with: %s logs bloodhound\n' "$0"
    ;;
  logs)
    podman compose --project-directory "${STACK_DIR}" logs bloodhound | grep 'Initial'
    ;;
  down)
    podman compose --project-directory "${STACK_DIR}" down
    ;;
  reset)
    podman compose --project-directory "${STACK_DIR}" down --volumes
    ;;
  *)
    printf 'Usage: %s {up|logs|down|reset}\n' "$0" >&2
    exit 2
    ;;
esac
