#!/usr/bin/env bash
set -euo pipefail
REMOTE="${DEPLOY_REMOTE:-devops}"
REMOTE_DIR='/var/www/devops-site'
SITE_URL="${DEPLOY_URL:-https://devops.local}"
CA_CERT="${DEPLOY_CA_CERT:-${HOME}/devops.crt}"
fail() { printf 'Deploy failed: %s\n' "$*" >&2; exit 1; }
DRY_RUN=false
case "${1:-}" in
    '') [[ $# -eq 0 ]] || fail 'invalid arguments' ;;
    --dry-run) [[ $# -eq 1 ]] || fail 'invalid arguments'; DRY_RUN=true ;;
    *) fail 'usage: scripts/deploy.sh [--dry-run]' ;;
esac
ROOT=$(git rev-parse --show-toplevel) || fail 'not inside a Git repository'
LOCAL_DIR="$ROOT/site/"
[[ -f "$LOCAL_DIR/index.html" ]] || fail 'site/index.html is missing'
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]] || fail 'commit or remove all staged, unstaged and untracked changes first'
[[ -r "$CA_CERT" || "$DRY_RUN" == true ]] || fail "CA certificate is not readable: $CA_CERT"
ARGS=(-avz --delete --chmod=D755,F644 -e 'ssh -o BatchMode=yes -o ConnectTimeout=5')
$DRY_RUN && ARGS+=(--dry-run)
rsync "${ARGS[@]}" "$LOCAL_DIR" "$REMOTE:$REMOTE_DIR/" || fail 'rsync failed'
if $DRY_RUN; then
    echo 'Dry run finished; server content was not changed.'
    exit 0
fi
curl --fail --silent --show-error --connect-timeout 5 --max-time 15 --cacert "$CA_CERT" "$SITE_URL/" >/dev/null || fail 'HTTPS verification failed after synchronization'
printf 'Deployed commit %s\n' "$(git -C "$ROOT" rev-parse --short HEAD)"
