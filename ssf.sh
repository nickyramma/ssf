#!/bin/bash

# Многофункциональный скрипт для настройки сервера:
# 1. Конфигурация SSH (изменение порта, отключение пароля, добавление ключа)
# 2. Отключить ICMP Ping
# 3. Установить Reshala-Remnawave-Bedolaga (DonMatteoVPN)
# 4. Установить Remnawave Node (Remnanode)
# 5. Обновить Remnawave Node (Remnanode)
# 6. Установить TrafficGuard-auto
# 7. Установить Warp Native
# 8. Проверить и установить обновления
# 9. Комплексная диагностика Remnanode (VLESS)

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="ssf.sh"
SCRIPT_REPO="https://raw.githubusercontent.com/nickyramma/ssf/main/ssf.sh"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$SCRIPT_NAME"
VERSION_FILE="/tmp/ssf_version.txt"

SSH_CONFIG_FILE="/etc/ssh/sshd_config"
CURRENT_USER=$(whoami) # ��олучаем имя текущего пользователя
OLD_SSH_PORT="22"

# --- Функция для конфигурирования SSH ---
configure_ssh() {
    echo "--- Начинаем конфигурирование SSH ---"

    # --- Запрос нового порта у пользователя ---
    while true; do
        read -p "Пожалуйста, введите новый желаемый порт для SSH (например, 2222): " NEW_SSH_PORT
        if [[ "$NEW_SSH_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_SSH_PORT" -ge 1024 ] && [ "$NEW_SSH_PORT" -le 65535 ] && [ "$NEW_SSH_PORT" -ne "$OLD_SSH_PORT" ]; then
            echo "Выбран новый порт SSH: $NEW_SSH_PORT"
            break
        else
            echo "Некорректный порт. Пожалуйста, введите число от 1024 до 65535, отличное от $OLD_SSH_PORT."
        fi
    done

    # --- Запрос отключения входа по паролю ---
    DISABLE_PASSWORD_AUTH="no"
    SSH_PUBLIC_KEY="" # Переменная для хранения публичного ключа

    echo ""
    echo "--- Внимание! Конфигурация аутентификации ---"
    echo "Если вы отключите вход по паролю, вы сможете входить ТОЛЬКО по SSH-ключам."
    echo "Убедитесь, что у вас есть рабочий SSH-ключ, прежде чем отключать парольную аутентификацию!"
    echo ""

    while true; do
        read -p "Отключить вход по паролю и разрешить только вход по SSH-ключам? (y/N): " -n 1 -r REPLY_PASSWORD_AUTH
        echo # (добавляем новую строку после ввода)
        if [[ "$REPLY_PASSWORD_AUTH" =~ ^[Yy]$ ]]; then
            DISABLE_PASSWORD_AUTH="yes"
            echo "Вход по паролю будет отключен. Убедитесь, что у вас настроен вход по SSH-ключам!"

            # Если пользователь выбрал отключить пароль, спрашиваем о добавлении ключа
            echo ""
            echo "Поскольку вы выбрали отключить вход по паролю, мы можем добавить ваш публичный SSH-ключ."
            echo "Ключ буде�� добавлен для текущего пользователя: '$CURRENT_USER'."
            echo "Пожалуйста, скопируйте полный текст вашего публичного SSH-ключа (начинается с ssh-rsa, ssh-ed25519 и т.д.)"
            echo "и вставьте его ниже. После вставки нажмите Enter, затем Ctrl+D, чтобы завершить ввод."
            echo "(или просто нажмите Enter, если не хотите добавлять ключ сейчас):"
            echo "--- Вставьте ваш публичный SSH-ключ здесь (Ctrl+D для завершения) ---"
            SSH_PUBLIC_KEY=$(cat) # Читаем ввод пользователя до Ctrl+D
            echo "--- Ввод ключа завершен ---"

            if [[ -n "$SSH_PUBLIC_KEY" ]]; then
                echo "Получен SSH-ключ. Он будет добавлен для пользователя '$CURRENT_USER'."
            else
                echo "SSH-ключ не был введен. Если вы отключите парольный вход без ключа, вы можете потерять доступ!"
                read -p "Вы уверены, что хотите продолжить без добавления ключа? (y/N): " -n 1 -r CONFIRM_NO_KEY
                echo
                if [[ ! $CONFIRM_NO_KEY =~ ^[Yy]$ ]]; then
                    echo "Отменено пользователем. Возвращаемся в главное меню."
                    return 1 # Возвращаемся в меню
                fi
            fi
            break
        elif [[ "$REPLY_PASSWORD_AUTH" =~ ^[Nn]$ || -z "$REPLY_PASSWORD_AUTH" ]]; then
            DISABLE_PASSWORD_AUTH="no"
            echo "Вход по паролю останется включенным."
            break
        else
            echo "Некорректный ввод. Пожалуйста, ответьте 'y' или 'n'."
        fi
    done

    # --- Подтверждение всех изменений ---
    echo ""
    echo "--- Подтверждение выбранных настроек ---"
    echo "Новый порт SSH: $NEW_SSH_PORT"
    echo "Отключить вход по паролю: $(if [ "$DISABLE_PASSWORD_AUTH" == "yes" ]; then echo "Да"; else echo "Нет"; fi)"
    if [ "$DISABLE_PASSWORD_AUTH" == "yes" ] && [ -n "$SSH_PUBLIC_KEY" ]; then
        echo "SSH-ключ будет добавлен для пользователя '$CURRENT_USER'."
    elif [ "$DISABLE_PASSWORD_AUTH" == "yes" ] && [ -z "$SSH_PUBLIC_KEY" ]; then
        echo "ВНИМАНИЕ: SSH-ключ НЕ БУДЕТ добавлен. Убедитесь, что он уже настроен!"
    fi
    read -p "Вы уверены, что хотите применить эти изменения? (y/N): " -n 1 -r
    echo # (добавляем новую строку после ввода)
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено пользователем. Возвращаемся в главное меню."
        return 1 # Возвращаемся в меню
    fi

    # --- 1. Отключение SSH-сокета systemd ---
    echo "1. Проверяем и отключаем SSH-сокет systemd..."
    if systemctl is-active --quiet sshd.socket; then
        echo "sshd.socket активен. Отключаем и останавливаем его."
        systemctl disable sshd.socket
        systemctl stop sshd.socket
        echo "sshd.socket успешно отключен и остановлен."
    elif systemctl is-active --quiet ssh.socket; then
        echo "ssh.socket активен. Отключаем и останавливаем его."
        systemctl disable ssh.socket
        systemctl stop ssh.socket
        echo "ssh.socket успешно отключен и остановлен."
    else
        echo "SSH-сокет systemd (sshd.socket или ssh.socket) не активен или не найден. Пропускаем."
    fi

    # --- 2. Изменение порта и настроек аутентификации в sshd_config ---
    echo "2. Изменяем порт и настройки аутентификации в $SSH_CONFIG_FILE..."

    # Создаем резервную копию оригинального файла
    cp "$SSH_CONFIG_FILE" "${SSH_CONFIG_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
    echo "Создана резервная копия: ${SSH_CONFIG_FILE}.bak_$(date +%Y%m%d_%H%M%S)"

    # Удаляем или комментируем все старые строки Port
    sed -i "/^Port /d" "$SSH_CONFIG_FILE"
    echo "Port $NEW_SSH_PORT" >> "$SSH_CONFIG_FILE" # Добавляем новую строку Port в конец файла
    echo "Порт SSH изменен на $NEW_SSH_PORT."

    # Настройка PasswordAuthentication
    if [ "$DISABLE_PASSWORD_AUTH" == "yes" ]; then
        echo "Отключение входа по паролю..."
        sed -i -E 's/^#?PasswordAuthentication yes/PasswordAuthentication no/' "$SSH_CONFIG_FILE"
        sed -i -E 's/^#?ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' "$SSH_CONFIG_FILE"
        sed -i -E 's/^#?UsePAM yes/UsePAM no/' "$SSH_CONFIG_FILE"
        echo "PasswordAuthentication, ChallengeResponseAuthentication и UsePAM установлены в 'no'."
    else
        echo "Вход по паролю останется включенным."
        sed -i -E 's/^#?PasswordAuthentication no/PasswordAuthentication yes/' "$SSH_CONFIG_FILE"
        echo "PasswordAuthentication установлен в 'yes'."
    fi

    echo "Текущие настройки Port и PasswordAuthentication в $SSH_CONFIG_FILE:"
    grep -E "(^Port|^PasswordAuthentication|^ChallengeResponseAuthentication|^UsePAM)" "$SSH_CONFIG_FILE" | grep -v '^#' # Показываем соответствующие строки

    # --- 2.1 Добавление SSH-ключа (если выбрано) ---
    if [ "$DISABLE_PASSWORD_AUTH" == "yes" ] && [ -n "$SSH_PUBLIC_KEY" ]; then
        echo "2.1 Добавляем предоставленный публичный SSH-ключ для пользователя '$CURRENT_USER'..."
        HOME_DIR=$(eval echo ~"$CURRENT_USER") # Получаем домашнюю директорию пользователя
        SSH_DIR="$HOME_DIR/.ssh"
        AUTHORIZED_KEYS_FILE="$SSH_DIR/authorized_keys"

        # Создаем директорию .ssh и файл authorized_keys, если их нет
        mkdir -p -m 700 "$SSH_DIR"
        touch "$AUTHORIZED_KEYS_FILE"
        chmod 600 "$AUTHORIZED_KEYS_FILE"

        # Добавляем ключ в authorized_keys, если его там еще нет
        if ! grep -qF "$SSH_PUBLIC_KEY" "$AUTHORIZED_KEYS_FILE"; then
            echo "$SSH_PUBLIC_KEY" >> "$AUTHORIZED_KEYS_FILE"
            echo "Публичный SSH-ключ добавлен в $AUTHORIZED_KEYS_FILE."
        else
            echo "Публичный SSH-ключ уже существует в $AUTHORIZED_KEYS_FILE. Пропускаем добавление."
        fi
        # Устанавливаем правильные владельца и права (важно для SSH!)
        chown -R "$CURRENT_USER:$CURRENT_USER" "$SSH_DIR"
        echo "Установлены правильные права доступа для $SSH_DIR и $AUTHORIZED_KEYS_FILE."
    fi

    # --- 3. Настройка фаервола ---
    echo "3. Настраиваем фаервол..."

    if command -v ufw &> /dev/null; then
        echo "Обнаружен UFW. Настраиваем UFW..."
        ufw allow "$NEW_SSH_PORT"/tcp
        if ufw status | grep -q "${OLD_SSH_PORT}/tcp"; then # Проверяем, есть ли правило для старого порта
            ufw delete allow "$OLD_SSH_PORT"/tcp
            echo "Правило для старого порта $OLD_SSH_PORT/tcp удалено из UFW."
        else
            echo "Правило для старого порта $OLD_SSH_PORT/tcp не найдено в UFW, пропускаем удаление."
        fi
        # ufw reload # UFW автоматически перезагружается при изменениях, но на всякий случай
        echo "UFW настроен. Новый порт $NEW_SSH_PORT/tcp разрешен."
        ufw status verbose | grep -E "($NEW_SSH_PORT|$OLD_SSH_PORT|Status)"

    elif command -v firewall-cmd &> /dev/null; then
        echo "Обнаружен firewalld. Настраиваем firewalld..."
        firewall-cmd --permanent --add-port="$NEW_SSH_PORT"/tcp
        firewall-cmd --permanent --remove-port="$OLD_SSH_PORT"/tcp 2>/dev/null # Удаляем старое, ошибки игнорируем, если нет правила
        firewall-cmd --reload
        echo "firewalld настроен. Новый порт $NEW_SSH_PORT/tcp разрешен."
        firewall-cmd --list-all | grep -E "(ports|$NEW_SSH_PORT|$OLD_SSH_PORT)"

    else
        echo "Не удалось определить поддерживаемый фаервол (UFW или firewalld)."
        echo "Вам необходимо вручную настроить ваш фаервол, чтобы разрешить входящие соединения на порту $NEW_SSH_PORT/tcp."
        echo "Пример для iptables (может отличаться):"
        echo "sudo iptables -A INPUT -p tcp --dport $NEW_SSH_PORT -j ACCEPT"
        echo "sudo service netfilter-persistent save" # или другая команда для сохранения iptables
    fi

    # --- 4. Перезапуск SSH-сервиса ---
    echo "4. Перезапускаем SSH-сервис..."
    if systemctl is-active --quiet sshd; then
        systemctl restart sshd
        echo "Сервис sshd перезапущен."
    elif systemctl is-active --quiet ssh; then
        systemctl restart ssh
        echo "Сервис ssh перезапущен."
    else
        echo "Не удалось найти активный сервис SSH (sshd или ssh). Пожалуйста, проверьте вручную."
        return 1
    fi

    echo "--- Скрипт SSH выполнен. ---"
    echo "ВАЖНО: НЕ ЗАКРЫВАЙТЕ ЭТО SSH-СОЕДИНЕНИЕ, пока не проверите новое!"
    echo "Попробуйте подключиться из нового терминала:"
    echo "ssh -p $NEW_SSH_PORT ваш_пользователь@ваш_IP_сервера_или_домен"
    if [ "$DISABLE_PASSWORD_AUTH" == "yes" ]; then
        echo "ПОМНИТЕ: Теперь вы можете подключиться ТОЛЬКО с помощью SSH-ключа!"
        echo "При подключении используйте: ssh -p $NEW_SSH_PORT -i /путь/к/вашему/ssh_ключу ваш_пользователь@ваш_IP_сервера_или_домен"
    fi
    echo "Убедитесь, что новый порт и выбранный метод аутентификации работают, прежде чем закрывать текущее соединение."
    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для отключения ICMP Ping ---
disable_icmp_ping() {
    echo "--- Отключение ICMP Ping ---"
    echo "Это сделает ваш сервер менее заметным для сканирования."

    read -p "Вы уверены, что хотите отключить ICMP Ping? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено пользователем. Возвращаемся в главное меню."
        return 1
    fi

    SYSCTL_CONF="/etc/sysctl.conf"
    SYSCTL_D_CONF="/etc/sysctl.d/99-disable-ping.conf" # Отдельный файл для чистоты

    # Создаем резервную копию
    if [ -f "$SYSCTL_CONF" ]; then
        cp "$SYSCTL_CONF" "${SYSCTL_CONF}.bak_$(date +%Y%m%d_%H%M%S)"
        echo "Создана резервная копия $SYSCTL_CONF."
    fi

    echo "Добавляем или изменяем настройки net.ipv4.icmp_echo_ignore_all..."

    # Удаляем старые записи из sysctl.conf, если они есть
    sed -i '/^net.ipv4.icmp_echo_ignore_all/d' "$SYSCTL_CONF"

    # Создаем или перезаписываем файл в sysctl.d для отключения пинга
    echo "net.ipv4.icmp_echo_ignore_all = 1" | tee "$SYSCTL_D_CONF" > /dev/null
    echo "Файл $SYSCTL_D_CONF создан с параметром net.ipv4.icmp_echo_ignore_all = 1."

    # Применяем изменения
    sysctl -p "$SYSCTL_D_CONF"
    echo "Изменения применены. ICMP Ping отключен."

    echo "Текущее значение net.ipv4.icmp_echo_ignore_all: $(sysctl -n net.ipv4.icmp_echo_ignore_all)"
    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для установки DonMatteoVPN ---
install_donmatteovpn() {
    echo "--- Установка Reshala-Remnawave-Bedolaga (DonMatteoVPN) ---"

    read -p "Вы уверены, что хотите начать установку скрипта DonMatteoVPN? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено пользователем. Возвращаемся в главное меню."
        return 1
    fi

    echo "Начинаем загрузку и запуск установочного скрипта..."

    # Проверяем наличие wget
    if ! command -v wget &> /dev/null; then
        echo "wget не найден. Устанавливаем wget..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y wget
        elif command -v yum &> /dev/null; then
            yum install -y wget
        elif command -v dnf &> /dev/null; then
            dnf install -y wget
        else
            echo "Не удалось установить wget. Пожалуйста, установите его вручную и повторите попытку."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
    fi

    # Выполняем команду установки
    wget -O install.sh https://raw.githubusercontent.com/DonMatteoVPN/Reshala-Remnawave-Bedolaga/main/install.sh \
      && bash install.sh \
      && reshala
    
    # Прове��ка успешности установки
    if [ $? -eq 0 ]; then
        echo "Установка DonMatteoVPN, предположительно, завершена успешно."
    else
        echo "Во время установки DonMatteoVPN произошла ошибка."
    fi

    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для установки Remnawave Node ---
install_remnanode() {
    echo "--- Установка Remnawave Node (Remnanode) ---"
    echo "Для установки Remnanode требуется Docker и Docker Compose."
    echo ""

    read -p "Вы уверены, что хотите начать установку Remnanode? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено пользователем. Возвращаемся в главное меню."
        return 1
    fi

    # --- Проверка и установка Docker ---
    if ! command -v docker &> /dev/null; then
        echo "Docker не найден. Предлагаем установить Docker."
        read -p "Установить Docker сейчас? (y/N): " -n 1 -r INSTALL_DOCKER_REPLY
        echo
        if [[ "$INSTALL_DOCKER_REPLY" =~ ^[Yy]$ ]]; then
            echo "Начинаем установку Docker..."
            # Установка curl, если отсутствует
            if ! command -v curl &> /dev/null; then
                echo "curl не найден. Устанавливаем curl..."
                if command -v apt-get &> /dev/null; then
                    apt-get update && apt-get install -y curl
                elif command -v yum &> /dev/null; then
                    yum install -y curl
                elif command -v dnf &> /dev/null; then
                    dnf install -y curl
                else
                    echo "Не удалось установить curl. Пожалуйста, установите его вручную."
                    read -p "Нажмите Enter для продолжения..."
                    return 1
                fi
            fi
            # Запуск официального установочного скрипта Docker
            sudo curl -fsSL https://get.docker.com | sh
            if [ $? -ne 0 ]; then
                echo "Ошибка при установке Docker. Пожалуйста, проверьте логи и повторите попытку."
                read -p "Нажмите Enter для продолжения..."
                return 1
            fi
            echo "Docker успешно установлен."
            # Добавляем текущего пользователя в группу docker, чтобы не использовать sudo постоянно
            sudo usermod -aG docker "$CURRENT_USER"
            echo "Пользователь '$CURRENT_USER' добавлен в группу 'docker'. Для применения изменений может потребоваться перезагрузка."
            # Даем небольшую задержку, чтобы Docker мог полностью инициализироваться
            sleep 5
        else
            echo "Установка Docker отменена. Remnanode не может быть установлен без Docker."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
    fi

    # --- Проверка и установка Docker Compose V2 (если не установлен) ---
    if ! docker compose version &> /dev/null; then
        echo "Docker Compose V2 не найден. Предлагаем установить Docker Compose."
        read -p "Установить Docker Compose сейчас? (y/N): " -n 1 -r INSTALL_COMPOSE_REPLY
        echo
        if [[ "$INSTALL_COMPOSE_REPLY" =~ ^[Yy]$ ]]; then
            echo "Начинаем установку Docker Compose V2..."
            if command -v apt-get &> /dev/null; then
                apt-get update && apt-get install -y docker-compose-plugin
            elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
                echo "Для RHEL/CentOS/Fedora Docker Compose V2 обычно устанавливается вместе с Docker."
                echo "Пожалуйста, убедитесь, что Docker Compose доступен после установки Docker."
            else
                echo "Не удалось определить менеджер пакетов для установки Docker Compose."
                echo "Пожалуйста, установите Docker Compose V2 вручную: https://docs.docker.com/compose/install/"
                read -p "Нажмите Enter для продолжения..."
                return 1
            fi
            if [ $? -ne 0 ]; then
                echo "Ошибка при установке Docker Compose. Пожалуйста, проверьте логи и повторите попытку."
                read -p "Нажмите Enter для продолжения..."
                return 1
            fi
            echo "Docker Compose V2 успешно установлен."
        else
            echo "Установка Docker Compose отменена. Remnanode не может быть установлен без Docker Compose."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
    fi

    echo "Docker и Docker Compose готовы к использованию."


    # Запрос SECRET_KEY
    echo ""
    read -p "Пожалуйста, введите ваш SECRET_KEY для Remnanode (полученный из панели управления Remnawave): " SECRET_KEY_INPUT
    if [[ -z "$SECRET_KEY_INPUT" ]]; then
        echo "SECRET_KEY не был введен. Отмена установки Remnanode."
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

    # NODE_PORT всегда 2222
    NODE_PORT_INPUT="2222"
    echo "Порт для Remnanode автоматически установлен на: $NODE_PORT_INPUT"


    # Создание директории для Remnanode
    REMNA_DIR="/opt/remnanode"
    mkdir -p "$REMNA_DIR"
    cd "$REMNA_DIR" || { echo "Не удалось перейти в директорию $REMNA_DIR. Отмена."; read -p "Нажмите Enter для продолжения..."; return 1; }
    echo "Создана директория $REMNA_DIR и перешли в нее."

    # Создание docker-compose.yml
    echo "Создаем docker-compose.yml..."
    cat << EOF > docker-compose.yml
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=${NODE_PORT_INPUT}
      - SECRET_KEY="${SECRET_KEY_INPUT}"
EOF
    echo "Файл docker-compose.yml создан:"
    cat docker-compose.yml

    # Запуск Remnanode через Docker Compose
    echo "Запускаем Remnawave Node..."
    docker compose up -d
    
    # Проверка статуса
    if [ $? -eq 0 ]; then
        echo "Remnawave Node запущен успешно!"
        echo "Вы можете проверить статус командой: docker compose ps"
        echo "И логи: docker compose logs -f remnanode"
    else
        echo "Во время запуска Remnawave Node произошла ошибка."
    fi

    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для обновления Remnawave Node ---
update_remnanode() {
    echo "--- Обновление Remnawave Node (Remnanode) ---"

    # Проверка наличия Docker
    if ! command -v docker &> /dev/null; then
        echo "✗ Ошибка: Docker не найден."
        echo "Пожалуйста, установите Docker перед обновлением Remnanode."
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

    # Проверка наличия Docker Compose
    if ! docker compose version &> /dev/null; then
        echo "✗ Ошибка: Docker Compose V2 не найден."
        echo "Пожалуйста, установите Docker Compose V2 перед обновлением Remnanode."
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

    echo "Docker и Docker Compose найдены."
    echo ""

    # Поиск директории установки Remnanode
    REMNA_DIR=""
    SEARCH_PATHS=("/opt/remnanode" "/root/remnanode" "/home/remnanode" "$(pwd)")
    COMPOSE_FILES=("docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml")

    echo "Поиск директории установки Remnanode..."
    for path in "${SEARCH_PATHS[@]}"; do
        if [ -d "$path" ]; then
            for compose_file in "${COMPOSE_FILES[@]}"; do
                if [ -f "$path/$compose_file" ]; then
                    REMNA_DIR="$path"
                    echo "✓ Найдена директория: $REMNA_DIR"
                    echo "  Файл compose: $compose_file"
                    break 2
                fi
            done
        fi
    done

    # Если директория не найдена автоматически, спросить у пользователя
    if [ -z "$REMNA_DIR" ]; then
        echo "Автоматический поиск не дал результатов."
        echo ""
        read -p "Пожалуйста, введите путь к директории Remnanode вручную: " REMNA_DIR

        # Проверка наличия директории
        if [ ! -d "$REMNA_DIR" ]; then
            echo "✗ Ошибка: Директория '$REMNA_DIR' не существует."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi

        # Проверка наличия файла compose
        FOUND_COMPOSE=0
        for compose_file in "${COMPOSE_FILES[@]}"; do
            if [ -f "$REMNA_DIR/$compose_file" ]; then
                FOUND_COMPOSE=1
                echo "✓ Найден файл compose: $compose_file"
                break
            fi
        done

        if [ $FOUND_COMPOSE -eq 0 ]; then
            echo "✗ Ошибка: В директории '$REMNA_DIR' не найдено файлов compose."
            echo "  Ожидаемые файлы: docker-compose.yml, docker-compose.yaml, compose.yml, compose.yaml"
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
    fi

    echo ""
    echo "--- Информация об обновлении ---"
    echo "Директория: $REMNA_DIR"
    echo ""

    # Запрос подтверждения
    read -p "Продолжить обновление? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено пользователем. Возвращаемся в главное меню."
        return 1
    fi

    # Переход в директорию Remnanode
    cd "$REMNA_DIR" || { echo "✗ Ошибка: Не удалось перейти в директорию $REMNA_DIR."; read -p "Нажмите Enter для продолжения..."; return 1; }
    echo "Перешли в директорию: $REMNA_DIR"
    echo ""

    # Выполнение обновления
    echo "--- Начинаем обновление ---"
    echo ""

    echo "1. Загружаем новый образ контейнера..."
    docker compose pull
    if [ $? -ne 0 ]; then
        echo "✗ Ошибка при загрузке образа (docker compose pull)."
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi
    echo "✓ Образ успешно загружен."
    echo ""

    echo "2. Пересоздаем контейнер с новым образом..."
    docker compose up -d --force-recreate --remove-orphans
    if [ $? -ne 0 ]; then
        echo "✗ Ошибка при запуске контейнера (docker compose up -d --force-recreate --remove-orphans)."
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi
    echo "✓ Контейнер успешно обновлен и запущен."
    echo ""

    echo "3. Очищаем неиспользуемые образы..."
    docker image prune -f
    if [ $? -ne 0 ]; then
        echo "⚠ Предупреждение: Ошибка при очистке образов (docker image prune -f). Продолжаем."
    else
        echo "✓ Неиспользуемые образы удалены."
    fi
    echo ""

    # Показываем статус контейнера
    echo "--- Текущий статус контейнера ---"
    docker compose ps
    echo ""

    # Проверка успешности обновления
    if docker compose ps | grep -q "remnanode.*Up"; then
        echo "✓ Remnawave Node успешно обновлён!"
    else
        echo "⚠ Предупреждение: Статус контейнера remnanode не выглядит правильно. Пожалуйста, проверьте вручную."
    fi

    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для установки TrafficGuard-auto ---
install_trafficguard() {
    echo "--- Установка TrafficGuard-auto ---"

    read -p "Вы уверены, что хотите начать установку TrafficGuard-auto? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено пользователем. Возвращаемся в главное меню."
        return 1
    fi

    echo "Начинаем загрузку и запуск установочного скрипта TrafficGuard-auto..."

    # Проверяем наличие curl
    if ! command -v curl &> /dev/null; then
        echo "curl не найден. Устанавливаем curl..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y curl
        elif command -v yum &> /dev/null; then
            yum install -y curl
        elif command -v dnf &> /dev/null; then
            dnf install -y curl
        else
            echo "Не удалось установить curl. Пожалуйста, установите его вручную и повторите попытку."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
    fi

    # Выполняем команду установки
    curl -fsSL https://raw.githubusercontent.com/DonMatteoVPN/TrafficGuard-auto/refs/heads/main/install-trafficguard.sh | bash
    
    # Проверка успешности установки
    if [ $? -eq 0 ]; then
        echo "Установка TrafficGuard-auto, предположительно, завершена успешно."
    else
        echo "Во время установки TrafficGuard-auto произошла ошибка."
    fi

    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для установки Warp Native ---
install_warp_native() {
    echo "--- Установка Warp Native ---"

    read -p "Вы уверены, что хотите начать установку Warp Native? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено пользователем. Возвращаемся в главное меню."
        return 1
    fi

    echo "Начинаем загрузку и запуск установочного скрипта Warp Native..."

    # Проверяем наличие curl
    if ! command -v curl &> /dev/null; then
        echo "curl не найден. Устанавливаем curl..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y curl
        elif command -v yum &> /dev/null; then
            yum install -y curl
        elif command -v dnf &> /dev/null; then
            dnf install -y curl
        else
            echo "Не удалось установить curl. Пожалуйста, установите его вручную и повторите попытку."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
    fi

    # Выполняем команду установки
    bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/install.sh)
    
    # Проверка успешности установки
    if [ $? -eq 0 ]; then
        echo "Установка Warp Native, предположительно, завершена успешно."
    else
        echo "Во время установки Warp Native произошла ошибка. Пожалуйста, проверьте логи вывода."
    fi

    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для проверки и установки обновлений ---
check_and_update() {
    echo "--- Проверка и установка обновлений ---"
    echo "Текущая версия скрипта: $SCRIPT_VERSION"
    echo ""

    # Проверяем наличие curl
    if ! command -v curl &> /dev/null; then
        echo "curl не найден. Устанавливаем curl..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y curl
        elif command -v yum &> /dev/null; then
            yum install -y curl
        elif command -v dnf &> /dev/null; then
            dnf install -y curl
        else
            echo "Не удалось установить curl. Невозможно проверить обновления."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
    fi

    echo "Проверяем наличие новой версии на GitHub..."
    
    # Загружаем новый скрипт во временный файл
    TEMP_SCRIPT="/tmp/ssf_new.sh"
    if curl -fsSL -o "$TEMP_SCRIPT" "$SCRIPT_REPO"; then
        echo "✓ Скрипт успешно загружен."
        
        # Извлекаем версию из скрипта
        NEW_VERSION=$(grep "^SCRIPT_VERSION=" "$TEMP_SCRIPT" | cut -d'"' -f2)
        
        if [ -z "$NEW_VERSION" ]; then
            echo "⚠ Не удалось определить версию нового скрипта."
            rm -f "$TEMP_SCRIPT"
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
        
        echo "Доступная версия на GitHub: $NEW_VERSION"
        
        # Сравниваем версии
        if [ "$NEW_VERSION" == "$SCRIPT_VERSION" ]; then
            echo "✓ Вы используете последнюю версию скрипта."
            rm -f "$TEMP_SCRIPT"
            read -p "Нажмите Enter для продолжения..."
            return 0
        else
            echo ""
            echo "⚡ Доступно обновление!"
            echo "Текущая версия: $SCRIPT_VERSION"
            echo "Новая версия:   $NEW_VERSION"
            echo ""
            
            read -p "Хотите установить обновление? (y/N): " -n 1 -r REPLY
            echo
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Устанавливаем обновление..."
                
                # Создаем резервную копию текущего скрипта
                cp "$SCRIPT_PATH" "${SCRIPT_PATH}.bak_$(date +%Y%m%d_%H%M%S)"
                echo "✓ Резервная копия создана: ${SCRIPT_PATH}.bak_*"
                
                # Копируем новый скрипт на место старого
                cp "$TEMP_SCRIPT" "$SCRIPT_PATH"
                chmod +x "$SCRIPT_PATH"
                
                echo "✓ Обновление установлено успешно!"
                echo ""
                echo "⚠ ВНИМАНИЕ: Скрипт был обновлен. Перезагрузите его для полного применения изменений."
                echo "Запустите команду: $SCRIPT_PATH"
                echo ""
                rm -f "$TEMP_SCRIPT"
                read -p "Нажмите Enter для продолжения..."
                return 0
            else
                echo "Обновление отменено пользователем."
                rm -f "$TEMP_SCRIPT"
                read -p "Нажмите Enter для продолжения..."
                return 1
            fi
        fi
    else
        echo "✗ Ошибка при загрузке скрипта с GitHub."
        echo "Пожалуйста, проверьте интернет-соединение и повторите попытку."
        rm -f "$TEMP_SCRIPT"
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi
}

# --- Функция для комплексной диагностики Remnanode (VLESS) ---
diagnostic_remnanode() {
    echo "--- Комплексная диагностика Remnanode (VLESS) ---"
    echo ""

    # Инициализация переменных для результатов проверки
    DIAG_RESULTS=()
    DIAG_WARNINGS=()
    DIAG_ERRORS=()
    SERVER_PROBLEMS=0
    CLIENT_PROBLEMS=0

    # Запрос информации у пользователя
    read -p "Введите IP пользователя (CIDR): " USER_IP
    read -p "Введите домен сервера (если используется, иначе Enter): " SERVER_DOMAIN
    read -p "Введите порт (по умолчанию 443): " DIAG_PORT
    DIAG_PORT="${DIAG_PORT:-443}"

    read -p "Проверить SSL/TLS сертификат? (y/N): " -n 1 -r CHECK_SSL
    echo

    # === ПРОВЕРКА 1: Docker ===
    echo "Выполняется Проверка 1: Docker..."
    if ! command -v docker &> /dev/null; then
        DIAG_ERRORS+=("[✗] Docker не установлен")
        SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
    else
        DIAG_RESULTS+=("[✓] Docker установлен")
        
        if ! docker ps &> /dev/null; then
            DIAG_ERRORS+=("[✗] Docker daemon не работает")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        else
            DIAG_RESULTS+=("[✓] Docker работает")
        fi

        if ! docker compose version &> /dev/null; then
            DIAG_ERRORS+=("[✗] Docker Compose не установлен")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        else
            DIAG_RESULTS+=("[✓] Docker Compose установлен")
        fi
    fi

    # === ПРОВЕРКА 2: Контейнеры Remnanode ===
    echo "Выполняется Проверка 2: Контейнеры Remnanode..."
    if command -v docker &> /dev/null; then
        CONTAINER_STATUS=$(docker ps -a --filter "name=remnanode" --format "{{.Status}}" 2>/dev/null | head -1)
        
        if [ -z "$CONTAINER_STATUS" ]; then
            DIAG_WARNINGS+=("[!] Контейнер remnanode не найден")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        elif echo "$CONTAINER_STATUS" | grep -q "Up"; then
            DIAG_RESULTS+=("[✓] Контейнер запущен")
        elif echo "$CONTAINER_STATUS" | grep -q "Exited"; then
            DIAG_ERRORS+=("[✗] Контейнер остановлен")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        elif echo "$CONTAINER_STATUS" | grep -q "Restarting"; then
            DIAG_ERRORS+=("[✗] Контейнер перезапускается (может быть критическая ошибка)")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        fi
    fi

    # === ПРОВЕРКА 3: Прослушивание портов ===
    echo "Выполняется Проверка 3: Прослушивание портов..."
    if command -v ss &> /dev/null; then
        PORT_CHECK=$(ss -tulpn 2>/dev/null | grep -E ":$DIAG_PORT\s" | head -1)
    elif command -v netstat &> /dev/null; then
        PORT_CHECK=$(netstat -tulpn 2>/dev/null | grep -E ":$DIAG_PORT\s" | head -1)
    else
        PORT_CHECK=""
    fi

    if [ -n "$PORT_CHECK" ]; then
        DIAG_RESULTS+=("[✓] Порт $DIAG_PORT прослушивается")
    else
        DIAG_ERRORS+=("[✗] Порт $DIAG_PORT не прослушивается")
        SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
    fi

    # === ПРОВЕРКА 4: Firewall ===
    echo "Выполняется Проверка 4: Firewall..."
    FIREWALL_BLOCKED=0
    
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -qE "$DIAG_PORT/tcp.*ALLOW"; then
                DIAG_ERRORS+=("[✗] UFW блокирует порт $DIAG_PORT")
                FIREWALL_BLOCKED=1
                SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
            else
                DIAG_RESULTS+=("[✓] UFW разрешает порт $DIAG_PORT")
            fi
        else
            DIAG_RESULTS+=("[✓] UFW не активен")
        fi
    fi

    if command -v firewall-cmd &> /dev/null; then
        if ! firewall-cmd --query-port="$DIAG_PORT/tcp" &> /dev/null; then
            DIAG_ERRORS+=("[✗] firewalld блокирует порт $DIAG_PORT")
            FIREWALL_BLOCKED=1
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        else
            DIAG_RESULTS+=("[✓] firewalld разрешает порт $DIAG_PORT")
        fi
    fi

    if [ $FIREWALL_BLOCKED -eq 0 ] && ! command -v ufw &> /dev/null && ! command -v firewall-cmd &> /dev/null; then
        DIAG_RESULTS+=("[✓] Firewall не обнаружен (или iptables используется)")
    fi

    # === ПРОВЕРКА 5: Системное время ===
    echo "Выполняется Проверка 5: Системное время..."
    if command -v timedatectl &> /dev/null; then
        if timedatectl | grep -q "System clock synchronized: yes\|synchronized: yes"; then
            DIAG_RESULTS+=("[✓] Время синхронизировано")
        else
            DIAG_WARNINGS+=("[!] Время может быть не синхронизировано")
        fi
    else
        DIAG_RESULTS+=("[✓] Проверка времени не доступна")
    fi

    # === ПРОВЕРКА 6: Ресурсы сервера ===
    echo "Выполняется Проверка 6: Ресурсы сервера..."
    if command -v free &> /dev/null; then
        FREE_MEM=$(free -h | awk 'NR==2 {print $7}')
        MEM_PERCENT=$(free | awk 'NR==2 {printf "%.0f", ($3/$2)*100}')
        DIAG_RESULTS+=("[✓] Свободная память: $FREE_MEM ($MEM_PERCENT% использовано)")
        
        if [ "$MEM_PERCENT" -gt 90 ]; then
            DIAG_WARNINGS+=("[!] Почти нет свободной памяти ($MEM_PERCENT%)")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        fi
    fi

    if command -v df &> /dev/null; then
        DISK_USAGE=$(df / | awk 'NR==2 {printf "%.0f", ($3/$2)*100}')
        DISK_FREE=$(df -h / | awk 'NR==2 {print $4}')
        DIAG_RESULTS+=("[✓] Использование диска: $DISK_USAGE% (свободно: $DISK_FREE)")
        
        if [ "$DISK_USAGE" -gt 90 ]; then
            DIAG_WARNINGS+=("[!] Диск почти полон ($DISK_USAGE%)")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        fi
    fi

    if command -v uptime &> /dev/null; then
        UPTIME=$(uptime -p 2>/dev/null || uptime | sed 's/.*up //' | sed 's/,.*//')
        DIAG_RESULTS+=("[✓] Uptime: $UPTIME")
    fi

    # === ПРОВЕРКА 7: Публичный IP ===
    echo "Выполняется Проверка 7: Публичный IP..."
    if command -v hostname &> /dev/null; then
        SERVER_PUBLIC_IP=$(hostname -I | awk '{print $1}')
        DIAG_RESULTS+=("[✓] IP сервера: $SERVER_PUBLIC_IP")
    fi

    # === ПРОВЕРКА 8: Проверка сети пользователя ===
    echo "Выполняется Проверка 8: Проверка сети пользователя..."
    PING_RESULT=0
    
    if command -v ping &> /dev/null; then
        if ping -c 1 -W 2 "$USER_IP" &> /dev/null 2>&1; then
            DIAG_RESULTS+=("[✓] Ping до пользователя успешен")
        else
            DIAG_WARNINGS+=("[!] Ping до пользователя не проходит (может быть отключен ICMP)")
            CLIENT_PROBLEMS=$((CLIENT_PROBLEMS + 1))
            PING_RESULT=1
        fi
    fi

    if [ "$PING_RESULT" -eq 1 ] && command -v tracepath &> /dev/null; then
        TRACE_RESULT=$(tracepath -m 5 "$USER_IP" 2>&1 | tail -1)
        if echo "$TRACE_RESULT" | grep -q "no reply\|unreachable"; then
            DIAG_WARNINGS+=("[!] Маршрут до пользователя может быть заблокирован")
            CLIENT_PROBLEMS=$((CLIENT_PROBLEMS + 1))
        fi
    fi

    # === ПРОВЕРКА 9: Проверка домена ===
    echo "Выполняется Проверка 9: Проверка домена..."
    if [ -n "$SERVER_DOMAIN" ]; then
        if command -v dig &> /dev/null; then
            DOMAIN_IP=$(dig +short "$SERVER_DOMAIN" A 2>/dev/null | head -1)
        elif command -v host &> /dev/null; then
            DOMAIN_IP=$(host "$SERVER_DOMAIN" 2>/dev/null | awk '/has address/ {print $4; exit}')
        elif command -v nslookup &> /dev/null; then
            DOMAIN_IP=$(nslookup "$SERVER_DOMAIN" 2>/dev/null | awk '/^Address:/ {print $2; exit}')
        fi

        if [ -n "$DOMAIN_IP" ]; then
            if [ "$DOMAIN_IP" == "$SERVER_PUBLIC_IP" ] || [ "$DOMAIN_IP" == "127.0.0.1" ]; then
                DIAG_RESULTS+=("[✓] Домен $SERVER_DOMAIN указывает на правильный IP")
            else
                DIAG_ERRORS+=("[✗] Домен $SERVER_DOMAIN указывает на $DOMAIN_IP (ожидается $SERVER_PUBLIC_IP)")
                CLIENT_PROBLEMS=$((CLIENT_PROBLEMS + 1))
            fi
        else
            DIAG_WARNINGS+=("[!] Не удалось разрешить домен $SERVER_DOMAIN")
            CLIENT_PROBLEMS=$((CLIENT_PROBLEMS + 1))
        fi
    else
        DIAG_RESULTS+=("[✓] Домен не указан, пропуск проверки")
    fi

    # === ПРОВЕРКА 10: Проверка SSL ===
    echo "Выполняется Проверка 10: Проверка SSL..."
    if [[ "$CHECK_SSL" =~ ^[Yy]$ ]]; then
        if command -v openssl &> /dev/null; then
            SSL_OUTPUT=$(echo "Q" | timeout 5 openssl s_client -connect "$SERVER_PUBLIC_IP:$DIAG_PORT" -servername "${SERVER_DOMAIN:-$SERVER_PUBLIC_IP}" 2>&1)
            
            if echo "$SSL_OUTPUT" | grep -q "Verify return code"; then
                if echo "$SSL_OUTPUT" | grep -q "Verify return code: 0 (ok)"; then
                    DIAG_RESULTS+=("[✓] SSL сертификат валидный")
                else
                    DIAG_ERRORS+=("[✗] SSL сертификат невалидный")
                    CLIENT_PROBLEMS=$((CLIENT_PROBLEMS + 1))
                fi
            fi

            # Проверка срока действия
            EXPIRY=$(echo "$SSL_OUTPUT" | grep -oP "notAfter=\K.*" | head -1)
            if [ -n "$EXPIRY" ]; then
                DIAG_RESULTS+=("[✓] Сертификат действителен до: $EXPIRY")
            fi

            # Проверка TLS handshake ошибок
            if echo "$SSL_OUTPUT" | grep -q "handshake failure\|certificate verify failed\|SSLV3_ALERT"; then
                DIAG_ERRORS+=("[✗] Обнаружены ошибки TLS handshake")
                CLIENT_PROBLEMS=$((CLIENT_PROBLEMS + 1))
            fi
        else
            DIAG_RESULTS+=("[✓] openssl не найден, пропуск проверки сертификата")
        fi
    else
        DIAG_RESULTS+=("[✓] Проверка SSL пропущена пользователем")
    fi

    # === ПРОВЕРКА 11: Анализ логов ===
    echo "Выполняется Проверка 11: Анализ логов..."
    if command -v docker &> /dev/null; then
        LOGS=$(docker logs remnanode 2>&1 | tail -50)

        # Поиск различных проблем в логах
        if echo "$LOGS" | grep -qi "error\|failed"; then
            ERROR_TYPE=$(echo "$LOGS" | grep -i "error\|failed" | tail -1)
            DIAG_WARNINGS+=("[!] Обнаружены ошибки в логах")
        fi

        if echo "$LOGS" | grep -qi "tls\|handshake"; then
            DIAG_ERRORS+=("[✗] TLS/Handshake ошибки в логах")
            CLIENT_PROBLEMS=$((CLIENT_PROBLEMS + 1))
        fi

        if echo "$LOGS" | grep -qi "reality"; then
            DIAG_ERRORS+=("[✗] REALITY проблемы в логах")
            CLIENT_PROBLEMS=$((CLIENT_PROBLEMS + 1))
        fi

        if echo "$LOGS" | grep -qi "connection refused"; then
            DIAG_ERRORS+=("[✗] Connection refused в логах")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        fi

        if echo "$LOGS" | grep -qi "timeout"; then
            DIAG_WARNINGS+=("[!] Timeout ошибки в логах")
        fi

        if echo "$LOGS" | grep -qi "certificate.*expired"; then
            DIAG_ERRORS+=("[✗] SSL сертификат истек")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        fi

        if echo "$LOGS" | grep -qi "too many open files"; then
            DIAG_ERRORS+=("[✗] Слишком много открытых файлов (лимит недостаточный)")
            SERVER_PROBLEMS=$((SERVER_PROBLEMS + 1))
        fi

        if [ -z "$(echo "$LOGS" | grep -i "error\|failed\|tls\|reality\|connection refused")" ]; then
            DIAG_RESULTS+=("[✓] Критических ошибок в логах не обнаружено")
        fi
    fi

    # === ВЫВОД РЕЗУЛЬТАТОВ ===
    echo ""
    echo "════════════════════════════════════════════════"
    echo "           РЕЗУЛЬТАТЫ ДИАГНОСТИКИ"
    echo "════════════════════════════════════════════════"
    echo ""

    # Успешные проверки
    if [ ${#DIAG_RESULTS[@]} -gt 0 ]; then
        for result in "${DIAG_RESULTS[@]}"; do
            echo "$result"
        done
        echo ""
    fi

    # Предупреждения
    if [ ${#DIAG_WARNINGS[@]} -gt 0 ]; then
        for warning in "${DIAG_WARNINGS[@]}"; do
            echo "$warning"
        done
        echo ""
    fi

    # Ошибки
    if [ ${#DIAG_ERRORS[@]} -gt 0 ]; then
        for error in "${DIAG_ERRORS[@]}"; do
            echo "$error"
        done
        echo ""
    fi

    echo "════════════════════════════════════════════════"
    echo "              АНАЛИЗ РЕЗУЛЬТАТОВ"
    echo "════════════════════════════════════════════════"
    echo ""

    # Расчет вероятностей
    TOTAL_PROBLEMS=$((SERVER_PROBLEMS + CLIENT_PROBLEMS))
    
    if [ "$TOTAL_PROBLEMS" -eq 0 ]; then
        echo "[✓] Проблем не обнаружено!"
        echo "Вероятность проблемы на сервере: 0%"
        echo "Вероятность проблемы у пользователя: 0%"
        echo ""
        echo "Все проверки пройдены успешно."
    else
        SERVER_PERCENT=$((SERVER_PROBLEMS * 100 / TOTAL_PROBLEMS))
        CLIENT_PERCENT=$((CLIENT_PROBLEMS * 100 / TOTAL_PROBLEMS))

        echo "Вероятность проблемы на сервере: $SERVER_PERCENT%"
        echo "Вероятность проблемы у пользователя: $CLIENT_PERCENT%"
        echo ""

        if [ "$SERVER_PROBLEMS" -gt "$CLIENT_PROBLEMS" ]; then
            echo "⚠️  Основная проблема, похоже, на СЕРВЕРЕ"
            echo ""
            echo "Наиболее вероятные причины:"
            
            if echo "${DIAG_ERRORS[@]}" | grep -q "Docker"; then
                echo "• Docker не установлен или не работает"
            fi
            
            if echo "${DIAG_ERRORS[@]}" | grep -q "остановлен"; then
                echo "• Контейнер Remnanode остановлен"
            fi
            
            if echo "${DIAG_ERRORS[@]}" | grep -q "не прослушивается"; then
                echo "• Порт $DIAG_PORT не прослушивается"
            fi
            
            if echo "${DIAG_ERRORS[@]}" | grep -q "firewall\|UFW\|firewalld"; then
                echo "• Firewall блокирует порт $DIAG_PORT"
            fi
            
            if echo "${DIAG_ERRORS[@]}" | grep -q "истек"; then
                echo "• SSL сертификат истек"
            fi
            
            if echo "${DIAG_ERRORS[@]}" | grep -q "TLS"; then
                echo "• Неверный SSL сертификат"
            fi
        else
            echo "⚠️  Основная проблема, похоже, у ПОЛЬЗОВАТЕЛЯ"
            echo ""
            echo "Наиболее вероятные причины:"
            echo "• Неверный publicKey"
            echo "• Неправильный shortId"
            echo "• Неверный SNI/serverName"
            echo "• Неправильный домен в конфигурации"
            echo "• Блокировка провайдером пользователя"
            echo "• Неверный dest в конфигурации"
        fi
    fi

    echo ""
    echo "════════════════════════════════════════════════"
    echo "           РЕКОМЕНДАЦИИ ПО УСТРАНЕНИЮ"
    echo "════════════════════════════════════════════════"
    echo ""

    if [ "$SERVER_PROBLEMS" -gt 0 ]; then
        echo "📋 На сервере:"
        
        if echo "${DIAG_ERRORS[@]}" | grep -q "остановлен"; then
            echo "• Перезапустить контейнер: docker compose restart remnanode"
        fi
        
        if echo "${DIAG_ERRORS[@]}" | grep -q "Docker"; then
            echo "• Установить Docker: curl -fsSL https://get.docker.com | sh"
        fi
        
        if echo "${DIAG_ERRORS[@]}" | grep -q "firewall\|UFW"; then
            echo "• Разрешить порт в firewall (UFW): ufw allow $DIAG_PORT/tcp"
            echo "• Разрешить порт в firewall (firewalld): firewall-cmd --permanent --add-port=$DIAG_PORT/tcp && firewall-cmd --reload"
        fi
        
        if echo "${DIAG_ERRORS[@]}" | grep -q "истек"; then
            echo "• Обновить SSL сертификат"
        fi
        
        echo "• Проверить логи: docker logs -f remnanode"
        echo ""
    fi

    if [ "$CLIENT_PROBLEMS" -gt 0 ]; then
        echo "📋 У пользователя:"
        echo "• Проверить конфигурацию клиента (publicKey, shortId, serverName)"
        echo "• Убедиться, что используется правильный домен или IP"
        echo "• Проверить параметры VLESS конфигурации"
        echo "• Попробовать другой DNS сервер (8.8.8.8, 1.1.1.1)"
        echo "• Проверить, не блокируется ли ISP трафик на порту $DIAG_PORT"
        echo ""
    fi

    echo "════════════════════════════════════════════════"
    echo ""
    read -p "Нажмите Enter для продолжения..."
}

# --- Главное меню ---
main_menu() {
    while true; do
        clear
        echo "--- Меню настройки сервера ---"
        echo "1. Настройка SSH (смена порта, отключение пароля, добавление ключа)"
        echo "2. Отключить ICMP Ping"
        echo "3. Установить Reshala-Remnawave-Bedolaga (DonMatteoVPN)"
        echo "4. Установить Remnawave Node (Remnanode)"
        echo "5. Обновить Remnawave Node (Remnanode)"
        echo "6. Установить TrafficGuard-auto"
        echo "7. Установить Warp Native"
        echo "8. Проверить и установить обновления"
        echo "9. Комплексная диагностика Remnanode (VLESS)"
        echo "0. Выход"
        echo "----------------------------"
        read -p "Выберите опцию: " OPTION

        case $OPTION in
            1) configure_ssh ;;
            2) disable_icmp_ping ;;
            3) install_donmatteovpn ;;
            4) install_remnanode ;;
            5) update_remnanode ;;
            6) install_trafficguard ;;
            7) install_warp_native ;;
            8) check_and_update ;;
            9) diagnostic_remnanode ;;
            0) echo "Выход из скрипта. До свидания!"; exit 0 ;;
            *) echo "Неверная опция. Пожалуйста, выберите число от 0 до 9."; read -p "Нажмите Enter для продолжения..." ;;
        esac
    done
}

# --- Проверка прав root перед запуском меню ---
if [ "$(id -u)" -ne 0 ]; then
   echo "Этот скрипт должен быть запущен с правами root. Используйте sudo."
   exit 1
fi

# Запуск главного меню
main_menu
