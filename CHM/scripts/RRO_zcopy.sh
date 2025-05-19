#!/bin/bash

get_ip() {
    ip=$(systemctl status isc-dhcp-server | grep -oP 'DHCPACK on \K192\.168\.2\.\d+' | head -n1)
    [ -z "$ip" ] && ip=$(grep -Po '1\\host=\K[\d.]+' /etc/chameleon/fiscallistener.conf)
    for i in {1..4}; do
        ping -c1 -W1 "$ip" &> /dev/null && echo "$ip" && return || sleep 1
    done
    echo "❌ Не вдалося знайти доступний IP пристрою" >&2
    exit 1
}

get_mode() {
    mode_json=$(curl --silent --digest -u service:751426 "http://$ip/cgi/tbl/Net")
    echo "$mode_json" | grep -oP '"NtEnb":\K\d+'
}

# Змінена функція встановлення режиму на основі робочого скрипта
set_mode() {
    response=$(curl --digest -u service:751426 "http://$ip/cgi/tbl/Net" \
        -H 'X-HTTP-Method-Override: PATCH' \
        -H 'Content-Type: application/json' \
        -H "Referer: http://$ip/index.html" \
        --data "{\"NtEnb\":$1}" \
        --compressed -s)
    
    echo "$response" | grep -q "\"NtEnb\":$1" && return 0 || return 1
}

wait_for_ip() {
    for i in {1..10}; do
        ping -c1 -W1 "$ip" &> /dev/null && return
        sleep 1
    done
    echo "❌ Не вдалося підключитися до пристрою після зміни режиму" >&2
    exit 1
}

# --- Початок виконання ---
report_nums="$@"
ip=$(get_ip)

# Інформація про пристрій
device_info=$(curl --silent --digest -u service:751426 "http://$ip/cgi/state")
model=$(echo "$device_info" | grep -oP '"model":"\K[^"]+')
name=$(echo "$device_info" | grep -oP '"name":"\K[^"]+')
currZ=$(echo "$device_info" | grep -oP '"currZ":\K\d+')

echo " $model - $name"

# Виведення індикатора
curl --silent --digest -u service:751426 "http://$ip/cgi/scr" | grep -oP '(?<="str":")[^"]+' | awk 'NR==1 {sum=$0; getline; printf "  ┌──────────────────────┐\n  │ %-20s │\n  │ %-20s │\n  └──────────────────────┘\n", sum, $0}'

# Вивід IP та режиму
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

# Z-звіт
echo "🧾 Останній Z-звіт — $currZ"

# Якщо передано параметри — друкуємо без режимного перемикання
if [ -n "$report_nums" ]; then
    status=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep isOpenCheck: | tail -n1 | grep -o '[0-9]*$')
    if [[ "$status" != "0" ]]; then
        echo "⚠️ Чек відкрито"
        exit 1
    fi
    for num in $report_nums; do
        echo "Друк Z-звіту №$num"
        curl --silent --digest -u service:751426 "http://$ip/cgi/proc/printmmcjrn?$num&BegRcpt&EndRcpt"
    done
    exit 0
fi

# Запит на номери для друку
read -p "Введіть номери звітів для друку (через пробіл): " report_nums

# Перевірка необхідності зміни режиму, якщо режим MG
if [[ "$mode_name" = "MG" ]]; then
    read -p "Змінювати режим? (y/n) " change_mode
    
    # За замовчуванням "y", або якщо користувач натиснув Enter
    if [[ -z "$change_mode" || "$change_mode" =~ ^[Yy]$ ]]; then
        if set_mode 7; then
            echo "Режим успішно змінено, починаю друк"
            mode_changed=true
        else
            echo "❌ Помилка зміни режиму"
            exit 1
        fi
    else
        echo "Режим не змінено, починаю друк"
        mode_changed=false
    fi
else
    mode_changed=false
fi

# Перевірка isOpenCheck перед друком
while :; do
    status=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep isOpenCheck: | tail -n1 | grep -o '[0-9]*$')
    if [[ "$status" != "0" ]]; then
        echo "Чек відкрито, для друку необхідно закрити чек"
        read -p "Натисніть Enter для повторної перевірки..."
    else
        break
    fi
done

# Друк кожного переданого номера - змінено на формат з робочого скрипта
for num in $report_nums; do
    echo "Друк Z-звіту №$num"
    curl --digest -u service:751426 "http://$ip/cgi/proc/printmmcjrn?$num&BegRcpt&EndRcpt"
done

# Якщо режим був змінений - повертаємо назад у MG і перезавантажуємо пристрій
if [[ "$mode_changed" = true ]]; then
    sleep 5
    if set_mode 8; then
        echo "Режим успішно повернуто, перезавантажую..."
    else
        echo "Помилка повернення режиму, перезавантажую..."
    fi
    
    # Перезавантаження пристрою, як у робочому скрипті
    curl -X POST "http://$ip/cgi/pdwl" -H "Content-Type: application/octet-stream" --data "1"
fi
