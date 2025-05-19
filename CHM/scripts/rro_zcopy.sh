#!/bin/bash

login="service"
password="751426"

get_ip() {
  ip=$(systemctl status isc-dhcp-server | grep -oP 'DHCPACK on \K192\.168\.2\.\d+' | head -n1)
  [ -z "$ip" ] && ip=$(grep -Po '1\\host=\K[\d.]+' /etc/chameleon/fiscallistener.conf)
  for i in {1..4}; do
    ping -c1 -W1 "$ip" > /dev/null && echo "$ip" && return || sleep 1
  done
  echo "❌ Неможливо отримати IP пристрою." >&2
  exit 1
}

change_mode() {
  local ip=$1
  local new_mode=$2

  curl --silent --digest -u $login:$password "http://$ip/cgi/tbl/Net" -X POST -d "{\"NtEnb\":$new_mode}" > /dev/null
  sleep 5

  for i in {1..5}; do
    ping -c1 -W1 "$ip" > /dev/null && break || sleep 1
  done

  mode_check=$(curl --silent --digest -u $login:$password "http://$ip/cgi/tbl/Net" | grep -o '"NtEnb":[0-9]*' | grep -o '[0-9]*')
  if [ "$mode_check" = "$new_mode" ]; then
    echo "✅ Режим успішно змінено на $( [ "$new_mode" = "7" ] && echo "HTTP" || echo "MG" )"
  else
    echo "❌ Помилка при зміні режиму"
    exit 1
  fi
}

ip=$(get_ip)

# Модель та ім’я
device_info=$(curl --silent --digest -u $login:$password "http://$ip/cgi/state")
model=$(echo "$device_info" | grep -oP '"model":"\K[^"]+')
name=$(echo "$device_info" | grep -oP '"name":"\K[^"]+')
echo " $model - $name"

# Індикатор
indicator=$(curl --silent --digest -u $login:$password "http://$ip/cgi/scr" | grep -oP '(?<="str":")[^"]+' | awk 'NR==1 {sum=$0; getline; printf "  ┌──────────────────────┐\n  │ %-20s │\n  │ %-20s │\n  └──────────────────────┘\n", sum, $0}')
echo "$indicator"

# IP та режим
mode=$(curl --silent --digest -u $login:$password "http://$ip/cgi/tbl/Net" | grep -o '"NtEnb":[0-9]*' | grep -o '[0-9]*')
mode_name=$( [ "$mode" = "7" ] && echo "HTTP" || echo "MG" )
echo "IP: $ip, режим роботи - $mode_name"

# Непередані документи
ndoc=$(curl -s "http://$ip/cgi/status" | grep -o '"ndoc":[0-9]*' | grep -o '[0-9]*')
if [ "$ndoc" -eq 0 ]; then
  echo "Усі документи передані"
else
  echo "Не переданих документів - $ndoc"
fi

# Останній Z-звіт
last_z=$(curl --silent --digest -u $login:$password "http://$ip/cgi/param" | grep -o '"currZ":[0-9]*' | grep -o '[0-9]*')
echo "🧾 Останній Z-звіт — $last_z"

# Якщо передано аргументи — одразу друкуємо
if [[ -n "${BASH_ARGV[*]}" ]]; then
  is_open=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep 'isOpenCheck:' | tail -n1 | grep -o '[0-9]$')
  if [ "$is_open" != "0" ]; then
    echo "❌ Чек відкрито — неможливо друкувати звіти"
    exit 1
  fi
  for znum in "$@"; do
    curl --silent --digest -u $login:$password "http://$ip/cgi/zcopy?znum=$znum" > /dev/null
    echo "✅ Надруковано копію Z-звіту №$znum"
  done
  exit 0
fi

# Якщо MG — запропонувати змінити
if [ "$mode" = "8" ]; then
  echo "Режим MG буде змінено на HTTP для друку. Продовжити? (Y/n): "
  read -r answer
  if [[ "$answer" =~ ^[Nn]$ ]]; then
    echo "❌ Цей РРО працює в MG і не зможе виконати копію"
    exit 1
  fi
  change_mode "$ip" 7
  mode_changed=true
fi

# Перевірка isOpenCheck
while true; do
  is_open=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep 'isOpenCheck:' | tail -n1 | grep -o '[0-9]$')
  if [ "$is_open" = "0" ]; then
    break
  fi
  echo "❗ Чек відкрито, для друку необхідно закрити чек. Натисніть Enter після закриття..."
  read -r
done

# Запит звітів
echo -n "Введіть номери звітів для друку (через пробіл): "
read -r zlist

for znum in $zlist; do
  curl --silent --digest -u $login:$password "http://$ip/cgi/zcopy?znum=$znum" > /dev/null
  echo "✅ Надруковано копію Z-звіту №$znum"
done

# Повернення назад у MG
if [ "$mode_changed" = true ]; then
  echo "↩️ Повертаю режим назад у MG..."
  change_mode "$ip" 8
fi
