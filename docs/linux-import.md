# Использование OfflineLLM на Linux

Скрипт `offlineLLM.sh` — полный Linux-аналог `offlineLLM.ps1`. Поддерживает список
популярных моделей, просмотр установленных, экспорт и импорт `.tar`-архивов.

## Требования

- Linux (Red Hat / RHEL 8+, CentOS Stream, Rocky, AlmaLinux, Fedora, Ubuntu 20.04+)
- [Ollama](https://ollama.com/download) установлена
- `bash` 4.0+, `tar` (присутствуют по умолчанию)
- `jq` **или** `python3` — только для команды `export` (разбор JSON-манифестов)

## Установка

```bash
# Скопируйте скрипт на сервер (вместе с архивами)
scp offlineLLM.sh user@server:/home/user/
scp -r archives/   user@server:/home/user/

# Сделайте скрипт исполняемым
chmod +x offlineLLM.sh
```

## Команды

```bash
./offlineLLM.sh <команда> [параметры]
```

| Команда | Описание |
|---------|----------|
| `list-popular` | Создать файл со списком популярных моделей |
| `list-installed` | Показать установленные модели |
| `export` | Экспортировать модели в `.tar` архивы |
| `import` | Импортировать `.tar` архивы в Ollama |

## Параметры

| Опция | Команды | По умолчанию | Описание |
|-------|---------|--------------|----------|
| `-o FILE` | list-popular | `models.txt` | Выходной файл |
| `-n N` | list-popular | `50` | Количество моделей |
| `-m FILE` | export | `models.txt` | Файл со списком моделей |
| `-d DIR` | export, import | `./archives` | Каталог с `.tar`-архивами |
| `-p DIR` | export, import | `$OLLAMA_MODELS` или `~/.ollama/models` | Каталог моделей Ollama |
| `-f` | export, import | — | Перезаписать существующие файлы |
| `-r` | import | — | Перезапустить службу Ollama после импорта |

## Примеры

```bash
# Базовый импорт из ./archives
./offlineLLM.sh import

# Импорт с USB-накопителя
./offlineLLM.sh import -d /mnt/usb/archives

# Импорт и перезапуск службы
./offlineLLM.sh import -d /mnt/usb/archives -r

# Принудительная перезапись + перезапуск
./offlineLLM.sh import -d /mnt/usb/archives -f -r

# Когда Ollama запущена от другого пользователя (например, системная служба)
sudo ./offlineLLM.sh import -d /mnt/usb/archives -p /usr/share/ollama/.ollama/models -r
```

## Типичный сценарий: перенос с Windows

### На Windows-машине с интернетом

```powershell
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir .\archives
```

### Передача архивов на Linux-сервер

```bash
# Через SCP
scp archives/*.tar user@linux-server:/home/user/archives/
scp offlineLLM.sh  user@linux-server:/home/user/

# Через USB (если нет сети)
sudo mount /dev/sdb1 /mnt/usb
```

### На Linux-сервере

```bash
chmod +x offlineLLM.sh
./offlineLLM.sh import -d ./archives -r

# Проверка
ollama list
ollama run llama3.2 "Hello!"
```

## Типичный сценарий: перенос с Linux на Linux

### На Linux-машине с интернетом

```bash
# Составить список моделей
./offlineLLM.sh list-popular -o models.txt
nano models.txt  # оставьте только нужные

# Экспортировать (требуется jq или python3)
./offlineLLM.sh export -m models.txt -d ./archives
```

### На офлайн Linux-сервере

```bash
./offlineLLM.sh import -d ./archives -r
```

## Определение каталога моделей

Скрипт ищет каталог в следующем порядке:

1. Флаг `-p DIR` (явное указание)
2. Переменная окружения `$OLLAMA_MODELS`
3. `~/.ollama/models` (по умолчанию)

Если Ollama запущена как системная служба (через `systemctl`), она обычно использует:
```
/usr/share/ollama/.ollama/models
```

Проверьте актуальный путь:
```bash
systemctl cat ollama | grep OLLAMA_MODELS
# или
ps aux | grep ollama
```

## SELinux на Red Hat

Скрипт автоматически запускает `restorecon` после импорта, если он доступен:

```bash
restorecon -r ~/.ollama/models
```

Если `restorecon` недоступен или нужны права root:
```bash
sudo restorecon -r /usr/share/ollama/.ollama/models
```

Если SELinux блокирует Ollama даже после `restorecon`:
```bash
# Временно (для диагностики)
sudo setenforce 0

# Проверить, что Ollama работает
ollama list

# Вернуть SELinux и настроить политику
sudo setenforce 1
sudo ausearch -c 'ollama' --raw | audit2allow -M ollama-policy
sudo semodule -i ollama-policy.pp
```

## Управление службой Ollama на RHEL

```bash
# Статус
systemctl status ollama

# Перезапуск
sudo systemctl restart ollama

# Автозапуск
sudo systemctl enable ollama

# Журнал
journalctl -u ollama -f
```

## Устранение проблем

### Модели не отображаются после импорта

```bash
sudo systemctl restart ollama
ollama list
```

### Ошибка прав доступа

```bash
# Если Ollama запущена как пользователь 'ollama'
sudo chown -R ollama:ollama /usr/share/ollama/.ollama/models
# или импортируйте от имени нужного пользователя:
sudo ./offlineLLM.sh import -p /usr/share/ollama/.ollama/models
```

### Ошибка "jq не найден" при экспорте

```bash
# RHEL/CentOS/Fedora
sudo dnf install jq
# Ubuntu/Debian
sudo apt install jq
# Альтернатива — python3 (обычно уже установлен)
python3 --version
```

### SELinux: Permission denied

```bash
sudo restorecon -rv ~/.ollama/
# При необходимости:
sudo chcon -Rt svirt_sandbox_file_t ~/.ollama/models/
```

### tar: error opening archive / file not found

Убедитесь, что архивы сформированы корректно (формат `.tar`):
```bash
file archives/llama3.2-latest.tar
# Ожидаемый вывод: POSIX tar archive
tar -tf archives/llama3.2-latest.tar | head
```

### Нет места на диске

```bash
df -h ~/.ollama/
# или
df -h /usr/share/ollama/
```
