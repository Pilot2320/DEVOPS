# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины

- Имя: devops-vm
- ОС: Ubuntu Server 25.04 (64-bit)
- Оперативная память: 2048 МБ
- Процессоры: 2 ядра
- Диск: 25 ГБ, динамически расширяемый

## 2. Сетевые интерфейсы

| Адаптер | Тип | Интерфейс | Адрес | Назначение |
|---|---|---|---|---|
| 1 | NAT | enp0s3 | 10.0.2.15 | доступ в Интернет, пакеты |
| 2 | Host-only | enp0s8 | <192.168.56.101> | доступ с хоста |

## 3. Правило проброса портов

Адаптер 1 (NAT): имя `ssh`, TCP, адрес хоста 127.0.0.1, порт хоста 2222,
порт гостя 2222 (изначально 22, изменён после настройки sshd).

## 4. Учётные записи

| Имя | Группы | Аутентификация |
|---|---|---|
| student | student, sudo | пароль (только консоль ВМ; по SSH запрещён через AllowUsers) |
| devops | devops, sudo | SSH только по ключу ed25519 (`devops_vm.pub` в authorized_keys) |

Ключ на хосте: `ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm`

## 5. Служба SSH

- Порт: 2222
- Основной файл `/etc/ssh/sshd_config` не изменялся, копия: `sshd_config.backup`
- Дополняющий файл: `/etc/ssh/sshd_config.d/99-hardening.conf`:

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

- Конфликтующая строка `PasswordAuthentication yes` в `50-cloud-init.conf` закомментирована (если файл есть).
- Сокет-активация отключена, иначе порт остаётся 22.

## 6. Правила межсетевого экрана

- Политики: deny (incoming), allow (outgoing)
- Правила: 2222/tcp LIMIT (SSH), 80/tcp ALLOW (HTTP), 443/tcp ALLOW (HTTPS)
- Логирование: medium
- Правило для порта 22 не создаётся (не использовать `ufw allow ssh`)

## 7. Снимки состояния

| Наименование | Момент создания | Состояние |
|---|---|---|
| 01-clean-install |  чистая установка, пользователь student, SSH на порту 22 |
| 02-keys-configured |  создан devops, вход по ключу, ~/.ssh/config на хосте |
| 03-ssh-hardened |  SSH на 2222, парольный вход отключён |

## 8. Порядок восстановления с нуля (после отката на 01-clean-install)

1. Войти как student (консоль VirtualBox или `ssh student@127.0.0.1 -p 2222`,
   проброс на этом этапе: гость 22).
2. `sudo adduser devops && sudo usermod -aG sudo devops`
3. На хосте сгенерировать ключ (раздел 4) и скопировать его на ВМ командой
   `ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1`
   (в PowerShell эквивалент через `type ... | ssh ...`).
4. Войти как devops, создать `99-hardening.conf` (раздел 5), закомментировать
   `PasswordAuthentication yes` в `50-cloud-init.conf`, проверить `sudo sshd -t`.
5. `sudo systemctl disable --now ssh.socket && sudo systemctl enable --now ssh.service && sudo systemctl restart ssh`
6. В VirtualBox сменить порт гостя в пробросе с 22 на 2222.
7. Проверить вход в новом терминале (`ssh devops`), старую сессию не закрывать.
8. UFW: `default deny incoming`, `default allow outgoing`, разрешить 2222, 80, 443,
   затем `ufw enable`, затем заменить правило 2222 на `ufw limit 2222/tcp`.
9. Hostname: `sudo hostnamectl set-hostname devops-vm` и запись
   `127.0.1.1 devops-vm.devops.local devops-vm` в `/etc/hosts`.
10. На хосте: `<192.168.56.101> devops.local` в файл hosts.