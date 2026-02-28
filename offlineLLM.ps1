#Requires -Version 5.1
<#
.SYNOPSIS
    OfflineLLM — экспорт и импорт моделей Ollama для работы без интернета.

.DESCRIPTION
    Утилита позволяет:
    • Получить список популярных моделей Ollama (list-popular)
    • Просмотреть установленные модели (list-installed)
    • Экспортировать модели в .tar архивы (export) — на машине с интернетом
    • Импортировать архивы в Ollama (import) — на офлайн-машине

.PARAMETER Command
    list-popular    — создать файл со списком популярных моделей
    list-installed  — показать установленные модели
    export          — экспортировать модели из файла в архивы
    import          — импортировать архивы в Ollama

.EXAMPLE
    .\offlineLLM.ps1 list-popular -OutputFile models.txt

.EXAMPLE
    .\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir .\archives

.EXAMPLE
    .\offlineLLM.ps1 import -ArchiveDir .\archives

.LINK
    https://ollama.com
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('list-popular', 'list-installed', 'export', 'import')]
    [string]$Command,

    # list-popular
    [string]$OutputFile = 'models.txt',
    [int]$Count = 50,

    # export / import
    [string]$ModelsFile = 'models.txt',
    [string]$ArchiveDir = '.\archives',
    [string]$OllamaDir  = '',

    # flags
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ──────────────────────────────────────────────────────────────────────────────
# Output helpers
# ──────────────────────────────────────────────────────────────────────────────

function Write-Header ([string]$Text) {
    Write-Host ''
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ("  " + "-" * $Text.Length) -ForegroundColor DarkCyan
}

function Write-Step ([string]$Text) {
    Write-Host "  $Text" -ForegroundColor Gray
}

function Write-OK ([string]$Text) {
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-Warn ([string]$Text) {
    Write-Host "  [!!] $Text" -ForegroundColor Yellow
}

function Write-Fail ([string]$Text) {
    Write-Host "  [XX] $Text" -ForegroundColor Red
}

function Write-Info ([string]$Text) {
    Write-Host "  --> $Text" -ForegroundColor White
}

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

function Get-OllamaModelsDir {
    if ($OllamaDir -ne '') {
        return $OllamaDir
    }
    $envDir = [System.Environment]::GetEnvironmentVariable('OLLAMA_MODELS')
    if ($envDir) {
        return $envDir
    }
    return Join-Path $env:USERPROFILE '.ollama\models'
}

function Assert-OllamaInstalled {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if (-not $cmd) {
        throw "Ollama не найдена в PATH.`nУстановите Ollama: https://ollama.com/download"
    }
}

function Get-ModelParts ([string]$ModelSpec) {
    $spec = $ModelSpec.Trim()
    if ($spec -match '^([^:]+):(.+)$') {
        return @{ Name = $Matches[1].Trim(); Tag = $Matches[2].Trim() }
    }
    return @{ Name = $spec; Tag = 'latest' }
}

function ConvertTo-BlobFileName ([string]$Digest) {
    # "sha256:abc123..." → "sha256-abc123..."
    return $Digest -replace ':', '-'
}

function Get-ArchiveTool {
    # Explicitly prefer Windows native tar.exe — it understands Windows paths.
    # Git Bash / MinGW tar (found via PATH as 'tar') does NOT handle drive letters.
    $systemTar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $systemTar) { return $systemTar }

    Write-Warn "Windows tar.exe не найден в System32."
    Write-Warn "Используется Compress-Archive (ограничение 2 GB на файл)."
    Write-Warn "Для больших моделей требуется Windows 10 1803+."
    return 'compress-archive'
}

function New-Archive ([string]$SourceDir, [string]$ArchivePath, [string]$Tool) {
    if ($Tool -ne 'compress-archive') {
        & $Tool -cf $ArchivePath -C $SourceDir .
        if ($LASTEXITCODE -ne 0) {
            throw "tar завершился с кодом $LASTEXITCODE"
        }
    }
    else {
        Compress-Archive -Path "$SourceDir\*" -DestinationPath $ArchivePath -Force
    }
}

