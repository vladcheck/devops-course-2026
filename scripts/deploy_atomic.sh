#!/usr/bin/env bash

# Атомарный деплой с возможностью отката
# Использование: scripts/deploy_atomic.sh [--dry-run | --rollback]

set -euo pipefail

REMOTE="devops"
REMOTE_BASE="/var/www/devops-site"
RELEASES_DIR="$REMOTE_BASE/releases"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
NEW_RELEASE="$RELEASES_DIR/$TIMESTAMP"

# 1. Обработка аргумента --rollback
if [[ "${1:-}" == "--rollback" ]]; then
    echo "Выполняется откат на предыдущую версию..."
    ssh "$REMOTE" "cd $REMOTE_BASE && prev=\$(ls -1dt releases/* | head -n 2 | tail -n 1) && ln -sfn \$prev current_tmp && mv -T current_tmp current && echo \"Переключено на \$prev\""
    exit 0
fi

# 2. Проверки
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then echo "ОШИБКА: Нет index.html" >&2; exit 1; fi
if [[ -n "$(git status --porcelain)" ]]; then echo "ОШИБКА: Есть незафиксированные изменения" >&2; exit 1; fi

# 3. Обработка --dry-run
if [[ "${1:-}" == "--dry-run" ]]; then
    echo "[DRY-RUN] Будет создана папка: $NEW_RELEASE"
    rsync -avz --dry-run --chmod=D755,F644 --link-dest="$REMOTE_BASE/current" --rsync-path="mkdir -p $NEW_RELEASE && rsync" "$LOCAL_DIR" "$REMOTE:$NEW_RELEASE/"
    ssh "$REMOTE" "rm -rf $NEW_RELEASE"
    exit 0
fi

# 4. Реальный деплой (SSH-соединение №1)
echo "Доставка файлов в $NEW_RELEASE..."
# --rsync-path создает папку и запускает rsync в одном соединении
if ! rsync -avz --chmod=D755,F644 --link-dest="$REMOTE_BASE/current" --rsync-path="mkdir -p $NEW_RELEASE && rsync" "$LOCAL_DIR" "$REMOTE:$NEW_RELEASE/"; then
    echo "ОШИБКА: rsync не удался!" >&2
    exit 1
fi

# 5. Атомарное переключение (SSH-соединение №2)
echo "Переключение ссылки current..."
ssh "$REMOTE" "cd $REMOTE_BASE && ln -sfn releases/$TIMESTAMP current_tmp && mv -T current_tmp current && ls -1dt releases/* | tail -n +6 | xargs rm -rf"

# 6. Проверка доступности
echo "Проверка доступности ${SITE_URL}..."
if ! curl -f -s --cacert "${CA_CERT}" "${SITE_URL}" > /dev/null; then
    echo "ОШИБКА: Ресурс недоступен!" >&2
    exit 1
fi

echo "УСПЕХ: Атомарный деплой завершен. Версия: $TIMESTAMP"
exit 0
