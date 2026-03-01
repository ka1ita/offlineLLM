# OfflineLLM — Project Guide

A comprehensive guide for developers working with the OfflineLLM project.

---

## 1. Project Overview

**OfflineLLM** is a cross-platform utility for exporting and importing [Ollama](https://ollama.com) AI models between internet-connected and offline (air-gapped) machines. It supports both Windows and Linux platforms.

### Key Technologies

| Platform | Language | Dependencies |
|----------|----------|--------------|
| Windows | PowerShell 5.1+ | None (built-in `tar.exe` on Win10 1803+) |
| Linux | Bash 4.0+ | `jq` or `python3` (for JSON parsing during export) |

### High-Level Architecture

```
┌─────────────────┐     ┌─────────────┐     ┌─────────────────┐
│  Internet       │     │   Export    │     │   Archives      │
│  Machine        │────►│  (.tar)     │────►│  (USB/Network)  │
│  (Ollama)       │     │             │     │                 │
└─────────────────┘     └─────────────┘     └─────────────────┘
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │  Offline        │
                                                │  Machine        │
                                                │  (Ollama)       │
                                                └─────────────────┘
```

---

## 2. Getting Started

### Prerequisites

**Windows:**
- Windows 10 1803+ (for `tar.exe` support) or Windows 11
- [Ollama](https://ollama.com/download) installed
- PowerShell 5.1+ (built into Windows)

**Linux:**
- Bash 4.0+, `tar` (default)
- [Ollama](https://ollama.com/download) installed
- `jq` **or** `python3` for export command (JSON manifest parsing)

### Installation

No installation needed — just copy the script to your machine:

```powershell
# Windows
Copy-Item offlineLLM.ps1 C:\Tools\offlineLLM.ps1

# Linux
chmod +x offlineLLM.sh
sudo cp offlineLLM.sh /usr/local/bin/offlineLLM.sh
```

### Basic Usage

**Quick Start Workflow:**

```powershell
# 1. On internet machine — create list of popular models
.\offlineLLM.ps1 list-popular -OutputFile models.txt

# 2. Edit models.txt (keep only desired models)

# 3. Export models to archives
.\offlineLLM.ps1 export -ModelsFile models.txt -ArchiveDir .\archives

# 4. Copy archives/ to offline machine (via USB/network)

# 5. Import on offline machine
.\offlineLLM.ps1 import -ArchiveDir .\archives

# 6. Verify
ollama list
ollama run llama3.2 "Hello!"
```

### Running Tests

```powershell
# Quick syntax check
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\offlineLLM.ps1),
    [ref]$null, [ref]$null
)

# Functional test with tinyllama
.\offlineLLM.ps1 list-installed
.\offlineLLM.ps1 list-popular -OutputFile test.txt
.\offlineLLM.ps1 export -ModelsFile test.txt -ArchiveDir .\test-archives
.\offlineLLM.ps1 import -ArchiveDir .\test-archives
```

---

## 3. Project Structure

```
offlineLLM/
├── offlineLLM.ps1              # Main Windows script (all-in-one)
├── offlineLLM.sh               # Main Linux script (all-in-one)
├── CLAUDE.md                   # Claude Code instructions
├── README.md                   # User documentation (Russian)
├── config/
│   └── popular-models.txt      # Curated list of popular Ollama models
├── docs/
│   ├── architecture.md         # Technical architecture details
│   ├── usage.md                # Windows usage guide
│   ├── usage-linux.md          # Linux usage guide
│   └── development.md          # Developer guide
└── tasks/
    └── *.md                    # Task specifications
```

### Key Files

| File | Purpose |
|------|---------|
| `offlineLLM.ps1` | Single-file PowerShell utility — all commands in one script |
| `offlineLLM.sh` | Bash equivalent for Linux — same functionality |
| `config/popular-models.txt` | Pre-defined list of popular Ollama models |
| `docs/architecture.md` | Deep dive into OCI manifest format, blob storage, export/import algorithms |

---

## 4. Development Workflow

### Coding Standards

- **Language**: User-facing text in Russian; code comments in English
- **Output**: Error messages to stderr; structured output (tables) to stdout
- **Structure**: Single per platform — easy to copy and deploy
- **Id fileempotency**: Safe to re-run (existing files are skipped by default)
- **Error Handling**: One model's failure doesn't stop processing of others

### Code Organization (PowerShell)

```
offlineLLM.ps1
├── Parameters (param block)
├── Output Helpers (Write-Header, Write-OK, Write-Warn, Write-Fail)
├── Utility Helpers (Get-OllamaModelsDir, Assert-OllamaInstalled, etc.)
├── Ollama Helpers (Find-ManifestPath)
├── Built-in data ($Script:BuiltinPopularModels)
├── Command: list-popular (Get-OnlineModels, Invoke-ListPopular)
├── Command: list-installed (Invoke-ListInstalled)
├── Command: export (Export-SingleModel, Invoke-Export)
├── Command: import (Import-SingleArchive, Invoke-Import)
└── Entry point (switch + try/catch)
```

### Adding New Commands

1. Add value to `[ValidateSet(...)]` parameter `$Command`
2. Write function `Invoke-<CommandName>`
3. Add branch in `switch ($Command)` at the end

### Build & Deployment

No build process — scripts are ready to run. Simply copy to target machine.

---

## 5. Key Concepts

### Ollama Model Storage

Ollama uses content-addressable storage:

```
~/.ollama/models/
├── manifests/
│   └── registry.ollama.ai/
│       └── library/
│           └── <model-name>/
│               └── <tag>           # JSON manifest (OCI Image Format)
└── blobs/
    └── sha256-<hash>               # Binary files (GGUF models, configs)
```

### Manifest Format (OCI Image Manifest v2)

```json
{
  "schemaVersion": 2,
  "config": {
    "digest": "sha256:abc123...",
    "size": 123
  },
  "layers": [
    {
      "mediaType": "application/vnd.ollama.image.model",
      "digest": "sha256:def456...",
      "size": 4000000000
    }
  ]
}
```

### Blob Naming

- Digest: `sha256:abc123...`
- Filename: `sha256-abc123...` (colon replaced with dash)

### Archive Format

Each model = one `.tar` file (no compression):

```
llama3.2-latest.tar
├── manifests/
│   └── registry.ollama.ai/library/llama3.2/latest
└── blobs/
    ├── sha256-<config-hash>
    └── sha256-<model-hash>
```

---

## 6. Common Tasks

### Export Specific Models

```powershell
# Create models file
"llama3.2`nmistral:7b`nqwen2.5-coder:14b" | Out-File my-models.txt

# Export
.\offlineLLM.ps1 export -ModelsFile my-models.txt -ArchiveDir D:\ollama-backup
```

### Import to Custom Directory

```powershell
# Windows
.\offlineLLM.ps1 import -ArchiveDir E:\ollama-models -OllamaDir C:\custom\ollama\models

# Linux
./offlineLLM.sh import -d ./archives -p /custom/ollama/models
```

### Force Overwrite

```powershell
# Export (regenerate archives)
.\offlineLLM.ps1 export -ModelsFile models.txt -Force

# Import (overwrite existing files)
.\offlineLLM.ps1 import -ArchiveDir .\archives -Force
```

### Linux: Restart Ollama After Import

```bash
./offlineLLM.sh import -d ./archives -r
# or manually:
sudo systemctl restart ollama
```

---

## 7. Troubleshooting

### Models Not Appearing After Import

**Windows:**
```powershell
Stop-Service ollama -ErrorAction SilentlyContinue
Start-Service ollama
```

**Linux:**
```bash
sudo systemctl restart ollama
```

### "tar not found" (Windows)

Update Windows to version 1803+ (includes `tar.exe`).

### "jq not found" on Linux

```bash
# RHEL/CentOS/Fedora
sudo dnf install jq

# Ubuntu/Debian
sudo apt install jq

# Alternative: python3 (usually pre-installed)
```

### Permission Denied

- **Windows**: Run PowerShell as Administrator or use `-OllamaDir` flag
- **Linux**: Run as `ollama` user or use `sudo` with `-p` flag

### SELinux Blocking Access (RHEL)

```bash
sudo restorecon -r ~/.ollama/models
```

---

## 8. References

- [Ollama Official Site](https://ollama.com)
- [OCI Image Manifest Specification](https://github.com/opencontainers/image-spec/blob/main/manifest.md)
- [PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [Bash Scripting Guide](https://www.gnu.org/software/bash/manual/)

### Internal Documentation

| Document | Description |
|----------|-------------|
| `docs/architecture.md` | Deep technical architecture |
| `docs/development.md` | Developer guide with debugging tips |
| `docs/usage.md` | Windows usage guide |
| `docs/usage-linux.md` | Linux usage guide |

---

## Notes

- All user-facing output is in Russian
- Each exported model creates its own `.tar` file
- Models.txt comments (lines starting with `#`) are ignored during export
- Model spec format: `name:tag` or just `name` (defaults to `latest`)
- The Linux script requires `chmod +x` before first use

---

*Last updated: 2024. Auto-generated from project analysis.*