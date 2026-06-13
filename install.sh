#!/bin/bash

# Скрипт установки SSF (Server Setup Framework)
# Использование: curl -fsSL https://raw.githubusercontent.com/nickyramma/ssf/main/install.sh | bash

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

echo "📥 Скачиваем ssf.sh..."

# Скачиваем файл
if command -v curl &> /dev/null; then
    curl -fsSL https://raw.githubusercontent.com/nickyramma/ssf/main/ssf.sh -o /usr/local/bin/ssf
elif command -v wget &> /dev/null; then
    wget -q https://raw.githubusercontent.com/nickyramma/ssf/main/ssf.sh -O /usr/local/bin/ssf
fi

# Проверка успешности загрузки
if [ ! -f /usr/local/bin/ssf ]; then
    echo "❌ Ошибка: Не удалось скачать ssf.sh"
    exit 1
fi

echo "✅ Файл скачан"

# Устанавливаем права на исполнение
echo "🔧 Устанавливаем права на исполнение..."
chmod +x /usr/local/bin/ssf

echo "✅ Права установлены"

# Проверка успешности установки
if [ -x /usr/local/bin/ssf ]; then
    echo ""
    echo "✨ === Установка завершена успешно! === ✨"
    echo ""
    echo "Теперь вы можете использовать команду:"
    echo "  ssf"
    echo ""
    echo "Или с полной дорожкой:"
    echo "  /usr/local/bin/ssf"
    echo ""
else
    echo "❌ Ошибка: Не удалось установить права на исполнение"
    exit 1
fi
