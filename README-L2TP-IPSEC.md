# Руководство по настройке L2TP/IPsec VPN сервера на Ubuntu

## Описание

L2TP/IPsec - это комбинация двух протоколов:
- **IPsec** - обеспечивает шифрование и аутентификацию
- **L2TP** - обеспечивает туннелирование трафика

Этот VPN поддерживается нативно в Windows, macOS, iOS и Android без установки дополнительного ПО.

## Быстрая установка

### 1. Скачайте скрипты на ваш VPS

```bash
# Загрузите файлы на сервер
wget https://ваш-сервер/l2tp-ipsec-setup.sh
wget https://ваш-сервер/vpn-management.sh

# Или создайте их вручную, скопировав содержимое
```

### 2. Запустите установку

```bash
chmod +x l2tp-ipsec-setup.sh
sudo ./l2tp-ipsec-setup.sh
```

Скрипт спросит:
- **PSK (Pre-Shared Key)** - общий ключ для IPsec (можно автогенерировать)
- **Имя пользователя** - для VPN подключения
- **Пароль** - для пользователя VPN

### 3. Сохраните выданные учётные данные

После установки вы получите:
- IP адрес сервера
- PSK ключ
- Имя пользователя и пароль
- Инструкции по подключению клиентов

Все данные сохраняются в `/root/vpn-config.txt`

## Ручная установка (пошагово)

### Шаг 1: Установка пакетов

```bash
apt-get update
apt-get install -y strongswan xl2tpd libstrongswan-standard-plugins \
    libstrongswan-extra-plugins iptables iptables-persistent
```

### Шаг 2: Включение IP forwarding

```bash
cat > /etc/sysctl.d/99-vpn.conf <<EOF
net.ipv4.ip_forward = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF

sysctl -p /etc/sysctl.d/99-vpn.conf
```

### Шаг 3: Настройка IPsec

Создайте `/etc/ipsec.conf`:

```
config setup
    charondebug="ike 2, knl 2, cfg 2"
    uniqueids=never

conn L2TP-PSK
    authby=secret
    auto=add
    keyingtries=3
    type=transport
    left=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    ike=aes256-sha2_256-modp2048,aes128-sha1-modp1024!
    esp=aes256-sha2_256,aes128-sha1!
    forceencaps=yes
```

Создайте `/etc/ipsec.secrets`:

```bash
echo "%any %any : PSK \"ваш_секретный_ключ\"" > /etc/ipsec.secrets
chmod 600 /etc/ipsec.secrets
```

### Шаг 4: Настройка L2TP

Создайте `/etc/xl2tpd/xl2tpd.conf`:

```
[global]
port = 1701
auth file = /etc/ppp/chap-secrets

[lns default]
ip range = 192.168.42.10-192.168.42.250
local ip = 192.168.42.1
require authentication = yes
refuse pap = yes
require chap = yes
pppoptfile = /etc/ppp/options.xl2tpd
```

Создайте `/etc/ppp/options.xl2tpd`:

```
ipcp-accept-local
ipcp-accept-remote
noccp
auth
mtu 1410
mru 1410
nodefaultroute
proxyarp
ms-dns 8.8.8.8
ms-dns 8.8.4.4
```

### Шаг 5: Добавление пользователей

Создайте `/etc/ppp/chap-secrets`:

```bash
# username  server  password  IP
vpnuser     *       vpnpass   *
```

```bash
chmod 600 /etc/ppp/chap-secrets
```

### Шаг 6: Настройка firewall

```bash
# Определите ваш сетевой интерфейс
NET_IFACE=$(ip route | grep default | awk '{print $5}')

# NAT для VPN клиентов
iptables -t nat -A POSTROUTING -s 192.168.42.0/24 -o $NET_IFACE -j MASQUERADE

# Разрешение форвардинга
iptables -A FORWARD -s 192.168.42.0/24 -j ACCEPT
iptables -A FORWARD -d 192.168.42.0/24 -j ACCEPT

# Разрешение VPN портов
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -A INPUT -p udp --dport 1701 -j ACCEPT
iptables -A INPUT -p esp -j ACCEPT

# Сохранение правил
netfilter-persistent save
```

### Шаг 7: Запуск сервисов

```bash
systemctl restart strongswan-starter
systemctl enable strongswan-starter
systemctl restart xl2tpd
systemctl enable xl2tpd
```

## Управление VPN сервером

Используйте скрипт управления:

```bash
chmod +x vpn-management.sh
sudo ./vpn-management.sh
```

Или команды вручную:

### Проверка статуса

```bash
# Статус IPsec
ipsec status
systemctl status strongswan-starter

# Статус L2TP
systemctl status xl2tpd

# Активные подключения
ipsec statusall
```

### Добавление пользователя

```bash
echo "newuser * newpassword *" >> /etc/ppp/chap-secrets
systemctl restart xl2tpd
```

### Просмотр логов

```bash
# Логи IPsec
journalctl -u strongswan-starter -f

# Логи L2TP
journalctl -u xl2tpd -f

# Системные логи
tail -f /var/log/syslog | grep -E "ipsec|xl2tpd"
```

### Проверка правил iptables

```bash
# Просмотр NAT таблицы
iptables -t nat -L -v -n

# Просмотр правил форвардинга
iptables -L FORWARD -v -n

# Просмотр входящих правил
iptables -L INPUT -v -n
```

## Настройка клиентов

### Windows 10/11

