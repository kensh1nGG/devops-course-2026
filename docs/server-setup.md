# Конфигурация виртуальной машины devops-vm

## 1. Параметры машины
VirtualBox, Ubuntu Server 24.04.5 LTS, 2048 МБ RAM,
2 процессора, динамический диск VDI 25 ГБ.
Корневая файловая система ext4 занимает около 23 ГБ, /boot — 2 ГБ.

## 2. Сетевые интерфейсы
- enp0s3: NAT, 10.0.2.15/24, доступ в Интернет.
- enp0s8: Host-only, 192.168.56.102/24, доступ из Windows.
Адреса получены по DHCP. Проверка: ip -brief address.
На Windows в C:\Windows\System32\drivers\etc\hosts добавлена запись:
192.168.56.102 devops.local

## 3. Правило проброса портов
Адаптер 1, NAT, TCP:
127.0.0.1:2222 на Windows → порт 2222 гостевой системы.
Первоначальный гостевой порт 22 изменён после настройки SSH.

## 4. Учётные записи
student — пользователь установки.
devops — административный пользователь, входит в группу sudo.
Вход SSH разрешён только devops, по отдельному ключу Ed25519.
Закрытый ключ находится только на Windows: ~/.ssh/devops_vm.
На сервер передан открытый ключ в /home/devops/.ssh/authorized_keys.
Права ~/.ssh — 700, authorized_keys — 600.

Создание пользователя:
sudo adduser devops
sudo usermod -aG sudo devops

## 5. Служба SSH
Исходный файл сохранён в /etc/ssh/sshd_config.backup.
Настройки размещены в /etc/ssh/sshd_config.d/99-hardening.conf.
В 50-cloud-init.conf закомментирована PasswordAuthentication yes:
первое встретившееся значение имеет приоритет.

ssh.socket отключён, ssh.service включён:
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service

Перед перезапуском:
sudo sshd -t
sudo sshd -T
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd

Действующий сеанс сохраняется до проверки нового подключения.
Вход root и вход без ключа проверены: Permission denied (publickey).

Конфигурация клиента Windows ~/.ssh/config:
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

## 6. Правила межсетевого экрана
Входящий трафик по умолчанию запрещён, исходящий разрешён.
2222/tcp — LIMIT, 80/tcp и 443/tcp — ALLOW, IPv4 и IPv6.
Правила доступа создаются до включения UFW.

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw logging medium

Запрос из Windows к 192.168.56.102:8080 завершился тайм-аутом.
Журнал UFW BLOCK: SRC=192.168.56.1, DST=192.168.56.102,
PROTO=TCP, DPT=8080.

## 7. Снимки состояния
- 01-clean-install — после установки и обновления Ubuntu.
- 02-keys-configured — после настройки пользователя и SSH-ключа.
- 03-ssh-hardened — после защиты SSH, до настройки UFW.

## 8. Имя узла
sudo hostnamectl set-hostname devops-vm

В /etc/hosts:
127.0.1.1 devops-vm.devops.local devops-vm

hostname -f выводит devops-vm.devops.local.

## 9. Проверка SSH-туннеля
На сервере:
python3 -m http.server 8080 --bind 127.0.0.1

На Windows:
ssh -L 9090:127.0.0.1:8080 -N devops

Через http://127.0.0.1:9090 ресурс доступен.
Между Windows и сервером трафик проходит внутри SSH на порту 2222.
После проверки HTTP-сервер и туннель остановлены через Ctrl+C.

## 10. Аудит
scripts/audit.sh проверяет SSH и UFW.
Исправная конфигурация: 6 проверок пройдено, код 0.
При временном MaxAuthTries 10: одна ошибка, код 1.
После восстановления MaxAuthTries 3: код 0.

## 11. Содержимое 99-hardening.conf

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

## Веб-сервер

Пакет: nginx. Установка:
sudo apt -o Acquire::ForceIPv4=true install -y nginx

Конфигурация ресурса: /etc/nginx/sites-available/devops-site.
Ресурс активирован ссылкой в /etc/nginx/sites-enabled/.
Ссылка sites-enabled/default удалена, исходная конфигурация сохранена.

Каталог ресурса: /var/www/devops-site.
Владелец: devops:devops. Права каталогов 755, файлов 644.
www-data может читать файлы, но не изменять их.

HTTP на порту 80 перенаправляется кодом 301 на HTTPS.
HTTPS: порт 443, имя devops.local, TLS 1.2 и TLS 1.3.
Сертификат: /etc/ssl/certs/devops.crt, root:root, 644.
Закрытый ключ: /etc/ssl/private/devops.key, root:root, 600.

Формирование сертификата сроком на 365 дней:
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"

Применение конфигурации:
sudo nginx -t && sudo systemctl reload nginx

Журналы ресурса:
/var/log/nginx/devops-site.access.log
/var/log/nginx/devops-site.error.log

Доставка из WSL: scripts/deploy.sh.
Сценарий проверяет чистоту Git, наличие index.html,
нормализует права через rsync и проверяет HTTPS с --cacert.
Закрытый ключ TLS в репозитории не хранится.

Снимок после настройки HTTPS: 04-nginx-https.

## 9. Контейнеризация

Docker Engine установлен из официального репозитория Docker для Ubuntu.
Пакеты: docker-ce, docker-ce-cli, containerd.io,
docker-buildx-plugin, docker-compose-plugin.
Проверенные версии: Docker Engine 29.10.0, Compose v5.8.0.
Пользователь devops входит в группу docker.

Исходные файлы находятся в app/ репозитория.
Рабочий проект на сервере: /home/devops/app.
Файл /home/devops/app/.env содержит случайный пароль PostgreSQL,
имеет права 600 и исключён из Git и контекста сборки.
Шаблон переменных: app/.env.example.

Образ devops-app:1.1 основан на python:3.12-slim.
Приложение запускается от пользователя app через Gunicorn.
Из-за ошибки DNS внутри сборки использована команда:
docker build --network=host --progress=plain -t devops-app:1.1 .

Запуск на сервере из ~/app:
docker compose up -d --no-build

Сервисы: app и db (postgres:16-alpine).
Сеть проекта: app_backend.
Именованный том PostgreSQL: app_db_data.
Приложение опубликовано только на 127.0.0.1:5000.
Порт PostgreSQL 5432 на хосте не опубликован.
Запуск приложения ожидает healthy-состояния базы.

docker compose down сохраняет том и счётчик.
docker compose down -v удаляет данные; использовалось только
для учебного теста сброса счётчика.

В HTTPS-блок /etc/nginx/sites-available/devops-site добавлено:

    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

Статическая главная страница сохранена.
Приложение: https://devops.local/app/
Проверка здоровья: https://devops.local/app/health

При остановке app Nginx возвращает 502, журнал содержит
connect() failed (111: Connection refused).
После docker compose start app ответ восстанавливается до 200.

Раздел [5] scripts/audit.sh проверяет Docker, здоровье базы,
локальную публикацию портов и права .env.
Проверены коды 0 и 1 при временной публикации 5000 на всех адресах.
Создан снимок VirtualBox 05-docker-compose.
