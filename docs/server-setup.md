# Конфигурация виртуальной машины devops-vm

Студент: Заботкин Данила Викторович, ЭФБО-17-24. Номер по списку: 11.
Дата работы: 28–29.10.2026. Документ описывает воспроизводимую конфигурацию;
прохождение отдельных контрольных проверок фиксируется в отчётах.

## 1. Параметры машины

VirtualBox 7.2.22; Ubuntu Server 24.04 LTS; RAM 2048 МБ, 2 CPU,
динамический VDI 25 ГБ. Каталог VM на Windows: `D:\DevOpsLab\devops-vm`.
Система развёрнута из официального Ubuntu Server cloud image (VMDK) с NoCloud,
без графической оболочки; это импорт готовой ОС вместо ручного прохождения ISO-установщика.
Источник: https://cloud-images.ubuntu.com/noble/current/ . Контрольная сумма проверена.

На этом Windows-хосте активен Hyper-V для существующего WSL2. При 2 CPU загрузка
зависала на `Loading essential drivers`: benchmark модуля raid6_pq. Для данной VM
с ext4 и без RAID применён `sudo bash scripts/vbox-guest-workaround.sh`: запрет
ненужных btrfs/raid456/raid6_pq и пересборка initramfs/GRUB. Повторная загрузка:
15,611 с по systemd-analyze. Настройки Hyper-V хоста не изменялись.
Диагностика: https://github.com/VirtualBox/virtualbox/issues/726 .

## 2. Сетевые интерфейсы

| Интерфейс | Тип | Адрес | Назначение |
|---|---|---|---|
| enp0s3 | NAT | 10.0.2.15/24, DHCP | Интернет и репозитории пакетов |
| enp0s8 | Host-only | 192.168.56.101/24, статический | Доступ с хоста к SSH/HTTP/HTTPS |
| Host-only адаптер Windows | Host-only | 192.168.56.1/24 | Хост в учебном сегменте |

Статический адрес второго интерфейса выбран, чтобы записи hosts сохранялись после перезапуска.
На Windows в `C:\Windows\System32\drivers\etc\hosts`, на Linux-клиенте в `/etc/hosts`:

```text
192.168.56.101 devops.local stats.devops.local
```

## 3. Правило проброса портов

Начальная конфигурация: `127.0.0.1:2222 -> guest:22`.
После усиления SSH: `127.0.0.1:2222 -> guest:2222`.
С хоста также доступно прямое соединение с `192.168.56.101:2222`.
В WSL2 используется прямой Host-only адрес, так как его 127.0.0.1 относится к WSL2.

## 4. Учётные записи

`student` — исходная учётная запись, входит в sudo.
`devops` — рабочая учётная запись, группы sudo и после ПР7 docker; вход по отдельному Ed25519-ключу.
Пароли, приватные ключи и .env в репозитории отсутствуют. В sudo используется пароль соответствующей учётной записи.
Права `/home/devops/.ssh` — 700, `authorized_keys` — 600, владелец devops.

SSH-конфигурация Windows:

```sshconfig
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Для WSL заменяется только HostName на `192.168.56.101`; ключ хранится в Linux-home с правами 600.
Перед первым подключением сверяется SHA256-отпечаток серверного ключа с доверенной консолью.

## 5. Служба SSH

Конфигурация: `/etc/ssh/sshd_config.d/99-hardening.conf`, эталонная копия основного файла:
`/etc/ssh/sshd_config.backup`. Содержимое дополняющего файла хранится в `config/99-hardening.conf`.
Порт 2222; PermitRootLogin no; PasswordAuthentication no; KbdInteractiveAuthentication no;
PubkeyAuthentication yes; PermitEmptyPasswords no; MaxAuthTries 3; LoginGraceTime 30;
AllowUsers devops; X11Forwarding no; ClientAliveInterval 300; ClientAliveCountMax 2.

Файлы sshd_config.d читаются по имени; для скалярных параметров действует первое значение.
Строка PasswordAuthentication в файле cloud-init должна быть закомментирована,
иначе более ранний файл может перекрыть 99-hardening.conf. Проверка: `sudo sshd -T`.
В Ubuntu 24.04 отключена ssh.socket и включена ssh.service, чтобы порт задавал sshd:

```bash
sudo sshd -t
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh.service
sudo ss -tlnp | grep sshd
```

Старое соединение сохраняется до успешного входа по новому порту в отдельной сессии.

## 6. Правила межсетевого экрана

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw status verbose
```

Итог: входящие deny, исходящие allow; SSH 2222/tcp LIMIT, HTTP 80 и HTTPS 443 ALLOW.
Правила для приложений 5000, 8003 и баз 5432, 6379 не добавляются.
UFW проверяется также фактическими запросами: публикации Docker могут проходить через FORWARD.

## 7. Снимки состояния и восстановление

Контрольные точки: 01-clean-install (ОС и student), 02-keys-configured (devops и ключ),
03-ssh-hardened (защита SSH), 04-nginx-https (HTTPS), 05-docker-compose (Compose),
06-before-kr2 (до контрольной), 07-kr2 (результат контрольной).
Снимки 01–04 созданы и проверены 29.10.2026. Восстановление из 01-clean-install
с повторной настройкой учётной записи, SSH, UFW и аудитом 9/9 заняло 125,2 с.
После восстановления ветка снимков 04 и далее начинается от 01; снимки 02–03 сохранены отдельно.

