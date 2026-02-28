# Руководство разработчика OfflineLLM

## Принципы разработки

- **Без зависимостей**: только встроенные возможности Windows/PowerShell
- **Один файл**: вся логика в `offlineLLM.ps1` — легко копировать и деплоить
- **Устойчивость**: ошибка одной модели не прерывает обработку остальных
- **Идемпотентность**: повторный запуск безопасен (существующие файлы пропускаются)

## Локальная разработка

### Быстрый запуск без Ollama

Для тестирования структуры кода без реального Ollama:

```powershell
# Проверить синтаксис
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\offlineLLM.ps1),
    [ref]$null, [ref]$null
)
Write-Host "Синтаксических ошибок нет"
```

### Тест с реальной Ollama

```powershell
# 1. Убедиться, что Ollama запущена
ollama list

# 2. Скачать маленькую тестовую модель
ollama pull tinyllama

# 3. Тест list-popular
.\offlineLLM.ps1 list-popular -OutputFile test-popular.txt

# 4. Тест list-installed
.\offlineLLM.ps1 list-installed

# 5. Тест export (tinyllama ~600 MB)
echo "tinyllama" | Out-File -FilePath test-models.txt
.\offlineLLM.ps1 export -ModelsFile test-models.txt -ArchiveDir .\test-archives

# 6. Тест import (на той же машине)
.\offlineLLM.ps1 import -ArchiveDir .\test-archives -Force

# 7. Cleanup
Remove-Item test-popular.txt, test-models.txt -ErrorAction SilentlyContinue
Remove-Item .\test-archives -Recurse -ErrorAction SilentlyContinue
```

## Добавление новых команд

1. Добавить значение в `[ValidateSet(...)]` параметра `$Command`
2. Написать функцию `Invoke-<CommandName>`
3. Добавить ветку в `switch ($Command)` в конце файла

```powershell
# Пример: добавить команду 'verify'
function Invoke-Verify {
    Write-Header "Проверка целостности архивов"
    # ...
}

# В switch:
'verify' { Invoke-Verify }
```

## Структура кода

```
offlineLLM.ps1
│
├── Параметры (param block)
│
├── Helpers вывода
│   └── Write-Header, Write-Step, Write-OK, Write-Warn, Write-Fail, Write-Info
│
├── Helpers утилиты
│   ├── Get-OllamaModelsDir     — путь к ~/.ollama/models
│   ├── Assert-OllamaInstalled  — проверка ollama в PATH
│   ├── Get-ModelParts          — парсинг "name:tag"
│   ├── ConvertTo-BlobFileName  — "sha256:x" → "sha256-x"
│   ├── Get-ArchiveTool         — tar или compress-archive
│   ├── New-Archive             — создание архива
│   ├── Expand-Archive-Compat   — распаковка архива
│   └── Get-ArchiveExtension    — ".tar" или ".zip"
│
├── Helpers Ollama
│   └── Find-ManifestPath       — поиск манифеста модели
│
├── $Script:BuiltinPopularModels — встроенный список моделей
│
├── Команда list-popular
│   ├── Get-OnlineModels        — парсинг ollama.com
│   └── Invoke-ListPopular
│
├── Команда list-installed
│   └── Invoke-ListInstalled
│
├── Команда export
│   ├── Export-SingleModel      — экспорт одной модели
│   └── Invoke-Export           — цикл по models.txt
│
├── Команда import
│   ├── Import-SingleArchive    — импорт одного архива
│   └── Invoke-Import           — цикл по *.tar
│
└── Entry point (switch + try/catch)
```

## Как работает Find-ManifestPath

```powershell
function Find-ManifestPath ([string]$ModelsDir, [string]$Name, [string]$Tag) {
    # 1. Стандартный путь library-моделей
    # 2. Путь без /library/ для кастомных моделей
    # 3. Fallback: поиск по имени файла рекурсивно
}
```

Порядок поиска позволяет поддерживать как стандартные, так и кастомные модели.

## Обработка временных файлов

Экспорт и импорт используют временные директории в `$env:TEMP`:

```powershell
$tempDir = Join-Path $env:TEMP "offlineLLM_export_$(Get-Random)"
try {
    # ... работа с файлами
}
finally {
    # Всегда удаляем, даже при ошибке
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
```

## Расширение списка популярных моделей

Встроенный список находится в переменной `$Script:BuiltinPopularModels`:

```powershell
$Script:BuiltinPopularModels = @(
    '# === Новая категория ===',
    'new-model:7b',
    'another-model',
    ...
)
```

Онлайн-список получается парсингом `https://ollama.com/search?q=&sort=popular`.
Регулярное выражение: `href="/library/([a-z0-9_.-]+)"`.

Если сайт изменит структуру HTML, нужно обновить регекс в `Get-OnlineModels`.

## Поддержка нестандартных реестров

Сейчас поддерживаются только `registry.ollama.ai`-модели.
Для поддержки других реестров нужно расширить `Find-ManifestPath`:

```powershell
# Пример: добавить поиск для huggingface.co
$hfPath = Join-Path $ModelsDir "manifests\huggingface.co\$Name\$Tag"
if (Test-Path $hfPath) { return $hfPath }
```

## Возможные улучшения

| Улучшение | Сложность | Описание |
|-----------|-----------|----------|
| Прогресс-бар | Средняя | Write-Progress при копировании blob |
| Верификация | Средняя | Проверка SHA256 после импорта |
| Параллельный экспорт | Высокая | ForEach-Object -Parallel (PS 7+) |
| Дельта-обновление | Высокая | Переиспользование существующих blob |
| GUI-обёртка | Высокая | WPF или winforms поверх скрипта |
| Поддержка 7-Zip | Низкая | Добавить ветку в Get-ArchiveTool |

## Отладка

```powershell
# Включить подробный вывод PowerShell
.\offlineLLM.ps1 export -ModelsFile models.txt -Verbose

# Посмотреть структуру манифеста вручную
$manifest = Get-Content "$env:USERPROFILE\.ollama\models\manifests\registry.ollama.ai\library\llama3.2\latest" | ConvertFrom-Json
$manifest | ConvertTo-Json -Depth 5

# Список всех blob-файлов
Get-ChildItem "$env:USERPROFILE\.ollama\models\blobs" | Sort-Object Length -Descending | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,0)}}
```
