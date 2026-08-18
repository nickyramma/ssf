#!/bin/bash

# SSF Installer
# https://github.com/nickyramma/ssf

set -u

SSF_DIR="/usr/local/lib/ssf"
SSF_SCRIPT="$SSF_DIR/ssf.sh"
SSF_LAUNCHER="/usr/local/bin/ssf"
SSF_URL="https://raw.githubusercontent.com/nickyramma/ssf/main/ssf.sh"
TMP_FILE="/tmp/ssf.sh.new"
BACKUP_FILE="$SSF_SCRIPT.bak"

echo "========================================="
echo "     SSF — Server Setup Framework"
echo "           Установка SSF"
echo "========================================="
echo ""

# --------------------------------------------------
# Проверка root
# --------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Ошибка: установщик должен быть запущен от root."
    echo ""
    echo "Используйте:"
    echo "  sudo bash install.sh"
    echo ""
    exit 1
fi

# --------------------------------------------------
# Проверка curl / wget
# --------------------------------------------------

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "❌ Ошибка: не найден curl или wget."
    echo "Установите один из них и повторите установку."
    exit 1
fi

# --------------------------------------------------
# Создание директории
# --------------------------------------------------

echo "📁 Проверяем директорию SSF..."

if ! mkdir -p "$SSF_DIR"; then
    echo "❌ Не удалось создать $SSF_DIR"
    exit 1
fi

echo "✓ Директория готова: $SSF_DIR"
echo ""

# --------------------------------------------------
# Очистка временного файла
# --------------------------------------------------

rm -f "$TMP_FILE"

# --------------------------------------------------
# Скачивание ssf.sh во временный файл
# --------------------------------------------------

echo "📥 Скачиваем последнюю версию ssf.sh..."

DOWNLOAD_OK=0

if command -v curl >/dev/null 2>&1; then
    if curl -fsSL \
        --retry 3 \
        --connect-timeout 10 \
        "$SSF_URL" \
        -o "$TMP_FILE"; then
        DOWNLOAD_OK=1
    fi
else
    if wget -q \
        --tries=3 \
        --timeout=10 \
        "$SSF_URL" \
        -O "$TMP_FILE"; then
        DOWNLOAD_OK=1
    fi
fi

if [ "$DOWNLOAD_OK" -ne 1 ]; then
    echo "❌ Не удалось скачать ssf.sh"
    rm -f "$TMP_FILE"
    exit 1
fi

# --------------------------------------------------
# Проверка скачанного файла
# --------------------------------------------------

if [ ! -s "$TMP_FILE" ]; then
    echo "❌ Ошибка: скачанный ssf.sh пустой."
    rm -f "$TMP_FILE"
    exit 1
fi

if ! head -n 1 "$TMP_FILE" | grep -q '^#!'; then
    echo "❌ Ошибка: скачанный файл не похож на shell-скрипт."
    rm -f "$TMP_FILE"
    exit 1
fi

echo "✓ Файл успешно скачан."
echo ""

# --------------------------------------------------
# Проверка синтаксиса ДО установки
# --------------------------------------------------

echo "🔍 Проверяем синтаксис ssf.sh..."

if ! bash -n "$TMP_FILE"; then
    echo ""
    echo "❌ ОШИБКА: скачанный ssf.sh содержит синтаксические ошибки."
    echo ""
    echo "Текущая установленная версия НЕ будет изменена."
    echo ""
    rm -f "$TMP_FILE"
    exit 1
fi

echo "✓ Синтаксис корректен."
echo ""

# --------------------------------------------------
# Резервная копия текущей версии
# --------------------------------------------------

if [ -f "$SSF_SCRIPT" ]; then
    echo "💾 Создаём резервную копию текущей версии..."

    if ! cp -f "$SSF_SCRIPT" "$BACKUP_FILE"; then
        echo "❌ Не удалось создать резервную копию."
        rm -f "$TMP_FILE"
        exit 1
    fi

    echo "✓ Резервная копия: $BACKUP_FILE"
    echo ""
fi

# --------------------------------------------------
# Установка новой версии
# --------------------------------------------------

echo "📦 Устанавливаем ssf.sh..."

chmod +x "$TMP_FILE"

if ! mv -f "$TMP_FILE" "$SSF_SCRIPT"; then
    echo "❌ Не удалось установить новую версию ssf.sh."
    rm -f "$TMP_FILE"
    exit 1
fi

chmod +x "$SSF_SCRIPT"

echo "✓ ssf.sh установлен:"
echo "  $SSF_SCRIPT"
echo ""

# --------------------------------------------------
# Создание стабильного launcher
# --------------------------------------------------

echo "🔗 Настраиваем команду ssf..."

cat > "$SSF_LAUNCHER" <<'EOF'
#!/bin/bash

exec /usr/local/lib/ssf/ssf.sh "$@"
EOF

chmod +x "$SSF_LAUNCHER"

# --------------------------------------------------
# Проверка launcher
# --------------------------------------------------

if [ ! -x "$SSF_LAUNCHER" ]; then
    echo "❌ Не удалось создать launcher:"
    echo "  $SSF_LAUNCHER"
    exit 1
fi

if [ ! -x "$SSF_SCRIPT" ]; then
    echo "❌ Установленный ssf.sh не является исполняемым."
    exit 1
fi

# Финальная проверка
if ! bash -n "$SSF_SCRIPT"; then
    echo "❌ Финальная проверка ssf.sh не пройдена!"
    exit 1
fi

# --------------------------------------------------
# Завершение
# --------------------------------------------------

echo ""
echo "========================================="
echo "       ✨ SSF установлен успешно! ✨"
echo "========================================="
echo ""
echo "Основной файл:"
echo "  $SSF_SCRIPT"
echo ""
echo "Команда запуска:"
echo "  ssf"
echo ""
echo "Launcher:"
echo "  $SSF_LAUNCHER"
echo ""

# --------------------------------------------------
# Предложение запустить SSF
# --------------------------------------------------

read -r -p "Запустить SSF сейчас? [Y/n]: " START_SSF

case "$START_SSF" in
    n|N)
        echo ""
        echo "Установка завершена."
        echo "Для запуска выполните: ssf"
        ;;
    *)
        echo ""
        echo "🚀 Запускаем SSF..."
        echo ""
        exec "$SSF_LAUNCHER"
        ;;
esac

exit 0
