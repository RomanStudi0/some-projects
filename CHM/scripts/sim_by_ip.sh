#!/bin/bash

# Отримання параметра з командного рядка
client_name="$1"

# Перевірка чи параметр був переданий
if [ -z "$client_name" ]; then
    # Запитати ім'я клієнта з клавіатури
    read -p "Введіть ім'я клієнта: " client_name

    # Перевірка знову чи параметр тепер введений
    if [ -z "$client_name" ]; then
        echo "Помилка: Не введено ім'я клієнта. Вихід."
		echo "Не будемо ж сканувати всіх клієнтів))"
        exit 1
    fi
fi

# Команда, що надає таблицю VPN клієнтів Кулиничі
vpn_command="./vpnclient_super.sh $client_name"

# Виконуємо команду та обробляємо вихід
output=$($vpn_command | tail -n +2)  # Видаляємо перший рядок, починаючи з другого

# Ініціалізація лічильників провайдерів
vodafone_count=0
life_count=0
kyivstar_count=0
other_count=0

    echo "Таблиця точок:"
    echo "-------------------------------------------------------------"
    echo "|    Назва точки       |    Реальний IP        |  Оператор  |"
    echo "-------------------------------------------------------------"

# Перевірка для кожного рядка виводу
while IFS= read -r line; do
    hostname=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}')    #Отримуємо назву хоста
	IP=$(echo "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $NF); print $NF}')        #Отримуємо реальний IP в змінну
	first_b_of_IP=$(echo "$line" | awk '{gsub(/\./, "", $NF); print substr($NF, 1, 3)}')  #Отримуємо перші три цифри реальної адреси

    # Визначаємо провайдера
    case $first_b_of_IP in
        77[0-9])
            provider="Vodafone"
            ((vodafone_count++))
            ;;
        178)
            provider="Vodafone"
            ((vodafone_count++))
            ;;
        128)
            provider="Vodafone"
            ((vodafone_count++))
            ;;
        89[0-9])
            provider="Vodafone"
            ((vodafone_count++))
            ;;
        88[0-9])
            provider="Life"
            ((life_count++))
            ;;
        37[0-9])
            provider="Life"
            ((life_count++))
            ;;
        46[0-9])
            provider="Kyivstar"
            ((kyivstar_count++))
            ;;
        *)
            provider="Інший"
            ((other_count++))
            ;;
    esac
    # Виводимо результат

    printf "| %-20s | %-21s | %-10s |\n" "$hostname" "$IP" "$provider"
done <<< "$output"
    # Виведення кількості точок

    echo "   "
    echo "-------------------------------------------------------------"
    echo "Кількість Vodafone: $vodafone_count"
    echo "Кількість Life: $life_count"
    echo "Кількість Kyivstar: $kyivstar_count"
    echo "Кількість інших точок: $other_count"
	echo " "
total_count=$((vodafone_count + life_count + kyivstar_count + other_count))
	echo "Всього точок проскановано: $total_count"
    echo "-------------------------------------------------------------"
    echo "   "
