<p align="center">
  <img src="../../assets/i18n/es/banner.svg" alt="Multi-CLI. Usa varias cuentas a la vez sin cambiar entre ellas." width="760"/>
</p>

<p align="center">Usa varias cuentas a la vez sin cambiar entre ellas.</p>

<p align="center">
  <a href="#supported-tools"><img src="https://img.shields.io/badge/support-17%20adapters-255C60?style=flat-square&labelColor=14101F" alt="17 adaptadores"/></a>
  <a href="https://github.com/Spielewoy/multi-cli/releases/latest"><img src="https://img.shields.io/github/v/release/Spielewoy/multi-cli?style=flat-square&label=version&color=255C60&labelColor=14101F" alt="Versión 1.0.0"/></a>
  <a href="#install"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-255C60?style=flat-square&labelColor=14101F" alt="macOS, Linux y Windows"/></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-255C60?style=flat-square&labelColor=14101F" alt="Licencia MIT"/></a>
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

[Instalación](#install) · [Inicio rápido](#quick-start) · [Herramientas compatibles](#supported-tools) · [Comandos](#commands) · [Aislamiento](#how-isolation-works) · [Mover sesiones](#move-sessions-between-accounts) · [Solución de problemas](#troubleshooting) · [Desinstalación](#uninstall)

<a id="install"></a>

## Instalación

Usa el script de instalación para tu plataforma o descarga un paquete desde [GitHub Releases](https://github.com/Spielewoy/multi-cli/releases).

### macOS y Linux

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

### Windows

Abre PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

El instalador clona o actualiza Multi-CLI e instala `jq` si hace falta. Vuelve a ejecutar el mismo comando para actualizar. Reinicia la terminal después de instalar. En macOS y Linux, sigue la instrucción sobre el PATH si aparece.

<details>
<summary><strong>Instalar desde el código fuente</strong></summary>

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

Requisitos: Git, conexión a internet, Bash en macOS o Linux, o PowerShell en Windows. El instalador obtiene el binario `jq` necesario automáticamente cuando es posible.

<a id="quick-start"></a>

## Inicio rápido

```bash
# Comprueba el entorno y detecta las herramientas instaladas
multi-cli doctor
multi-cli tools

# Crea e inicia un perfil
multi-cli new claude-cli/work
multi-cli launch claude-cli/work

# Forma abreviada
multi-cli claude-cli/work
```

De forma predeterminada, las credenciales quedan dentro del perfil mientras se comparten los ajustes, conversaciones, agentes, habilidades y complementos compatibles. Añade `--isolated` cuando debas separar todo el directorio de la herramienta.

<a id="supported-tools"></a>

## Herramientas compatibles

| Herramienta | Adaptador | Plataformas | Límite de la cuenta |
|---|---|---|---|
| AGY CLI | `agy-cli` | Windows | Usuario del sistema operativo |
| Antigravity | `antigravity` | Windows | Usuario del sistema operativo |
| Claude Code | `claude-cli` | Windows, Linux, claves API en macOS | Superposición de archivos |
| Codex CLI | `codex` | Windows, macOS, Linux | Superposición de archivos |
| Codex Desktop | `codex-gui` | Windows | Usuario del sistema operativo |
| Command Code | `commandcode` | Windows, macOS, Linux | Superposición de archivos |
| GitHub Copilot CLI | `copilot-cli` | Windows, macOS, Linux | Secreto de proceso |
| GitHub Copilot en VS Code | `copilot-vscode` | Windows | Usuario del sistema operativo |
| Cursor CLI | `cursor-cli` | Windows, macOS, Linux | Secreto de proceso |
| Cursor Desktop | `cursor` | Windows, macOS, Linux | Directorio aislado de la herramienta |
| Gemini CLI | `gemini-cli` | Windows, macOS, Linux | Superposición de archivos |
| Grok Build CLI | `grok-cli` | Windows, macOS, Linux | Secreto de proceso |
| Kimi Code CLI | `kimi-cli` | Windows, macOS, Linux | Secreto de proceso |
| Kiro | `kiro` | Windows, macOS, Linux | Usuario del sistema operativo o directorio aislado |
| OpenCode | `opencode` | Windows, macOS, Linux | Directorio aislado de la herramienta |
| Windsurf | `windsurf` | Windows, macOS, Linux | Usuario del sistema operativo o directorio aislado |
| Zed | `zed` | Windows | Usuario del sistema operativo |

Los requisitos de cada plataforma y las limitaciones conocidas están en la [matriz de compatibilidad](../support-matrix.md). Ejecuta `multi-cli tools` para ver qué está disponible en tu equipo.

<a id="commands"></a>

## Comandos

### Perfiles

| Comando | Acción |
|---|---|
| `multi-cli new <tool>/<name>` | Crear un perfil de cuenta con credenciales separadas y estado normal compartido |
| `multi-cli new <tool>/<name> --isolated` | Crear un perfil con todo el directorio aislado; alias: `--isolate`, `-i` |
| `multi-cli new <tool>/<name> --from <template>` | Crear un perfil desde una plantilla guardada |
| `multi-cli <tool>/<name>` | Iniciar un perfil |
| `multi-cli launch <tool>/<name> [-- args...]` | Iniciar y pasar argumentos a la herramienta |
| `multi-cli list [<tool>]` | Enumerar perfiles |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | Copiar un perfil |
| `multi-cli rename <tool>/<old> <tool>/<new>` | Cambiar el nombre de un perfil |
| `multi-cli delete <tool>/<name>` | Eliminar un perfil tras confirmar |

### Credenciales y portabilidad

| Comando | Acción |
|---|---|
| `multi-cli auth set <tool>/<profile>` | Guardar un secreto de proceso en el almacén de credenciales del sistema |
| `multi-cli auth status <tool>/<profile>` | Comprobar si existe el secreto |
| `multi-cli auth clear <tool>/<profile>` | Eliminar el secreto |
| `multi-cli continue <tool> <src> <dest> [--dry-run] [--no-merge]` | Copiar el estado de sesión compatible, nunca las credenciales |
| `multi-cli template save <tool>/<profile> <name>` | Guardar una plantilla sin credenciales |
| `multi-cli template list \| delete <name>` | Enumerar o eliminar plantillas |
| `multi-cli export <tool>/<name> [path]` | Exportar un perfil |
| `multi-cli import <archive> <tool>/<name>` | Importar un perfil |

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
| Usuario del sistema operativo | La identidad de credenciales fija del producto | Nada, salvo que el adaptador lo indique |
| Directorio aislado de la herramienta | Todo el directorio de la herramienta | Nada |

Los perfiles usan el límite seguro más estrecho. `--isolated` crea un directorio separado para la herramienta y no comparte nada. Los productos ligados a una identidad de credenciales fija usan un usuario de Windows administrado por Multi-CLI y requieren una terminal con privilegios elevados.

Los adaptadores con secreto de proceso requieren un paso adicional antes de iniciarlos:

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work
multi-cli cursor-cli/work
```

Los perfiles creados por versiones anteriores de Multi-CLI conservan su aislamiento original de todo el directorio. Previsualiza la migración con:

```bash
multi-cli migrate codex/work --dry-run
```

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
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

Los datos de los perfiles se conservan salvo que confirmes su eliminación.

## Enlaces

- [Matriz de compatibilidad](../support-matrix.md)
- [Política de seguridad](../SECURITY.md)
- [Contribuir](../CONTRIBUTING.md)
- [Soporte](../SUPPORT.md)
- [Versiones en GitHub](https://github.com/Spielewoy/multi-cli/releases)

## Licencia

[MIT](../../LICENSE)
