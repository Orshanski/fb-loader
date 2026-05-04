#!/usr/bin/env bash
# Run sonar-scanner against fb-loader with the right env and cwd.
#
# Why this wrapper exists:
# - $SONAR_TOKEN is exported from ~/.zshrc, but Claude Code's Bash tool
#   does not inherit interactive-zsh env. A naive `sonar-scanner -Dsonar.token=$SONAR_TOKEN`
#   sends an empty token and uploads garbage analysis to SonarCloud.
# - sonar-project.properties lives at repo root; running from anywhere else
#   trips "mandatory properties" failure and again wastes a SonarCloud upload.
#
# Usage:
#   ./scripts/sonar-scan.sh                 # scan with last-built coverage
#   ./scripts/sonar-scan.sh --with-coverage # rebuild coverage first, then scan

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "--with-coverage" ]]; then
  shift
  "$REPO_ROOT/scripts/coverage.sh"
fi

# Pull SONAR_TOKEN (and friends) from interactive shell config if not already set.
if [[ -z "${SONAR_TOKEN:-}" && -f "$HOME/.zshrc" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.zshrc" >/dev/null 2>&1 || true
fi

if [[ -z "${SONAR_TOKEN:-}" ]]; then
  echo "ERROR: SONAR_TOKEN is empty. Set it in ~/.zshrc as 'export SONAR_TOKEN=...' or pass it inline." >&2
  exit 1
fi

cd "$REPO_ROOT"
exec sonar-scanner -Dsonar.token="$SONAR_TOKEN" "$@"
