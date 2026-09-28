#!/bin/bash

# L2TP/IPsec VPN Server Setup Script for Ubuntu
# Этот скрипт автоматизирует установку и настройку L2TP/IPsec VPN сервера

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Setup L2TP/IPsec VPN Server ===${NC}"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Run from root${NC}" 
   exit 1
fi

# Получение IP адреса сервера
SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n 1)
EXTERNAL_IP=$(curl -s ifconfig.me || echo "$SERVER_IP")

echo -e "${YELLOW}IP adress server: $SERVER_IP${NC}"
echo -e "${YELLOW}External IP: $EXTERNAL_IP${NC}"

# Параметры VPN (можно изменить)
read -p "Enter PSK (Pre-Shared Key) for IPsec [or press Enter for generation]: " VPN_IPSEC_PSK
if [ -z "$VPN_IPSEC_PSK" ]; then
    VPN_IPSEC_PSK=$(openssl rand -base64 32)
    echo -e "${GREEN}Generation PSK: $VPN_IPSEC_PSK${NC}"
fi

read -p "Enter user name VPN [default: vpnuser]: " VPN_USER
VPN_USER=${VPN_USER:-vpnuser}

read -p "Enter password $VPN_USER [or press Enter for generation]: " VPN_PASSWORD
if [ -z "$VPN_PASSWORD" ]; then
    VPN_PASSWORD=$(openssl rand -base64 16)
    echo -e "${GREEN}Generation password: $VPN_PASSWORD${NC}"
fi

# Диапазон IP для VPN клиентов
VPN_IP_RANGE="10.1.1.10-10.1.1.20"
VPN_LOCAL_IP="10.1.1.8"

# Определение сетевого интерфейса
NET_IFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
echo -e "${YELLOW}Network interface: $NET_IFACE${NC}"

echo -e "${GREEN}Update system...${NC}"
apt-get update
apt-get upgrade -y

echo -e "${GREEN}Setting requared packages...${NC}"
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    strongswan \
    xl2tpd \
    libstrongswan-standard-plugins \
    libstrongswan-extra-plugins \
    iptables \
    iptables-persistent \
    netfilter-persistent

echo -e "${GREEN}Setting system parameters...${NC}"
# Включение IP forwarding и отключение send_redirects
cat > /etc/sysctl.d/99-vpn.conf <<EOF
# IP Forwarding
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 0

# Отключение ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.$NET_IFACE.send_redirects = 0

# Отключение ICMP accept_redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Защита от IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF

sysctl -p /etc/sysctl.d/99-vpn.conf

echo -e "${GREEN}Setting IPsec (strongSwan)...${NC}"
# Бэкап оригинальных файлов
cp /etc/ipsec.conf /etc/ipsec.conf.bak 2>/dev/null || true
cp /etc/ipsec.secrets /etc/ipsec.secrets.bak 2>/dev/null || true

# Конфигурация IPsec
cat > /etc/ipsec.conf <<EOF
# IPsec configuration for L2TP/IPsec
config setup
    charondebug="ike 2, knl 2, cfg 2, net 2, esp 2, dmn 2, mgr 2"
    uniqueids=never

conn L2TP-PSK
    authby=secret
    auto=add
    keyingtries=3
    dpdaction=clear
    dpddelay=300s
    dpdtimeout=1000s
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%any
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
    ike=aes256-sha2_256-modp2048,aes256-sha2_256-modp1024,aes128-sha1-modp2048,aes128-sha1-modp1024,aes256-sha1-modp2048,aes256-sha1-modp1024!
    esp=aes256-sha2_256,aes128-sha1,aes256-sha1!
    forceencaps=yes
EOF

# PSK для IPsec
cat > /etc/ipsec.secrets <<EOF
# IPsec secrets
%any %any : PSK "$VPN_IPSEC_PSK"
EOF

chmod 600 /etc/ipsec.secrets

echo -e "${GREEN}Setting L2TP (xl2tpd)...${NC}"
# Бэкап оригинального файла
cp /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf.bak 2>/dev/null || true

# Конфигурация xl2tpd
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701
auth file = /etc/ppp/chap-secrets
access control = no

[lns default]
ip range = $VPN_IP_RANGE
local ip = $VPN_LOCAL_IP
require authentication = yes
refuse pap = yes
require chap = yes
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

