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

SCRIPT_VERSION="1.1.14"
SCRIPT_NAME="ssf.sh"
SCRIPT_REPO="https://raw.githubusercontent.com/nickyramma/ssf/main/ssf.sh"
SCRIPT_PATH="/usr/local/lib/ssf/ssf.sh"
VERSION_FILE="/tmp/ssf_version.txt"

SSH_CONFIG_FILE="/etc/ssh/sshd_config"
CURRENT_USER=$(whoami) # Получаем имя текущего пользователя
OLD_SSH_PORT="22"

# --- Проверка текущего состояния SSH без изменения конфигурации ---
check_ssh_status() {
    local CHECK_PORT="$1"
    local SSH_SERVICE=""

    echo "--- Проверка текущего SSH ---"

    if ! sshd -t; then
        echo "ОШИБКА: текущая конфигурация SSH не проходит проверку."
        return 1
    fi

    if ! sshd -T | awk '$1 == "port" { print $2 }' | grep -Fxq "$CHECK_PORT"; then
        echo "ОШИБКА: эффективная конфигурация SSH не содержит Port $CHECK_PORT."
        return 1
    fi

    if systemctl is-active --quiet ssh.service; then
        SSH_SERVICE="ssh.service"
    elif systemctl is-active --quiet sshd.service; then
        SSH_SERVICE="sshd.service"
    else
        echo "ОШИБКА: SSH service-unit не active."
        return 1
    fi

    if ! systemctl is-enabled --quiet "$SSH_SERVICE"; then
        echo "ОШИБКА: автозапуск $SSH_SERVICE не включён."
        return 1
    fi

    if ! ss -ltnH4 "sport = :$CHECK_PORT" | grep -q .; then
        echo "ОШИБКА: SSH не слушает IPv4-порт $CHECK_PORT."
        return 1
    fi

    if ss -ltnH6 "sport = :$CHECK_PORT" | grep -q .; then
        echo "✓ SSH active, автозапуск enabled; порт $CHECK_PORT слушается по IPv4 и IPv6."
    else
        echo "✓ SSH active, автозапуск enabled; порт $CHECK_PORT слушается по IPv4."
        echo "ВНИМАНИЕ: IPv6-сокет не найден."
    fi

    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            if ufw status | grep -Eq "^${CHECK_PORT}/tcp[[:space:]]+ALLOW[[:space:]]+Anywhere([[:space:]]|$)"; then
                echo "✓ UFW разрешает $CHECK_PORT/tcp для всех IPv4-адресов."
            else
                echo "ВНИМАНИЕ: в активном UFW не найдено правило $CHECK_PORT/tcp для всех IPv4-адресов."
            fi
        else
            echo "ВНИМАНИЕ: UFW установлен, но не активен."
        fi
    fi
}

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
        printf 'Отключить вход по паролю и разрешить только вход по SSH-ключам? (y/N): '
        read -r REPLY_PASSWORD_AUTH
        echo
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
                printf 'Вы уверены, что хотите продолжить без добавления ключа? (y/N): '
                read -r CONFIRM_NO_KEY
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
    printf 'Вы уверены, что хотите применить эти изменения? (y/N): '
    read -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено пользователем. Возвращаемся в главное меню."
        read -p "Нажмите Enter для продолжения..."
        return 1 # Возвращаемся в меню
    fi

    # Если выбран уже действующий порт, ничего не меняем: только показываем статус.
    if sshd -T 2>/dev/null | awk '$1 == "port" { print $2 }' | grep -Fxq "$NEW_SSH_PORT"; then
        echo "Порт $NEW_SSH_PORT уже настроен для SSH. Изменения не требуются."
        check_ssh_status "$NEW_SSH_PORT"
        read -p "Нажмите Enter для продолжения..."
        return 0
    fi

    # --- 1. Изменение порта и настроек аутентификации в sshd_config ---
    echo "1. Изменяем порт и настройки аутентификации в $SSH_CONFIG_FILE..."

    # Создаем резервную копию оригинального файла
    SSH_BACKUP_FILE="${SSH_CONFIG_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
    cp "$SSH_CONFIG_FILE" "$SSH_BACKUP_FILE"
    echo "Создана резервная копия: $SSH_BACKUP_FILE"

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

    if ! sshd -t; then
        echo "ОШИБКА: конфигурация SSH некорректна. Восстанавливаем резервную копию."
        cp -p "$SSH_BACKUP_FILE" "$SSH_CONFIG_FILE"
        return 1
    fi

    if ss -ltnH "sport = :$NEW_SSH_PORT" | grep -q .; then
        echo "ОШИБКА: порт $NEW_SSH_PORT уже занят. Конфигурация восстановлена."
        ss -ltnp "sport = :$NEW_SSH_PORT"
        cp -p "$SSH_BACKUP_FILE" "$SSH_CONFIG_FILE"
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

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

    # --- 2. Настройка фаервола ---
    echo "2. Настраиваем фаервол..."

    if command -v ufw &> /dev/null; then
        echo "Обнаружен UFW. Настраиваем UFW..."
        if ! ufw allow "$NEW_SSH_PORT"/tcp; then
            echo "ОШИБКА: не удалось создать правило UFW для $NEW_SSH_PORT/tcp."
            cp -p "$SSH_BACKUP_FILE" "$SSH_CONFIG_FILE"
            return 1
        fi
        if ufw status | grep -q "Status: active"; then
            if ! ufw status | grep -Eq "^${NEW_SSH_PORT}/tcp[[:space:]]+ALLOW[[:space:]]+Anywhere([[:space:]]|$)"; then
                echo "ОШИБКА: активный UFW не содержит правило $NEW_SSH_PORT/tcp для всех IPv4-адресов."
                cp -p "$SSH_BACKUP_FILE" "$SSH_CONFIG_FILE"
                return 1
            fi
            if grep -Eq '^IPV6=yes' /etc/default/ufw 2>/dev/null && ! ufw status | grep -Eq "^${NEW_SSH_PORT}/tcp[[:space:]]+ALLOW[[:space:]]+Anywhere[[:space:]]+\(v6\)$"; then
                echo "ОШИБКА: активный UFW не содержит правило $NEW_SSH_PORT/tcp для всех IPv6-адресов."
                cp -p "$SSH_BACKUP_FILE" "$SSH_CONFIG_FILE"
                return 1
            fi
            echo "Правило UFW для $NEW_SSH_PORT/tcp открыто для всех IPv4-адресов."
        else
            echo "ВНИМАНИЕ: правило UFW создано, но UFW не активен. Включите его отдельно, только убедившись, что SSH-разрешение сохранено."
        fi
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
        echo "Вам необходимо вручную настроить ваш фаервол, чтобы разрешить входящие соединения на порту $NEW_SSH_PORT."
        echo "Пример для iptables (может отличаться):"
        echo "sudo iptables -A INPUT -p tcp --dport $NEW_SSH_PORT -j ACCEPT"
        echo "sudo service netfilter-persistent save" # или другая команда для сохранения iptables
    fi

    # --- 3. Отключение socket activation ---
    echo "3. Отключаем SSH socket activation..."
    for SSH_SOCKET in ssh.socket sshd.socket; do
        if systemctl cat "$SSH_SOCKET" >/dev/null 2>&1; then
            if ! systemctl disable --now "$SSH_SOCKET"; then
                echo "ОШИБКА: не удалось отключить $SSH_SOCKET."
                return 1
            fi
            if systemctl is-active --quiet "$SSH_SOCKET" || systemctl is-enabled --quiet "$SSH_SOCKET"; then
                echo "ОШИБКА: $SSH_SOCKET всё ещё активен или включён."
                return 1
            fi
        fi
    done

    # --- 4. Выбор, включение и перезапуск service-unit ---
    if systemctl cat ssh.service >/dev/null 2>&1; then
        SSH_SERVICE="ssh.service"
    elif systemctl cat sshd.service >/dev/null 2>&1; then
        SSH_SERVICE="sshd.service"
    else
        echo "ОШИБКА: не найден SSH service-unit (ssh.service или sshd.service)."
        return 1
    fi

    if ! systemctl enable "$SSH_SERVICE"; then
        echo "ОШИБКА: не удалось включить автозапуск $SSH_SERVICE."
        return 1
    fi
    if ! systemctl restart "$SSH_SERVICE"; then
        echo "ОШИБКА: $SSH_SERVICE не запустился. Проверьте: systemctl status $SSH_SERVICE"
        return 1
    fi
    if ! systemctl is-active --quiet "$SSH_SERVICE"; then
        echo "ОШИБКА: $SSH_SERVICE не active после перезапуска."
        return 1
    fi
    if ! systemctl is-enabled --quiet "$SSH_SERVICE"; then
        echo "ОШИБКА: автозапуск $SSH_SERVICE не включён."
        return 1
    fi

    # --- 5. Подтверждение фактического слушателя ---
    echo "5. Проверяем SSH после перезапуска..."
    if ! sshd -T | awk '$1 == "port" { print $2 }' | grep -Fxq "$NEW_SSH_PORT"; then
        echo "ОШИБКА: эффективная конфигурация sshd не содержит Port $NEW_SSH_PORT."
        return 1
    fi
    if ! ss -ltnH4 "sport = :$NEW_SSH_PORT" | grep -q .; then
        echo "ОШИБКА: SSH не слушает IPv4-порт $NEW_SSH_PORT после перезапуска."
        ss -ltnp "sport = :$NEW_SSH_PORT"
        return 1
    fi
    if ss -ltnH6 "sport = :$NEW_SSH_PORT" | grep -q .; then
        echo "✓ SSH слушает $NEW_SSH_PORT по IPv4 и IPv6; сервис active, автозапуск enabled."
    else
        echo "✓ SSH слушает $NEW_SSH_PORT по IPv4; сервис active, автозапуск enabled."
        echo "ВНИМАНИЕ: IPv6-сокет не найден. Проверьте AddressFamily/ListenAddress, если IPv6 нужен."
    fi

    echo "--- Скрипт SSH выполнен. ---"
    echo "ВАЖНО: НЕ ЗАКРЫВАЙТЕ ЭТО SSH-СОЕДИНЕНИЕ, пока не проверите новое!"
    echo "Попробуйте подключиться из нового терминала:"
    echo "ssh -p $NEW_SSH_PORT ваш_пользователь@ваш_IP_сервера_или_домен"
    if [ "$DISABLE_PASSWORD_AUTH" == "yes" ]; then
        echo "ПОМНИТЕ: Теперь вы можете подключиться ТОЛЬКО с помощью SSH-ключа!"
        echo "При подключении используйте: ssh -p $NEW_SSH_PORT -i /путь/к/вашему/ssh_ключу ваш_пользователь@ваш_IP_сервера_ил�"
    fi
    echo "Убедитесь, что новый порт и выбранный метод аутентификации работают, прежде чем закрывать текущее со�"
    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для отключения ICMP Ping ---
