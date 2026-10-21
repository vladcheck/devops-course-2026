# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
- **Оперативная память:** 2048 МБ (2 ГБ)
- **Количество ядер процессора:** 2
- **Объём дискового накопителя:** 25 ГБ (динамически расширяемый, корневой раздел LVM занимает 12 ГБ)
- **Операционная система:** Ubuntu Server 24.04.5 LTS (GNU/Linux 6.8.0-146-generic x86_64)

## 2. Сетевые интерфейсы
В VirtualBox настроено два сетевых адаптера:
- **Адаптер 1 (NAT):** интерфейс `enp0s3`, IP-адрес `10.0.2.15/24`. Назначение: обеспечение доступа виртуальной машины в Интернет для установки пакетов и обновлений.
- **Адаптер 2 (Host-only / Виртуальный адаптер хоста):** интерфейс `enp0s8`, IP-адрес `192.168.56.101/24`. Назначение: обеспечение прямого доступа с хостовой системы на виртуальную машину (например, для работы веб-сервера Nginx).

## 3. Правило проброса портов
Для обеспечения доступа к SSH-серверу с хостовой системы настроен проброс портов в настройках Адаптера 1 (NAT):
- **Порт хостовой системы:** 2222
- **Порт гостевой системы:** 2222

## 4. Учётные записи
- **`student`**: создаётся при установке ОС. Входит в группы `student` и `sudo`. Аутентификация: по паролю.
- **`devops`**: создаётся вручную (команда `sudo adduser devops`). Входит в группы `devops` и `sudo`. Аутентификация: исключительно по SSH-ключу (пароль для SSH отключён).
- **Права на ключевой материал:** каталог `/home/devops/.ssh/` имеет права `700`, файл `authorized_keys` — права `600`.

## 5. Служба SSH
- **Порт прослушивания:** 2222
- **Расположение кастомной конфигурации:** `/etc/ssh/sshd_config.d/99-hardening.conf`
- **Изменённые директивы и их значения:**
```text
  Port 2222
  PermitRootLogin no
  PasswordAuthentication no
  PubkeyAuthentication yes
  PermitEmptyPasswords no
  MaxAuthTries 3
  LoginGraceTime 30
  AllowUsers devops
  X11Forwarding no
  ClientAliveInterval 300
  ClientAliveCountMax 2
```
- Особенность: в файле /etc/ssh/sshd_config.d/50-cloud-init.conf строка PasswordAuthentication yes закомментирована, чтобы не переопределять настройки из 99-hardening.conf.

## 6. Правила межсетевого экрана (UFW)
Статус: active

Политики по умолчанию: deny (incoming), allow (outgoing), disabled (routed)

Уровень логирования: medium

Разрешающие правила:

- 80/tcp (ALLOW IN) — для HTTP
- 443/tcp (ALLOW IN) — для HTTPS
- 2222/tcp (LIMIT IN) — для SSH с защитой от брутфорса (блокировка при >6 подключениях за 30 секунд)

## 7. Снимки состояния (VirtualBox)
- 01-clean-install: создан сразу после установки ОС и обновления пакетов.
- 03-ssh-hardened: создан после усиления безопасности SSH и настройки UFW.
- 04-dns-configured: создан после настройки локального доменного имени.

## 8. Локальное доменное имя
FQDN (полное доменное имя) сервера: devops-vm.devops.local

Настройка хоста (Windows): в файл C:\Windows\System32\drivers\etc\hosts добавлена запись 192.168.56.101 devops.local.

## 9. Инструкция по восстановлению (Runbook)
Для восстановления конфигурации с нуля после отката на снимок 01-clean-install выполните следующие шаги:

### Обновление системы:

```bash
sudo apt update && sudo apt upgrade -y
```

### Создание пользователя и настройка прав:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
mkdir -p /home/devops/.ssh
chmod 700 /home/devops/.ssh
echo "ВАШ_ПУБЛИЧНЫЙ_КЛЮЧ_ED25519" >> /home/devops/.ssh/authorized_keys
chmod 600 /home/devops/.ssh/authorized_keys
chown -R devops:devops /home/devops/.ssh
```

### Настройка SSH (Hardening):

Создайте файл /etc/ssh/sshd_config.d/99-hardening.conf с содержимым из раздела 5.
Закомментируйте PasswordAuthentication yes в /etc/ssh/sshd_config.d/50-cloud-init.conf.
Отключите сокет и перезапустите службу:

```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo sshd -t && sudo systemctl restart ssh
```

### Настройка UFW:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw limit 2222/tcp
sudo ufw logging medium
sudo ufw enable
```

### Настройка FQDN:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
```

## 10. Веб-сервер

- **Устанавливаемый пакет:** `nginx` (из стандартного репозитория Ubuntu).
- **Путь к конфигурации ресурса:** `/etc/nginx/sites-available/devops-site` (симлинк в `/etc/nginx/sites-enabled/devops-site`).
- **Каталог ресурса:** `/var/www/devops-site`.
- **Владелец и права:** Владелец `devops:devops`. Права: `755` для каталогов, `644` для файлов.
- **Пути к сертификату и ключу:** Сертификат — `/etc/ssl/certs/devops.crt` (права `644`, владелец `root`); Ключ — `/etc/ssl/private/devops.key` (права `600`, владелец `root`).
- **Команда формирования сертификата:**
  ```bash
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key \
    -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" \
    -addext "subjectAltName=DNS:devops.local"
  ```
- **Срок действия сертификата**: 365 дней.
