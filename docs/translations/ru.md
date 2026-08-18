<p align="center">
  <img src="../../assets/i18n/ru/banner.svg" alt="Multi-CLI. Используйте несколько аккаунтов одновременно без переключения." width="760"/>
</p>

<p align="center">Используйте несколько аккаунтов одновременно без переключения.</p>

<p align="center">
  <a href="#supported-tools"><img src="https://img.shields.io/badge/support-17%20adapters-255C60?style=flat-square&labelColor=14101F" alt="17 адаптеров"/></a>
  <a href="https://github.com/Spielewoy/multi-cli/releases/latest"><img src="https://img.shields.io/github/v/release/Spielewoy/multi-cli?style=flat-square&label=version&color=255C60&labelColor=14101F" alt="Версия 1.0.0"/></a>
  <a href="#install"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-255C60?style=flat-square&labelColor=14101F" alt="macOS, Linux и Windows"/></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-255C60?style=flat-square&labelColor=14101F" alt="Лицензия MIT"/></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> |
  <a href="es.md">Español</a> |
  <a href="ar.md">العربية</a> |
  <a href="zh.md">中文</a> |
  <a href="ru.md"><b>Русский</b></a> |
  <a href="he.md">עברית</a>
</p>

## Содержание

[Установка](#install) · [Быстрый старт](#quick-start) · [Поддерживаемые инструменты](#supported-tools) · [Команды](#commands) · [Изоляция](#how-isolation-works) · [Перенос сессий](#move-sessions-between-accounts) · [Устранение неполадок](#troubleshooting) · [Удаление](#uninstall)

<a id="install"></a>

## Установка

Используйте установочный скрипт для своей платформы или скачайте готовый архив в [GitHub Releases](https://github.com/Spielewoy/multi-cli/releases).

### macOS и Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

### Windows

Откройте PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

Установщик клонирует или обновит Multi-CLI и при необходимости установит `jq`. Для обновления повторно выполните ту же команду. После установки перезапустите терминал. В macOS и Linux выполните показанную инструкцию для PATH, если она появится.

<details>
<summary><strong>Установка из исходного кода</strong></summary>

```bash
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
./scripts/install.sh --local
```

Windows PowerShell:

```powershell
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
.\scripts\install.ps1 -Local
```

</details>

Требования: Git, подключение к интернету, Bash в macOS или Linux либо PowerShell в Windows. По возможности установщик сам получает необходимый исполняемый файл `jq`.

<a id="quick-start"></a>

## Быстрый старт

```bash
# Проверьте окружение и найдите установленные инструменты
multi-cli doctor
multi-cli tools

# Создайте и запустите профиль
multi-cli new claude-cli/work
multi-cli launch claude-cli/work

# Короткая форма запуска
multi-cli claude-cli/work
```

По умолчанию учётные данные остаются внутри профиля, а поддерживаемые настройки, диалоги, агенты, навыки и плагины доступны совместно. Используйте `--isolated` только для адаптеров, поддерживающих изоляцию всего каталога. Адаптеры с отдельным пользователем ОС отклоняют этот флаг, поскольку перенаправление каталога не изолирует фиксированное хранилище учётных данных ОС.

<a id="supported-tools"></a>

## Поддерживаемые инструменты

| Инструмент | Адаптер | Платформы | Граница аккаунта |
|---|---|---|---|
| AGY CLI | `agy-cli` | Windows | Пользователь ОС |
| Antigravity | `antigravity` | Windows | Пользователь ОС |
| Claude Code | `claude-cli` | Windows, Linux, ключи API в macOS | Наложение файлов |
| Codex CLI | `codex` | Windows, macOS, Linux | Наложение файлов |
| Codex Desktop | `codex-gui` | Windows | Пользователь ОС |
| Command Code | `commandcode` | Windows, macOS, Linux | Наложение файлов |
| GitHub Copilot CLI | `copilot-cli` | Windows, macOS, Linux | Секрет процесса |
| GitHub Copilot в VS Code | `copilot-vscode` | Windows | Пользователь ОС |
| Cursor CLI | `cursor-cli` | Windows, macOS, Linux | Секрет процесса |
| Cursor Desktop | `cursor` | Windows, macOS, Linux | Изолированный домашний каталог инструмента |
| Gemini CLI | `gemini-cli` | Windows, macOS, Linux | Наложение файлов |
| Grok Build CLI | `grok-cli` | Windows, macOS, Linux | Секрет процесса |
| Kimi Code CLI | `kimi-cli` | Windows, macOS, Linux | Секрет процесса |
| Kiro | `kiro` | Windows, macOS, Linux | Пользователь ОС |
| OpenCode | `opencode` | Windows, macOS, Linux | Изолированный домашний каталог инструмента |
| Windsurf | `windsurf` | Windows, macOS, Linux | Пользователь ОС |
| Zed | `zed` | Windows | Пользователь ОС |

Требования платформ и известные ограничения описаны в [матрице поддержки](../support-matrix.md). Выполните `multi-cli tools`, чтобы увидеть доступные на компьютере инструменты.

<a id="commands"></a>

## Команды

### Профили

| Команда | Действие |
|---|---|
| `multi-cli new <tool>/<name>` | Создать профиль с отдельными учётными данными и общим обычным состоянием |
| `multi-cli new <tool>/<name> --isolated` | Создать профиль с изоляцией всего домашнего каталога, если адаптер это поддерживает; псевдонимы: `--isolate`, `-i` |
| `multi-cli new <tool>/<name> --from <template>` | Создать профиль схемы v2 из шаблона схемы v2 |
| `multi-cli <tool>/<name>` | Запустить профиль |
| `multi-cli launch <tool>/<name> [-- args...]` | Запустить инструмент и передать ему аргументы |
| `multi-cli list [<tool>]` | Показать список профилей |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | Скопировать профиль схемы v2 |
| `multi-cli rename <tool>/<old> <tool>/<new>` | Переименовать профиль |
| `multi-cli delete <tool>/<name>` | Удалить профиль после подтверждения |

### Учётные данные и переносимость

| Команда | Действие |
|---|---|
| `multi-cli auth set <tool>/<profile>` | Сохранить секрет процесса в хранилище учётных данных ОС |
| `multi-cli auth status <tool>/<profile>` | Проверить наличие секрета |
| `multi-cli auth clear <tool>/<profile>` | Удалить секрет |
| `multi-cli continue <tool> <src> <dest> [--dry-run] [--no-merge]` | Скопировать поддерживаемое состояние сессии без учётных данных |
| `multi-cli template save <tool>/<profile> <name>` | Сохранить шаблон схемы v2 без учётных данных |
| `multi-cli template list \| delete <name>` | Показать или удалить шаблоны |
| `multi-cli export <tool>/<name> [path]` | Экспортировать профиль схемы v2 |
| `multi-cli import <archive> <tool>/<name>` | Импортировать архив схемы v2 |

### Обслуживание

| Команда | Действие |
|---|---|
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | Перенести устаревший профиль на схему v2 |
| `multi-cli status` | Показать профили и их размеры |
| `multi-cli stats` | Показать использование хранилища профилями |
| `multi-cli doctor [--deep]` | Проверить окружение и при необходимости выполнить аудит сред выполнения |
| `multi-cli completion {bash\|zsh\|powershell}` | Вывести настройки автодополнения оболочки |
| `multi-cli help` | Показать все команды |
| `multi-cli version` | Показать установленную версию |

<a id="how-isolation-works"></a>

## Как работает изоляция

| Режим | Что хранится отдельно | Что остаётся общим |
|---|---|---|
| Наложение файлов | Заданные файлы учётных данных | Обычные настройки и диалоги инструмента |
| Секрет процесса | Одни учётные данные, переданные дочернему процессу | Обычное состояние инструмента |
| Пользователь ОС | Фиксированная идентичность учётных данных продукта | Ничего, если адаптер не указывает иное |
| Изолированный домашний каталог инструмента | Весь домашний каталог инструмента | Ничего |

Профили аккаунтов используют самую узкую безопасную границу. `--isolated` создаёт отдельный домашний каталог инструмента и ничего не разделяет, но работает только с адаптерами, поддерживающими изоляцию всего каталога. Адаптеры с отдельным пользователем ОС отклоняют этот флаг, поскольку перенаправление каталога не изолирует фиксированное хранилище учётных данных. Продукты с такой идентичностью используют пользователя ОС под управлением Multi-CLI; в Windows требуется терминал с повышенными правами.

Адаптерам с секретом процесса нужен дополнительный шаг перед запуском:

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work
multi-cli cursor-cli/work
```

Профили из предыдущих версий Multi-CLI сохраняют исходный режим изоляции всего домашнего каталога. Предварительно проверьте миграцию командой:

```bash
multi-cli migrate codex/work --dry-run
```

Переносимы только профили, шаблоны и архивы схемы v2. Сначала мигрируйте исходный устаревший профиль, а затем клонируйте его или создайте новый шаблон либо экспорт.

<a id="move-sessions-between-accounts"></a>

## Перенос сессий между аккаунтами

Скопируйте поддерживаемое состояние диалога, когда аккаунт достигнет лимита:

```bash
multi-cli continue codex work personal --dry-run
multi-cli continue codex work personal
multi-cli codex/personal
codex resume
```

`base` обозначает обычный домашний каталог инструмента, поэтому на любой стороне может быть профиль или стандартная установка. Учётные данные никогда не копируются. Перенос сессий поддерживают `codex`, `claude-cli`, `gemini-cli` и `commandcode`.

## Псевдонимы оболочки

Каждый профиль получает короткую команду, например `claude-cli-work`.

| Платформа | Расположение |
|---|---|
| macOS и Linux | `~/MultiCliProfiles/bin/` |
| Windows | `~/MultiCliProfiles/bin/`, а для профилей с графическим интерфейсом также ярлыки меню Пуск |

## Настройка

| Переменная | Значение по умолчанию | Назначение |
|---|---|---|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | Хранилище профилей |
| `MULTICLI_OVERRIDE_BINARY` | не задано | Переопределить найденный исполняемый файл для одного запуска |
| `MULTICLI_REPO` | репозиторий GitHub | Переопределить источник установки |
| `MULTICLI_INSTALL_DIR` | системное значение по умолчанию | Переопределить каталог установки |

<a id="troubleshooting"></a>

## Устранение неполадок

```bash
multi-cli doctor
multi-cli doctor --deep
multi-cli tools
```

Если после установки команда `multi-cli` или псевдоним нового профиля не найдены, перезапустите терминал. Требования отдельных продуктов приведены в [матрице поддержки](../support-matrix.md).

<a id="uninstall"></a>

## Удаление

macOS и Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

Данные профилей сохраняются, если вы не подтвердите их удаление.

## Ссылки

- [Матрица поддержки](../support-matrix.md)
- [Политика безопасности](../SECURITY.md)
- [Как внести вклад](../CONTRIBUTING.md)
- [Поддержка](../SUPPORT.md)
- [Релизы GitHub](https://github.com/Spielewoy/multi-cli/releases)

## Лицензия

[MIT](../../LICENSE)