1. Откройте **Параметры** → **Сеть и Интернет** → **VPN**
2. Нажмите **Добавить VPN-подключение**
3. Заполните:
   - Поставщик услуг VPN: **Windows (встроенный)**
   - Имя подключения: **My VPN**
   - Имя или адрес сервера: **IP_вашего_сервера**
   - Тип VPN: **L2TP/IPsec с общим ключом**
   - Общий ключ: **ваш_PSK**
   - Имя пользователя: **vpnuser**
   - Пароль: **vpnpass**
4. Сохраните и подключитесь

### macOS

1. Откройте **Системные настройки** → **Сеть**
2. Нажмите **+** для добавления нового подключения
3. Выберите:
   - Интерфейс: **VPN**
   - Тип VPN: **L2TP через IPsec**
4. Заполните:
   - Адрес сервера: **IP_вашего_сервера**
   - Имя учётной записи: **vpnuser**
5. Нажмите **Параметры аутентификации**:
   - Пароль: **vpnpass**
   - Общий секрет: **ваш_PSK**
6. Нажмите **ОК** и **Подключить**

### iOS/iPadOS

1. Откройте **Настройки** → **VPN** → **Добавить конфигурацию VPN**
2. Выберите тип: **L2TP**
3. Заполните:
   - Описание: **My VPN**
   - Сервер: **IP_вашего_сервера**
   - Учётная запись: **vpnuser**
   - Пароль: **vpnpass**
   - Секрет: **ваш_PSK**
4. Сохраните и подключитесь

### Android

1. Откройте **Настройки** → **Сеть и Интернет** → **VPN**
2. Нажмите **+** для добавления VPN
3. Заполните:
   - Название: **My VPN**
   - Тип: **L2TP/IPSec PSK**
   - Адрес сервера: **IP_вашего_сервера**
   - Ключ IPSec: **ваш_PSK**
   - Имя пользователя: **vpnuser**
   - Пароль: **vpnpass**
4. Сохраните и подключитесь

## Проверка работы VPN

После подключения проверьте:

```bash
# На сервере - посмотрите активные туннели
ipsec statusall

# Посмотрите интерфейсы PPP
ip addr show | grep ppp

# На клиенте - проверьте свой IP
curl ifconfig.me
```

Если всё работает, вы должны видеть IP адрес вашего VPS сервера.

## Устранение проблем

### Клиент не может подключиться к серверу

```bash
# Проверьте, открыты ли порты
netstat -tulpn | grep -E "500|4500|1701"

# Проверьте firewall
ufw status
iptables -L -v -n
```

### IPsec туннель не устанавливается

```bash
# Посмотрите логи
journalctl -u strongswan-starter -n 50

# Проверьте конфигурацию
ipsec verify
```

### L2TP не работает после установки IPsec

```bash
# Проверьте, что xl2tpd запущен
systemctl status xl2tpd

# Посмотрите логи L2TP
journalctl -u xl2tpd -n 50
```

### Клиент подключается, но нет доступа в интернет

```bash
# Проверьте IP forwarding
sysctl net.ipv4.ip_forward

# Проверьте NAT правила
iptables -t nat -L POSTROUTING -v -n

# Проверьте правила форвардинга
iptables -L FORWARD -v -n
```

## Безопасность

### Рекомендации:

1. **Используйте сильный PSK** (минимум 32 символа)
2. **Используйте сложные пароли** для пользователей
3. **Ограничьте доступ по IP** если возможно
4. **Регулярно обновляйте систему**:
   ```bash
   apt-get update && apt-get upgrade
   ```
5. **Мониторьте подключения**:
   ```bash
   watch -n 2 'ipsec statusall | grep ESTABLISHED'
   ```
6. **Настройте fail2ban** для защиты от brute-force

### Смена PSK

```bash
nano /etc/ipsec.secrets
# Измените PSK
systemctl restart strongswan-starter
```

## Порты, используемые VPN

- **UDP 500** - IKE (Internet Key Exchange)
- **UDP 4500** - NAT-T (NAT Traversal)
- **UDP 1701** - L2TP
- **Protocol ESP (50)** - Encrypted Security Payload

Убедитесь, что эти порты открыты в файрволе вашего VPS провайдера.

## Производительность

Для улучшения производительности:

```bash
# Увеличьте буферы сети
cat >> /etc/sysctl.d/99-vpn.conf <<EOF
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
EOF

sysctl -p /etc/sysctl.d/99-vpn.conf
```

## Удаление VPN сервера

```bash
# Остановка сервисов
systemctl stop strongswan-starter xl2tpd
systemctl disable strongswan-starter xl2tpd

# Удаление пакетов
apt-get remove --purge strongswan xl2tpd

# Удаление правил iptables
iptables -t nat -D POSTROUTING -s 192.168.42.0/24 -j MASQUERADE
iptables -D FORWARD -s 192.168.42.0/24 -j ACCEPT
iptables -D FORWARD -d 192.168.42.0/24 -j ACCEPT
netfilter-persistent save

# Удаление конфигураций
rm -rf /etc/ipsec.* /etc/xl2tpd/ /etc/ppp/chap-secrets
```

## Полезные ссылки

- [strongSwan документация](https://docs.strongswan.org/)
- [xl2tpd документация](https://github.com/xelerance/xl2tpd)
- [L2TP/IPsec на Ubuntu](https://ubuntu.com/server/docs)

---

**Внимание:** Этот VPN предназначен для базовых нужд. Для более продвинутых сценариев рассмотрите WireGuard или OpenVPN.
