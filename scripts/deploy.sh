#!/usr/bin/env bash
set -euo pipefail
trap 'echo "Ошибка деплоя" >&2; exit 1' ERR

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${ROOT}/site/"
DRY_RUN=false

if [[ $# -eq 1 && "$1" == "--dry-run" ]]; then
    DRY_RUN=true
elif [[ $# -ne 0 ]]; then
    echo "Использование: scripts/deploy.sh [--dry-run]" >&2
    exit 1
fi

if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Нет site/index.html: доставка отменена" >&2
    exit 1
fi

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "Есть незафиксированные изменения: доставка отменена" >&2
    exit 1
fi

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
OPTIONS=(-avz --delete --chmod=D755,F644
         -e "ssh -o BatchMode=yes -o ConnectTimeout=5")

if "$DRY_RUN"; then
    rsync "${OPTIONS[@]}" --dry-run "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"
    echo "Пробный запуск завершён. Коммит: $COMMIT"
    exit 0
fi

if [[ ! -r "$CA_CERT" ]]; then
    echo "Нет доступного сертификата: $CA_CERT" >&2
    exit 1
fi

rsync "${OPTIONS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"
curl --noproxy '*' --fail --silent --show-error \
    --connect-timeout 5 --max-time 15 \
    --cacert "$CA_CERT" --output /dev/null "$SITE_URL"

echo "Деплой успешен. Коммит: $COMMIT"
