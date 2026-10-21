#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo " [OK]  $desc"
    ((PASS++))
  else
    echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
    ((FAIL++))
  fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1: проверьте, что значение параметра port отлично от 22
check "Порт SSH нестандартный (не 22)" "true" "$( [ "$(sudo sshd -T | awk '/^port/{print $2}')" != "22" ] && echo "true" || echo "false" )"

# TODO 2: проверьте, что значение параметра maxauthtries равно 3
check "MaxAuthTries равно 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: проверьте, что политика по умолчанию для входящего трафика равна deny
check "Политика по умолчанию для входящего трафика - deny" "deny" "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: ' $3>=1000 && $3<65534 {printf " %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
# Проверка синтаксиса Nginx
check "Конфигурация Nginx корректна" "0" "$(sudo nginx -t > /dev/null 2>&1; echo $?)"

# Проверка срока действия сертификата (не менее 30 дней = 2592000 секунд)
check "Сертификат действителен более 30 дней" "0" "$(sudo openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt > /dev/null 2>&1; echo $?)"

# Проверка на отсутствие файлов, доступных для записи всем (должен быть пустой вывод)
check "В каталоге ресурса нет файлов с правом записи для всех" "" "$(sudo find /var/www/devops-site -type f -perm -o+w)"

# Проверка прав на закрытый ключ (должно быть 600)
check "Права на ключ TLS равны 600" "600" "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"

echo "[5] Контейнеризация"
check "Служба Docker активна" "active" "$(systemctl is-active docker)"
check "Контейнер БД в состоянии healthy" "healthy" "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo 'not found')"
check "Порты 5000 и 5432 не прослушиваются на 0.0.0.0" "" "$(sudo ss -tln | grep -E '0.0.0.0:(5000|5432)' || true)"
check "Права файла .env равны 600" "600" "$(stat -c '%a' ~/app/.env 2>/dev/null || echo 'missing')"

echo "----------------------------------------"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
