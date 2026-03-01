# OfflineLLM

Утилита для экспорта и импорта моделей [Ollama](https://ollama.com) между машинами.
Позволяет перенести модели с компьютера с интернетом на офлайн-машину — **Windows или Linux**.

## Скрипты

| Скрипт | Платформа | Назначение |
|--------|-----------|------------|
| `offlineLLM.ps1` | Windows | Список моделей, экспорт, импорт |
| `offlineLLM.sh` | Linux (RHEL/CentOS/Fedora/Ubuntu) | Список моделей, экспорт, импорт |

## Требования

### Windows (`offlineLLM.ps1`)
- Windows 10 1803+ (для поддержки `tar.exe`) или Windows 11
- [Ollama](https://ollama.com/download) установлена
- PowerShell 5.1+ (встроен в Windows)

### Linux (`offlineLLM.sh`)
- Bash 4.0+, `tar` (по умолчанию присутствуют)
- [Ollama](https://ollama.com/download) установлена
- `jq` **или** `python3` — для команды `export` (разбор JSON-манифестов)

## Быстрый старт

### 1. На машине с интернетом — составить список моделей

**Windows:**
```powershell
.\offlineLLM.ps1 list-popular -OutputFile models.txt
```

**Linux:**
```bash
chmod +x offlineLLM.sh
./offlineLLM.sh list-popular -o models.txt
```

Откройте `models.txt` и оставьте только нужные модели (удалите остальные строки).

### 2. На машине с интернетом — экспортировать модели

**Windows:**
```powershell
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir .\archives
```

**Linux:**
```bash
./offlineLLM.sh export -m models.txt -d ./archives
```

Каждая модель сохранится как отдельный `.tar` файл в папке `archives/`.

### 3. Скопировать папку `archives/` на целевую машину

Используйте USB-накопитель, внешний диск или локальную сеть.

### 4а. Импорт на Windows

```powershell
.\offlineLLM.ps1 import -ArchiveDir .\archives
```

### 4б. Импорт на Linux

```bash
./offlineLLM.sh import -d ./archives -r
```

### 5. Проверить импортированные модели

```bash
ollama list
ollama run llama3.2 "Привет!"
```

## Все команды

| Команда | Описание |
|---------|----------|
| `list-popular` | Создать файл со списком популярных моделей |
| `list-installed` | Показать установленные модели |
| `export` | Экспортировать модели в `.tar` архивы |
| `import` | Импортировать архивы в Ollama |

## Параметры

### `list-popular`

**Windows:**
```powershell
.\offlineLLM.ps1 list-popular [-OutputFile <путь>] [-Count <число>]
```

**Linux:**
```bash
./offlineLLM.sh list-popular [-o <путь>] [-n <число>]
```

| Параметр (Windows) | Параметр (Linux) | По умолчанию | Описание |
|--------------------|------------------|--------------|----------|
| `-OutputFile` | `-o FILE` | `models.txt` | Путь к выходному файлу |
| `-Count` | `-n N` | `50` | Максимальное количество онлайн-моделей |

### `export`

**Windows:**
```powershell
.\offlineLLM.ps1 export [-ModelsFile <путь>] [-ArchiveDir <путь>] [-OllamaDir <путь>] [-Force]
```

**Linux:**
```bash
./offlineLLM.sh export [-m <путь>] [-d <путь>] [-p <путь>] [-f]
```

| Параметр (Windows) | Параметр (Linux) | По умолчанию | Описание |
|--------------------|------------------|--------------|----------|
| `-ModelsFile` | `-m FILE` | `models.txt` | Файл со списком моделей |
| `-ArchiveDir` | `-d DIR` | `./archives` | Папка для сохранения архивов |
| `-OllamaDir` | `-p DIR` | авто | Путь к каталогу моделей Ollama |
| `-Force` | `-f` | — | Перезаписать существующие архивы |

### `import`

**Windows:**
```powershell
.\offlineLLM.ps1 import [-ArchiveDir <путь>] [-OllamaDir <путь>] [-Force]
```

**Linux:**
```bash
./offlineLLM.sh import [-d <путь>] [-p <путь>] [-f] [-r]
```

| Параметр (Windows) | Параметр (Linux) | По умолчанию | Описание |
|--------------------|------------------|--------------|----------|
| `-ArchiveDir` | `-d DIR` | `./archives` | Папка с архивами |
| `-OllamaDir` | `-p DIR` | авто | Путь к каталогу моделей Ollama |
| `-Force` | `-f` | — | Перезаписать существующие файлы |
| — | `-r` | — | Перезапустить Ollama после импорта |

## Формат файла моделей

Файл `models.txt` — обычный текстовый файл. Строки с `#` — комментарии.

```
# Мои модели для офлайн-машины
llama3.2
mistral:7b
qwen2.5-coder:14b
phi4
```

## Примеры

### Windows

```powershell
# Экспорт конкретных моделей
echo "llama3.2`nmixtral:8x7b" | Out-File models.txt
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir D:\ollama-backup

# Импорт с кастомным путём Ollama
.\offlineLLM.ps1 import -ArchiveDir E:\ollama-models -OllamaDir C:\ollama\models

# Принудительная перезапись
.\offlineLLM.ps1 export -ModelsFile models.txt -Force
```

### Linux

```bash
# Получить список популярных моделей, отредактировать, экспортировать
./offlineLLM.sh list-popular -o models.txt
nano models.txt
./offlineLLM.sh export -m models.txt -d ./archives

# Импорт с USB-носителя и перезапуском сервиса
./offlineLLM.sh import -d /mnt/usb/archives -r

# Импорт в нестандартный каталог Ollama (например, системный пользователь)
sudo ./offlineLLM.sh import -d ./archives -p /usr/share/ollama/.ollama/models

# Принудительная перезапись существующих файлов
./offlineLLM.sh import -d ./archives -f -r
```

## Типичные размеры моделей

| Модель | Размер |
|--------|--------|
| tinyllama (1B) | ~600 MB |
| phi3.5 (3.8B) | ~2.2 GB |
| llama3.2 (3B) | ~2 GB |
| mistral (7B) | ~4.1 GB |
| llama3.1 (8B) | ~4.7 GB |
| qwen2.5 (14B) | ~9 GB |
| llama3.3 (70B) | ~40 GB |

## Устранение проблем

**Модели не отображаются после импорта (Windows):**
```powershell
Stop-Service ollama -ErrorAction SilentlyContinue
Start-Service ollama
# или перезапустите приложение Ollama из трея
```

**Модели не отображаются после импорта (Linux):**
```bash
sudo systemctl restart ollama
# или при запуске вручную: перезапустите процесс ollama serve
```

**Ошибка "tar не найден" (Windows):**
Обновите Windows до версии 1803+.

**Ошибка "jq не найден" при экспорте (Linux):**
```bash
# RHEL/CentOS/Fedora
sudo dnf install jq
# Ubuntu/Debian
sudo apt install jq
# Альтернатива без установки — достаточно python3 (обычно уже есть)
```

**Нет прав на запись в каталог Ollama:**
- Windows: запустите PowerShell от имени администратора или укажите `-OllamaDir` в доступную папку
- Linux: запустите от имени пользователя `ollama` или используйте `sudo` с флагом `-p`

**SELinux блокирует доступ к файлам (RHEL):**
```bash
sudo restorecon -r ~/.ollama/models
```

## Документация

- [Архитектура](docs/architecture.md)
- [Руководство по использованию (Windows)](docs/usage.md)
- [Импорт на Linux / Red Hat](docs/linux-import.md)
- [Руководство разработчика](docs/development.md)

## Лицензия

MIT