disable_icmp_ping() {
    echo "--- Отключение ICMP Ping ---"
    echo "Это сделает ваш сервер менее заметным для сканирования."

    printf 'Вы уверены, что хотите отключить ICMP Ping? (y/N): '
    read -r REPLY
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
            if sed -i "s|${PATTERN_ACCEPT}|${PATTERN_DROP}|" "$UFW_BEFORE_RULES"; then
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
            echo "⚠ Не удалось изменить правило ICMP: строка с echo-request не найдена в $UFW_BEFORE_RULES"
        fi
    else
        echo "Файл $UFW_BEFORE_RULES не найден. Пропускаем изменение UFW правил."
    fi

    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для установки DonMatteoVPN ---
install_donmatteovpn() {
    echo "--- Установка Reshala-Remnawave-Bedolaga (DonMatteoVPN) ---"

    printf 'Вы уверены, что хотите начать установку скрипта DonMatteoVPN? (y/N): '
    read -r REPLY
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

    printf 'Вы уверены, что хотите начать установку Remnanode? (y/N): '
    read -r REPLY
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Отменено пользователем. Возвращаемся в главное меню."
        return 1
    fi

    # --- Проверка и установка Docker ---
    if ! command -v docker &> /dev/null; then
        echo "Docker не найден. Предлагаем установить Docker."
        printf 'Установить Docker сейчас? (y/N): '
        read -r INSTALL_DOCKER_REPLY
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
            echo "Пользователь '$CURRENT_USER' добавлен в группу 'docker'. Для применения изменений может потребоваться перезапуск сессии."
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

    # --- Запрос версии/тега образа Remnawave Node ---
    echo ""
    echo "--- Выбор версии образа Remnawave Node ---"
    read -p "Введите тег/версию образа (по умолчанию 'latest', просто нажмите Enter): " REMNANODE_IMAGE_TAG
    # Если пользователь ничего не ввёл — используем latest
    if [ -z "$REMNANODE_IMAGE_TAG" ]; then
        REMNANODE_IMAGE_TAG="latest"
    fi
    REMNANODE_IMAGE="remnawave/node:$REMNANODE_IMAGE_TAG"
    echo "Будет использован образ: $REMNANODE_IMAGE"

    # --- Запрос порта для Remnanode ---
    echo ""
    echo "--- Выбор порта для Remnanode ---"
    read -p "Введите порт для NODE_PORT (по умолчанию '2222', просто нажмите Enter): " NODE_PORT
    if [ -z "$NODE_PORT" ]; then
        NODE_PORT="2222"
    fi
    echo "Будет использован порт: $NODE_PORT"

    # --- Запрос SECRET_KEY ---
    echo ""
    echo "--- Настройка SECRET_KEY ---"
    echo "Пожалуйста, введите SECRET_KEY для Remnanode."
    echo "Это критический параметр для безопасности. Если не введете - оставим пустым."
    read -p "Введите SECRET_KEY: " SECRET_KEY
    
    # --- Запрос пути для Remnanode ---
    echo ""
    echo "--- Выбор директории для Remnanode ---"
    read -p "Введите путь для установки Remnanode (по умолчанию '/opt/remnanode', просто нажмите Enter): " REMNANODE_PATH
    if [ -z "$REMNANODE_PATH" ]; then
        REMNANODE_PATH="/opt/remnanode"
    fi
    
    # Создаем директорию, если её нет
    mkdir -p "$REMNANODE_PATH"
    echo "Директория для Remnanode: $REMNANODE_PATH"

    # --- Создание docker-compose.yml ---
    echo ""
    echo "--- Создание конфигурации Docker Compose ---"
    
    COMPOSE_FILE="$REMNANODE_PATH/docker-compose.yml"
    
    cat > "$COMPOSE_FILE" << EOF
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: $REMNANODE_IMAGE
    network_mode: host
    cap_add:
      - NET_ADMIN
    restart: always
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=$NODE_PORT
      - SECRET_KEY="$SECRET_KEY"
EOF
    
    echo "Файл docker-compose.yml создан в $REMNANODE_PATH"
    echo ""
    echo "Содержимое docker-compose.yml:"
    cat "$COMPOSE_FILE"

    # --- Запуск контейнера ---
    echo ""
    echo "--- Запуск Remnanode ---"
    cd "$REMNANODE_PATH"
    
    echo "Загружаем образ и запускаем контейнер..."
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        echo "✓ Remnanode успешно запущен!"
        echo ""
        echo "Проверяем статус контейнера:"
        docker-compose ps
        
        echo ""
        echo "Логи Remnanode:"
        docker-compose logs --tail=20
        
        echo ""
        echo "✓ Установка Remnanode завершена успешно!"
        echo "Директория установки: $REMNANODE_PATH"
        echo "Образ: $REMNANODE_IMAGE"
        echo "Порт: $NODE_PORT"
        echo ""
        echo "Для управления Remnanode используйте команды:"
        echo "  Статус: docker-compose -f $COMPOSE_FILE ps"
        echo "  Логи: docker-compose -f $COMPOSE_FILE logs -f"
        echo "  Перезагрузка: docker-compose -f $COMPOSE_FILE restart"
        echo "  Остановка: docker-compose -f $COMPOSE_FILE down"
    else
        echo "✗ Ошибка при запуске Remnanode. Пожалуйста, проверьте логи Docker."
        read -p "��ажмите Enter для продолжения..."
        return 1
    fi

    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для обновления Remnawave Node ---
update_remnanode() {
    echo "--- Обновление Remnawave Node (Remnanode) ---"
    echo ""

    read -p "Введите путь к директории Remnanode (по умолчанию '/opt/remnanode', просто нажмите Enter): " REMNANODE_PATH
    if [ -z "$REMNANODE_PATH" ]; then
        REMNANODE_PATH="/opt/remnanode"
    fi

    if [ ! -f "$REMNANODE_PATH/docker-compose.yml" ]; then
        echo "✗ Файл docker-compose.yml не найден в $REMNANODE_PATH"
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

    echo "Останавливаем текущий контейнер..."
    cd "$REMNANODE_PATH"
    docker-compose down

    echo "Загружаем новый образ..."
    docker-compose pull

    echo "Запускаем обновленный контейнер..."
    docker-compose up -d

    if [ $? -eq 0 ]; then
        echo "✓ Remnanode успешно обновлен!"
        docker-compose ps
    else
        echo "✗ Ошибка при обновлении Remnanode."
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

    read -p "Нажмите Enter для продолжения..."
}

# --- Функция для установки TrafficGuard-auto ---
install_trafficguard() {
  echo "--- Установка TrafficGuard-auto ---"
  echo ""

  printf 'Вы уверены, что хотите начать установку TrafficGuard-auto? (y/N): '
  read -r REPLY
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
          echo "Не удалось установить curl."
          read -p "Нажмите Enter для продолжения..."
          return 1
      fi
  fi

  # Выполняем команду установки (примерный URL, уточните реальный)
  curl -fsSL https://raw.githubusercontent.com/TrafficGuard/auto/main/install.sh | bash

  if [ $? -eq 0 ]; then
      echo "✓ Установка TrafficGuard-auto завершена успешно."
  else
      echo "✗ Во время установки произошла ошибка."
  fi

  read -p "Нажмите Enter для продолжения..."
}

# --- Функция для установки Warp Native ---
install_warp_native() {
  echo "--- Установка Warp Native ---"
  echo ""

  printf 'Вы уверены, что хотите начать установку Warp Native? (y/N): '
  read -r REPLY
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
          echo "Не удалось установить curl."
          read -p "Нажмите Enter для продолжения..."
          return 1
      fi
  fi

  # Выполняем команду установки (примерный URL, уточните реальный)
  curl -fsSL https://raw.githubusercontent.com/Warp/native/main/install.sh | bash

  if [ $? -eq 0 ]; then
      echo "✓ Установка Warp Native завершена успешно."
  else
      echo "✗ Во время установки произошла ошибка."
  fi

  read -p "Нажмите Enter для продолжения..."
}

# --- Функция для комплексной диагностики Remnanode (VLESS) ---
diagnostic_remnanode() {
  echo "--- Комплексная диагностика Remnanode (VLESS) ---"
  echo ""

  read -p "Введите путь к директории Remnanode (по умолчанию '/opt/remnanode', просто нажмите Enter): " REMNANODE_PATH
  if [ -z "$REMNANODE_PATH" ]; then
      REMNANODE_PATH="/opt/remnanode"
  fi

  echo "Начинаем диагностику Remnanode..."
  echo ""

  # Проверка Docker
  echo "--- Проверка Docker ---"
  if command -v docker &> /dev/null; then
      echo "✓ Docker установлен"
      docker --version
  else
      echo "✗ Docker не установлен"
  fi

  echo ""
  echo "--- Проверка контейнера Remnanode ---"
  if [ -f "$REMNANODE_PATH/docker-compose.yml" ]; then
      cd "$REMNANODE_PATH"
      docker-compose ps
      
      echo ""
      echo "--- Логи контейнера ---"
      docker-compose logs --tail=50
      
      echo ""
      echo "--- Проверка портов ---"
      docker-compose exec -T remnanode netstat -tulpn 2>/dev/null || echo "netstat недоступен в контейнере"
  else
      echo "✗ docker-compose.yml не найден в $REMNANODE_PATH"
  fi

  echo ""
  echo "--- Диагностика завершена ---"
  read -p "Нажмите Enter для продолжения..."
}

# --- Функция для проверки и установки обновлений ---
check_and_update() {
    echo "--- Проверка и установка обновлений ---"
    echo "Текущая версия скрипта: $SCRIPT_VERSION"
    echo ""

    if ! command -v curl >/dev/null 2>&1; then
        echo "curl не найден. Устанавливаем curl..."

        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y curl
        elif command -v yum >/dev/null 2>&1; then
            yum install -y curl
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y curl
        else
            echo "❌ Не удалось установить curl."
            read -p "Нажмите Enter для продолжения..."
            return 1
        fi
    fi

    TEMP_SCRIPT="/tmp/ssf.new.$$"
    BACKUP_FILE="${SCRIPT_PATH}.bak_$(date +%Y%m%d_%H%M%S)"

    echo "📥 Проверяем новую версию..."

    if ! curl -fsSL "$SCRIPT_REPO" -o "$TEMP_SCRIPT"; then
        echo "❌ Не удалось скачать новую версию SSF."
        rm -f "$TEMP_SCRIPT"
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

    if [ ! -s "$TEMP_SCRIPT" ]; then
        echo "❌ Загруженный файл пустой."
        rm -f "$TEMP_SCRIPT"
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

    if ! bash -n "$TEMP_SCRIPT"; then
        echo "❌ Новая версия содержит синтаксические ошибки."
        echo "Обновление отменено."
        rm -f "$TEMP_SCRIPT"
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

    NEW_VERSION=$(grep '^SCRIPT_VERSION=' "$TEMP_SCRIPT" | head -n1 | cut -d'"' -f2)

    if [ -z "$NEW_VERSION" ]; then
        echo "❌ Не удалось определить версию новой версии."
        rm -f "$TEMP_SCRIPT"
        read -p "Нажмите Enter для продолжения..."
        return 1
    fi

    echo "Доступная версия на GitHub: $NEW_VERSION"
    echo "Текущая версия:           $SCRIPT_VERSION"
    echo ""

    if [ "$NEW_VERSION" = "$SCRIPT_VERSION" ]; then
        echo "✓ У вас уже установлена последняя версия."
        rm -f "$TEMP_SCRIPT"
        read -p "Нажмите Enter для продолжения..."
        return 0
    fi

    echo "⚡ Доступно обновление!"
    echo ""
    printf 'Установить версию %s? (y/N): ' "$NEW_VERSION"
    read -r REPLY
    echo

    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "Обновление отменено."
        rm -f "$TEMP_SCRIPT"
        read -p "Нажмите Enter для продолжения..."
        return 0
    fi

    echo "📦 Устанавливаем новую версию..."

    if [ -f "$SCRIPT_PATH" ]; then
        cp -p "$SCRIPT_PATH" "$BACKUP_FILE"
        echo "✓ Резервная копия: $BACKUP_FILE"
    fi

    INSTALL_TMP="${SCRIPT_PATH}.new.$$"

    if ! install -m 755 "$TEMP_SCRIPT" "$INSTALL_TMP"; then
        echo "❌ Не удалось подготовить новую версию."
        rm -f "$TEMP_SCRIPT" "$INSTALL_TMP"
        return 1
    fi

    if ! bash -n "$INSTALL_TMP"; then
        echo "❌ Новая версия не прошла финальную проверку."
        rm -f "$TEMP_SCRIPT" "$INSTALL_TMP"
        return 1
    fi

    if ! mv -f "$INSTALL_TMP" "$SCRIPT_PATH"; then
        echo "❌ Не удалось заменить текущий SSF."

        rm -f "$TEMP_SCRIPT" "$INSTALL_TMP"

        if [ -f "$BACKUP_FILE" ]; then
            cp -p "$BACKUP_FILE" "$SCRIPT_PATH"
            chmod 755 "$SCRIPT_PATH"
            echo "✓ Резервная копия восстановлена."
        fi

        return 1
    fi

    chmod 755 "$SCRIPT_PATH"
    rm -f "$TEMP_SCRIPT"

    echo ""
    echo "========================================="
    echo "✓ SSF успешно обновлён!"
    echo "========================================="
    echo ""
    echo "Старая версия: $SCRIPT_VERSION"
    echo "Новая версия:  $NEW_VERSION"
    echo ""
    echo "🚀 Запускаем новую версию..."
    echo ""

    exec "$SCRIPT_PATH" "$@"
}

# --- Главное меню ---
main_menu() {
    while true; do
        clear
        echo "--- Меню настройки сервера ---"
        echo "1. Настройка SSH (смена порта, отключение пароля, добавление ключа)"
        echo "2. Отключить ICMP Ping (скрыть сервер от сетевых сканеров)"
        echo "3. Установить Reshala-Remnawave-Bedolaga (Управление сервером)"
        echo "4. Установить Remnawave Node (Remnanode)"
        echo "5. Обновить Remnawave Node (Remnanode)"
        echo "6. Установить TrafficGuard-auto"
        echo "7. Установить Warp Native"
        echo "8. Проверить и установить обновления"
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
