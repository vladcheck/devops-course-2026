#!/usr/bin/env bash

# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]

set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
fi

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл ${LOCAL_DIR}index.html не найден. Доставка отменена." >&2
    exit 1
fi

# Проверка на незафиксированные изменения (включая добавленные в индекс)
cd "$(git rev-parse --show-toplevel)"
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения. Доставка отменена." >&2
    exit 1
fi

# 3. Синхронизация каталога
# Флаг -e "ssh -o BatchMode=yes -o ConnectTimeout=5" гарантирует, что скрипт не зависнет, запрашивая пароль
echo "Начинаю синхронизацию..."
rsync -avz --delete --chmod=D755,F644 ${DRY_RUN} -e "ssh -o BatchMode=yes -o ConnectTimeout=5" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if [[ -n "${DRY_RUN}" ]]; then
    echo "Пробный запуск (--dry-run) завершен успешно."
    exit 0
fi

# 5. Проверка доступности
echo "Проверка доступности ресурса..."
if ! curl --cacert "${CA_CERT}" -f -s -o /dev/null "${SITE_URL}"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен после деплоя." >&2
    exit 1
fi

# 7. Успешное завершение — вывод короткого хеша коммита
COMMIT_HASH="$(git rev-parse --short HEAD)"
echo "Деплой успешно завершен. Доставлен коммит: ${COMMIT_HASH}"
exit 0
