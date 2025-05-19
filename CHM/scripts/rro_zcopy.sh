#!/bin/bash

get_ip() {
    ip=$(systemctl status isc-dhcp-server | grep -oP 'DHCPACK on \K192\.168\.2\.\d+' | head -n1)
    [ -z "$ip" ] && ip=$(grep -Po '1\\host=\K[\d.]+' /etc/chameleon/fiscallistener.conf)

    for i in {1..4}; do
        ping -c1 -W1 "$ip" &> /dev/null && echo "$ip" && return
        sleep 1
    done

    echo "Не вдалося отримати доступний IP пристрою" >&2
    exit 1
}

show_rr_indicator() {
    curl --silent --digest -u service:751426 "http://$1/cgi/scr" -X GET \
    | grep -oP '(?<="str":")[^"]+' \
    | awk 'NR==1 {sum=$0; getline; printf "  ┌──────────────────────┐\n  │ %-20s │\n  │ %-20s │\n  └──────────────────────┘\n", sum, $0}'
}

get_mode() {
    curl --silent --digest -u service:751426 "http://$1/cgi/tbl/Net" | grep -oP '"NtEnb":\K\d+'
}

set_mode() {
    local ip=$1
    local mode=$2
    curl --silent --digest -u service:751426 "http://$ip/cgi/tbl/Net" \
        -H 'X-HTTP-Method-Override: PATCH' \
        -H 'Content-Type: application/json' \
        -H "Referer: http://$ip/index.html" \
        --data "{\"NtEnb\":$mode}" --compressed \
        | grep -q "\"NtEnb\":$mode"
}

check_is_open() {
    local status=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep isOpenCheck: | tail -n1 | grep -oP '\d+$')
    echo "$status"
}

wait_check_close() {
    while true; do
        is_open=$(check_is_open)
        if [ "$is_open" == "0" ]; then
            return
        else
            echo "Чек відкрито, для друку необхідно закрити чек. Натисніть Enter після закриття..."
            read
        fi
    done
}

print_reports() {
    local ip=$1
    shift
    local reports=("$@")

    wait_check_close

    for report_num in "${reports[@]}"; do
        curl --digest -u service:751426 "http://$ip/cgi/proc/printmmcjrn?$report_num&BegRcpt&EndRcpt"
    done
}

main() {
    ip=$(get_ip)
    show_rr_indicator "$ip"

    currZ=$(curl --silent --digest -u service:751426 "http://$ip/cgi/state" -X GET | grep -oP '"currZ":\K\d+')
    echo "Останній Z-звіт - $currZ"

    mode=$(get_mode "$ip")

    if [ "$#" -gt 0 ]; then
        # Аргументи передано — режим не змінювати, але перевірити isOpenCheck
        is_open=$(check_is_open)
        if [ "$is_open" != "0" ]; then
            echo "Чек відкрито — неможливо надрукувати звіт"
            exit 1
        fi
        print_reports "$ip" "$@"
        exit 0
    fi

    read -p "Введіть номери звітів для друку (через пробіл): " -a report_nums

    if [ "$mode" == "7" ]; then
        echo "Поточний режим — HTTP. Друк дозволено."
    elif [ "$mode" == "8" ]; then
        echo "Поточний режим — MG. Щоб надрукувати звіт, потрібно перейти в HTTP режим."
        read -p "Перейти в HTTP режим? (y/n): " confirm_mode
        if [[ ! "$confirm_mode" =~ ^[Yy]$ ]]; then
            echo "Цей РРО працює в MG і не зможе виконати копію."
            exit 1
        fi
        if set_mode "$ip" 7; then
            echo "Режим успішно змінено на HTTP"
        else
            echo "Не вдалося змінити режим"
            exit 1
        fi
    else
        echo "Невідомий режим: $mode"
        exit 1
    fi

    print_reports "$ip" "${report_nums[@]}"

    if [ "$mode" == "8" ]; then
        sleep 5
        if set_mode "$ip" 8; then
            echo "Режим повернено в MG, перезавантаження..."
        else
            echo "Не вдалося повернути режим MG. Перезавантаження..."
        fi
        curl -X POST "http://$ip/cgi/pdwl" -H "Content-Type: application/octet-stream" --data "1" --verbose
    fi
}

main "$@"
