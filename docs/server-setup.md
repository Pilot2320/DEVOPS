# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
- Имя: devops-vm
- ОС: Ubuntu Server 24.04 / 25.04 (64-bit)
- Оперативная память: 2048 МБ
- Процессоры: 2 ядра
- Диск: 25 ГБ, динамически расширяемый

## 2. Сетевые интерфейсы
| Адаптер | Тип | Интерфейс | Адрес | Назначение |
|---|---|---|---|---|
| 1 | NAT | enp0s3 | 10.0.2.15 | доступ в Интернет, пакеты |
| 2 | Host-only | enp0s8 | 192.168.56.101 | доступ с хоста |

## 3. Правило проброса портов
Адаптер 1 (NAT): имя `ssh`, TCP, адрес хоста 127.0.0.1, порт хоста 2222, порт гостя 2222.

## 4. Учётные записи
| Имя | Группы | Аутентификация |
|---|---|---|
| student | student, sudo | пароль (только консоль ВМ) |
| devops | devops, sudo, docker | SSH только по ключу ed25519 (`devops_vm.pub`) |

## 5. Служба SSH
- Порт: 2222
- Дополняющий файл: `/etc/ssh/sshd_config.d/99-hardening.conf` (запрет root, только ключ, MaxAuthTries 3, AllowUsers devops).

## 6. Правила межсетевого экрана (UFW)
- Политики: deny (incoming), allow (outgoing)
- Правила: `2222/tcp LIMIT`, `80/tcp ALLOW`, `443/tcp ALLOW`

## 7. Веб-сервер (Nginx)
- Пакет: `nginx`
- Конфигурация ресурса: `/etc/nginx/sites-available/devops-site` (активирован через symlink в `/etc/nginx/sites-enabled/devops-site`, дефолтный конфиг удалён).
- Каталог сайта: `/var/www/devops-site` (владелец: `devops:devops`, права каталога: `755`, файлов: `644`).
- Сертификат TLS: `/etc/ssl/certs/devops.crt` (права: `644`, владелец `root`).
- Закрытый ключ TLS: `/etc/ssl/private/devops.key` (права: `600`, владелец `root`).
- Команда выпуска сертификата:
  ```bash
  sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key \
    -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" \
    -addext "subjectAltName=DNS:devops.local"
  ```
- Срок действия: 365 дней (1 год).
- Настройки: редирект HTTP (порт 80) -> HTTPS (порт 443, код 301).

## 8. Обратный прокси-сервер (Reverse Proxy)
- Маршрутизация: секция `location /app/` в блоке HTTPS конфигурации `/etc/nginx/sites-available/devops-site`.
- Проксирует запросы на `http://127.0.0.1:5000/`.
- Заголовки проксирования: `Host $host`, `X-Real-IP $remote_addr`, `X-Forwarded-For $proxy_add_x_forwarded_for`, `X-Forwarded-Proto $scheme`.

