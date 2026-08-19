<p align="center">
  <img src="../../assets/i18n/ru/banner.svg" alt="Multi-CLI. Используйте несколько аккаунтов одновременно без переключения." width="760"/>
</p>

<p align="center">Используйте несколько аккаунтов одновременно без переключения.</p>

<p align="center">
  <a href="#supported-ai-tools"><img src="https://img.shields.io/badge/%D0%BF%D0%BE%D0%B4%D0%B4%D0%B5%D1%80%D0%B6%D0%BA%D0%B0-17%20AI%20%D0%B8%D0%BD%D1%81%D1%82%D1%80%D1%83%D0%BC%D0%B5%D0%BD%D1%82%D0%BE%D0%B2-255C60?style=flat-square&labelColor=14101F" alt="17 поддерживаемых AI-инструментов"/></a>
  <a href="../../release/VERSION"><img src="https://img.shields.io/badge/%D0%B2%D0%B5%D1%80%D1%81%D0%B8%D1%8F-v1.0.0-255C60?style=flat-square&labelColor=14101F" alt="Версия v1.0.0"/></a>
  <a href="#install"><img src="https://img.shields.io/badge/%D0%BF%D0%BB%D0%B0%D1%82%D1%84%D0%BE%D1%80%D0%BC%D1%8B-macOS%20%7C%20Linux%20%7C%20Windows-255C60?style=flat-square&labelColor=14101F" alt="macOS, Linux и Windows"/></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/%D0%BB%D0%B8%D1%86%D0%B5%D0%BD%D0%B7%D0%B8%D1%8F-MIT-255C60?style=flat-square&labelColor=14101F" alt="Лицензия MIT"/></a>
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

[Установка](#install) · [Быстрый старт](#quick-start) · [AI-инструменты](#supported-ai-tools) · [Команды](#commands) · [Изоляция](#how-isolation-works) · [Перенос сессий](#move-sessions-between-accounts) · [Устранение неполадок](#troubleshooting) · [Удаление](#uninstall)

<a id="install"></a>

## Установка

### Требования

- macOS или Linux: [Bash 3.2 или новее](https://www.gnu.org/software/bash/)
- Windows: [Windows PowerShell 5.1](https://www.microsoft.com/download/details.aspx?id=54616)
- [jq 1.7.1](https://jqlang.github.io/jq/download/), устанавливается автоматически при отсутствии
- Один из [поддерживаемых AI-инструментов](#supported-ai-tools)

### Установка из исходного кода

Для этого способа требуется [Git](https://git-scm.com/downloads).

```bash
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
./install/install.sh --local
```

Windows PowerShell:

```powershell
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
.\install\install.ps1 -Local
```

<a id="quick-start"></a>

## Быстрый старт

```bash
multi-cli doctor
multi-cli new claude-cli/work
multi-cli claude-cli/work
```

<a id="supported-ai-tools"></a>

## Поддерживаемые AI-инструменты

| AI-инструмент | ID | Платформы | Граница аккаунта |
|---|---|---|---|
| [AGY CLI](../adapters/agy-cli.md) | `agy-cli` | Windows | Пользователь ОС |
| [Antigravity](../adapters/antigravity.md) | `antigravity` | Windows | Пользователь ОС |
| [Claude Code](../adapters/claude-cli.md) | `claude-cli` | Windows, Linux, ключи API в macOS | Наложение файлов |
| [Codex CLI](../adapters/codex.md) | `codex` | Windows, macOS, Linux | Наложение файлов |
| [Codex Desktop](../adapters/codex-gui.md) | `codex-gui` | Windows | Пользователь ОС |
| [Command Code](../adapters/commandcode.md) | `commandcode` | Windows, macOS, Linux | Наложение файлов |
| [GitHub Copilot CLI](../adapters/copilot-cli.md) | `copilot-cli` | Windows, macOS, Linux | Секрет процесса |
| [GitHub Copilot в VS Code](../adapters/copilot-vscode.md) | `copilot-vscode` | Windows | Пользователь ОС |
| [Cursor CLI](../adapters/cursor-cli.md) | `cursor-cli` | Windows, macOS, Linux | Секрет процесса |
| [Cursor Desktop](../adapters/cursor.md) | `cursor` | Windows, macOS, Linux | Изолированный домашний каталог инструмента |
| [Gemini CLI](../adapters/gemini-cli.md) | `gemini-cli` | Windows, macOS, Linux | Наложение файлов |
| [Grok Build CLI](../adapters/grok-cli.md) | `grok-cli` | Windows, macOS, Linux | Секрет процесса |
| [Kimi Code CLI](../adapters/kimi-cli.md) | `kimi-cli` | Windows, macOS, Linux | Секрет процесса |
| [Kiro](../adapters/kiro.md) | `kiro` | Windows, macOS, Linux | Пользователь ОС |
| [OpenCode](../adapters/opencode.md) | `opencode` | Windows, macOS, Linux | Изолированный домашний каталог инструмента |
| [Windsurf](../adapters/windsurf.md) | `windsurf` | Windows, macOS, Linux | Пользователь ОС |
| [Zed](../adapters/zed.md) | `zed` | Windows | Пользователь ОС |

Ограничения платформ описаны в [матрице поддержки](../support-matrix.md). Выполните `multi-cli tools`, чтобы проверить свой компьютер.

<a id="commands"></a>

## Команды

### Профили

| Команда | Действие |
|---|---|
| `multi-cli new <tool>/<name>` | Создать профиль с отдельными учётными данными и общим обычным состоянием |
| `multi-cli new <tool>/<name> --isolated` | Создать профиль с изоляцией всего домашнего каталога, если AI-инструмент это поддерживает; псевдонимы: `--isolate`, `-i` |
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
| Пользователь ОС | Фиксированная идентичность учётных данных продукта | Ничего, если AI-инструмент не разрешает иное |
| Изолированный домашний каталог инструмента | Весь домашний каталог инструмента | Ничего |

Профили используют самую узкую поддерживаемую границу. `--isolated` создаёт отдельный домашний каталог инструмента. Фиксированные учётные данные ОС используют пользователя ОС под управлением Multi-CLI и требуют терминал с повышенными правами в Windows.

AI-инструментам с секретом процесса нужен дополнительный шаг перед запуском:

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work
multi-cli cursor-cli/work
```

Старые профили сохраняют исходный режим изоляции всего домашнего каталога. Предварительно проверьте миграцию командой:

```bash
multi-cli migrate codex/work --dry-run
```

Переносимы только профили, шаблоны и архивы схемы v2. Сначала мигрируйте старые профили.

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
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/install/uninstall.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/install/uninstall.ps1 | iex
```

Данные профилей сохраняются, если вы не подтвердите их удаление.

## Ссылки

- [Матрица поддержки](../support-matrix.md)
- [Политика безопасности](../SECURITY.md)
- [Как внести вклад](../CONTRIBUTING.md)
- [Поддержка](../SUPPORT.md)

## Лицензия

[MIT](../../LICENSE)
