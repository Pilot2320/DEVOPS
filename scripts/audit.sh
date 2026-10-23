#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0
check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
SSH_PORT="$(sudo sshd -T | awk '/^port/{print $2; exit}')"
check "Порт SSH отличен от 22 (текущий: $SSH_PORT)" "yes" "$([[ "$SSH_PORT" != "22" ]] && echo yes || echo no)"
check "MaxAuthTries равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
check "Политика входящего трафика: deny" "deny" "$(sudo ufw status verbose | grep Default | awk '{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx 2>/dev/null || echo inactive)"
check "Синтаксис конфигурации Nginx корректен" "0" "$(if sudo nginx -t >/dev/null 2>&1; then echo 0; else echo 1; fi)"
check "Сертификат действует ещё минимум 30 дней" "0" "$(if openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then echo 0; else echo 1; fi)"
check "В каталоге ресурса нет файлов с правами записи для всех" "0" "$(find /var/www/devops-site -perm -o+w 2>/dev/null | wc -l)"
check "Права закрытого ключа TLS равны 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null || echo '')"

echo "[5] Контейнеризация"
check "Служба docker активна" "active" "$(systemctl is-active docker 2>/dev/null || echo inactive)"
check "Контейнер СУБД в состоянии healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo '')"
check "Порты 5000 и 5432 не открыты наружу" "0" "$(sudo ss -tln 2>/dev/null | grep -E ':(5000|5432)\b' | grep -v '127\.0\.0\.1' | wc -l)"
check "Файл .env имеет права 600" "600" "$(stat -c '%a' "$HOME/app/.env" 2>/dev/null || echo '')"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
