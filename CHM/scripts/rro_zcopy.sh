#!/bin/bash

# Функція отримання IP
get_ip() {
    ip=$(systemctl status isc-dhcp-server 2>/dev/null | grep -oP 'DHCPACK on \K192\.168\.2\.\d+' | head -n1)
    [ -z "$ip" ] && ip=$(grep -Po '1\\host=\K[\d.]+' /etc/chameleon/fiscallistener.conf)
    
    for i in {1..4}; do
        ping -c1 -W1 "$ip" &>/dev/null && echo "$ip" && return
        sleep 1
    done

    echo "❌ Неможливо отримати IP-адресу РРО." >&2
    exit 1
}

# Функція перемикання в HTTP (якщо потрібно)
switch_to_http() {
    local current_mode=$(curl --silent --digest -u service:751426 "http://$ip/cgi/tbl/Net" | grep -oP '"NtEnb":\K\d+')
    if [ "$current_mode" = "7" ]; then
        echo "✅ Поточний режим: HTTP"
        return 0
    elif [ "$current_mode" = "8" ]; then
        echo "⚠️ Режим MG. Потрібно змінити на HTTP для друку."
        read -p "Змінити режим на HTTP? (Y/n): " confirm
        [[ "$confirm" =~ ^[Nn]$ ]] && echo "❌ Цей РРО працює в MG і не зможе виконати копію." && exit 1

        response=$(curl --silent --digest -u service:751426 "http://$ip/cgi/tbl/Net" \
            -H 'X-HTTP-Method-Override: PATCH' \
            -H 'Content-Type: application/json' \
            --data '{"NtEnb":7}')

        echo "$response" | grep -q '"NtEnb":7' && {
            echo "✅ Режим змінено на HTTP"
            mode_changed=true
        } || {
            echo "❌ Помилка зміни режиму"
            exit 1
        }
    else
        echo "❌ Невідомий режим: $current_mode"
        exit 1
    fi
}

# Повернення режиму у MG, якщо був змінений
restore_mode_if_changed() {
    if [ "$mode_changed" = true ]; then
        sleep 5
        curl -X POST "http://$ip/cgi/pdwl" -H "Content-Type: application/octet-stream" --data "1" &>/dev/null

        # Очікування доступності пристрою
        echo "⏳ Очікування перезапуску пристрою..."
        for i in {1..20}; do
            ping -c1 -W1 "$ip" &>/dev/null && break
            sleep 1
        done

        # Перевірка поточного режиму
        new_mode=$(curl --silent --digest -u service:751426 "http://$ip/cgi/tbl/Net" | grep -oP '"NtEnb":\K\d+')
        if [ "$new_mode" = "8" ]; then
            echo "✅ Режим успішно повернуто в MG"
        else
            echo "⚠️ Не вдалося повернути режим у MG. Поточний режим: $new_mode"
        fi
    fi
}

# Перевірка чи чек відкрито
check_receipt_closed() {
    status=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep 'isOpenCheck:' | tail -n 1 | grep -oP '\d+$')
    if [ "$status" != "0" ]; then
        echo "⚠️ Чек відкрито, для друку необхідно закрити чек."
        read -p "Натисніть Enter після закриття чека..."
        status=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep 'isOpenCheck:' | tail -n 1 | grep -oP '\d+$')
        if [ "$status" != "0" ]; then
            echo "❌ Чек все ще відкрито. Неможливо виконати друк."
            exit 1
        fi
    fi
}

# Головна частина скрипта
report_nums="$@"
ip=$(get_ip)
# Головна частина скрипта
report_nums="$@"
ip=$(get_ip)

# Отримання моделі та назви
device_info=$(curl --silent --digest -u service:751426 "http://$ip/cgi/state")
model=$(echo "$device_info" | grep -oP '"model":"\K[^"]+')
name=$(echo "$device_info" | grep -oP '"name":"\K[^"]+')
echo " $model - $name"

# Виведення індикатора
indicator=$(curl --silent --digest -u service:751426 "http://$ip/cgi/scr" | grep -oP '(?<="str":")[^"]+' | awk 'NR==1 {sum=$0; getline; printf "  ┌──────────────────────┐\n  │ %-20s │\n  │ %-20s │\n  └──────────────────────┘\n", sum, $0}')
echo "$indicator"

# Отримання режиму
mode_raw=$(curl --silent --digest -u service:751426 "http://$ip/cgi/tbl/Net")
current_mode=$(echo "$mode_raw" | grep -oP '"NtEnb":\K\d+')
mode_name="Невідомо"
[ "$current_mode" = "7" ] && mode_name="HTTP"
[ "$current_mode" = "8" ] && mode_name="MG"
echo "IP: $ip, режим роботи - $mode_name"

# Перевірка ndoc
ndoc=$(curl -s "http://$ip/cgi/status" | grep -o '"ndoc":[0-9]*' | grep -o '[0-9]*')
if [[ "$ndoc" -eq 0 ]]; then
    echo "Усі документи передані"
else
    echo "Не переданих документів - $ndoc"
fi

# Вивід поточного Z-звіту
currZ=$(echo "$device_info" | grep -oP '"currZ":\K\d+')
echo "🧾 Останній Z-звіт — $currZ"

# Виведення індикатора
indicator=$(curl --silent --digest -u service:751426 "http://$ip/cgi/scr" | grep -oP '(?<="str":")[^"]+' | awk 'NR==1 {sum=$0; getline; printf "  ┌──────────────────────┐\n  │ %-20s │\n  │ %-20s │\n  └──────────────────────┘\n", sum, $0}')
echo "$indicator"

# Вивід поточного Z-звіту
currZ=$(curl --silent --digest -u service:751426 "http://$ip/cgi/state" | grep -oP '"currZ":\K\d+')
echo "🧾 Останній Z-звіт — $currZ"

# Якщо немає аргументів, запитати користувача
if [ -z "$report_nums" ]; then
    read -p "Введіть номери звітів для друку (через пробіл): " report_nums
fi

# Якщо передано аргументи — не перемикай режим, але перевір чек
if [ -z "$@" ]; then
    switch_to_http
else
    status=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep 'isOpenCheck:' | tail -n 1 | grep -oP '\d+$')
    if [ "$status" != "0" ]; then
        echo "❌ Чек відкрито. Не можна друкувати у цьому стані."
        exit 1
    fi
fi

# Перевірка isOpenCheck перед друком
check_receipt_closed

# Друк звітів
for report_num in $report_nums; do
    curl --silent --digest -u service:751426 "http://$ip/cgi/proc/printmmcjrn?$report_num&BegRcpt&EndRcpt"
done

# Повернення режиму, якщо змінювався
restore_mode_if_changed
