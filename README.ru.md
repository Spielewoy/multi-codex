[English](README.md) | [Español](README.es.md) | [العربية](README.ar.md) | [中文](README.zh.md) | **Русский** | [עברית](README.he.md)

# multi-cli

**Запускайте несколько аккаунтных профилей инструментов ИИ-программирования одновременно.**

Профиль schema-v2 изолирует учётные данные и квоту аккаунта, а при безопасной границе разделяет диалоги, настройки и расширения. Если вендор объединяет аутентификацию с сессиями, multi-cli использует отдельного пользователя ОС или режим полного корня `--isolated`. [Матрица поддержки](docs/support-matrix.md) указывает точный режим и требования для каждой платформы.

Существующие профили schema-v1 остаются устаревшими профилями с полным корнем до миграции — см. [Устаревшие профили](#устаревшие-профили).

[![GitHub repository](https://img.shields.io/badge/GitHub-Repository-blue?logo=github)](https://github.com/Spielewoy/multi-cli)
[![GitHub profile](https://img.shields.io/badge/GitHub-Spielewoy-lightgrey?logo=github)](https://github.com/Spielewoy)
[![GitHub stars](https://img.shields.io/github/stars/Spielewoy/multi-cli?style=social)](https://github.com/Spielewoy/multi-cli/stargazers)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#установка)
[![License](https://img.shields.io/badge/license-MIT-green)](#лицензия)

---

## Поддерживаемые инструменты

В репозиторий входят 17 адаптеров. `supported` означает, что multi-cli предоставляет на этой ОС хотя бы один рабочий режим изоляции; `unsupported` означает, что продукт или режим там недоступен. Авторитетный источник — [docs/support-matrix.md](docs/support-matrix.md).

| Инструмент | Тип | Windows | macOS | Linux |
|------|------|---------|-------|-------|
| [Claude Code](claude-cli/) | CLI | supported (file overlay) | supported for API-key profiles only; subscription OAuth is unsupported | supported (file overlay) |
| [OpenAI Codex CLI](codex/) | CLI | supported (file overlay; file credential store mode) | supported | supported |
| [Gemini CLI](gemini-cli/) | CLI | supported (file overlay) | supported | supported |
| [OpenCode](opencode/) | CLI | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) |
| [Command Code](commandcode/) | CLI | supported (file overlay; use `commandcode`, bare `cmd` collides with cmd.exe) | supported | supported |
| [Cursor Desktop](cursor/) | IDE | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) |
| [Cursor CLI](cursor-cli/) | CLI | supported (process token via `multi-cli auth set`) | supported | supported |
| [Antigravity](antigravity/) | IDE | supported (OS-user isolation; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (owned-user GUI/Secret Service session not implemented) |
| [AGY CLI](agy-cli/) | CLI | supported (OS-user isolation; elevated terminal) | unsupported (owned-user Keychain isolation not proven) | unsupported (owned-user Secret Service session not implemented) |
| [Kiro](kiro/) | IDE | supported (OS-user isolation) | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) |
| [Zed](zed/) | IDE | supported (OS-user isolation; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (owned-user GUI/Secret Service session not implemented) |
| [Devin Desktop / Windsurf](windsurf/) | IDE | supported (OS-user isolation; elevated terminal) | supported (`--isolated` whole-root) | supported (`--isolated` whole-root) |
| [GitHub Copilot CLI](copilot-cli/) | CLI | supported (process token via `multi-cli auth set`) | supported | supported |
| [Copilot in VS Code](copilot-vscode/) | IDE | supported (OS-user isolation; elevated terminal) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (owned-user GUI/Secret Service session not implemented) |
| [Kimi Code CLI](kimi-cli/) | CLI | supported (process token via `multi-cli auth set`) | supported | supported |
| [Codex Desktop App](codex-gui/) | GUI | supported (owned Windows user and Store AppX activation) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (no desktop app) |
| [Grok Build CLI](grok-cli/) | CLI/TUI | supported (process token via `multi-cli auth set`) | supported | supported |

У каждого инструмента есть собственная папка в корне репозитория с файлом `adapter.json`, описывающим границу аккаунта, разделяемое обычное состояние и доказательства, необходимые для повышения до статуса «верифицировано».

---

## Установка

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

**Windows** — откройте PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

> После установки **перезапустите терминал**, чтобы изменения PATH вступили в силу.

### Из исходного кода

```bash
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
./scripts/install.sh --local        # macOS/Linux
.\scripts\install.ps1 -Local        # Windows
```

> После установки **перезапустите терминал**, чтобы изменения PATH вступили в силу.

> [jq](https://jqlang.github.io/jq/) **устанавливается автоматически** установщиком на всех платформах — ручная настройка не требуется.

---

## Быстрый старт

```bash
# Create a profile
multi-cli new claude-cli/work

# Launch it
multi-cli launch claude-cli/work

# Or use the shorthand
multi-cli claude-cli/work
```

Каждый профиль получает автоматический псевдоним оболочки:

| Платформа | Расположение |
|----------|----------|
| macOS / Linux | `~/MultiCliProfiles/bin/` (добавьте в `PATH`) |
| Windows | Ярлыки в меню «Пуск» создаются автоматически |

---

## Команды

### Управление профилями

| Команда | Описание |
|---------|-------------|
| `multi-cli new <tool>/<name>` | Создать профиль аккаунта (отдельные учётные данные, общее обычное состояние) |
| `multi-cli new <tool>/<name> --isolated` | Создать профиль полного корня без общего состояния |
| `multi-cli new <tool>/<name> --shared` | Устаревший общий профиль schema-v1; профили schema-v2 уже используют объявленное общее состояние по умолчанию |
| `multi-cli new <tool>/<name> --from <tpl>` | Создать из сохранённого шаблона |
| `multi-cli <tool>/<name>` | Запустить профиль (сокращение) |
| `multi-cli launch <tool>/<name>` | Запустить профиль |
| `multi-cli list [<tool>]` | Показать все профили |
| `multi-cli status` | List profiles with their type and disk size |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | Скопировать существующий профиль |
| `multi-cli rename <tool>/<old> <tool>/<new>` | Переименовать профиль |
| `multi-cli delete <tool>/<name>` | Удалить профиль и все его данные |

### Аутентификация аккаунтов и миграция

| Команда | Описание |
|---------|-------------|
| `multi-cli auth set <tool>/<profile>` | Сохранить процессный секрет профиля в хранилище учётных данных ОС (интерактивный запрос или чтение одной строки из stdin) |
| `multi-cli auth status <tool>/<profile>` | Сообщить, сохранены ли учётные данные для профиля |
| `multi-cli auth clear <tool>/<profile>` | Удалить сохранённые учётные данные |
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | Мигрировать устаревший профиль schema-v1 в schema-v2 |

`auth` применяется только к адаптерам с механизмом `processSecret` (`cursor-cli`, `copilot-cli`, `kimi-cli`, `grok-cli`). Запуск остаётся отключённым, пока учётные данные не сохранены. Про `migrate` см. [Устаревшие профили](#устаревшие-профили).

### Шаблоны

| Команда | Описание |
|---------|-------------|
| `multi-cli template save <tool>/<profile> <name>` | Сохранить профиль как переиспользуемый шаблон |
| `multi-cli template list` | Показать сохранённые шаблоны |
| `multi-cli template delete <name>` | Удалить шаблон |

### Резервное копирование и перенос

| Команда | Описание |
|---------|-------------|
| `multi-cli export <tool>/<name> [path]` | Архивировать профиль в `.tar.gz` (`.zip` в Windows) |
| `multi-cli import <archive> <tool>/<name>` | Восстановить профиль из архива |

### Сессии

| Команда | Описание |
|---------|-------------|
| `multi-cli continue <tool> <src> <dest>` | Скопировать состояние диалога (сессии/транскрипты/историю) из одного профиля в другой — учётные данные никогда не копируются |
| `multi-cli continue <tool> <src> <dest> --no-merge` | Перезаписать файлы назначения вместо сохранения более новых |
| `multi-cli continue <tool> <src> <dest> --dry-run` | Предварительный просмотр того, что будет скопировано, без изменений |

`base` работает как имя профиля с любой стороны и означает настоящий домашний каталог инструмента (`~/.codex`, `~/.claude`, …). Поддерживается для `codex`, `claude-cli`, `gemini-cli` и `commandcode`. См. [Продолжение диалога между аккаунтами](#продолжение-диалога-между-аккаунтами).

### Утилиты

| Команда | Описание |
|---------|-------------|
| `multi-cli tools` | Показать все поддерживаемые инструменты и статус их установки |
| `multi-cli stats` | Показать использование диска по профилям |
| `multi-cli doctor` | Диагностировать окружение |
| `multi-cli completion {bash\|zsh\|powershell}` | Настроить автодополнение оболочки |
| `multi-cli help` | Показать справку |
| `multi-cli version` | Показать версию |

---

## Как работает изоляция

Адаптеры schema-v2 объявляют механизм аккаунта отдельно от обычного состояния:

| Механизм | Как это работает |
|-----------|--------------|
| `fileOverlay` | Учётные данные остаются внутри профиля; объявленное обычное состояние связывается с родным общим домашним каталогом инструмента. |
| `processSecret` | Уникальные для профиля учётные данные с наивысшим приоритетом внедряются только в дочерний процесс. Запуск остаётся отключённым, пока не настроено безопасное хранилище секретов. |
| `osUserCredentialStore` | Uses a multi-cli-owned OS user for tools with a fixed credential identity. Windows requires elevation; macOS/Linux require `sudo`. |
| `inseparable` | Вендор объединяет аутентификацию и обычное состояние; корректный запуск завершается отказом, а ограничение показывается пользователю. |

Профили версии 1 сохраняют прежнее поведение с полным корнем (`env`, `userDataDir`, `redirectHome`, `appdata` и `sandboxUser`) для совместимости. Каждый `<id>/adapter.json` указывает возможности продукта/платформы и требования к доказательствам.

---

<a id="продолжение-диалога-между-аккаунтами"></a>

## Продолжение диалога между аккаунтами

Уперлись в лимит запросов на аккаунте A посреди разговора? Переключитесь на профиль, вошедший в аккаунт B, и продолжите диалог с того места, где он остановился. `multi-cli continue` копирует переносимое состояние диалога — сессии, транскрипты, историю — между профилями. **Учётные данные никогда не копируются.**

```bash
# You were working in codex/work (account A) and got rate-limited.
# codex/personal is logged into account B.
multi-cli continue codex work personal          # copy the conversation state
multi-cli continue codex work personal --dry-run  # preview first, if you like

codex-personal                                  # launch account B's profile
codex resume <session-id>                        # resume the same chat (codex ≥ 0.30)
```

Запустите `codex resume` без аргументов, чтобы открыть интерактивный выбор прошлых сессий — искать id не понадобится. Если он всё же нужен, id сессии — это UUID в имени файла rollout внутри `sessions/YYYY/MM/DD/`.

`base` — допустимое имя профиля с любой стороны; оно указывает на настоящий домашний каталог инструмента (`~/.codex`, `~/.claude`, …), поэтому можно продолжать диалог в установку по умолчанию или из неё.

По умолчанию файлы **объединяются** — более новые файлы в месте назначения сохраняются. Передайте `--no-merge`, чтобы вместо этого перезаписать назначение, или `--dry-run` для предварительного просмотра без изменений.

После копирования возобновите работу внутри профиля назначения собственной командой инструмента:

| Инструмент | Команда возобновления |
|------|----------------|
| codex | `codex resume <session-id>` (≥ 0.30) |
| claude-cli | `claude --resume <session-id>` (запускать из того же каталога проекта) |
| gemini-cli | `gemini --resume` (последняя автосохранённая сессия) или `/chat resume <tag>` для сохранённых контрольных точек |
| commandcode | запуск из того же рабочего каталога |

**Не поддерживается:** `opencode` (сессии и учётные данные находятся в одной общей базе данных SQLite) и `cursor` (чаты хранятся в SQLite с привязкой к пути рабочей области).

> Устаревшие профили schema-v1 по умолчанию заполняются из `base`. Профили аккаунтов schema-v2 уже читают объявленные диалоги и настройки из общего нативного корня, а изолированные профили начинают пустыми. Используйте `multi-cli continue`, чтобы копировать поддерживаемые диалоги в изолированный профиль или из него.

---

## Типы профилей

| Флаг | Значение |
|------|---------|
| *(нет)* | **Общий по умолчанию** — учётные данные раздельны; диалоги и настройки общие, когда адаптер это допускает. |
| `-i`, `--isolate`, `--isolated` | **Изолированный** — весь корень инструмента находится в профиле; ничего не разделяется. |
| `--shared` | Устаревший псевдоним общего режима, если адаптер его поддерживает. |
| `--cli` | **CLI** — запуск только из терминала. |
| `--from <tpl>` | Клонировать из сохранённого шаблона. |

---

## Переменные окружения

| Переменная | По умолчанию | Назначение |
|----------|---------|---------|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | Где хранятся все профили |
| `MULTICLI_OVERRIDE_BINARY` | *(не задано)* | Принудительно задать путь к бинарнику для следующего запуска |
| `MULTICLI_REPO` | *(не задано)* | Git-URL для удалённой установки |
| `MULTICLI_PLATFORM` | *(авто)* | Переопределить определение платформы (`darwin`, `linux`) |

---

## Устаревшие профили

Профили, созданные до schema-v2, — это устаревшие профили с полным корнем: они сохраняют прежнее поведение `env`, `userDataDir`, `redirectHome`, `appdata` и `sandboxUser` для совместимости. Каталог профиля без файла `.profile.json` считается устаревшим.

`multi-cli migrate <tool>/<name>` преобразует устаревший профиль в schema-v2: объявленные учётные данные перемещаются в профиль, а объявленное обычное состояние связывается с общим домашним каталогом инструмента. Используйте `--dry-run`, чтобы просмотреть план перемещения без изменений, и `--prefer-profile`, чтобы заменить конфликтующие общие файлы копией из профиля — целевые учётные данные никогда не перезаписываются. Хранилище профилей и корень общего состояния должны находиться на одном томе, так как миграция использует атомарные перемещения в пределах одного тома.

---

## Диагностика

```bash
multi-cli doctor
```

Проверяет, что хранилище профилей существует, каталог псевдонимов находится в PATH, и что бинарник каждого инструмента обнаружен (или показывает подсказку по установке).

---

## Автодополнение оболочки

```bash
multi-cli completion bash   # or zsh, powershell
```

Следуйте инструкциям, чтобы добавить его в `.zshrc`, `.bashrc` или `$PROFILE` PowerShell.

---

## Удаление

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

Вас спросят, удалить ли данные профилей — ничто не удаляется без подтверждения.

---

## Ссылки

- [Матрица поддержки](docs/support-matrix.md) — статус изоляции по продуктам и ОС, а также критерии верификации
- [Политика безопасности](SECURITY.md)
- [Лицензия](LICENSE)
- [Репозиторий на GitHub](https://github.com/Spielewoy/multi-cli)

---

## Благодарности

- **Автор** — [Spielewoy](https://github.com/Spielewoy)

---

## Лицензия

[MIT](LICENSE)
