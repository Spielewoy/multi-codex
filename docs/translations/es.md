<p align="center">
  <img src="../../assets/i18n/es/banner.svg" alt="Multi-CLI. Usa varias cuentas a la vez sin cambiar entre ellas." width="760"/>
</p>

<p align="center">Usa varias cuentas a la vez sin cambiar entre ellas.</p>

<p align="center">
  <a href="#supported-ai-tools"><img src="https://img.shields.io/badge/soporte-17%20herramientas%20de%20IA-255C60?style=flat-square&labelColor=14101F" alt="17 herramientas de IA compatibles"/></a>
  <a href="../../release/VERSION"><img src="https://img.shields.io/badge/versi%C3%B3n-v1.0.0-255C60?style=flat-square&labelColor=14101F" alt="Versión v1.0.0"/></a>
  <a href="#install"><img src="https://img.shields.io/badge/plataformas-macOS%20%7C%20Linux%20%7C%20Windows-255C60?style=flat-square&labelColor=14101F" alt="macOS, Linux y Windows"/></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/licencia-MIT-255C60?style=flat-square&labelColor=14101F" alt="Licencia MIT"/></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> |
  <a href="es.md"><b>Español</b></a> |
  <a href="ar.md">العربية</a> |
  <a href="zh.md">中文</a> |
  <a href="ru.md">Русский</a> |
  <a href="he.md">עברית</a>
</p>

## Contenido

