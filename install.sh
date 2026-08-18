#!/bin/bash

# Скрипт установки SSF (Server Setup Framework)
# Использование: curl -fsSL https://raw.githubusercontent.com/nickyramma/ssf/main/install.sh | bash

set -e

echo "=== Установка SSF (Server Setup Framework) ==="
echo ""

# Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Ошибка: Этот скрипт должен быть запущен с правами root."
    echo "Используйте: sudo bash install.sh или curl -fsSL https://raw.githubusercontent.com/nickyramma/ssf/main/install.sh | sudo bash"
    exit 1
fi

# Проверка наличия curl или wget
if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
    echo "❌ Ошибка: curl или wget не найдены. Установите один из них и повторите попытку."
    exit 1
fi

# Переменные пути
SSF_LIB_DIR="/usr/local/lib/ssf"
SSF_BIN="/usr/local/bin/ssf"
SSF_MAIN="/usr/local/lib/ssf/ssf.sh"
SSF_BACKUP="/usr/local/lib/ssf/ssf.sh.bak"
SSF_REMOTE_URL="https://raw.githubusercontent.com/nickyramma/ssf/main/ssf.sh"
SSF_TMP="/tmp/ssf.sh.new"

# Очистка временного файла при выходе
cleanup() {
    if [ -f "$SSF_TMP" ]; then
        rm -f "$SSF_TMP"
    fi
}
trap cleanup EXIT

echo "📥 Скачиваем ssf.sh..."

# Скачиваем файл во временное место
DOWNLOAD_EXIT_CODE=0
if command -v curl &> /dev/null; then
    curl -fsSL --retry 3 --connect-timeout 10 \
        "$SSF_REMOTE_URL" \
        -o "$SSF_TMP" || DOWNLOAD_EXIT_CODE=$?
elif command -v wget &> /dev/null; then
    wget -q --timeout=10 --tries=3 \
        "$SSF_REMOTE_URL" \
        -O "$SSF_TMP" || DOWNLOAD_EXIT_CODE=$?
fi

# Проверка успешности загрузки
if [ $DOWNLOAD_EXIT_CODE -ne 0 ]; then
    echo "❌ Ошибка: Не удалось скачать ssf.sh"
    exit 1
fi

# Проверка, что файл не пустой
if [ ! -s "$SSF_TMP" ]; then
    echo "❌ Ошибка: Скачанный файл пуст"
    exit 1
fi

# Проверка, что первая строка содержит shebang
FIRST_LINE=$(head -n 1 "$SSF_TMP")
if [ "$FIRST_LINE" != "#!/bin/bash" ]; then
    echo "❌ Ошибка: Скачанный файл не является bash-скриптом"
    exit 1
fi

echo "✅ Файл скачан"

# Проверка синтаксиса скрипта
echo "🔍 Проверяем синтаксис скрипта..."
if ! bash -n "$SSF_TMP" 2>/dev/null; then
    echo "❌ Ошибка: Синтаксис скрипта некорректен"
    exit 1
fi

echo "✅ Синтаксис проверен"

# Создание директории для установки
echo "📁 Создаём директорию $SSF_LIB_DIR..."
mkdir -p "$SSF_LIB_DIR"

# Сохранение резервной копии, если файл уже существует
if [ -f "$SSF_MAIN" ]; then
    echo "💾 Сохраняем резервную копию..."
    cp "$SSF_MAIN" "$SSF_BACKUP"
fi

# Установка прав исполнения на временный файл
chmod +x "$SSF_TMP"

# Атомарная замена файла
echo "🔄 Устанавливаем ssf.sh..."
mv "$SSF_TMP" "$SSF_MAIN"

# Создание launcher-файла в /usr/local/bin/ssf
echo "🔗 Создаём launcher в $SSF_BIN..."
cat > "$SSF_BIN" << 'LAUNCHER'
#!/bin/bash
exec /usr/local/lib/ssf/ssf.sh "$@"
LAUNCHER

chmod +x "$SSF_BIN"

# Финальные проверки
echo "✓ Проверяем установку..."

if [ ! -x "$SSF_BIN" ]; then
    echo "❌ Ошибка: Launcher не исполняем"
    exit 1
fi

if [ ! -x "$SSF_MAIN" ]; then
    echo "❌ Ошибка: ssf.sh не исполняем"
    exit 1
fi

if ! bash -n "$SSF_MAIN" 2>/dev/null; then
    echo "❌ Ошибка: Установленный ssf.sh имеет синтаксические ошибки"
    exit 1
fi

echo "✅ Все проверки пройдены"

echo ""
echo "========================================="
echo " SSF установлен успешно"
echo "========================================="
echo ""
echo "Файл:"
echo "  $SSF_MAIN"
echo ""
echo "Команда:"
echo "  ssf"
echo ""

# Предложение запустить SSF
read -p "Запустить SSF сейчас? [Y/n]: " -r RESPONSE
RESPONSE=${RESPONSE:-Y}

if [[ "$RESPONSE" =~ ^[Yy]$ ]]; then
    exec "$SSF_BIN"
else
    echo "Установка завершена. Вы можете запустить SSF командой: ssf"
    exit 0
fi
