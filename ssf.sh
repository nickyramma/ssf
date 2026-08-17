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

SCRIPT_VERSION="1.1.7"
SCRIPT_NAME="ssf.sh"
SCRIPT_REPO="https://raw.githubusercontent.com/nickyramma/ssf/main/ssf.sh"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$SCRIPT_NAME"
VERSION_FILE="/tmp/ssf_version.txt"

SSH_CONFIG_FILE="/etc/ssh/sshd_config"
CURRENT_USER=$(whoami) # Получаем имя текущего пользователя
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
            echo "Ключ будет добавлен для текущего пользователя: '$CURRENT_USER'."
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
        echo "Вам необходимо вручную настроить ваш фаервол, чтобы разрешить входящие соединения на порту $NEW_SSH_PORT"
        echo "Пример для iptables (может отличаться):"
        echo "sudo iptables -A INPUT -p tcp --dport $NEW_SSH_PORT -j ACCEPT"
        echo "sudo service netfilter-persistent save" # или другая команда для сохранения iptables
    fi

    # --- 3.1 Включаем ssh/sshd (systemd enable) ---
    echo "3.1. Включаем SSH-сервис в systemd (enable)..."
    if systemctl is-enabled --quiet ssh 2>/dev/null || systemctl is-enabled --quiet sshd 2>/dev/null; then
        echo "SSH-сервис уже включён (enabled)."
    else
        systemctl enable ssh 2>/dev/null || systemctl enable sshd 2>/dev/null || echo "Не удалось выполнить 'systemctl enable' для ssh/sshd"
    fi

    # --- 4. Перезапуск SSH-сервиса ---
    echo "4. Перезапуск SSH-сервиса..."
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
    if [ -f "$SYSCTL_CONF" ]; then
        sed -i '/^net.ipv4.icmp_echo_ignore_all/d' "$SYSCTL_CONF"
    fi

    # Создаем или перезаписываем файл в sysctl.d для отключения пинга
    echo "net.ipv4.icmp_echo_ignore_all = 1" | tee "$SYSCTL_D_CONF" > /dev/null
    echo "Файл $SYSCTL_D_CONF создан с параметром net.ipv4.icmp_echo_ignore_all = 1."

    # Применяем изменения
    sysctl -p "$SYSCTL_D_CONF"
    echo "Изменения применены. ICMP Ping отключен."

    echo "Текущее значение net.ipv4.icmp_echo_ignore_all: $(sysctl -n net.ipv4.icmp_echo_ignore_all)"

    # --- Дополнение: изменить правило в /etc/ufw/before.rules, если файл существует ---
    UFW_BEFORE_RULES="/etc/ufw/before.rules"
    UFW_BACKUP="${UFW_BEFORE_RULES}.bak"
    PATTERN_ACCEPT='-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT'
    PATTERN_DROP='-A ufw-before-input -p icmp --icmp-type echo-request -j DROP'

    if [ -f "$UFW_BEFORE_RULES" ]; then
        # Создаём резервную копию только если её ещё нет
        if [ ! -f "$UFW_BACKUP" ]; then
            if cp -p "$UFW_BEFORE_RULES" "$UFW_BACKUP" 2>/dev/null; then
                echo "Создана резервная копия $UFW_BACKUP."
            else
                echo "⚠ Не удалось создать резервную копию $UFW_BACKUP. Продолжаем осторожно."
            fi
        else
            echo "Резервная копия $UFW_BACKUP уже существует. Пропускаем создание резервной копии."
        fi

        # Проверяем, есть ли строка с -j DROP уже
        if grep -qF -- "$PATTERN_DROP" "$UFW_BEFORE_RULES"; then
            echo "✓ ICMP echo-request уже отключён в $UFW_BEFORE_RULES (найдена строка -j DROP)."
        elif grep -qF -- "$PATTERN_ACCEPT" "$UFW_BEFORE_RULES"; then
            # Заменяем только точную строку ACCEPT -> DROP
            TMP_FILE=$(mktemp)
            if awk -v a="$PATTERN_ACCEPT" -v b="$PATTERN_DROP" '$0==a { print b; next } { print }' "$UFW_BEFORE_RULES" > "$TMP_FILE" && mv "$TMP_FILE" "$UFW_BEFORE_RULES"; then
                # Проверяем, удалось ли заменить
                if grep -qF -- "$PATTERN_DROP" "$UFW_BEFORE_RULES"; then
                    echo "✓ Правило в $UFW_BEFORE_RULES обновлено: ACCEPT -> DROP."
                    # Перезагружаем UFW, если он установлен и активен
                    if command -v ufw &> /dev/null; then
                        UFW_STATUS=$(ufw status 2>/dev/null || true)
                        if echo "$UFW_STATUS" | grep -q "Status: active"; then
                            if ufw reload; then
                                echo "✓ UFW перезагружен."
                            else
                                echo "⚠ Не удалось перезагрузить UFW."
                            fi
                        else
                            echo "UFW установлен, но не активен. Пропускаем перезагрузку UFW."
                        fi
                    else
                        echo "UFW не найден. Изменение файла выполнено локально."
                    fi
                    echo "✓ ICMP echo-request отключён"
                else
                    echo "⚠ Не удалось изменить правило ICMP в $UFW_BEFORE_RULES"
                fi
            else
                echo "⚠ Ошибка при попытке изменить $UFW_BEFORE_RULES"
            fi
        else
            # Ни ACCEPT, ни DROP нет — необходимо безопасно вставить DROP внутри таблицы *filter перед COMMIT
            # Сначала находим таблицу *filter
            FILTER_LINE=$(grep -nF -- '*filter' "$UFW_BEFORE_RULES" | head -n1 | cut -d: -f1 || true)
            if [ -n "$FILTER_LINE" ]; then
                # Найдём первый COMMIT после начала таблицы *filter
                REL_COMMIT_LINE=$(tail -n +$FILTER_LINE "$UFW_BEFORE_RULES" | grep -nF -- 'COMMIT' | head -n1 | cut -d: -f1 || true)
                if [ -n "$REL_COMMIT_LINE" ]; then
                    COMMIT_LINE=$((FILTER_LINE + REL_COMMIT_LINE - 1))
                    TMP_FILE=$(mktemp)
                    # Вставляем PATTERN_DROP перед строкой COMMIT внутри найденной таблицы
                    awk -v ins_line="$COMMIT_LINE" -v pat="$PATTERN_DROP" 'NR==ins_line { print pat; print $0; next } { print }' "$UFW_BEFORE_RULES" > "$TMP_FILE" && mv "$TMP_FILE" "$UFW_BEFORE_RULES"

                    # Проверяем, добавилось ли правило
                    if grep -qF -- "$PATTERN_DROP" "$UFW_BEFORE_RULES"; then
                        echo "✓ Правило DROP добавлено внутри таблицы *filter перед COMMIT в $UFW_BEFORE_RULES."
                        # Перезагружаем UFW, если он установлен и активен
                        if command -v ufw &> /dev/null; then
                            UFW_STATUS=$(ufw status 2>/dev/null || true)
                            if echo "$UFW_STATUS" | grep -q "Status: active"; then
                                if ufw reload; then
                                    echo "✓ UFW перезагружен."
                                else
                                    echo "⚠ Не удалось перезагрузить UFW после добавления правила."
                                fi
                            else
                                echo "UFW установлен, но не активен. Пропускаем перезагрузку UFW."
                            fi
                        else
                            echo "UFW не найден. Изменение файла выполнено локально."
                        fi
                    else
                        echo "⚠ Не удалось добавить правило DROP в $UFW_BEFORE_RULES. Откатываем изменения при наличии бэкапа."
                        [ -f "$UFW_BACKUP" ] && cp -p "$UFW_BACKUP" "$UFW_BEFORE_RULES" 2>/dev/null || true
                    fi
                else
                    echo "⚠ Не удалось найти COMMIT после таблицы *filter. Пропускаем изменение UFW before.rules."
                fi
            else
                echo "⚠ Таблица *filter не найдена в $UFW_BEFORE_RULES. Пропускаем изменение UFW before.rules."
            fi
        fi
    else
        echo "Файл $UFW_BEFORE_RULES не найден. Пропускаем изменение UFW правил."
    fi

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
    
    # Проверка успешности установки
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
            curl -fsSL https://get.docker.com | sh
            if [ $? -ne 0 ]; then
                echo "Ошибка при установке Docker. Пожалуйста, проверьте логи и повторите попытку."
                read -p "Нажмите Enter для продолжения..."
                return 1
            fi
            echo "Docker успешно установлен."
            # Добавляем текущего пользователя в группу docker, чтобы не использовать sudo постоянно
            usermod -aG docker "$CURRENT_USER"
            echo "Пользователь '$CURRENT_USER' добавлен в группу 'docker'. Для применения изменений может потребоваться пере[...]
            # Даем небольшую задержку, чтобы Docker мог полностью инициализироваться
            sleep 5
        else
            echo "Установка Docker отменена. Remnanode не может быть установлен без Docker."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
    fi

    # --- Проверка Docker Compose ---
    echo ""
    echo "--- Проверка Docker Compose ---"
    if ! command -v docker-compose &> /dev/null; then
        echo "Docker Compose не найден. Устанавливаем Docker Compose..."
        
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y docker-compose
        elif command -v yum &> /dev/null; then
            yum install -y docker-compose
        elif command -v dnf &> /dev/null; then
            dnf install -y docker-compose
        else
            echo "Не удалось установить Docker Compose. Пожалуйста, установите его вручную."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
        echo "Docker Compose успешно установлен."
    else
        echo "Docker Compose найден."
    fi

# (rest of file unchanged)