[Instalación](#install) · [Inicio rápido](#quick-start) · [Herramientas de IA](#supported-ai-tools) · [Comandos](#commands) · [Aislamiento](#how-isolation-works) · [Mover sesiones](#move-sessions-between-accounts) · [Solución de problemas](#troubleshooting) · [Desinstalación](#uninstall)

<a id="install"></a>

## Instalación

### Requisitos

- macOS o Linux: [Bash 3.2 o posterior](https://www.gnu.org/software/bash/)
- Windows: [Windows PowerShell 5.1](https://www.microsoft.com/download/details.aspx?id=54616)
- [jq 1.7.1](https://jqlang.github.io/jq/download/), se instala automáticamente si no está disponible
- Una de las [herramientas de IA compatibles](#supported-ai-tools)

### Instalar desde el código fuente

Este método requiere [Git](https://git-scm.com/downloads).

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

## Inicio rápido

```bash
multi-cli doctor
multi-cli new claude-cli/work
multi-cli claude-cli/work
```

<a id="supported-ai-tools"></a>

## Herramientas de IA compatibles

| Herramienta de IA | ID | Plataformas | Límite de la cuenta |
|---|---|---|---|
| [AGY CLI](../adapters/agy-cli.md) | `agy-cli` | Windows | Usuario del sistema operativo |
| [Antigravity](../adapters/antigravity.md) | `antigravity` | Windows | Usuario del sistema operativo |
| [Claude Code](../adapters/claude-cli.md) | `claude-cli` | Windows, Linux, claves API en macOS | Superposición de archivos |
| [Codex CLI](../adapters/codex.md) | `codex` | Windows, macOS, Linux | Superposición de archivos |
| [Codex Desktop](../adapters/codex-gui.md) | `codex-gui` | Windows | Usuario del sistema operativo |
| [Command Code](../adapters/commandcode.md) | `commandcode` | Windows, macOS, Linux | Superposición de archivos |
| [GitHub Copilot CLI](../adapters/copilot-cli.md) | `copilot-cli` | Windows, macOS, Linux | Secreto de proceso |
| [GitHub Copilot en VS Code](../adapters/copilot-vscode.md) | `copilot-vscode` | Windows | Usuario del sistema operativo |
| [Cursor CLI](../adapters/cursor-cli.md) | `cursor-cli` | Windows, macOS, Linux | Secreto de proceso |
| [Cursor Desktop](../adapters/cursor.md) | `cursor` | Windows, macOS, Linux | Directorio aislado de la herramienta |
| [Gemini CLI](../adapters/gemini-cli.md) | `gemini-cli` | Windows, macOS, Linux | Superposición de archivos |
| [Grok Build CLI](../adapters/grok-cli.md) | `grok-cli` | Windows, macOS, Linux | Secreto de proceso |
| [Kimi Code CLI](../adapters/kimi-cli.md) | `kimi-cli` | Windows, macOS, Linux | Secreto de proceso |
| [Kiro](../adapters/kiro.md) | `kiro` | Windows, macOS, Linux | Usuario del sistema operativo |
| [OpenCode](../adapters/opencode.md) | `opencode` | Windows, macOS, Linux | Directorio aislado de la herramienta |
| [Windsurf](../adapters/windsurf.md) | `windsurf` | Windows, macOS, Linux | Usuario del sistema operativo |
| [Zed](../adapters/zed.md) | `zed` | Windows | Usuario del sistema operativo |

Consulta los límites de cada plataforma en la [matriz de compatibilidad](../support-matrix.md). Ejecuta `multi-cli tools` para comprobar tu equipo.

<a id="commands"></a>

## Comandos

### Perfiles

| Comando | Acción |
|---|---|
| `multi-cli new <tool>/<name>` | Crear un perfil de cuenta con credenciales separadas y estado normal compartido |
| `multi-cli new <tool>/<name> --isolated` | Crear un perfil con todo el directorio aislado si la herramienta de IA lo admite; alias: `--isolate`, `-i` |
| `multi-cli new <tool>/<name> --from <template>` | Crear un perfil con esquema v2 desde una plantilla con esquema v2 |
| `multi-cli <tool>/<name>` | Iniciar un perfil |
| `multi-cli launch <tool>/<name> [-- args...]` | Iniciar y pasar argumentos a la herramienta |
| `multi-cli list [<tool>]` | Enumerar perfiles |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | Copiar un perfil con esquema v2 |
| `multi-cli rename <tool>/<old> <tool>/<new>` | Cambiar el nombre de un perfil |
| `multi-cli delete <tool>/<name>` | Eliminar un perfil tras confirmar |

### Credenciales y portabilidad

| Comando | Acción |
|---|---|
| `multi-cli auth set <tool>/<profile>` | Guardar un secreto de proceso en el almacén de credenciales del sistema |
| `multi-cli auth status <tool>/<profile>` | Comprobar si existe el secreto |
| `multi-cli auth clear <tool>/<profile>` | Eliminar el secreto |
| `multi-cli continue <tool> <src> <dest> [--dry-run] [--no-merge]` | Copiar el estado de sesión compatible, nunca las credenciales |
| `multi-cli template save <tool>/<profile> <name>` | Guardar una plantilla con esquema v2 sin credenciales |
| `multi-cli template list \| delete <name>` | Enumerar o eliminar plantillas |
| `multi-cli export <tool>/<name> [path]` | Exportar un perfil con esquema v2 |
| `multi-cli import <archive> <tool>/<name>` | Importar un archivo con esquema v2 |

### Mantenimiento

| Comando | Acción |
|---|---|
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | Migrar un perfil antiguo al esquema v2 |
| `multi-cli status` | Mostrar perfiles y tamaños |
| `multi-cli stats` | Mostrar el uso de almacenamiento de los perfiles |
| `multi-cli doctor [--deep]` | Diagnosticar el entorno y, opcionalmente, auditar los entornos de ejecución |
| `multi-cli completion {bash\|zsh\|powershell}` | Mostrar la configuración de autocompletado del shell |
| `multi-cli help` | Mostrar todos los comandos |
| `multi-cli version` | Mostrar la versión instalada |

<a id="how-isolation-works"></a>

## Cómo funciona el aislamiento

| Modo | Qué queda separado | Qué queda compartido |
|---|---|---|
| Superposición de archivos | Archivos de credenciales declarados | Configuración y conversaciones nativas |
| Secreto de proceso | Una credencial inyectada en el proceso secundario | El estado normal de la herramienta |
| Usuario del sistema operativo | La identidad de credenciales fija del producto | Nada, salvo que la herramienta de IA lo permita |
| Directorio aislado de la herramienta | Todo el directorio de la herramienta | Nada |

Los perfiles usan el límite compatible más estrecho. `--isolated` crea un directorio de herramienta separado. Las credenciales fijas del sistema usan un usuario del sistema administrado por Multi-CLI y requieren una terminal con privilegios elevados en Windows.

Las herramientas de IA que usan un secreto de proceso requieren un paso adicional antes de iniciarlas:

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work
multi-cli cursor-cli/work
```

Los perfiles antiguos conservan su aislamiento original de todo el directorio. Previsualiza la migración con:

```bash
multi-cli migrate codex/work --dry-run
```

Solo los perfiles, plantillas y archivos con esquema v2 son portables. Migra primero los perfiles antiguos.

<a id="move-sessions-between-accounts"></a>

## Mover sesiones entre cuentas

Copia el estado compatible de una conversación cuando una cuenta llegue a su límite:

```bash
multi-cli continue codex work personal --dry-run
multi-cli continue codex work personal
multi-cli codex/personal
codex resume
```

`base` representa el directorio normal de la herramienta, por lo que cualquiera de los extremos puede ser un perfil o la instalación predeterminada. Las credenciales nunca se copian. La transferencia de sesiones es compatible con `codex`, `claude-cli`, `gemini-cli` y `commandcode`.

## Alias del shell

Cada perfil recibe un atajo como `claude-cli-work`.

| Plataforma | Ubicación |
|---|---|
| macOS y Linux | `~/MultiCliProfiles/bin/` |
| Windows | `~/MultiCliProfiles/bin/`, además de accesos directos del menú Inicio para perfiles gráficos |

## Configuración

| Variable | Valor predeterminado | Función |
|---|---|---|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | Almacenamiento de perfiles |
| `MULTICLI_OVERRIDE_BINARY` | sin definir | Sustituir la detección del ejecutable para un inicio |
| `MULTICLI_REPO` | repositorio de GitHub | Cambiar el origen de instalación |
| `MULTICLI_INSTALL_DIR` | valor predeterminado de la plataforma | Cambiar el directorio de instalación |

<a id="troubleshooting"></a>

## Solución de problemas

```bash
multi-cli doctor
multi-cli doctor --deep
multi-cli tools
```

Reinicia la terminal si no encuentra `multi-cli` o el alias de un perfil nuevo después de instalar. La [matriz de compatibilidad](../support-matrix.md) incluye los requisitos específicos de cada producto.

<a id="uninstall"></a>

## Desinstalación

macOS y Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/install/uninstall.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/install/uninstall.ps1 | iex
```

Los datos de los perfiles se conservan salvo que confirmes su eliminación.

## Enlaces

- [Matriz de compatibilidad](../support-matrix.md)
- [Política de seguridad](../SECURITY.md)
- [Contribuir](../CONTRIBUTING.md)
- [Soporte](../SUPPORT.md)

## Licencia

[MIT](../../LICENSE)
