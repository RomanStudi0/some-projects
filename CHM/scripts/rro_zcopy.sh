#!/bin/bash

# Призначення: Друк Z-звітів із врахуванням режимів MG/HTTP, стану чеку, параметрів запуску

# --- Функції ---

get_ip() {
    ip=$(systemctl status isc-dhcp-server | grep -oP 'DHCPACK on \K192\.168\.2\.\d+' | head -n1)
    if [ -z "$ip" ]; then
        ip=$(grep -Po '1\\host=\K[\d.]+' /etc/chameleon/fiscallistener.conf)
    fi

    for i in {1..4}; do
        ping -c1 -W1 "$ip" > /dev/null && break || sleep 1
    done

    if [ -z "$ip" ]; then
        echo "❌ Не вдалося визначити IP пристрою"
        exit 1
    fi
}

get_mode() {
    curl --silent --digest -u service:751426 "http://$ip/cgi/tbl/Net" | grep -oP '"NtEnb":\K\d+'
}

set_mode() {
    local mode=$1
    curl --silent --digest -u service:751426 -X PUT -d "{\"NtEnb\":$mode}" "http://$ip/cgi/tbl/Net" > /dev/null
}

check_is_open() {
    local status=$(grep 'isOpenCheck:' /var/log/chameleon/fiscallistener.log | tail -n 1 | awk '{print $NF}')
    echo "$status"
}

print_zcopy() {
    for z in "${zreports[@]}"; do
        echo "🔄 Друк звіту №$z..."
        curl --silent --digest -u service:751426 "http://$ip/cgi/zcopy?znum=$z" > /dev/null
    done
}

# --- Основна логіка ---

get_ip

# Отримання індикатора (товару)
indicator=$(curl --silent --digest -u service:751426 "http://$ip/cgi/scr" | grep -oP '(?<="str":")[^"]+' | awk 'NR==1 {sum=$0; getline; printf "  ┌──────────────────────┐\n  │ %-20s │\n  │ %-20s │\n  └──────────────────────┘\n", sum, $0}')
echo "$indicator"

# Отримання моделі та імені
device_info=$(curl --silent --digest -u service:751426 "http://$ip/cgi/state")
model=$(echo "$device_info" | grep -oP '"model":"\K[^"]+')
name=$(echo "$device_info" | grep -oP '"name":"\K[^"]+')
echo " $model - $name"

# Отримання поточного режиму
current_mode=$(get_mode)
mode_name="Невідомо"
[ "$current_mode" = "7" ] && mode_name="HTTP"
[ "$current_mode" = "8" ] && mode_name="MG"
echo "IP: $ip, режим роботи - $mode_name"

# Перевірка непереданих документів
ndoc=$(curl -s "http://$ip/cgi/status" | grep -o '"ndoc":[0-9]*' | grep -o '[0-9]*')
if [[ "$ndoc" -eq 0 ]]; then
    echo "Усі документи передані"
else
    echo "Не переданих документів - $ndoc"
fi

# Отримання поточного Z-звіту
currZ=$(curl --silent --digest -u service:751426 "http://$ip/cgi/znum" | grep -oP '\d+')
echo "🧾 Останній Z-звіт — $currZ"

# --- Якщо передано параметри ---
if [ $# -gt 0 ]; then
    status=$(check_is_open)
    if [ "$status" != "0" ]; then
        echo "⚠️ Чек відкрито. Неможливо виконати друк."
        exit 1
    fi

    zreports=("$@")
    print_zcopy
    exit 0
fi

# --- Режим MG -> HTTP, якщо потрібно ---
if [ "$current_mode" = "8" ]; then
    read -p "Режим MG буде змінено на HTTP для друку. Продовжити? [Y/n]: " confirm
    confirm=${confirm,,}  # до нижнього регістру
    if [[ "$confirm" = "n" ]]; then
        echo "❌ Цей РРО працює в MG і не зможе виконати копію"
        exit 1
    fi

    set_mode 7
    echo "⏳ Очікування переходу в HTTP режим..."
    sleep 5
    for i in {1..10}; do
        ping -c1 -W1 "$ip" > /dev/null && break || sleep 1
    done

    new_mode=$(get_mode)
    if [ "$new_mode" = "7" ]; then
        echo "✅ Режим успішно змінено на HTTP"
    else
        echo "❌ Не вдалося змінити режим на HTTP"
        exit 1
    fi
fi

# --- Перевірка відкритого чеку ---
while true; do
    status=$(check_is_open)
    if [ "$status" = "0" ]; then
        break
    else
        echo "⚠️ Чек відкрито. Для друку необхідно закрити чек. Натисніть Enter після закриття..."
        read
    fi
done

# --- Ввід звітів для друку ---
read -p "Введіть номери звітів для друку (через пробіл): " -a zreports

print_zcopy

# --- Повернення режиму назад у MG ---
if [ "$current_mode" = "8" ]; then
    set_mode 8
    echo "🔁 Повернення у MG режим..."
    sleep 5
    for i in {1..10}; do
        ping -c1 -W1 "$ip" > /dev/null && break || sleep 1
    done

    back_mode=$(get_mode)
    if [ "$back_mode" = "8" ]; then
        echo "✅ Режим успішно повернуто у MG"
    else
        echo "⚠️ Не вдалося повернути режим у MG"
    fi
fi
