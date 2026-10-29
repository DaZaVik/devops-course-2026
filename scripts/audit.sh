#!/usr/bin/env bash
# Run on the target server as devops. No secret values are printed.
set -uo pipefail
export LC_ALL=C
PASS=0; FAIL=0
AUDIT_STAGE="${AUDIT_STAGE:-8}"
[[ "$AUDIT_STAGE" =~ ^[5-8]$ ]] || { echo 'AUDIT_STAGE must be 5, 6, 7 or 8' >&2; exit 1; }
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$desc"; ((PASS+=1))
    else
        printf '  [FAIL] %s (expected: %s; actual: %s)\n' "$desc" "$expected" "$actual"
        ((FAIL+=1))
    fi
}
result() { if "$@" >/dev/null 2>&1; then printf 0; else printf 1; fi; }
printf 'Configuration audit: %s, %s\n' "$(hostname -f)" "$(date -Is)"
echo '[1] SSH'
SSHD=$(sudo /usr/sbin/sshd -T 2>/dev/null) || SSHD=''
ssh_value() { awk -v key="$1" '$1==key {print $2}' <<<"$SSHD"; }
check 'root login disabled' no "$(ssh_value permitrootlogin)"
check 'password authentication disabled' no "$(ssh_value passwordauthentication)"
check 'keyboard-interactive authentication disabled' no "$(ssh_value kbdinteractiveauthentication)"
SSH_PORT=$(ssh_value port)
[[ "$SSH_PORT" =~ ^[0-9]+$ && "$SSH_PORT" -ne 22 ]] && PORT_OK=yes || PORT_OK=no
check 'non-default SSH port' yes "$PORT_OK"
check 'MaxAuthTries' 3 "$(ssh_value maxauthtries)"
check 'AllowUsers' devops "$(ssh_value allowusers)"
echo '[2] Firewall'
UFW=$(sudo ufw status verbose 2>/dev/null) || UFW=''
check 'UFW active' active "$(awk '/^Status:/{print $2}' <<<"$UFW")"
check 'default incoming deny' yes "$(grep -q 'Default: deny (incoming)' <<<"$UFW" && echo yes || echo no)"
check 'SSH rate limit' yes "$(grep -Eq '^2222/tcp[[:space:]]+LIMIT' <<<"$UFW" && echo yes || echo no)"
echo '[3] Accounts'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
if (( AUDIT_STAGE >= 6 )); then
    echo '[4] Web server'
    check 'nginx active' active "$(systemctl is-active nginx 2>/dev/null || true)"
    check 'nginx configuration syntax' 0 "$(result sudo nginx -t)"
    check 'certificate lifetime >= threshold' 0 "$(result openssl x509 -checkend "${AUDIT_CERT_SECONDS:-2592000}" -noout -in /etc/ssl/certs/devops.crt)"
    WRITABLE=$(find /var/www/devops-site -perm -o+w -print 2>/dev/null) || WRITABLE='find failed'
    check 'no world-writable site files or directories' '' "$WRITABLE"
    check 'TLS private key permissions' 600 "$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null || true)"
fi
if (( AUDIT_STAGE >= 7 )); then
    echo '[5] Containers'
    check 'docker active' active "$(systemctl is-active docker 2>/dev/null || true)"
    DB_ID=$(docker compose --project-directory "$HOME/app" ps -q db 2>/dev/null) || DB_ID=''
    check 'PostgreSQL healthy' healthy "$(docker inspect -f '{{.State.Health.Status}}' "$DB_ID" 2>/dev/null || true)"
    BAD_SOCKETS=$(ss -H -ltn | awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127\.0\.0\.1:/ {print $4}')
    check 'ports 5000/5432 not listening externally' '' "$BAD_SOCKETS"
    # Inspect publications too: ss alone misses DNAT when userland-proxy is disabled.
    APP_BIND=$(docker compose --project-directory "$HOME/app" port app 5000 2>/dev/null) || APP_BIND=''
    check 'app publication exactly loopback' '127.0.0.1:5000' "$APP_BIND"
    DB_BIND=$(docker inspect -f '{{json .HostConfig.PortBindings}}' "$DB_ID" 2>/dev/null) || DB_BIND='error'
    [[ "$DB_BIND" == '{}' || "$DB_BIND" == null ]] && DB_PRIVATE=yes || DB_PRIVATE=no
    check 'database has no published ports' yes "$DB_PRIVATE"
    check 'app .env permissions' 600 "$(stat -c '%a' "$HOME/app/.env" 2>/dev/null || true)"
fi
if (( AUDIT_STAGE >= 8 )); then
    echo '[6] Control work 2 - variant 3'
    REDIS_ID=$(docker compose --project-directory "$HOME/kr2" ps -q redis 2>/dev/null) || REDIS_ID=''
    check 'Redis healthy' healthy "$(docker inspect -f '{{.State.Health.Status}}' "$REDIS_ID" 2>/dev/null || true)"
    check 'KR2 publication exactly loopback' '127.0.0.1:8003' "$(docker compose --project-directory "$HOME/kr2" port app 8003 2>/dev/null || true)"
    check 'KR2 .env permissions' 600 "$(stat -c '%a' "$HOME/kr2/.env" 2>/dev/null || true)"
    check 'KR2 certificate lifetime >= 30 days' 0 "$(result openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/kr2.crt)"
    check 'KR2 nginx site enabled' 0 "$(result test -L /etc/nginx/sites-enabled/kr2)"
fi
printf 'Passed: %s; failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
