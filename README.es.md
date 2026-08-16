[English](README.md) | **Español** | [العربية](README.ar.md) | [中文](README.zh.md) | [Русский](README.ru.md) | [עברית](README.he.md)

# multi-cli

**Ejecuta varios perfiles de cuenta de herramientas de programación con IA de forma simultánea.**

Un perfil schema-v2 aísla la credencial y la cuota de la cuenta mientras comparte las conversaciones, la configuración y las extensiones cuando existe un límite seguro. Si el proveedor combina autenticación y sesiones, usa un usuario del sistema operativo o `--isolated` para un perfil de raíz completa. La [matriz de compatibilidad](docs/support-matrix.md) indica el modo exacto y los requisitos de cada plataforma.

Los perfiles schema-v1 existentes siguen siendo perfiles heredados de raíz completa hasta que se migren — consulta [Perfiles heredados](#perfiles-heredados).

[![GitHub repository](https://img.shields.io/badge/GitHub-Repository-blue?logo=github)](https://github.com/Spielewoy/multi-cli)
[![GitHub profile](https://img.shields.io/badge/GitHub-Spielewoy-lightgrey?logo=github)](https://github.com/Spielewoy)
[![GitHub stars](https://img.shields.io/github/stars/Spielewoy/multi-cli?style=social)](https://github.com/Spielewoy/multi-cli/stargazers)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#instalación)
[![License](https://img.shields.io/badge/license-MIT-green)](#licencia)

---

## Herramientas compatibles

Este repositorio incluye 17 adaptadores. `supported` significa que multi-cli ofrece al menos un modo de aislamiento funcional en ese sistema; `experimental` significa que la implementación está disponible, pero aún requiere la verificación indicada en un sistema real; `unsupported` significa que el producto o el modo no está disponible allí. La fuente autorizada es [docs/support-matrix.md](docs/support-matrix.md).

| Herramienta | Tipo | Windows | macOS | Linux |
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
| [Codex Desktop App](codex-gui/) | GUI | experimental (secondary-user AppX launch with owner and session checks; real Windows E2E required) | unsupported (owned-user GUI/Keychain session not proven) | unsupported (no desktop app) |
| [Grok Build CLI](grok-cli/) | CLI/TUI | supported (process token via `multi-cli auth set`) | supported | supported |

Cada herramienta tiene su propia carpeta en la raíz del repositorio con un `adapter.json` que describe el límite de la cuenta, el estado normal compartido y la evidencia necesaria para ser promovido a verificado.

---

## Instalación

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

**Windows** — abre PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

> Después de la instalación, **reinicia tu terminal** para que los cambios en el PATH surtan efecto.

### Desde el código fuente

```bash
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
./scripts/install.sh --local        # macOS/Linux
.\scripts\install.ps1 -Local        # Windows
```

> Después de la instalación, **reinicia tu terminal** para que los cambios en el PATH surtan efecto.

> [jq](https://jqlang.github.io/jq/) se **instala automáticamente** con el instalador en todas las plataformas — no se requiere configuración manual.

---

## Inicio rápido

```bash
# Create a profile
multi-cli new claude-cli/work

# Launch it
multi-cli launch claude-cli/work

# Or use the shorthand
multi-cli claude-cli/work
```

Cada perfil obtiene un alias de shell automático:

| Plataforma | Ubicación |
|----------|----------|
| macOS / Linux | `~/MultiCliProfiles/bin/` (añadir al `PATH`) |
| Windows | Accesos directos del menú Inicio creados automáticamente |

---

## Comandos

### Gestión de perfiles

| Comando | Descripción |
|---------|-------------|
| `multi-cli new <tool>/<name>` | Crear un perfil de cuenta (credenciales separadas; estado normal compartido) |
| `multi-cli new <tool>/<name> --isolated` | Crear un perfil de raíz completa sin estado compartido |
| `multi-cli new <tool>/<name> --shared` | Perfil compartido heredado de schema-v1; los perfiles schema-v2 ya comparten por defecto el estado normal declarado |
| `multi-cli new <tool>/<name> --from <tpl>` | Crear a partir de una plantilla guardada |
| `multi-cli <tool>/<name>` | Lanzar un perfil (abreviatura) |
| `multi-cli launch <tool>/<name>` | Lanzar un perfil |
| `multi-cli list [<tool>]` | Listar todos los perfiles |
| `multi-cli status` | List profiles with their type and disk size |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | Copiar un perfil existente |
| `multi-cli rename <tool>/<old> <tool>/<new>` | Renombrar un perfil |
| `multi-cli delete <tool>/<name>` | Eliminar un perfil y todos sus datos |

### Autenticación de cuentas y migración

| Comando | Descripción |
|---------|-------------|
| `multi-cli auth set <tool>/<profile>` | Guardar la credencial de secreto de proceso del perfil en el almacén de credenciales del sistema operativo (pregunta interactivamente o lee una línea desde stdin) |
| `multi-cli auth status <tool>/<profile>` | Indicar si hay una credencial guardada para el perfil |
| `multi-cli auth clear <tool>/<profile>` | Eliminar la credencial guardada |
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | Migrar un perfil heredado schema-v1 a schema-v2 |

`auth` solo se aplica a los adaptadores que usan el mecanismo `processSecret` (`cursor-cli`, `copilot-cli`, `kimi-cli`, `grok-cli`). El lanzamiento permanece deshabilitado hasta que se guarde una credencial. Consulta [Perfiles heredados](#perfiles-heredados) para `migrate`.

### Plantillas

| Comando | Descripción |
|---------|-------------|
| `multi-cli template save <tool>/<profile> <name>` | Guardar un perfil como plantilla reutilizable |
| `multi-cli template list` | Listar las plantillas guardadas |
| `multi-cli template delete <name>` | Eliminar una plantilla |

### Copia de seguridad y transferencia

| Comando | Descripción |
|---------|-------------|
| `multi-cli export <tool>/<name> [path]` | Archivar un perfil en `.tar.gz` (`.zip` en Windows) |
| `multi-cli import <archive> <tool>/<name>` | Restaurar un perfil desde un archivo |

### Sesiones

| Comando | Descripción |
|---------|-------------|
| `multi-cli continue <tool> <src> <dest>` | Copiar el estado de la conversación (sesiones/transcripciones/historial) de un perfil a otro — nunca las credenciales |
| `multi-cli continue <tool> <src> <dest> --no-merge` | Sobrescribir los archivos de destino en lugar de conservar los más recientes |
| `multi-cli continue <tool> <src> <dest> --dry-run` | Previsualizar lo que se copiaría, sin cambiar nada |

`base` funciona como nombre de perfil en cualquiera de los extremos y significa el directorio home real de la herramienta (`~/.codex`, `~/.claude`, …). Compatible con `codex`, `claude-cli`, `gemini-cli` y `commandcode`. Consulta [Continuar un chat entre cuentas](#continuar-un-chat-entre-cuentas).

### Utilidades

| Comando | Descripción |
|---------|-------------|
| `multi-cli tools` | Listar todas las herramientas compatibles y su estado de instalación |
| `multi-cli stats` | Mostrar el uso de disco por perfil |
| `multi-cli doctor` | Diagnosticar tu entorno |
| `multi-cli completion {bash\|zsh\|powershell}` | Configurar el autocompletado del shell |
| `multi-cli help` | Mostrar ayuda |
| `multi-cli version` | Mostrar la versión |

---

## Cómo funciona el aislamiento

Los adaptadores schema-v2 declaran un mecanismo de cuenta separado del estado normal:

| Mecanismo | Cómo funciona |
|-----------|--------------|
| `fileOverlay` | Las credenciales permanecen dentro del perfil; el estado normal declarado enlaza con el home compartido nativo de la herramienta. |
| `processSecret` | Una credencial por perfil, de máxima precedencia, se inyecta únicamente en el proceso hijo. El lanzamiento permanece deshabilitado hasta que se configure un almacenamiento seguro de secretos. |
| `osUserCredentialStore` | Las identidades fijas del llavero se separan con un usuario del sistema operativo propiedad de multi-cli. Permanece deshabilitado hasta que se verifiquen la propiedad y la limpieza. |
| `inseparable` | El proveedor combina la autenticación y el estado normal; el lanzamiento conforme falla de forma cerrada y se muestra la limitación. |

Los perfiles de la versión 1 conservan el comportamiento anterior de raíz completa (`env`, `userDataDir`, `redirectHome`, `appdata` y `sandboxUser`) por compatibilidad. Cada `<id>/adapter.json` indica las capacidades por producto/plataforma y los requisitos de evidencia.

---

<a id="continuar-un-chat-entre-cuentas"></a>

## Continuar un chat entre cuentas

¿Alcanzaste un límite de velocidad en la cuenta A a mitad de una conversación? Cambia a un perfil con sesión iniciada en la cuenta B y retoma el chat donde se quedó. `multi-cli continue` copia el estado portable de la conversación — sesiones, transcripciones, historial — entre perfiles. **Las credenciales nunca se copian.**

```bash
# You were working in codex/work (account A) and got rate-limited.
# codex/personal is logged into account B.
multi-cli continue codex work personal          # copy the conversation state
multi-cli continue codex work personal --dry-run  # preview first, if you like

codex-personal                                  # launch account B's profile
codex resume <session-id>                        # resume the same chat (codex ≥ 0.30)
```

Ejecuta `codex resume` sin argumentos para abrir un selector interactivo de sesiones anteriores, así nunca tendrás que buscar un id. Si lo necesitas, el id de sesión es el UUID del nombre de archivo de rollout bajo `sessions/YYYY/MM/DD/`.

`base` es un nombre de perfil válido en cualquiera de los extremos y se refiere al directorio home real de la herramienta (`~/.codex`, `~/.claude`, …), por lo que puedes continuar hacia o desde tu instalación predeterminada.

Por defecto, los archivos se **fusionan** — se conservan los archivos más recientes del destino. Pasa `--no-merge` para sobrescribir el destino, o `--dry-run` para previsualizar sin cambiar nada.

Después de copiar, reanuda dentro del perfil de destino con el comando propio de la herramienta:

| Herramienta | Comando de reanudación |
|------|----------------|
| codex | `codex resume <session-id>` (≥ 0.30) |
| claude-cli | `claude --resume <session-id>` (ejecutar desde el mismo directorio de proyecto) |
| gemini-cli | `gemini --resume` (última sesión guardada automáticamente) o `/chat resume <tag>` para puntos de control guardados |
| commandcode | lanzar desde el mismo directorio de trabajo |

**No compatible:** `opencode` (las sesiones y las credenciales viven en una única base de datos SQLite compartida) y `cursor` (los chats se almacenan en SQLite indexados por la ruta del espacio de trabajo).

> Los perfiles heredados de esquema v1 se siembran desde `base` por defecto. Los perfiles de cuenta de esquema v2 ya leen las conversaciones y la configuración declaradas desde la raíz nativa compartida; los perfiles aislados empiezan vacíos. Usa `multi-cli continue` para copiar conversaciones compatibles hacia o desde un perfil aislado.

---

## Tipos de perfil

| Opción | Significado |
|------|---------|
| *(ninguno)* | **Compartido por defecto** — credenciales separadas; conversaciones y configuración compartidas cuando el adaptador lo permite. |
| `-i`, `--isolate`, `--isolated` | **Aislado** — toda la raíz de la herramienta vive dentro del perfil; no se comparte nada. |
| `--shared` | Alias heredado para el modo compartido cuando el adaptador lo admite. |
| `--cli` | **CLI** — marca el perfil para lanzamiento solo en terminal. |
| `--from <tpl>` | Clonar desde una plantilla guardada. |

---

## Variables de entorno

| Variable | Valor por defecto | Propósito |
|----------|---------|---------|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | Dónde se almacenan todos los perfiles |
| `MULTICLI_OVERRIDE_BINARY` | *(sin definir)* | Forzar una ruta de binario específica para el próximo lanzamiento |
| `MULTICLI_REPO` | *(sin definir)* | URL de Git para la instalación remota |
| `MULTICLI_PLATFORM` | *(automático)* | Anular la detección de plataforma (`darwin`, `linux`) |

---

## Perfiles heredados

Los perfiles creados antes de schema-v2 son perfiles heredados de raíz completa: conservan el comportamiento anterior de `env`, `userDataDir`, `redirectHome`, `appdata` y `sandboxUser` por compatibilidad. Un directorio de perfil sin archivo `.profile.json` se trata como heredado.

`multi-cli migrate <tool>/<name>` convierte un perfil heredado a schema-v2: las credenciales declaradas se mueven al perfil y el estado normal declarado se enlaza con el home compartido de la herramienta. Usa `--dry-run` para previsualizar el plan de movimiento sin cambiar nada, y `--prefer-profile` para reemplazar los archivos compartidos en conflicto con la copia del perfil — los destinos de credenciales nunca se sobrescriben. El almacenamiento de perfiles y la raíz de estado compartido deben estar en el mismo volumen, porque la migración usa movimientos atómicos dentro del mismo volumen.

---

## Diagnóstico

```bash
multi-cli doctor
```

Comprueba que el almacenamiento de perfiles existe, que el directorio de alias está en el PATH y que el binario de cada herramienta se detecta (o muestra una sugerencia de instalación).

---

## Autocompletado del shell

```bash
multi-cli completion bash   # or zsh, powershell
```

Sigue las instrucciones para añadirlo a tu `.zshrc`, `.bashrc` o `$PROFILE` de PowerShell.

---

## Desinstalación

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

Se te preguntará si deseas eliminar los datos de tus perfiles — nada se borra sin confirmación.

---

## Enlaces

- [Matriz de compatibilidad](docs/support-matrix.md) — estado de aislamiento por producto y por SO, y los criterios de verificación
- [Política de seguridad](SECURITY.md)
- [Licencia](LICENSE)
- [Repositorio en GitHub](https://github.com/Spielewoy/multi-cli)

---

## Créditos

- **Creador** — [Spielewoy](https://github.com/Spielewoy)

---

## Licencia

[MIT](LICENSE)
