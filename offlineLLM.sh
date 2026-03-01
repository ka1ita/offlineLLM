#!/usr/bin/env bash
# OfflineLLM — Экспорт и импорт моделей Ollama для работы без интернета (Linux)
#
# Использование:
#   ./offlineLLM.sh <команда> [параметры]
#
# Команды:
#   list-popular   [-o FILE] [-n N]              Список популярных моделей
#   list-installed                                Установленные модели
#   export         [-m FILE] [-d DIR] [-p DIR] [-f]   Экспорт в .tar архивы
#   import         [-d DIR] [-p DIR] [-f] [-r]   Импорт из .tar архивов

set -uo pipefail

# ─── Цвета ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; GRAY='\033[0;37m'; WHITE='\033[1;37m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; GRAY=''; WHITE=''; NC=''
fi

# ─── Вспомогательные функции вывода ───────────────────────────────────────────
step()   { echo -e "  ${GRAY}$*${NC}"; }
ok()     { echo -e "  ${GREEN}[OK]${NC} $*"; }
warn()   { echo -e "  ${YELLOW}[!!]${NC} $*" >&2; }
fail()   { echo -e "  ${RED}[XX]${NC} $*" >&2; }
info()   { echo -e "  ${WHITE}--> $*${NC}"; }

header() {
    local text="$*"
    local len=${#text}
    echo
    echo -e "  ${CYAN}${text}${NC}"
    printf '  '; printf '%0.s-' $(seq 1 "$len"); echo
}

# ─── Встроенный список популярных моделей ─────────────────────────────────────
builtin_models() {
    cat <<'EOF'
# === Универсальные LLM ===
llama3.3
llama3.2
llama3.2:1b
llama3.1:8b
llama3.1:70b
mistral
mistral-nemo
gemma3:4b
gemma3:12b
gemma2:9b
gemma2:27b
qwen2.5:7b
qwen2.5:14b
qwen2.5:72b
phi4
phi3.5
command-r
solar
neural-chat
wizardlm2
tinyllama

# === Кодирование ===
qwen2.5-coder:7b
qwen2.5-coder:14b
codellama
codellama:34b
deepseek-coder-v2
codegemma
starcoder2

# === Рассуждения (Reasoning) ===
deepseek-r1:7b
deepseek-r1:14b
deepseek-r1:32b
deepseek-r1:70b

# === Мультимодальные ===
llava
llava-phi3
moondream
bakllava

# === Встраивания (Embeddings) ===
nomic-embed-text
mxbai-embed-large
bge-m3
all-minilm
EOF
}

# ─── Значения по умолчанию ────────────────────────────────────────────────────
OUTPUT_FILE="models.txt"
COUNT=50
MODELS_FILE="models.txt"
ARCHIVE_DIR="./archives"
OLLAMA_DIR=""
FORCE=0
RESTART_SERVICE=0

# ─── Вспомогательные функции ──────────────────────────────────────────────────
get_ollama_dir() {
    if [[ -n "$OLLAMA_DIR" ]]; then
        echo "$OLLAMA_DIR"
    elif [[ -n "${OLLAMA_MODELS:-}" ]]; then
        echo "$OLLAMA_MODELS"
    else
        echo "$HOME/.ollama/models"
    fi
}

assert_ollama_installed() {
    if ! command -v ollama &>/dev/null; then
        fail "ollama не найдена в PATH."
        info "Установите Ollama: curl -fsSL https://ollama.com/install.sh | sh"
        exit 1
    fi
}

assert_tar_installed() {
    if ! command -v tar &>/dev/null; then
        fail "tar не найден."
        info "Установите: sudo dnf install tar"
        exit 1
    fi
}

# Принимает путь к файлу манифеста, возвращает дайджесты блобов (config + layers)
parse_manifest_digests() {
    local manifest_file="$1"
    if command -v jq &>/dev/null; then
        jq -r '(.config.digest // empty), (.layers[]?.digest // empty)' \
            "$manifest_file" 2>/dev/null
    elif command -v python3 &>/dev/null; then
        python3 - "$manifest_file" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    m = json.load(f)
d = (m.get('config') or {}).get('digest', '')
if d:
    print(d)
for layer in (m.get('layers') or []):
    d = layer.get('digest', '')
    if d:
        print(d)
PYEOF
    else
        fail "Для экспорта требуется jq или python3 (разбор JSON манифестов)"
        return 1
    fi
}

# Возвращает путь к файлу манифеста для модели name:tag в каталоге models_dir
find_manifest() {
    local models_dir="$1" name="$2" tag="$3"

    # Стандартные пути
    local c1="$models_dir/manifests/registry.ollama.ai/library/$name/$tag"
    local c2="$models_dir/manifests/registry.ollama.ai/$name/$tag"
    [[ -f "$c1" ]] && echo "$c1" && return 0
    [[ -f "$c2" ]] && echo "$c2" && return 0

    # Резервный поиск: ищем файл с именем <tag>, родительский каталог — <name>
    if [[ -d "$models_dir/manifests" ]]; then
        while IFS= read -r mf; do
            local parent
            parent=$(basename "$(dirname "$mf")")
            if [[ "$parent" == "$name" ]]; then
                echo "$mf"
                return 0
            fi
        done < <(find "$models_dir/manifests" -type f -name "$tag" 2>/dev/null)
    fi

    return 1
}

# ─── list-popular ─────────────────────────────────────────────────────────────
do_list_popular() {
    header "Список популярных моделей Ollama"

    local online_models=()
    local source_label="встроенный список"

    if command -v curl &>/dev/null; then
        step "Запрос популярных моделей с ollama.com..."
        local html
        html=$(curl -sf --max-time 15 -A "Mozilla/5.0 OfflineLLM/1.0" \
               "https://ollama.com/search?q=&sort=popular" 2>/dev/null) || true
        if [[ -n "$html" ]]; then
            while IFS= read -r model; do
                [[ -n "$model" ]] && online_models+=("$model")
            done < <(
                echo "$html" \
                | grep -oE 'href="/library/[a-z0-9_.-]+"' \
                | sed 's|href="/library/||; s|"||g' \
                | sort -u \
                | head -n "$COUNT"
            )
        fi
    fi

    if [[ ${#online_models[@]} -gt 0 ]]; then
        ok "Получено ${#online_models[@]} моделей с ollama.com"
        source_label="ollama.com (онлайн)"
    else
        warn "Не удалось получить список онлайн. Используется встроенный список."
    fi

    {
        echo "# Популярные модели Ollama"
        echo "# Сгенерировано: $(date '+%Y-%m-%d %H:%M')"
        echo "# Источник: $source_label"
        echo "#"
        echo "# Отредактируйте файл, оставив нужные модели, затем запустите:"
        echo "#   ./offlineLLM.sh export -m $OUTPUT_FILE -d ./archives"
        echo "#"
        echo "# Формат: model  или  model:tag  (тег 'latest' используется по умолчанию)"
        echo ""

        if [[ ${#online_models[@]} -gt 0 ]]; then
            echo "# === Популярные модели с ollama.com ==="
            printf '%s\n' "${online_models[@]}"
        else
            echo "# === Встроенный список популярных моделей ==="
            builtin_models
        fi

        # Добавляем уже установленные модели
        if command -v ollama &>/dev/null; then
            local installed
            installed=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$') || true
            if [[ -n "$installed" ]]; then
                echo ""
                echo "# === Уже установленные на этой машине ==="
                echo "$installed"
            fi
        fi
    } > "$OUTPUT_FILE"

    local lines
    lines=$(wc -l < "$OUTPUT_FILE")
    ok "Сохранено: $OUTPUT_FILE  ($lines строк)"
    echo ""
    info "Следующий шаг: отредактируйте $OUTPUT_FILE, затем запустите:"
    info "  ./offlineLLM.sh export -m $OUTPUT_FILE -d ./archives"
}

# ─── list-installed ───────────────────────────────────────────────────────────
do_list_installed() {
    header "Установленные модели Ollama"
    assert_ollama_installed
    ollama list
}

# ─── export ───────────────────────────────────────────────────────────────────
export_single_model() {
    local model_spec="$1" models_dir="$2" dest_dir="$3"

    # Разбираем спецификацию модели (name:tag или name)
    local name tag
    if [[ "$model_spec" == *:* ]]; then
        name="${model_spec%%:*}"
        tag="${model_spec#*:}"
    else
        name="$model_spec"
        tag="latest"
    fi

    echo ""
    info "Модель: $name:$tag"

    # Ищем манифест
    local manifest_path
    manifest_path=$(find_manifest "$models_dir" "$name" "$tag") || manifest_path=""

    if [[ -z "$manifest_path" ]]; then
        warn "Модель $name:$tag не найдена локально. Загрузка через Ollama..."
        if ! ollama pull "$name:$tag"; then
            fail "Не удалось загрузить $name:$tag"
            return 1
        fi
        manifest_path=$(find_manifest "$models_dir" "$name" "$tag") || manifest_path=""
    fi

    if [[ -z "$manifest_path" ]]; then
        fail "Манифест не найден для $name:$tag после загрузки"
        return 1
    fi

    step "Манифест: $manifest_path"

    # Получаем дайджесты blob-файлов
    local digests=()
    while IFS= read -r digest; do
        [[ -n "$digest" ]] && digests+=("$digest")
    done < <(parse_manifest_digests "$manifest_path")

    if [[ ${#digests[@]} -eq 0 ]]; then
        fail "Не удалось прочитать дайджесты из манифеста"
        return 1
    fi

    # Создаём временный каталог для сборки архива
    local tmpdir
    tmpdir=$(mktemp -d)

    # Копируем манифест с сохранением относительного пути
    local rel_manifest="${manifest_path#"$models_dir/"}"
    local dest_manifest="$tmpdir/$rel_manifest"
    mkdir -p "$(dirname "$dest_manifest")"
    cp "$manifest_path" "$dest_manifest"

    # Копируем blob-файлы
    mkdir -p "$tmpdir/blobs"
    local total_bytes=0
    local missing=0

    for digest in "${digests[@]}"; do
        local blob_name="${digest//:/-}"
        local blob_src="$models_dir/blobs/$blob_name"

        if [[ ! -f "$blob_src" ]]; then
            fail "Blob не найден: $blob_name"
            missing=1
            continue
        fi

        local blob_size blob_mb
        blob_size=$(stat -c%s "$blob_src")
        total_bytes=$(( total_bytes + blob_size ))
        blob_mb=$(( blob_size / 1048576 ))
        step "  + $blob_name  (${blob_mb} MB)"
        cp "$blob_src" "$tmpdir/blobs/$blob_name"
    done

    if [[ "$missing" -eq 1 ]]; then
        fail "Экспорт $name:$tag прерван из-за отсутствующих blob-файлов"
        rm -rf "$tmpdir"
        return 1
    fi

    # Формируем имя архива (заменяем спецсимволы на дефис)
    local safe_name
    safe_name="${name}-${tag}"
    safe_name="${safe_name//[^a-zA-Z0-9._-]/-}"
    local archive_path="$dest_dir/${safe_name}.tar"

    if [[ -f "$archive_path" && "$FORCE" -eq 0 ]]; then
        warn "Архив уже существует: $archive_path  (используйте -f для перезаписи)"
        rm -rf "$tmpdir"
        return 0
    fi

    local total_gb
    total_gb=$(awk "BEGIN { printf \"%.2f\", $total_bytes / 1073741824 }")
    step "Создание архива: ${safe_name}.tar  (данных ~${total_gb} GB)..."

    if ! tar -cf "$archive_path" -C "$tmpdir" .; then
        fail "tar завершился с ошибкой"
        rm -rf "$tmpdir"
        return 1
    fi

    rm -rf "$tmpdir"

    local archive_mb
    archive_mb=$(( $(stat -c%s "$archive_path") / 1048576 ))
    ok "$name:$tag  -->  ${safe_name}.tar  (${archive_mb} MB)"
    return 0
}

do_export() {
    header "Экспорт моделей Ollama в архивы"
    assert_ollama_installed
    assert_tar_installed

    if [[ ! -f "$MODELS_FILE" ]]; then
        fail "Файл со списком моделей не найден: $MODELS_FILE"
        info "Создайте его командой: ./offlineLLM.sh list-popular -o $MODELS_FILE"
        exit 1
    fi

    local models_dir
    models_dir=$(get_ollama_dir)
    step "Каталог моделей Ollama : $models_dir"

    if [[ ! -d "$models_dir" ]]; then
        fail "Каталог моделей Ollama не найден: $models_dir"
        info "Запустите Ollama и загрузите хотя бы одну модель."
        exit 1
    fi

    mkdir -p "$ARCHIVE_DIR"

    # Читаем файл моделей: пропускаем комментарии и пустые строки
    local models=()
    while IFS= read -r line; do
        line="${line%%#*}"           # убираем inline-комментарии
        line="${line//[[:space:]]/}" # убираем пробелы (имена моделей их не содержат)
        [[ -n "$line" ]] && models+=("$line")
    done < "$MODELS_FILE"

    if [[ ${#models[@]} -eq 0 ]]; then
        fail "Файл '$MODELS_FILE' не содержит моделей (только комментарии или пуст)."
        exit 1
    fi

    step "Моделей для экспорта    : ${#models[@]}"

    local success=0 failed=0

    for model in "${models[@]}"; do
        if export_single_model "$model" "$models_dir" "$ARCHIVE_DIR"; then
            (( success++ )) || true
        else
            (( failed++ )) || true
        fi
    done

    echo ""
    header "Итог экспорта"
    ok "Успешно : $success"
    [[ "$failed" -gt 0 ]] && fail "С ошибками : $failed"
    echo ""
    info "Архивы сохранены в: $ARCHIVE_DIR"
    info "Скопируйте папку '$ARCHIVE_DIR' на офлайн-машину и запустите:"
    info "  ./offlineLLM.sh import -d $ARCHIVE_DIR"

    [[ "$failed" -gt 0 ]] && exit 1
    return 0
}

# ─── import ───────────────────────────────────────────────────────────────────
do_import() {
    header "Импорт моделей Ollama из архивов"
    assert_ollama_installed
    assert_tar_installed

    if [[ ! -d "$ARCHIVE_DIR" ]]; then
        fail "Каталог с архивами не найден: $ARCHIVE_DIR"
        exit 1
    fi

    local archives=()
    mapfile -t archives < <(find "$ARCHIVE_DIR" -maxdepth 1 -name "*.tar" | sort)

    if [[ ${#archives[@]} -eq 0 ]]; then
        fail "В каталоге '$ARCHIVE_DIR' нет .tar архивов."
        exit 1
    fi

    local models_dir
    models_dir=$(get_ollama_dir)
    step "Каталог моделей Ollama : $models_dir"
    step "Найдено архивов        : ${#archives[@]}"

    mkdir -p "$models_dir/blobs" "$models_dir/manifests"

    local success=0 failed=0
    local tmpdir=""

    cleanup() {
        [[ -n "$tmpdir" && -d "$tmpdir" ]] && rm -rf "$tmpdir"
    }
    trap cleanup EXIT

    for archive in "${archives[@]}"; do
        echo ""
        local aname
        aname=$(basename "$archive")
        info "Архив: $aname"

        tmpdir=$(mktemp -d)

        if ! tar -xf "$archive" -C "$tmpdir"; then
            fail "Не удалось распаковать: $aname"
            rm -rf "$tmpdir"; tmpdir=""
            (( failed++ )) || true
            continue
        fi

        # Импорт blob-файлов
        if [[ -d "$tmpdir/blobs" ]]; then
            while IFS= read -r -d '' blob; do
                local bname size_mb dest
                bname=$(basename "$blob")
                size_mb=$(( $(stat -c%s "$blob") / 1048576 ))
                dest="$models_dir/blobs/$bname"

                if [[ -f "$dest" && "$FORCE" -eq 0 ]]; then
                    step "  Blob (существует, пропуск): $bname"
                else
                    cp "$blob" "$dest"
                    step "  Blob: $bname  (${size_mb} MB)"
                fi
            done < <(find "$tmpdir/blobs" -type f -print0)
        fi

        # Импорт манифестов
        if [[ -d "$tmpdir/manifests" ]]; then
            while IFS= read -r -d '' mf; do
                local rel dest
                rel="${mf#"$tmpdir/manifests/"}"
                dest="$models_dir/manifests/$rel"
                mkdir -p "$(dirname "$dest")"
                cp "$mf" "$dest"
                step "  Манифест: $rel"
            done < <(find "$tmpdir/manifests" -type f -print0)
        fi

        rm -rf "$tmpdir"; tmpdir=""
        ok "Импортирован: $(basename "$archive" .tar)"
        (( success++ )) || true
    done

    # Восстановление контекстов SELinux (RHEL/CentOS)
    if command -v restorecon &>/dev/null; then
        step "Восстановление контекстов SELinux..."
        restorecon -r "$models_dir" 2>/dev/null \
            && step "  Контексты SELinux восстановлены" \
            || warn "restorecon завершился с ошибкой — запустите вручную от root"
    fi

    echo ""
    header "Итог импорта"
    ok "Импортировано : $success"
    [[ "$failed" -gt 0 ]] && fail "С ошибками    : $failed"

    echo ""
    info "Проверьте установленные модели:"
    info "  ollama list"

    if [[ "$RESTART_SERVICE" -eq 1 ]]; then
        echo ""
        step "Перезапуск сервиса Ollama..."
        if systemctl restart ollama 2>/dev/null; then
            ok "Сервис Ollama перезапущен"
        elif sudo systemctl restart ollama 2>/dev/null; then
            ok "Сервис Ollama перезапущен (via sudo)"
        else
            warn "Не удалось перезапустить автоматически. Запустите вручную:"
            info "  sudo systemctl restart ollama"
        fi
    else
        echo ""
        info "Если модели не отображаются в 'ollama list', перезапустите сервис:"
        info "  sudo systemctl restart ollama"
    fi

    [[ "$failed" -gt 0 ]] && exit 1
    return 0
}

# ─── Справка ──────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF

OfflineLLM — экспорт и импорт моделей Ollama для работы без интернета (Linux)

Использование: $(basename "$0") <команда> [параметры]

Команды:
  list-popular    Создать файл со списком популярных моделей
  list-installed  Показать установленные модели
  export          Экспортировать модели из файла в .tar архивы
  import          Импортировать .tar архивы в Ollama

Параметры:
  -o FILE   Выходной файл (list-popular)              (по умолчанию: models.txt)
  -n N      Количество моделей (list-popular)         (по умолчанию: 50)
  -m FILE   Файл со списком моделей (export)          (по умолчанию: models.txt)
  -d DIR    Каталог архивов (export/import)           (по умолчанию: ./archives)
  -p DIR    Каталог моделей Ollama (export/import)    (по умолчанию: ~/.ollama/models)
  -f        Перезаписывать существующие файлы
  -r        Перезапустить Ollama после импорта (import)
  -h        Показать эту справку

Примеры:
  $(basename "$0") list-popular -o models.txt
  $(basename "$0") list-installed
  $(basename "$0") export -m models.txt -d ./archives
  $(basename "$0") export -m models.txt -d ./archives -f
  $(basename "$0") import -d /mnt/usb/archives -r
  sudo $(basename "$0") import -d /mnt/usb/archives -p /usr/share/ollama/.ollama/models

Примечания:
  • Для экспорта требуется jq или python3 (разбор JSON-манифестов)
  • Запускайте от того же пользователя, от которого работает Ollama
  • На RHEL с SELinux контексты файлов восстанавливаются через restorecon автоматически

EOF
}

# ─── Точка входа ──────────────────────────────────────────────────────────────
COMMAND="${1:-}"

if [[ -z "$COMMAND" || "$COMMAND" == "-h" || "$COMMAND" == "--help" || "$COMMAND" == "help" ]]; then
    usage
    exit 0
fi

shift

# Разбираем параметры (общие для всех команд)
while getopts ":o:n:m:d:p:frh" opt; do
    case "$opt" in
        o) OUTPUT_FILE="$OPTARG" ;;
        n) COUNT="$OPTARG" ;;
        m) MODELS_FILE="$OPTARG" ;;
        d) ARCHIVE_DIR="$OPTARG" ;;
        p) OLLAMA_DIR="$OPTARG" ;;
        f) FORCE=1 ;;
        r) RESTART_SERVICE=1 ;;
        h) usage; exit 0 ;;
        :) fail "Параметр -${OPTARG} требует аргумент."; usage; exit 1 ;;
        *) fail "Неизвестный параметр: -${OPTARG}"; usage; exit 1 ;;
    esac
done

case "$COMMAND" in
    list-popular)   do_list_popular ;;
    list-installed) do_list_installed ;;
    export)         do_export ;;
    import)         do_import ;;
    *)
        fail "Неизвестная команда: $COMMAND"
        usage
        exit 1
        ;;
esac
