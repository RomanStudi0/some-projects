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

set_mode() {
    curl --silent --digest -u service:751426 -X POST "http://$ip/cgi/tbl/Net" -d '{"NtEnb":'"$1"'}' &> /dev/null
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
curl --silent --digest -u service:751426 "http://$ip/cgi/scr" | 
    grep -oP '(?<="str":")[^"]+' | 
    awk 'NR==1 {sum=$0; getline; printf "  ┌──────────────────────┐\n  │ %-20s │\n  │ %-20s │\n  └──────────────────────┘\n", sum, $0}'

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
    status=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep isOpenCheck: | tail -n1 | grep -o '[0-9]*

# Запит на номери для друку
read -p "Введіть номери звітів для друку (через пробіл): " report_nums

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

# Друк кожного переданого номера
for num in $report_nums; do
    echo "Друк Z-звіту №$num"
    curl --silent --digest -u service:751426 "http://$ip/cgi/execute?ZCopy=$num" -X GET &> /dev/null
done

# Якщо початковий режим був MG — повертаємо
if [[ "$mode_name" = "MG" ]]; then
    echo "⏪ Повернення режиму назад у MG..."
    set_mode 8
    sleep 5
    wait_for_ip
    final_mode=$(get_mode)
    if [[ "$final_mode" = "8" ]]; then
        echo "✅ Режим повернуто назад у MG"
    else
        echo "❌ Не вдалося повернути режим MG"
    fi
fi)
    if [[ "$status" != "0" ]]; then
        echo "⚠️ Чек відкрито"
        exit 1
    fi
    for num in $report_nums; do
        echo "Друк Z-звіту №$num"
        curl --silent --digest -u service:751426 "http://$ip/cgi/execute?ZCopy=$num" -X GET &> /dev/null
    done
    exit 0
fi

# Запит на номери для друку
read -p "Введіть номери звітів для друку (через пробіл): " report_nums

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

# Друк кожного переданого номера
for num in $report_nums; do
    echo "Друк Z-звіту №$num"
    curl --silent --digest -u service:751426 "http://$ip/cgi/execute?ZCopy=$num" -X GET &> /dev/null
done

# Якщо початковий режим був MG — повертаємо
if [[ "$mode_name" = "MG" ]]; then
    echo "⏪ Повернення режиму назад у MG..."
    set_mode 8
    sleep 5
    wait_for_ip
    final_mode=$(get_mode)
    if [[ "$final_mode" = "8" ]]; then
        echo "✅ Режим повернуто назад у MG"
    else
        echo "❌ Не вдалося повернути режим MG"
    fi
fi
