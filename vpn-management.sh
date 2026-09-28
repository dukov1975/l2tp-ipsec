#!/bin/bash

# Скрипт управления L2TP/IPsec VPN сервером

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}This script run from root${NC}" 
   exit 1
fi

show_status() {
    echo -e "${GREEN}=== Status VPN server ===${NC}\n"
    
    echo -e "${YELLOW}IPsec (strongSwan):${NC}"
    systemctl status strongswan-starter --no-pager | head -n 5
    echo ""
    ipsec status
    
    echo -e "\n${YELLOW}L2TP (xl2tpd):${NC}"
    systemctl status xl2tpd --no-pager | head -n 5
    
    echo -e "\n${YELLOW}Active connections:${NC}"
    ipsec statusall | grep -i "established" || echo "No active IPsec tunnels"
    
    echo -e "\n${YELLOW}Interfaces PPP:${NC}"
    ip addr show | grep -E "ppp|10.1.1" || echo "No active PPP connections"
}

add_user() {
    echo -e "${GREEN}=== Add user VPN ===${NC}"
    read -p "Enter login: " username
    read -sp "Enter password: " password
    echo ""
    
    if grep -q "^$username" /etc/ppp/chap-secrets; then
        echo -e "${RED}User $username already exists${NC}"
        read -p "Update password? (y/n): " update
        if [ "$update" = "y" ]; then
            sed -i "/^$username/d" /etc/ppp/chap-secrets
            echo "$username * $password *" >> /etc/ppp/chap-secrets
            echo -e "${GREEN}Password for $username updated${NC}"
        fi
    else
        echo "$username * $password *" >> /etc/ppp/chap-secrets
        echo -e "${GREEN}User $username added${NC}"
    fi
    
    systemctl restart xl2tpd
}

remove_user() {
    echo -e "${GREEN}=== Delete user VPN ===${NC}"
    echo -e "${YELLOW}Current users:${NC}"
    grep -v "^#" /etc/ppp/chap-secrets | awk '{print "  - " $1}'
    echo ""
    
    read -p "Enter name for delete: " username
    
    if grep -q "^$username" /etc/ppp/chap-secrets; then
        sed -i "/^$username/d" /etc/ppp/chap-secrets
        echo -e "${GREEN}User $username deleted${NC}"
        systemctl restart xl2tpd
    else
        echo -e "${RED}User $username not found${NC}"
    fi
}

list_users() {
    echo -e "${GREEN}=== Users list VPN ===${NC}"
    grep -v "^#" /etc/ppp/chap-secrets | awk '{print "User: " $1 " | Password: " $3}'
}

show_logs() {
    echo -e "${GREEN}=== Logs VPN server ===${NC}\n"
    echo -e "${YELLOW}Last 20 stroke of IPsec logs:${NC}"
    journalctl -u strongswan-starter -n 20 --no-pager
    
    echo -e "\n${YELLOW}Last 20 stroke of L2TP logs:${NC}"
    journalctl -u xl2tpd -n 20 --no-pager
}

restart_services() {
    echo -e "${GREEN}=== Restart VPN services ===${NC}"
    systemctl restart strongswan-starter
    systemctl restart xl2tpd
    echo -e "${GREEN}Services restarted${NC}"
}

show_config() {
    if [ -f /root/vpn-config.txt ]; then
        cat /root/vpn-config.txt
    else
        echo -e "${RED}Files of configurations not found${NC}"
    fi
}

show_firewall() {
    echo -e "${GREEN}=== Rule firewall ===${NC}\n"
    echo -e "${YELLOW}NAT table:${NC}"
    iptables -t nat -L -v -n | grep -A 5 "POSTROUTING"
    
    echo -e "\n${YELLOW}Filter table (FORWARD):${NC}"
    iptables -L FORWARD -v -n | head -n 20
    
    echo -e "\n${YELLOW}Filter table (INPUT):${NC}"
    iptables -L INPUT -v -n | grep -E "500|4500|1701|esp"
}

# Меню
while true; do
    echo -e "\n${GREEN}╔════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Manage L2TP/IPsec VPN Server      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════╝${NC}\n"
    echo "1) Show status"
    echo "2) Add user"
    echo "3) Delete user"
    echo "4) List of users"
    echo "5) Show logs"
    echo "6) Restart services"
    echo "7) Show configurations"
    echo "8) Show rules firewall"
    echo "9) Exit"
    echo ""
    read -p "Choice: " choice
    
    case $choice in
        1) show_status ;;
        2) add_user ;;
        3) remove_user ;;
        4) list_users ;;
        5) show_logs ;;
        6) restart_services ;;
        7) show_config ;;
        8) show_firewall ;;
        9) exit 0 ;;
        *) echo -e "${RED}Wrong choice${NC}" ;;
    esac
done
