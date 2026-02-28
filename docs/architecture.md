# Архитектура OfflineLLM

## Обзор

OfflineLLM — однофайловая PowerShell-утилита без внешних зависимостей.
Взаимодействует с Ollama через файловую систему (прямой доступ к `~/.ollama/models/`)
и через CLI (`ollama list`, `ollama pull`).

## Структура хранилища Ollama

Ollama использует адресацию по содержимому (content-addressable storage):

```
%USERPROFILE%\.ollama\models\          ← OLLAMA_MODELS (переопределяется)
├── manifests/
│   └── registry.ollama.ai/
│       └── library/
│           └── <model-name>/
│               └── <tag>             ← JSON-манифест (OCI Image Manifest v2)
└── blobs/
    └── sha256-<hex>                  ← Бинарные файлы (GGUF, конфиги)
```

### Формат манифеста

Манифест — JSON в формате OCI Image Manifest:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.docker.distribution.manifest.v2+json",
  "config": {
    "mediaType": "application/vnd.ollama.image.params",
    "digest": "sha256:abc...",
    "size": 123
  },
  "layers": [
    {
      "mediaType": "application/vnd.ollama.image.model",
      "digest": "sha256:def...",
      "size": 4000000000
    },
    {
      "mediaType": "application/vnd.ollama.image.template",
      "digest": "sha256:ghi...",
      "size": 1024
    }
  ]
}
```

### Именование blob-файлов

Дайджест `sha256:abc123...` → файл `blobs/sha256-abc123...` (двоеточие заменяется дефисом).

## Алгоритм экспорта

```
models.txt
    │
    ▼
Для каждой модели name:tag
    │
    ├─► Find-ManifestPath()
    │       manifests/registry.ollama.ai/library/name/tag
    │       (если не найден → ollama pull name:tag)
    │
    ├─► Парсинг JSON: извлечь дайджесты config + layers
    │
    ├─► Копирование файлов во временную директорию:
    │       temp/manifests/registry.ollama.ai/library/name/tag
    │       temp/blobs/sha256-abc...
    │       temp/blobs/sha256-def...
    │
    ├─► tar -cf name-tag.tar -C temp .
    │   (или Compress-Archive как резервный вариант)
    │
    └─► archives/name-tag.tar
```

## Алгоритм импорта

```
archives/*.tar
    │
    ▼
Для каждого архива
    │
    ├─► tar -xf archive.tar -C temp/
    │
    ├─► Копирование blobs:
    │       temp/blobs/* → ~/.ollama/models/blobs/*
    │
    ├─► Копирование manifests:
    │       temp/manifests/**/* → ~/.ollama/models/manifests/**/*
    │
    └─► Ollama обнаруживает модели при следующем запуске
```

## Формат архива

Каждая модель — отдельный `.tar` файл (без сжатия):

```
llama3.2-latest.tar
├── manifests/
│   └── registry.ollama.ai/
│       └── library/
│           └── llama3.2/
│               └── latest
└── blobs/
    ├── sha256-<config-hash>     ← Параметры модели (JSON, маленький)
    ├── sha256-<template-hash>   ← Шаблон промпта (текст)
    └── sha256-<model-hash>      ← Веса модели (GGUF, основной файл)
```

## Выбор инструмента архивирования

```
tar.exe (Windows 10 1803+)      ← приоритет, нет ограничений по размеру
    │   FAIL
    └─► Compress-Archive         ← резервный, лимит 2 GB на файл
            (предупреждение для больших моделей)
```

## Компоненты скрипта

| Функция | Назначение |
|---------|------------|
| `Get-OllamaModelsDir` | Определяет путь к моделям (`OLLAMA_MODELS`, `~/.ollama/models`) |
| `Assert-OllamaInstalled` | Проверяет наличие `ollama` в PATH |
| `Get-ModelParts` | Парсит `name:tag` → `{Name, Tag}` |
| `Find-ManifestPath` | Ищет файл манифеста по имени и тегу |
| `ConvertTo-BlobFileName` | `sha256:abc` → `sha256-abc` |
| `Get-ArchiveTool` | Определяет доступный инструмент архивирования |
| `New-Archive` | Создаёт архив (tar/zip) |
| `Expand-Archive-Compat` | Распаковывает архив (tar/zip) |
| `Export-SingleModel` | Экспортирует одну модель в архив |
| `Import-SingleArchive` | Импортирует один архив |
| `Invoke-ListPopular` | Команда `list-popular` |
| `Invoke-ListInstalled` | Команда `list-installed` |
| `Invoke-Export` | Команда `export` |
| `Invoke-Import` | Команда `import` |

## Обработка ошибок

- Каждая модель обрабатывается независимо; ошибка одной не прерывает цикл
- Временные директории удаляются в блоке `finally`
- Неустановленные модели загружаются автоматически через `ollama pull`
- Ненайденные blob-файлы вызывают ошибку с сохранением состояния

## Поддерживаемые источники моделей

| Источник | Поддержка | Путь манифеста |
|----------|-----------|----------------|
| `registry.ollama.ai/library` | Полная | `manifests/registry.ollama.ai/library/<name>/<tag>` |
| `registry.ollama.ai` (custom) | Частичная | `manifests/registry.ollama.ai/<name>/<tag>` |
| Другие реестры | Поиском | `Find-ManifestPath` ищет по имени файла |