# Опции PPP
cat > /etc/ppp/options.xl2tpd <<EOF
# PPP options for xl2tpd
ipcp-accept-local
ipcp-accept-remote
noccp
auth
crtscts
idle 1800
mtu 1410
mru 1410
nodefaultroute
debug
lock
proxyarp
connect-delay 5000
ms-dns 8.8.8.8
ms-dns 8.8.4.4
EOF

# Добавление пользователя VPN
cat > /etc/ppp/chap-secrets <<EOF
# Secrets for authentication using CHAP
# client    server    secret    IP addresses
$VPN_USER   *         $VPN_PASSWORD   *
EOF

chmod 600 /etc/ppp/chap-secrets

echo -e "${GREEN}Setting firewall (iptables)...${NC}"

# Очистка старых правил для VPN
iptables -t nat -D POSTROUTING -s 10.1.1.0/24 -o $NET_IFACE -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -s 10.1.1.0/24 -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -d 10.1.1.0/24 -j ACCEPT 2>/dev/null || true

# Добавление правил NAT для VPN клиентов
iptables -t nat -A POSTROUTING -s 10.1.1.0/24 -o $NET_IFACE -j MASQUERADE

# Разрешение форвардинга для VPN
iptables -A FORWARD -s 10.1.1.0/24 -j ACCEPT
iptables -A FORWARD -d 10.1.1.0/24 -j ACCEPT

# Разрешение VPN трафика
iptables -A INPUT -p udp --dport 500 -j ACCEPT
iptables -A INPUT -p udp --dport 4500 -j ACCEPT
iptables -A INPUT -p udp --dport 1701 -j ACCEPT
iptables -A INPUT -p esp -j ACCEPT

# Разрешение established соединений
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Сохранение правил iptables
netfilter-persistent save

echo -e "${GREEN}Restart services...${NC}"
systemctl restart strongswan-starter
systemctl enable strongswan-starter
systemctl restart xl2tpd
systemctl enable xl2tpd

# Проверка статуса
sleep 3
echo -e "\n${GREEN}=== Status services ===${NC}"
systemctl status strongswan-starter --no-pager | head -n 5
systemctl status xl2tpd --no-pager | head -n 5

# Сохранение конфигурации в файл
CONFIG_FILE="/root/vpn-config.txt"
cat > $CONFIG_FILE <<EOF
========================================
L2TP/IPsec VPN Server Configuration
========================================

External IP of server: $EXTERNAL_IP
Local IP server: $SERVER_IP

IPsec PSK: $VPN_IPSEC_PSK

VPN users:
  login: $VPN_USER
  password: $VPN_PASSWORD

Range IP for clients: $VPN_IP_RANGE
Gateway VPN: $VPN_LOCAL_IP

DNS серверы: 8.8.8.8, 8.8.4.4

========================================
Настройка клиента (Windows/macOS/iOS):
========================================

1. Создайте новое L2TP/IPsec соединение
2. Адрес сервера: $EXTERNAL_IP
3. Тип VPN: L2TP/IPsec с общим ключом
4. Pre-Shared Key (PSK): $VPN_IPSEC_PSK
5. Имя пользователя: $VPN_USER
6. Пароль: $VPN_PASSWORD

========================================
Проверка работы:
========================================

# Проверить статус IPsec:
ipsec status

# Проверить статус xl2tpd:
systemctl status xl2tpd

# Логи IPsec:
journalctl -u strongswan-starter -f

# Логи L2TP:
journalctl -u xl2tpd -f

# Проверить правила iptables:
iptables -L -v -n
iptables -t nat -L -v -n

========================================
Добавление дополнительных пользователей:
========================================

Отредактируйте файл /etc/ppp/chap-secrets:
echo "username * password *" >> /etc/ppp/chap-secrets
systemctl restart xl2tpd

========================================
EOF

echo -e "\n${GREEN}=== Установка завершена! ===${NC}\n"
cat $CONFIG_FILE
echo -e "\n${YELLOW}Конфигурация сохранена в: $CONFIG_FILE${NC}"
echo -e "${YELLOW}Для добавления пользователей: nano /etc/ppp/chap-secrets${NC}\n"