Для восстановления с 01-clean-install:

1. Учесть, что снимок возвращает и проброс на гостевой порт 22; войти как student.
   Этот ранний снимок ещё без обхода ошибки RAID6. При зависании на загрузке выполнить
   на Windows `VBoxManage controlvm devops-vm pause`, затем `... resume`;
   при необходимости повторить при следующем зависшем benchmark. После входа
   применить описанный в разделе 1 скрипт внутри VM. Приватные ключи не переносить в Git.
2. Создать devops: `sudo adduser devops`, `sudo usermod -aG sudo devops`.
3. Разместить публичный ключ в `/home/devops/.ssh/authorized_keys`, назначить 700/600 и владельца devops.
4. Проверить вход devops по ключу до отключения паролей.
5. Создать резервную копию sshd_config, перенести `config/99-hardening.conf`, устранить более раннюю PasswordAuthentication из cloud-init.
6. Выполнить sshd -t, отключить ssh.socket, включить и перезапустить ssh.service.
7. В VirtualBox изменить гостевой порт NAT с 22 на 2222; проверить новую сессию devops, сохраняя старую.
8. Выполнить правила из раздела 6. В `/etc/hosts` VM задать `127.0.1.1 devops-vm.devops.local devops-vm`.
9. Выполнить `AUDIT_STAGE=5 scripts/audit.sh`; код возврата должен быть 0.

## 8. Веб-сервер

Пакет nginx из Ubuntu. Ресурс: `/etc/nginx/sites-available/devops-site`, ссылка в sites-enabled.
Стандартная ссылка default отключается. Конфигурация в `config/devops-site.conf`.
Каталог `/var/www/devops-site`, владелец devops:devops, каталоги 755, файлы 644.
Сертификат `/etc/ssl/certs/devops.crt` (644), ключ `/etc/ssl/private/devops.key` (root, 600).

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key -out /etc/ssl/certs/devops.crt \
  -subj '/CN=devops.local' -addext 'subjectAltName=DNS:devops.local'
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt
sudo nginx -t && sudo systemctl reload nginx
```

Сертификат передаётся клиенту через проверенный SSH в `~/devops.crt`; приватный ключ VM не покидает.
HTTP возвращает 301 на HTTPS. HSTS для учебного самоподписанного сертификата не включается.
`scripts/deploy.sh` запускается в любом каталоге репозитория, отвергает грязное дерево и отсутствие index,
использует один rsync с BatchMode, --delete и --chmod, затем curl --cacert. Первый запуск — --dry-run.
Аудит этапа: `AUDIT_STAGE=6 scripts/audit.sh`. Проверка завышенного порога сертификата:
`AUDIT_STAGE=6 AUDIT_CERT_SECONDS=40000000 scripts/audit.sh` (ожидается код 1).

## 9. Контейнеризация

Установка Docker Engine из официального APT-репозитория, не docker.io: `sudo scripts/install-docker.sh`.
Проверенные версии: Engine 29.9.2, Compose v5.6.1. После включения devops в docker требуется новое соединение.
Для hello-world Docker Hub выдал сетевую ошибку CDN; успешный запуск выполнен через
официально описанный публичный кэш `mirror.gcr.io/library/hello-world:latest`.
Источник: https://docs.cloud.google.com/artifact-registry/docs/pull-cached-dockerhub-images .
Образы python:3.12-slim и postgres:16-alpine загружены непосредственно из Docker Hub.
Проект на VM: `/home/devops/app`; пароль PostgreSQL хранится только в `.env` с правами 600.
Доставка `rsync -avz --delete --exclude=.env app/ devops:app/`, сначала с --dry-run.
Сервисы app и db, сеть backend, том db_data; app опубликован только на 127.0.0.1:5000, db не опубликован.
Передача `/app/` через Nginx к `http://127.0.0.1:5000/` убирает префикс /app/.
Оба сервиса имеют restart: unless-stopped; db healthcheck pg_isready, app ждёт service_healthy.
Аудит этапа: `AUDIT_STAGE=7 scripts/audit.sh`.

## 10. Контрольная работа №2

Вариант 3: `stats.devops.local`, порт 8003, ветка `kr2/variant-3` отдельного репозитория devops-kr2.
Проект на VM: `/home/devops/kr2`; Redis 7 Alpine, сеть backend, том redis_data в /data, включён AOF.
Действующий пароль генерируется только на VM, файл .env имеет права 600 и исключён из Git и образа.
App опубликован только на 127.0.0.1:8003, Redis не публикуется.
Отдельная конфигурация Nginx `/etc/nginx/sites-available/kr2`, сертификат `/etc/ssl/certs/kr2.crt`
с SAN stats.devops.local и ключ `/etc/ssl/private/kr2.key` (root, 600).
Конфигурация devops-site и правила UFW при добавлении КР2 не изменяются.
Для полного контроля: `AUDIT_STAGE=8 scripts/audit.sh`. PR КР2 не сливается до защиты.
