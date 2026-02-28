# Импорт моделей Ollama на Linux (Red Hat / RHEL)

Скрипт `import-linux.sh` импортирует `.tar`-архивы, созданные командой
`offlineLLM.ps1 export` на Windows, в Ollama на Linux-сервере.

## Требования

- Red Hat Enterprise Linux 8/9 (или CentOS Stream, Fedora, Rocky Linux, AlmaLinux)
- [Ollama](https://ollama.com/download) установлена
- `bash` 4.0+, `tar` (присутствуют по умолчанию)
- Доступ к файловой системе каталога моделей Ollama

## Установка

```bash
# Скопируйте скрипт на сервер (вместе с архивами)
scp import-linux.sh user@server:/home/user/
scp -r archives/    user@server:/home/user/

# Сделайте скрипт исполняемым
chmod +x import-linux.sh
```

## Использование

```bash
./import-linux.sh [ОПЦИИ]
```

| Опция | По умолчанию | Описание |
|-------|--------------|----------|
| `-d DIR` | `./archives` | Каталог с `.tar`-архивами |
| `-o DIR` | `$OLLAMA_MODELS` или `~/.ollama/models` | Каталог моделей Ollama |
| `-f` | — | Перезаписать существующие файлы |
| `-r` | — | Перезапустить службу Ollama после импорта |
| `-h` | — | Показать справку |

## Примеры

```bash
# Базовый импорт из ./archives
./import-linux.sh

# Импорт с USB-накопителя
./import-linux.sh -d /mnt/usb/archives

# Импорт и перезапуск службы
./import-linux.sh -d /mnt/usb/archives -r

# Принудительная перезапись + перезапуск
./import-linux.sh -d /mnt/usb/archives -f -r

# Когда Ollama запущена от другого пользователя (например, системная служба)
sudo ./import-linux.sh -d /mnt/usb/archives -o /usr/share/ollama/.ollama/models -r
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
scp import-linux.sh user@linux-server:/home/user/

# Через USB (если нет сети)
# Скопируйте вручную, затем смонтируйте:
sudo mount /dev/sdb1 /mnt/usb
```

### На Linux-сервере

```bash
chmod +x import-linux.sh
./import-linux.sh -d ./archives -r

# Проверка
ollama list
ollama run llama3.2 "Hello!"
```

## Определение каталога моделей

Скрипт ищет каталог в следующем порядке:

1. Флаг `-o DIR` (явное указание)
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

На RHEL с включённым SELinux скрипт автоматически запускает `restorecon`:

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
# или
sudo ./import-linux.sh -o /usr/share/ollama/.ollama/models
```

### SELinux: Permission denied

```bash
sudo restorecon -rv ~/.ollama/
# При необходимости:
sudo chcon -Rt svirt_sandbox_file_t ~/.ollama/models/
```

### tar: error opening archive / file not found

Убедитесь, что архивы сформированы скриптом `offlineLLM.ps1` (формат `.tar`, не `.zip`):
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
