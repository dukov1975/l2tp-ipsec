#!/bin/bash

# Скрипт управления L2TP/IPsec VPN сервером

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Этот скрипт должен быть запущен от root${NC}" 
   exit 1
fi

show_status() {
    echo -e "${GREEN}=== Статус VPN сервера ===${NC}\n"
    
    echo -e "${YELLOW}IPsec (strongSwan):${NC}"
    systemctl status strongswan-starter --no-pager | head -n 5
    echo ""
    ipsec status
    
    echo -e "\n${YELLOW}L2TP (xl2tpd):${NC}"
    systemctl status xl2tpd --no-pager | head -n 5
    
    echo -e "\n${YELLOW}Активные подключения:${NC}"
    ipsec statusall | grep -i "established" || echo "Нет активных IPsec туннелей"
    
    echo -e "\n${YELLOW}Интерфейсы PPP:${NC}"
    ip addr show | grep -E "ppp|192.168.42" || echo "Нет активных PPP соединений"
}

add_user() {
    echo -e "${GREEN}=== Добавление пользователя VPN ===${NC}"
    read -p "Введите имя пользователя: " username
    read -sp "Введите пароль: " password
    echo ""
    
    if grep -q "^$username" /etc/ppp/chap-secrets; then
        echo -e "${RED}Пользователь $username уже существует${NC}"
        read -p "Обновить пароль? (y/n): " update
        if [ "$update" = "y" ]; then
            sed -i "/^$username/d" /etc/ppp/chap-secrets
            echo "$username * $password *" >> /etc/ppp/chap-secrets
            echo -e "${GREEN}Пароль для $username обновлён${NC}"
        fi
    else
        echo "$username * $password *" >> /etc/ppp/chap-secrets
        echo -e "${GREEN}Пользователь $username добавлен${NC}"
    fi
    
    systemctl restart xl2tpd
}

remove_user() {
    echo -e "${GREEN}=== Удаление пользователя VPN ===${NC}"
    echo -e "${YELLOW}Текущие пользователи:${NC}"
    grep -v "^#" /etc/ppp/chap-secrets | awk '{print "  - " $1}'
    echo ""
    
    read -p "Введите имя пользователя для удаления: " username
    
    if grep -q "^$username" /etc/ppp/chap-secrets; then
        sed -i "/^$username/d" /etc/ppp/chap-secrets
        echo -e "${GREEN}Пользователь $username удалён${NC}"
        systemctl restart xl2tpd
    else
        echo -e "${RED}Пользователь $username не найден${NC}"
    fi
}

list_users() {
    echo -e "${GREEN}=== Список пользователей VPN ===${NC}"
    grep -v "^#" /etc/ppp/chap-secrets | awk '{print "Пользователь: " $1 " | Пароль: " $3}'
}

show_logs() {
    echo -e "${GREEN}=== Логи VPN сервера ===${NC}\n"
    echo -e "${YELLOW}Последние 20 строк IPsec логов:${NC}"
    journalctl -u strongswan-starter -n 20 --no-pager
    
    echo -e "\n${YELLOW}Последние 20 строк L2TP логов:${NC}"
    journalctl -u xl2tpd -n 20 --no-pager
}

restart_services() {
    echo -e "${GREEN}=== Перезапуск VPN сервисов ===${NC}"
    systemctl restart strongswan-starter
    systemctl restart xl2tpd
    echo -e "${GREEN}Сервисы перезапущены${NC}"
}

show_config() {
    if [ -f /root/vpn-config.txt ]; then
        cat /root/vpn-config.txt
    else
        echo -e "${RED}Файл конфигурации не найден${NC}"
    fi
}

show_firewall() {
    echo -e "${GREEN}=== Правила firewall ===${NC}\n"
    echo -e "${YELLOW}NAT таблица:${NC}"
    iptables -t nat -L -v -n | grep -A 5 "POSTROUTING"
    
    echo -e "\n${YELLOW}Filter таблица (FORWARD):${NC}"
    iptables -L FORWARD -v -n | head -n 20
    
    echo -e "\n${YELLOW}Filter таблица (INPUT):${NC}"
    iptables -L INPUT -v -n | grep -E "500|4500|1701|esp"
}

# Меню
while true; do
    echo -e "\n${GREEN}╔════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Управление L2TP/IPsec VPN Server ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════╝${NC}\n"
    echo "1) Показать статус"
    echo "2) Добавить пользователя"
    echo "3) Удалить пользователя"
    echo "4) Список пользователей"
    echo "5) Показать логи"
    echo "6) Перезапустить сервисы"
    echo "7) Показать конфигурацию"
    echo "8) Показать правила firewall"
    echo "9) Выход"
    echo ""
    read -p "Выберите действие: " choice
    
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
        *) echo -e "${RED}Неверный выбор${NC}" ;;
    esac
done
