# SSF - Server Setup Framework

Многофункциональный скрипт для настройки и управления Linux сервером.

## 📋 Функциональность

Скрипт предоставляет удобное меню для следующих операций:

1. **Настройка SSH** - изменение порта, отключение пароля, добавление SSH-ключа
2. **Отключение ICMP Ping** - скрывает сервер от сканирования
3. **Установка DonMatteoVPN** - установка Reshala-Remnawave-Bedolaga
4. **Установка Remnanode** - установка Remnawave Node с Docker
5. **Установка TrafficGuard-auto** - автоматическое управление трафиком

## 🚀 Быстрая установка

Выполните одну из этих команд на вашем сервере с правами root:

### Способ 1 - с curl (рекомендуется)
```bash
sudo curl -fsSL https://raw.githubusercontent.com/nickyramma/ssf/main/install.sh | bash
```

### Способ 2 - с wget
```bash
sudo wget -q https://raw.githubusercontent.com/nickyramma/ssf/main/install.sh -O - | bash
```

### Способ 3 - скачать и запустить локально
```bash
wget https://raw.githubusercontent.com/nickyramma/ssf/main/install.sh
sudo bash install.sh
```

## 💻 Использование

После установки просто выполните:

```bash
ssf
```

Или с sudo, если требуется:

```bash
sudo ssf
```

Скрипт откроет интерактивное меню с выбором операций.

## ⚠️ Требования

- Linux сервер (Debian/Ubuntu, CentOS/RHEL, Fedora)
- Права root или sudo
- curl или wget для загрузки скрипта

## 📝 Заметки

- **SSH конфигурация**: Скрипт создает резервную копию оригинального файла конфигурации перед изменениями
- **Firewall**: Автоматически настраивает UFW или firewalld в зависимости от установленного ПО
- **Docker**: Для установки Remnanode требуется Docker и Docker Compose
- **Root привилегии**: Большинство операций требуют прав root

## 🔒 Безопасность

- Все изменения создают резервные копии оригинальных файлов
- SSH-ключи добавляются только с вашего согласия
- Скрипт запрашивает подтверждение перед критическими операциями

## 📄 Лицензия

MIT
