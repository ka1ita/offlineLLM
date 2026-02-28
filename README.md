# OfflineLLM

Утилита для экспорта и импорта моделей [Ollama](https://ollama.com) между машинами.
Позволяет перенести модели с компьютера с интернетом на компьютер без интернета.

## Требования

- Windows 10 1803+ (для поддержки `tar.exe`) или Windows 11
- [Ollama](https://ollama.com/download) установлена на обеих машинах
- PowerShell 5.1+ (встроен в Windows)

## Быстрый старт

### 1. На машине с интернетом — составить список моделей

```powershell
.\offlineLLM.ps1 list-popular -OutputFile models.txt
```

Откройте `models.txt` и оставьте только нужные модели (удалите остальные строки).

### 2. На машине с интернетом — экспортировать модели

```powershell
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir .\archives
```

Каждая модель сохранится как отдельный `.tar` файл в папке `archives\`.

### 3. Скопировать папку `archives\` на офлайн-машину

Используйте USB-накопитель, внешний диск или локальную сеть.

### 4. На офлайн-машине — импортировать модели

```powershell
.\offlineLLM.ps1 import -ArchiveDir .\archives
```

### 5. Проверить импортированные модели

```powershell
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

```powershell
.\offlineLLM.ps1 list-popular [-OutputFile <путь>] [-Count <число>]
```

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `-OutputFile` | `models.txt` | Путь к выходному файлу |
| `-Count` | `50` | Максимальное количество онлайн-моделей |

### `export`

```powershell
.\offlineLLM.ps1 export [-ModelsFile <путь>] [-ArchiveDir <путь>] [-OllamaDir <путь>] [-Force]
```

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `-ModelsFile` | `models.txt` | Файл со списком моделей |
| `-ArchiveDir` | `.\archives` | Папка для сохранения архивов |
| `-OllamaDir` | авто | Путь к каталогу моделей Ollama |
| `-Force` | — | Перезаписать существующие архивы |

### `import`

```powershell
.\offlineLLM.ps1 import [-ArchiveDir <путь>] [-OllamaDir <путь>] [-Force]
```

| Параметр | По умолчанию | Описание |
|----------|--------------|----------|
| `-ArchiveDir` | `.\archives` | Папка с архивами |
| `-OllamaDir` | авто | Путь к каталогу моделей Ollama |
| `-Force` | — | Перезаписать существующие файлы |

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

```powershell
# Экспорт конкретных моделей
echo "llama3.2`nmixtral:8x7b" | Out-File models.txt
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir D:\ollama-backup

# Импорт с кастомным путём Ollama
.\offlineLLM.ps1 import -ArchiveDir E:\ollama-models -OllamaDir C:\ollama\models

# Принудительная перезапись
.\offlineLLM.ps1 export -ModelsFile models.txt -Force
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

**Модели не отображаются после импорта:**
```powershell
# Перезапустите службу Ollama
Stop-Service ollama -ErrorAction SilentlyContinue
Start-Service ollama
# или перезапустите приложение Ollama из трея
```

**Ошибка "tar не найден":**
Обновите Windows до версии 1803+. Альтернативно установите [7-Zip](https://www.7-zip.org/).

**Нет прав на запись в каталог Ollama:**
Запустите PowerShell от имени администратора или измените `-OllamaDir` на папку без ограничений.

## Документация

- [Архитектура](docs/architecture.md)
- [Руководство по использованию](docs/usage.md)
- [Руководство разработчика](docs/development.md)

## Лицензия

MIT