## 9. Контейнеризация (Docker & Docker Compose)
- Способ установки Docker Engine: официальный репозиторий Docker (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`). Пакет `docker.io` исключён.
- Участники группы docker: `devops` (запуск контейнеров без `sudo`).
- Расположение проекта: `/home/devops/app/`.
- Переменные окружения: файл `/home/devops/app/.env` (права `600`, исключён из Git через `.gitignore` и из контекста сборки через `.dockerignore`). Содержит случайный пароль базы данных `POSTGRES_PASSWORD`.
- Публикуемые порты: сервис `app` прослушивает строго локальный сокет `127.0.0.1:5000:5000` для изоляции от внешней сети. Порт PostgreSQL `5432` во внешнюю сеть не публикуется.
- Именованные тома: `app_db_data` (сохраняет базу PostgreSQL в `/var/lib/postgresql/data` при перезапуске `docker compose down`).
- Запуск контейнера: процесс `app` работает от непривилегированного пользователя `app` (UID=1001, non-root).

## 10. Снимки состояния
| Наименование | Момент создания | Состояние |
|---|---|---|
| 01-clean-install | Чистая установка | student, SSH на 22 |
| 02-keys-configured | Настройка ключей | пользователь devops, вход по SSH-ключу |
| 03-ssh-hardened | Харденинг SSH | порт 2222, UFW активен |
| 04-nginx-https | Настройка Nginx | Nginx, HTTPS, TLS-сертификат, деплой rsync |
| 05-docker-compose | Контейнеризация | Docker Compose (Flask + PostgreSQL), Reverse Proxy /app/ |

| 05-docker-compose | Контейнеризация | Docker Compose (Flask + PostgreSQL), Reverse Proxy /app/ |
| 04-nginx-https | Настройка Nginx | Nginx, HTTPS, TLS-сертификат, деплой rsync |


## 11. Управление конфигурациями (Ansible)
- **Расположение проекта:** каталог `ansible/` в корне репозитория.
- **Управляющий узел (Control Node):** рабочая станция с ОС Linux / WSL (Ubuntu 24.04), установлены `ansible-core 2.16+` и утилита `sshpass`.
- **Управляемый узел (Managed Node):** виртуальная машина `devops-vm` (IP: `192.168.56.101`, порт `22`, адаптер Host-only).
- **Файлы инвентаря (Inventory):**
  - `inventory/bootstrap.ini`: первичное подключение под учетной записью `student` с интерактивным вводом паролей (`--ask-pass`, `--ask-become-pass`);
  - `inventory/prod.ini`: постоянная эксплуатация под учетной записью `devops` по SSH-ключу (`~/.ssh/devops_vm`) без интерактивного ввода.
- **Учетные записи:**
  - `student`: начальный вход для создания сервисной учетной записи;
  - `devops`: автоматизированный запуск, входит в группы `sudo` (с правилом `NOPASSWD:ALL` в `/etc/sudoers.d/devops`) и `docker`.
- **Структура и зоны ответственности ролей:**
  - `base`: проверка дистрибутива (Ubuntu 24.04 amd64), установка системных утилит и зависимостей модулей (`python3-requests`, `python3-debian`), подключение официального Docker-репозитория (`deb822_repository`) и запуск Docker Engine;
  - `ssh`: создание пользователя `devops`, размещение открытого ключа `devops_vm.pub`, настройка NOPASSWD в `sudoers`, жесткий харденинг в `/etc/ssh/sshd_config.d/00-ansible-hardening.conf` (запрет входа по паролям и под root), правила межсетевого экрана UFW (разрешены порты 22 и 80, incoming deny);
  - `nginx`: установка Nginx, настройка reverse proxy через Jinja2-шаблон `devops-ci-app.conf.j2` на локальный сокет `127.0.0.1:5000`, отключение сайта по умолчанию, двухэтапный handler (проверка `nginx -t` перед `systemctl reload nginx`);
  - `app`: включение `devops` в группу `docker`, безопасное скачивание проверенного образа из GHCR по полному неизменяемому SHA, запуск контейнера `devops-ci-app` с привязкой порта строго к `127.0.0.1:5000:5000`, опрос эндпоинта жизнеспособности через модуль `uri` (ожидание HTTP 200 и `status: ok`).
- **Параметры приложения и реестра контейнеров:**
  - Образ: `ghcr.io/pilot2320/devops-ci-app`;
  - Неизменяемый тег: полный 40-значный SHA коммита из ПР № 10 (`4098ee88f0bcdc3e3349f3ac9dcb623daad57d14`);
  - Локальный сокет контейнера: `127.0.0.1:5000:5000` (защита от прямого обхода Nginx через iptables Docker);
  - Эндпоинт проверки здоровья: `http://127.0.0.1:5000/health`.
- **Команды управления и проверки:**
  - Первичный запуск (bootstrap): `ansible-playbook -i inventory/bootstrap.ini site.yml --ask-pass --ask-become-pass`
  - Повторный запуск (prod): `ansible-playbook site.yml` (обеспечивает идемпотентность, результат `changed=0, failed=0`)
  - Автоматизированный read-only аудит: `ansible-playbook verify.yml` (проверка `sshd -T`, фактов контейнера и HTTP 200 без изменения системы).
