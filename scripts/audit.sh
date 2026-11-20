#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK] $desc"
        ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

sudo -v || exit 1
ssh_config=$(sudo /usr/sbin/sshd -T) || exit 1
ufw_status=$(sudo ufw status verbose) || exit 1

echo "Аудит: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"

check "Вход root запрещён" "no" \
    "$(awk '/^permitrootlogin /{print $2}' <<< "$ssh_config")"
check "Парольная аутентификация отключена" "no" \
    "$(awk '/^passwordauthentication /{print $2}' <<< "$ssh_config")"
check "Порт SSH задан и отличается от 22" "yes" \
    "$(awk '/^port /{seen=1; if ($2==22) bad=1} END {print (seen && !bad) ? "yes" : "no"}' <<< "$ssh_config")"
check "MaxAuthTries равен 3" "3" \
    "$(awk '/^maxauthtries /{print $2}' <<< "$ssh_config")"

echo "[2] Межсетевой экран"
check "UFW активен" "active" \
    "$(awk '/^Status:/{print $2}' <<< "$ufw_status")"
check "Входящий трафик по умолчанию запрещён" "deny" \
    "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$ufw_status")"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"

check "Nginx активен" "active" "$(systemctl is-active nginx)"

nginx_ok=no
if sudo nginx -t; then nginx_ok=yes; fi
check "Конфигурация Nginx корректна" "yes" "$nginx_ok"

cert_ok=no
if openssl x509 -in /etc/ssl/certs/devops.crt -noout \
    -checkend "${CERT_MIN_SECONDS:-2592000}"; then
    cert_ok=yes
fi
check "Сертификат действует не менее заданного срока" "yes" "$cert_ok"

permissions_ok=no
if writable=$(find /var/www/devops-site -perm -o+w) &&
   key_mode=$(sudo stat -c '%a' /etc/ssl/private/devops.key) &&
   [[ -z "$writable" && "$key_mode" == "600" ]]; then
    permissions_ok=yes
fi
check "Нет записи для всех, права ключа 600" "yes" "$permissions_ok"


echo "[5] Контейнеризация"
check "Docker активен" "active" "$(systemctl is-active docker)"

check "PostgreSQL healthy" "healthy" \
  "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"

ports_ok=yes
while read -r address; do
    case "$address" in
        127.0.0.1:5000|127.0.0.1:5432) ;;
        *:5000|*:5432) ports_ok=no ;;
    esac
done < <(ss -H -ltn | awk '{print $4}')
check "Порты 5000/5432 доступны только локально" "yes" "$ports_ok"

check "Права .env равны 600" "600" \
  "$(stat -c '%a' "$HOME/app/.env" 2>/dev/null)"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
