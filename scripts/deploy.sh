#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

# 1. Проверка аргументов
DRY_RUN=""
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN="--dry-run"
elif [[ -n "${1:-}" ]]; then
    echo "Ошибка: неизвестный аргумент: $1" >&2
    exit 1
fi

# 2. Проверка требования 4 (наличие index.html)
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: Файл ${LOCAL_DIR}index.html отсутствует!" >&2
    exit 1
fi

# 3. Проверка требования 5 (отсутствие незафиксированных изменений в Git)
if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: В репозитории есть незафиксированные изменения!" >&2
    exit 1
fi

# 4. Доставка через rsync
SSH_CMD="ssh -o BatchMode=yes -o ConnectTimeout=5"
rsync -avz --delete --chmod=D755,F644 ${DRY_RUN} -e "${SSH_CMD}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 5. Если dry-run, завершаем с кодом 0 без проверки доступности
if [[ -n "${DRY_RUN}" ]]; then
    echo "Тестовый запуск (--dry-run) успешно завершён."
    exit 0
fi

# 6. Проверка доступности ресурса по HTTPS
if ! curl -fsS --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
    echo "Ошибка: Ресурс ${SITE_URL} недоступен!" >&2
    exit 1
fi

# 7. Успех: вывод короткого хеша коммита
COMMIT_HASH="$(git rev-parse --short HEAD)"
echo "Деплой успешно выполнен. Хеш коммита: ${COMMIT_HASH}"
exit 0