function Expand-Archive-Compat ([string]$ArchivePath, [string]$DestDir, [string]$Tool) {
    if ($Tool -ne 'compress-archive') {
        if (-not (Test-Path $DestDir)) {
            New-Item -ItemType Directory -Path $DestDir | Out-Null
        }
        & $Tool -xf $ArchivePath -C $DestDir
        if ($LASTEXITCODE -ne 0) {
            throw "tar завершился с кодом $LASTEXITCODE"
        }
    }
    else {
        Expand-Archive -Path $ArchivePath -DestinationPath $DestDir -Force
    }
}

function Get-ArchiveExtension ([string]$Tool) {
    if ($Tool -eq 'compress-archive') { return '.zip' }
    return '.tar'
}

# ──────────────────────────────────────────────────────────────────────────────
# Manifest resolution
# ──────────────────────────────────────────────────────────────────────────────

function Find-ManifestPath ([string]$ModelsDir, [string]$Name, [string]$Tag) {
    # Standard library path
    $candidates = @(
        (Join-Path $ModelsDir "manifests\registry.ollama.ai\library\$Name\$Tag")
        (Join-Path $ModelsDir "manifests\registry.ollama.ai\$Name\$Tag")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    # Fallback: search all manifests for matching name/tag
    $manifestRoot = Join-Path $ModelsDir 'manifests'
    if (Test-Path $manifestRoot) {
        $found = Get-ChildItem $manifestRoot -Recurse -File |
            Where-Object { $_.Name -eq $Tag -and $_.Directory.Name -eq $Name }
        if ($found) { return $found[0].FullName }
    }

    return $null
}

# ──────────────────────────────────────────────────────────────────────────────
# list-popular
# ──────────────────────────────────────────────────────────────────────────────

$Script:BuiltinPopularModels = @(
    '# === Универсальные LLM ===',
    'llama3.3', 'llama3.2', 'llama3.2:1b',
    'llama3.1:8b', 'llama3.1:70b',
    'mistral', 'mistral-nemo',
    'gemma3:4b', 'gemma3:12b', 'gemma2:9b', 'gemma2:27b',
    'qwen2.5:7b', 'qwen2.5:14b', 'qwen2.5:72b',
    'phi4', 'phi3.5',
    'command-r', 'solar', 'neural-chat', 'wizardlm2', 'tinyllama',
    '',
    '# === Кодирование ===',
    'qwen2.5-coder:7b', 'qwen2.5-coder:14b',
    'codellama', 'codellama:34b',
    'deepseek-coder-v2', 'codegemma', 'starcoder2',
    '',
    '# === Рассуждения (Reasoning) ===',
    'deepseek-r1:7b', 'deepseek-r1:14b', 'deepseek-r1:32b', 'deepseek-r1:70b',
    '',
    '# === Мультимодальные ===',
    'llava', 'llava-phi3', 'moondream', 'bakllava',
    '',
    '# === Встраивания (Embeddings) ===',
    'nomic-embed-text', 'mxbai-embed-large', 'bge-m3', 'all-minilm'
)

function Get-OnlineModels ([int]$MaxCount) {
    Write-Step "Запрос популярных моделей с ollama.com..."
    try {
        $headers = @{ 'User-Agent' = 'Mozilla/5.0 OfflineLLM/1.0' }
        $response = Invoke-WebRequest -Uri 'https://ollama.com/search?q=&sort=popular' `
            -Headers $headers -TimeoutSec 15 -UseBasicParsing

        $modelNames = [regex]::Matches($response.Content, 'href="/library/([a-z0-9_.-]+)"') |
            ForEach-Object { $_.Groups[1].Value } |
            Sort-Object -Unique

        if ($modelNames.Count -gt 0) {
            Write-OK "Получено $($modelNames.Count) моделей с ollama.com"
            return $modelNames | Select-Object -First $MaxCount
        }
    }
    catch {
        Write-Warn "Не удалось получить список онлайн: $($_.Exception.Message)"
    }
    return $null
}

function Invoke-ListPopular {
    Write-Header "Список популярных моделей Ollama"

    $onlineModels = Get-OnlineModels -MaxCount $Count

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Популярные модели Ollama")
    $lines.Add("# Сгенерировано: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $lines.Add("# Источник: $(if ($onlineModels) { 'ollama.com (онлайн)' } else { 'встроенный список' })")
    $lines.Add("#")
    $lines.Add("# Отредактируйте файл, оставив нужные модели, затем запустите:")
    $lines.Add("#   .\offlineLLM.ps1 export -ModelsFile $OutputFile -ArchiveDir .\archives")
    $lines.Add("#")
    $lines.Add("# Формат: model  или  model:tag  (тег 'latest' используется по умолчанию)")
    $lines.Add("")

    if ($onlineModels) {
        $lines.Add("# === Популярные модели с ollama.com ===")
        foreach ($m in $onlineModels) { $lines.Add($m) }
    }
    else {
        $lines.Add("# === Встроенный список популярных моделей ===")
        foreach ($m in $Script:BuiltinPopularModels) { $lines.Add($m) }
    }

    # Append installed models
    try {
        $installed = & ollama list 2>$null |
            Select-Object -Skip 1 |
            ForEach-Object { ($_ -split '\s+')[0] } |
            Where-Object { $_ -and $_ -ne '' }

        if ($installed) {
            $lines.Add("")
            $lines.Add("# === Уже установленные на этой машине ===")
            foreach ($m in $installed) { $lines.Add($m) }
        }
    }
    catch { }

    $lines | Set-Content -Path $OutputFile -Encoding UTF8

    Write-OK "Сохранено: $OutputFile  ($($lines.Count) строк)"
    Write-Host ""
    Write-Info "Следующий шаг: отредактируйте $OutputFile, затем запустите:"
    Write-Info "  .\offlineLLM.ps1 export -ModelsFile $OutputFile -ArchiveDir .\archives"
}

# ──────────────────────────────────────────────────────────────────────────────
# list-installed
# ──────────────────────────────────────────────────────────────────────────────

function Invoke-ListInstalled {
    Write-Header "Установленные модели Ollama"
    Assert-OllamaInstalled
    & ollama list
}

# ──────────────────────────────────────────────────────────────────────────────
# export
# ──────────────────────────────────────────────────────────────────────────────

function Export-SingleModel ([string]$ModelSpec, [string]$ModelsDir, [string]$DestDir, [string]$Tool) {
    $parts = Get-ModelParts $ModelSpec
    $name  = $parts.Name
    $tag   = $parts.Tag

    Write-Host ""
    Write-Info "Модель: $name`:$tag"

    # Locate manifest
    $manifestPath = Find-ManifestPath $ModelsDir $name $tag

    if (-not $manifestPath) {
        Write-Warn "Модель $name`:$tag не найдена локально. Загрузка через Ollama..."
        try {
            & ollama pull "$name`:$tag"
            $manifestPath = Find-ManifestPath $ModelsDir $name $tag
        }
        catch {
            Write-Fail "Не удалось загрузить $name`:$tag : $($_.Exception.Message)"
            return $false
        }
    }

    if (-not $manifestPath) {
        Write-Fail "Манифест не найден для $name`:$tag после загрузки"
        return $false
    }

    Write-Step "Манифест: $manifestPath"

    # Parse manifest JSON
    try {
        $manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Fail "Не удалось прочитать манифест: $($_.Exception.Message)"
        return $false
    }

    # Collect blob digests
    $digests = [System.Collections.Generic.List[string]]::new()
    if ($manifest.config -and $manifest.config.digest) {
        $digests.Add($manifest.config.digest)
    }
    foreach ($layer in $manifest.layers) {
        if ($layer.digest) { $digests.Add($layer.digest) }
    }

    # Prepare temp staging directory
    $tempDir = Join-Path $env:TEMP "offlineLLM_export_$(Get-Random)"
    try {
        New-Item -ItemType Directory -Path $tempDir | Out-Null

        # Copy manifest (preserve relative path from ModelsDir)
        $relManifestPath = $manifestPath.Substring($ModelsDir.TrimEnd('\').Length).TrimStart('\', '/')
        $destManifest    = Join-Path $tempDir $relManifestPath
        New-Item -ItemType Directory -Path (Split-Path $destManifest) -Force | Out-Null
        Copy-Item $manifestPath $destManifest

        # Copy blobs
        $blobsDest = Join-Path $tempDir 'blobs'
        New-Item -ItemType Directory -Path $blobsDest | Out-Null

        $totalBytes = 0L
        $missingBlob = $false

        foreach ($digest in $digests) {
            $blobName = ConvertTo-BlobFileName $digest
            $blobSrc  = Join-Path $ModelsDir "blobs\$blobName"

            if (-not (Test-Path $blobSrc)) {
                Write-Fail "Blob не найден: $blobName"
                $missingBlob = $true
                continue
            }

            $blobSize   = (Get-Item $blobSrc).Length
            $totalBytes += $blobSize
            Write-Step "  + $blobName  ($([math]::Round($blobSize / 1MB, 1)) MB)"
            Copy-Item $blobSrc (Join-Path $blobsDest $blobName)
        }

        if ($missingBlob) {
            Write-Fail "Экспорт $name`:$tag прерван из-за отсутствующих blob-файлов"
            return $false
        }

        # Determine archive filename: replace invalid chars
        $safeName    = "$name-$tag" -replace '[/\\:*?"<>|]', '-'
        $ext         = Get-ArchiveExtension $Tool
        $archivePath = Join-Path $DestDir "$safeName$ext"

        if ((Test-Path $archivePath) -and -not $Force) {
            Write-Warn "Архив уже существует: $archivePath  (используйте -Force для перезаписи)"
            return $true
        }

        $totalGB = [math]::Round($totalBytes / 1GB, 2)
        Write-Step "Создание архива: $safeName$ext  (данных ~$totalGB GB)..."
        New-Archive -SourceDir $tempDir -ArchivePath $archivePath -Tool $Tool

        $archiveSizeMB = [math]::Round((Get-Item $archivePath).Length / 1MB, 0)
        Write-OK "$name`:$tag  -->  $safeName$ext  ($archiveSizeMB MB)"
        return $true
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-Export {
    Write-Header "Экспорт моделей Ollama в архивы"
    Assert-OllamaInstalled

    if (-not (Test-Path $ModelsFile)) {
        throw "Файл со списком моделей не найден: $ModelsFile`n" +
              "Создайте его командой:  .\offlineLLM.ps1 list-popular -OutputFile $ModelsFile"
    }

    $modelsDir = Get-OllamaModelsDir
    Write-Step "Каталог моделей Ollama : $modelsDir"

    if (-not (Test-Path $modelsDir)) {
        throw "Каталог моделей Ollama не найден: $modelsDir`nЗапустите Ollama и загрузите хотя бы одну модель."
    }

    # Create output directory
    if (-not (Test-Path $ArchiveDir)) {
        New-Item -ItemType Directory -Path $ArchiveDir | Out-Null
        Write-Step "Создан каталог архивов  : $ArchiveDir"
    }

    # Read model list (skip blank lines and comments)
    $models = @(Get-Content $ModelsFile -Encoding UTF8 |
        Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' })

    if ($models.Count -eq 0) {
        throw "Файл '$ModelsFile' не содержит моделей (только комментарии или пуст)."
    }

    Write-Step "Моделей для экспорта    : $($models.Count)"

    $tool    = Get-ArchiveTool
    $success = 0
    $failed  = 0

    foreach ($model in $models) {
        $ok = Export-SingleModel -ModelSpec $model.Trim() -ModelsDir $modelsDir `
                                 -DestDir $ArchiveDir -Tool $tool
        if ($ok) { $success++ } else { $failed++ }
    }

    Write-Host ""
    Write-Header "Итог экспорта"
    Write-OK "Успешно : $success"
    if ($failed -gt 0) { Write-Fail "С ошибками : $failed" }
    Write-Host ""
    Write-Info "Архивы сохранены в: $ArchiveDir"
    Write-Info "Скопируйте папку '$ArchiveDir' на офлайн-машину и запустите:"
    Write-Info "  .\offlineLLM.ps1 import -ArchiveDir .\archives"
}

# ──────────────────────────────────────────────────────────────────────────────
# import
# ──────────────────────────────────────────────────────────────────────────────

function Import-SingleArchive ([string]$ArchivePath, [string]$ModelsDir, [string]$Tool) {
    $archiveName = [System.IO.Path]::GetFileNameWithoutExtension($ArchivePath)
    Write-Host ""
    Write-Info "Архив: $([System.IO.Path]::GetFileName($ArchivePath))"

    $tempDir = Join-Path $env:TEMP "offlineLLM_import_$(Get-Random)"
    try {
        New-Item -ItemType Directory -Path $tempDir | Out-Null

        Write-Step "Распаковка..."
        Expand-Archive-Compat -ArchivePath $ArchivePath -DestDir $tempDir -Tool $Tool

        # Import blobs
        $tempBlobs = Join-Path $tempDir 'blobs'
        if (Test-Path $tempBlobs) {
            $blobsDest = Join-Path $ModelsDir 'blobs'
            if (-not (Test-Path $blobsDest)) {
                New-Item -ItemType Directory -Path $blobsDest | Out-Null
            }

            $blobs = Get-ChildItem $tempBlobs -File
            foreach ($blob in $blobs) {
                $destBlob = Join-Path $blobsDest $blob.Name
                if ((Test-Path $destBlob) -and -not $Force) {
                    Write-Step "  Blob (существует, пропуск): $($blob.Name)"
                }
                else {
                    Copy-Item $blob.FullName $destBlob -Force
                    Write-Step "  Blob: $($blob.Name)  ($([math]::Round($blob.Length/1MB,1)) MB)"
                }
            }
        }

        # Import manifests
        $tempManifests = Join-Path $tempDir 'manifests'
        if (Test-Path $tempManifests) {
            $manifestFiles = Get-ChildItem $tempManifests -Recurse -File
            foreach ($mf in $manifestFiles) {
                $relPath  = $mf.FullName.Substring($tempManifests.Length).TrimStart('\', '/')
                $destPath = Join-Path $ModelsDir "manifests\$relPath"
                $destParent = Split-Path $destPath

                if (-not (Test-Path $destParent)) {
                    New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                }
                Copy-Item $mf.FullName $destPath -Force
                Write-Step "  Манифест: $relPath"
            }
        }

        Write-OK "Импортирован: $archiveName"
        return $true
    }
    catch {
        Write-Fail "Ошибка при импорте '$archiveName': $($_.Exception.Message)"
        return $false
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-Import {
    Write-Header "Импорт моделей Ollama из архивов"
    Assert-OllamaInstalled

    if (-not (Test-Path $ArchiveDir)) {
        throw "Каталог с архивами не найден: $ArchiveDir"
    }

    $tool     = Get-ArchiveTool
    $ext      = Get-ArchiveExtension $Tool
    $archives = @(Get-ChildItem $ArchiveDir -Filter "*$ext")

    if ($archives.Count -eq 0) {
        throw "В каталоге '$ArchiveDir' нет архивов (*$ext)."
    }

    $modelsDir = Get-OllamaModelsDir
    Write-Step "Каталог моделей Ollama : $modelsDir"
    Write-Step "Найдено архивов        : $($archives.Count)"

    if (-not (Test-Path $modelsDir)) {
        New-Item -ItemType Directory -Path $modelsDir | Out-Null
        Write-Step "Создан каталог моделей : $modelsDir"
    }

    $success = 0
    $failed  = 0

    foreach ($archive in $archives) {
        $ok = Import-SingleArchive -ArchivePath $archive.FullName `
                                   -ModelsDir $modelsDir -Tool $tool
        if ($ok) { $success++ } else { $failed++ }
    }

    Write-Host ""
    Write-Header "Итог импорта"
    Write-OK "Импортировано : $success"
    if ($failed -gt 0) { Write-Fail "С ошибками    : $failed" }
    Write-Host ""
    Write-Info "Проверьте установленные модели:"
    Write-Info "  ollama list"
    Write-Host ""
    Write-Info "Если модели не отображаются, перезапустите Ollama:"
    Write-Info "  (Windows) Закройте и снова откройте приложение Ollama из трея"
}

# ──────────────────────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────────────────────

try {
    switch ($Command) {
        'list-popular'   { Invoke-ListPopular }
        'list-installed' { Invoke-ListInstalled }
        'export'         { Invoke-Export }
        'import'         { Invoke-Import }
    }
}
catch {
    Write-Fail "Ошибка: $($_.Exception.Message)"
    exit 1
}
