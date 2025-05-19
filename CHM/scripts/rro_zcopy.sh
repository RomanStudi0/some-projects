#!/bin/bash

login="service"
password="751426"

get_ip() {
  ip=$(systemctl status isc-dhcp-server 2>/dev/null | grep -oP 'DHCPACK on \K192\.168\.2\.\d+' | head -n1)
  [ -z "$ip" ] && ip=$(grep -Po '1\\host=\K[\d.]+' /etc/chameleon/fiscallistener.conf)
  for i in {1..4}; do ping -c1 -W1 "$ip" &>/dev/null && break || sleep 1; done
  echo "$ip"
}

get_mode() {
  curl --silent --digest -u "$login:$password" "http://$ip/cgi/tbl/Net" | grep -oP '"NtEnb":\K\d+'
}

set_mode_http() {
  curl --silent --digest -u "$login:$password" "http://$ip/cgi/tbl/Net" \
    -X POST -d '{"NtEnb":7,"NtNum":1,"NtBaud":38400,"Query":0,"LgNum":1,"WBar":0,"NetPsw":0,"ComPsw":0}' > /dev/null
}

set_mode_mg() {
  curl --silent --digest -u "$login:$password" "http://$ip/cgi/tbl/Net" \
    -X POST -d '{"NtEnb":8,"NtNum":1,"NtBaud":38400,"Query":0,"LgNum":1,"WBar":0,"NetPsw":0,"ComPsw":0}' > /dev/null
}

wait_for_ip() {
  for i in {1..15}; do ping -c1 -W1 "$ip" &>/dev/null && return 0 || sleep 1; done
  return 1
}

print_zcopies() {
  for znum in "$@"; do
    curl --silent --digest -u "$login:$password" "http://$ip/cgi/zcopy?znum=$znum" > /dev/null
    echo "✅ Надруковано копію Z-звіту №$znum"
  done
}

# --- Основний блок ---
ip=$(get_ip)
[ -z "$ip" ] && echo "❌ IP пристрою не знайдено" && exit 1

# Модель та назва
info=$(curl --silent --digest -u "$login:$password" "http://$ip/cgi/state")
model=$(echo "$info" | grep -oP '"model":"\K[^"]+')
serial=$(echo "$info" | grep -oP '"name":"\K[^"]+')
echo " $model - $serial"

# Індикатор
curl --silent --digest -u "$login:$password" "http://$ip/cgi/scr" | \
  grep -oP '(?<="str":")[^"]+' | awk 'NR==1 {sum=$0; getline; printf "  ┌──────────────────────┐\n  │ %-20s │\n  │ %-20s │\n  └──────────────────────┘\n", sum, $0}'

# IP + режим
mode=$(get_mode)
mode_name=$([ "$mode" -eq 8 ] && echo "MG" || echo "HTTP")
echo "IP: $ip, режим роботи - $mode_name"

# Непередані документи
ndoc=$(curl -s "http://$ip/cgi/status" | grep -o '"ndoc":[0-9]*' | grep -o '[0-9]*')
if [ "$ndoc" -eq 0 ]; then
  echo "Усі документи передані"
else
  echo "Не переданих документів - $ndoc"
fi

# Поточний Z-звіт
znum=$(curl --silent --digest -u "$login:$password" "http://$ip/cgi/zrep" | grep -oP '"currZ":\K\d+')
[ -n "$znum" ] && echo "🧾 Останній Z-звіт — $znum"

# --- Якщо передано аргументи — одразу друкуємо ---
if [[ "$#" -gt 0 ]]; then
  is_open=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep 'isOpenCheck:' | tail -n1 | grep -o '[0-9]$')
  if [ "$is_open" != "0" ]; then
    echo "❌ Чек відкрито — неможливо друкувати звіти"
    exit 1
  fi
  print_zcopies "$@"
  exit 0
fi

if [[ "$#" -gt 0 ]]; then
  # --- Якщо режим MG, запропонувати змінити ---
  if [ "$mode" -eq 8 ]; then
    read -p "Режим MG буде змінено на HTTP для друку. Продовжити? (Y/n): " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && echo "Цей РРО працює в MG і не зможе виконати копію" && exit 1
    set_mode_http
    sleep 5
    wait_for_ip || { echo "❌ Після зміни режиму пристрій не відповідає"; exit 1; }
    mode=$(get_mode)
    if [ "$mode" -ne 7 ]; then
      echo "❌ Не вдалося змінити режим на HTTP"
      exit 1
    fi
  fi

  # --- Перевірка isOpenCheck ---
  while true; do
    is_open=$(tail -n 2 /var/log/chameleon/fiscallistener.log | grep 'isOpenCheck:' | tail -n1 | grep -o '[0-9]$')
    if [ "$is_open" == "0" ]; then
      break
    else
      echo "Чек відкрито, для друку необхідно закрити чек"
      read -p "Натисніть Enter після закриття чеку..."
    fi
  done

  # --- Введення вручну номерів Z-звітів ---
  read -p "Введіть номери звітів для друку (через пробіл): " -a zlist
  print_zcopies "${zlist[@]}"

  # --- Якщо змінювався режим — повертаємо назад ---
  if [ "$mode_name" == "MG" ]; then
    set_mode_mg
    sleep 5
    wait_for_ip
    new_mode=$(get_mode)
    if [ "$new_mode" -eq 8 ]; then
      echo "✅ Режим успішно повернено на MG"
    else
      echo "⚠️ Не вдалося повернути режим MG"
    fi
  fi
fi
