# OfflineLLM — Claude Code Instructions

## Project Overview

Cross-platform utility for exporting and importing Ollama AI models between
internet-connected and air-gapped (offline) machines.

## Tech Stack

- **Windows**: PowerShell 5.1+ (no external dependencies required)
- **Linux**: Bash 4.0+, requires `jq` or `python3` for export (JSON parsing)
- **Archive format**: `.tar` (Windows: `tar.exe` Win10 1803+, fallback Compress-Archive)
- **Ollama API**: direct file access to `~/.ollama/models/` directory

## Project Structure

```
offlineLLM/
├── CLAUDE.md                   # This file — instructions for Claude Code
├── README.md                   # User-facing documentation (Russian)
├── offlineLLM.ps1              # Main Windows script — all functionality
├── offlineLLM.sh               # Main Linux script — all functionality
├── config/
│   └── popular-models.txt      # Curated list of popular Ollama models
├── docs/
│   ├── architecture.md         # Technical architecture
│   ├── usage.md                # Usage guide with examples (Windows)
│   ├── linux-import.md         # Linux import guide (Red Hat / RHEL)
│   └── development.md          # Developer guide
└── tasks/
    ├── 1-init.md               # Original task specification
    └── 2-migrate-to-zip.md     # Linux import task specification
```

## Key Commands

### Windows (offlineLLM.ps1)

```powershell
.\offlineLLM.ps1 list-popular   [-OutputFile models.txt] [-Count 50]
.\offlineLLM.ps1 list-installed
.\offlineLLM.ps1 export         [-ModelsFile models.txt] [-ArchiveDir .\archives] [-Force]
.\offlineLLM.ps1 import         [-ArchiveDir .\archives] [-OllamaDir <path>] [-Force]
```

### Linux (offlineLLM.sh)

```bash
chmod +x offlineLLM.sh
./offlineLLM.sh list-popular   [-o models.txt] [-n 50]
./offlineLLM.sh list-installed
./offlineLLM.sh export         [-m models.txt] [-d ./archives] [-p ollama_dir] [-f]
./offlineLLM.sh import         [-d ./archives] [-p ollama_dir] [-f] [-r]
```

| Flag | Meaning |
|------|---------|
| `-o FILE` | Output file for list-popular (default: `models.txt`) |
| `-n N` | Model count for list-popular (default: `50`) |
| `-m FILE` | Models list file for export (default: `models.txt`) |
| `-d DIR` | Archive directory for export/import (default: `./archives`) |
| `-p DIR` | Ollama models dir (default: `$OLLAMA_MODELS` or `~/.ollama/models`) |
| `-f` | Force overwrite existing files |
| `-r` | Restart Ollama service after import (`systemctl restart ollama`) |

## Ollama Model Storage

Ollama stores models in `$env:USERPROFILE\.ollama\models\` (or `$env:OLLAMA_MODELS`):

```
~/.ollama/models/
├── manifests/
│   └── registry.ollama.ai/
│       └── library/
│           └── <model-name>/
│               └── <tag>       # JSON manifest (OCI image format)
└── blobs/
    └── sha256-<hash>           # Binary blob files (GGUF models, configs, etc.)
```

Each manifest is an OCI image manifest JSON referencing config and layer blobs by digest.
Blob filenames use a dash instead of colon: `sha256:abc...` → `sha256-abc...`.

## Archive Format

Archives are `.tar` files mirroring Ollama's directory structure:

```
model-name-tag.tar
├── manifests/
│   └── registry.ollama.ai/library/<name>/<tag>
└── blobs/
    ├── sha256-<config-hash>
    └── sha256-<layer-hash>...
```

## Development Conventions

- All user-facing text is in Russian
- Error messages go to stderr; structured output (tables) to stdout
- Use `Write-OK`, `Write-Warn`, `Write-Fail` helpers for colored output
- Every exported model gets its own `.tar` file — one model = one archive
- Comments in models.txt start with `#` and are ignored during export
- Model spec format: `name:tag` or just `name` (defaults to `latest`)

## Known Limitations

- `tar.exe` required for models with blobs > 2GB (available Windows 10 1803+)
- Custom registry models (non `registry.ollama.ai/library/`) may need manual path adjustment
- Very large models (70B+) may take significant time and disk space during export

## Testing

```powershell
# Quick smoke test — list installed models
.\offlineLLM.ps1 list-installed

# Generate popular models list
.\offlineLLM.ps1 list-popular -OutputFile test-models.txt

# Export a small model (tinyllama ~600MB)
echo "tinyllama" > test-export.txt
.\offlineLLM.ps1 export -ModelsFile test-export.txt -ArchiveDir .\test-archives

# Import on same or different machine
.\offlineLLM.ps1 import -ArchiveDir .\test-archives
```
