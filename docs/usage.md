# Руководство по использованию OfflineLLM

## Типичный сценарий: перенос моделей на офлайн-машину

### Шаг 1 — Составить список моделей (машина с интернетом)

```powershell
.\offlineLLM.ps1 list-popular -OutputFile models.txt
```

Скрипт попытается загрузить актуальный список с `ollama.com`. При отсутствии интернета
использует встроенный список популярных моделей.

Откройте `models.txt` и оставьте только нужные модели:

```
# Мои модели
llama3.2
qwen2.5-coder:14b
nomic-embed-text
```

### Шаг 2 — Экспортировать модели (машина с интернетом)

```powershell
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir .\archives
```

**Что происходит:**
- Если модель установлена — экспортируется из кэша Ollama без загрузки
- Если модели нет — запускается `ollama pull` для её скачивания
- Каждая модель сохраняется как отдельный `.tar` файл

Результат:
```
archives\
├── llama3.2-latest.tar          (2.0 GB)
├── qwen2.5-coder-14b.tar        (9.0 GB)
└── nomic-embed-text-latest.tar  (0.3 GB)
```

### Шаг 3 — Перенести архивы на офлайн-машину

Скопируйте папку `archives\` на USB-накопитель или внешний диск.
Также скопируйте `offlineLLM.ps1`.

### Шаг 4 — Импортировать модели (офлайн-машина)

```powershell
.\offlineLLM.ps1 import -ArchiveDir .\archives
```

### Шаг 5 — Проверить

```powershell
ollama list
ollama run llama3.2 "Привет, как дела?"
```

---

## Примеры команд

### Просмотр установленных моделей

```powershell
.\offlineLLM.ps1 list-installed
```

Аналог `ollama list`.

### Экспорт конкретных моделей

```powershell
# Создать файл на лету и экспортировать
@"
deepseek-r1:7b
phi4
tinyllama
"@ | Out-File -FilePath my-models.txt -Encoding UTF8

.\offlineLLM.ps1 export -ModelsFile my-models.txt -ArchiveDir D:\usb-drive\ollama
```

### Импорт в нестандартный каталог Ollama

```powershell
.\offlineLLM.ps1 import -ArchiveDir E:\ollama-archives -OllamaDir C:\custom\ollama\models
```

### Принудительное обновление архива

```powershell
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir .\archives -Force
```

### Экспорт одной модели

```powershell
echo "mistral:7b" | Out-File -FilePath one.txt
.\offlineLLM.ps1 export -ModelsFile one.txt -ArchiveDir .\archives
```

### Использование переменной окружения OLLAMA_MODELS

Если Ollama настроена на нестандартный каталог через переменную `OLLAMA_MODELS`,
скрипт подхватывает её автоматически:

```powershell
$env:OLLAMA_MODELS = 'D:\my-models'
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir .\archives
```

Либо явно:
```powershell
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir .\archives -OllamaDir D:\my-models
```

---

## Формат файла models.txt

```
# Это комментарий — строки с # игнорируются
# Пустые строки тоже игнорируются

# Формат: model  или  model:tag
llama3.2           # → llama3.2:latest
llama3.1:8b        # → конкретный тег 8b
deepseek-r1:70b
```

---

## Устранение проблём

### Модели не видны после импорта

Перезапустите Ollama:
```powershell
# Если Ollama работает как служба Windows
Stop-Service ollama
Start-Service ollama

# Если запускается через трей — закройте и откройте заново
```

### Ошибка: "Blob не найден"

Установка Ollama повреждена. Переустановите модель:
```powershell
ollama rm model-name
ollama pull model-name
```
Затем повторите экспорт.

### Ошибка: "tar завершился с ненулевым кодом"

Проверьте, что `tar.exe` доступен:
```powershell
where.exe tar
tar --version
```

Если tar не найден — обновите Windows до 1803+ или используйте PowerShell 7
(снимает ограничение 2 GB в Compress-Archive).

### Предупреждение о 2 GB лимите

Скрипт автоматически выдаст предупреждение, если `tar` недоступен.
Для моделей меньше 2 GB (1B–7B) `Compress-Archive` работает нормально.
Для крупных моделей (13B+) требуется `tar`.

### Нет прав на запись в каталог Ollama

```powershell
# Запустите PowerShell от имени администратора
# или укажите другой каталог
.\offlineLLM.ps1 import -ArchiveDir .\archives -OllamaDir "$env:USERPROFILE\.ollama\models"
```

### Политика выполнения PowerShell блокирует скрипт

```powershell
# Разрешить выполнение скриптов для текущего пользователя
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Или запустить с явным обходом политики (только для этого запуска)
powershell -ExecutionPolicy Bypass -File .\offlineLLM.ps1 list-popular
```

---

## Ориентировочные размеры архивов

| Модель | Параметры | Размер архива |
|--------|-----------|---------------|
| tinyllama | 1B | ~600 MB |
| phi3.5 | 3.8B | ~2.2 GB |
| llama3.2 | 3B | ~2.0 GB |
| gemma3 | 4B | ~2.5 GB |
| mistral | 7B | ~4.1 GB |
| llama3.1 | 8B | ~4.7 GB |
| qwen2.5-coder | 14B | ~9.0 GB |
| gemma2 | 27B | ~16 GB |
| deepseek-r1 | 32B | ~19 GB |
| llama3.1 | 70B | ~40 GB |
| deepseek-r1 | 70B | ~40 GB |
