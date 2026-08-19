<div dir="rtl">

<p align="center">
  <img src="../../assets/i18n/he/banner.svg" alt="Multi-CLI. השתמשו בכמה חשבונות בו-זמנית בלי לעבור ביניהם." width="760"/>
</p>

<p align="center">השתמשו בכמה חשבונות בו-זמנית בלי לעבור ביניהם.</p>

<p align="center">
  <a href="#supported-ai-tools"><img src="https://img.shields.io/badge/%D7%AA%D7%9E%D7%99%D7%9B%D7%94-17%20%D7%9B%D7%9C%D7%99%20AI-255C60?style=flat-square&labelColor=14101F" alt="17 כלי AI נתמכים"/></a>
  <a href="../../release/VERSION"><img src="https://img.shields.io/badge/%D7%92%D7%A8%D7%A1%D7%94-v1.0.0-255C60?style=flat-square&labelColor=14101F" alt="גרסה v1.0.0"/></a>
  <a href="#install"><img src="https://img.shields.io/badge/%D7%A4%D7%9C%D7%98%D7%A4%D7%95%D7%A8%D7%9E%D7%95%D7%AA-macOS%20%7C%20Linux%20%7C%20Windows-255C60?style=flat-square&labelColor=14101F" alt="macOS, Linux ו-Windows"/></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/%D7%A8%D7%99%D7%A9%D7%99%D7%95%D7%9F-MIT-255C60?style=flat-square&labelColor=14101F" alt="רישיון MIT"/></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> |
  <a href="es.md">Español</a> |
  <a href="ar.md">العربية</a> |
  <a href="zh.md">中文</a> |
  <a href="ru.md">Русский</a> |
  <a href="he.md"><b>עברית</b></a>
</p>

## תוכן העניינים

[התקנה](#install) · [התחלה מהירה](#quick-start) · [כלי AI](#supported-ai-tools) · [פקודות](#commands) · [בידוד](#how-isolation-works) · [העברת סשנים](#move-sessions-between-accounts) · [פתרון תקלות](#troubleshooting) · [הסרת התקנה](#uninstall)

<a id="install"></a>

## התקנה

### דרישות

- macOS או Linux: [Bash 3.2 ואילך](https://www.gnu.org/software/bash/)
- Windows: [Windows PowerShell 5.1](https://www.microsoft.com/download/details.aspx?id=54616)
- [jq 1.7.1](https://jqlang.github.io/jq/download/), מותקן אוטומטית אם חסר
- אחד מ[כלי ה-AI הנתמכים](#supported-ai-tools)

### התקנה מקוד המקור

שיטה זו דורשת את [Git](https://git-scm.com/downloads).

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

## התחלה מהירה

```bash
multi-cli doctor
multi-cli new claude-cli/work
multi-cli claude-cli/work
```

<a id="supported-ai-tools"></a>

## כלי AI נתמכים

| כלי AI | מזהה | פלטפורמות | גבול החשבון |
|---|---|---|---|
| [AGY CLI](../adapters/agy-cli.md) | `agy-cli` | Windows | משתמש מערכת ההפעלה |
| [Antigravity](../adapters/antigravity.md) | `antigravity` | Windows | משתמש מערכת ההפעלה |
| [Claude Code](../adapters/claude-cli.md) | `claude-cli` | Windows, Linux, מפתחות API ב-macOS | שכבת קבצים |
| [Codex CLI](../adapters/codex.md) | `codex` | Windows, macOS, Linux | שכבת קבצים |
| [Codex Desktop](../adapters/codex-gui.md) | `codex-gui` | Windows | משתמש מערכת ההפעלה |
| [Command Code](../adapters/commandcode.md) | `commandcode` | Windows, macOS, Linux | שכבת קבצים |
| [GitHub Copilot CLI](../adapters/copilot-cli.md) | `copilot-cli` | Windows, macOS, Linux | סוד תהליך |
| [GitHub Copilot ב-VS Code](../adapters/copilot-vscode.md) | `copilot-vscode` | Windows | משתמש מערכת ההפעלה |
| [Cursor CLI](../adapters/cursor-cli.md) | `cursor-cli` | Windows, macOS, Linux | סוד תהליך |
| [Cursor Desktop](../adapters/cursor.md) | `cursor` | Windows, macOS, Linux | תיקיית בית מבודדת לכלי |
| [Gemini CLI](../adapters/gemini-cli.md) | `gemini-cli` | Windows, macOS, Linux | שכבת קבצים |
| [Grok Build CLI](../adapters/grok-cli.md) | `grok-cli` | Windows, macOS, Linux | סוד תהליך |
| [Kimi Code CLI](../adapters/kimi-cli.md) | `kimi-cli` | Windows, macOS, Linux | סוד תהליך |
| [Kiro](../adapters/kiro.md) | `kiro` | Windows, macOS, Linux | משתמש מערכת ההפעלה |
| [OpenCode](../adapters/opencode.md) | `opencode` | Windows, macOS, Linux | תיקיית בית מבודדת לכלי |
| [Windsurf](../adapters/windsurf.md) | `windsurf` | Windows, macOS, Linux | משתמש מערכת ההפעלה |
| [Zed](../adapters/zed.md) | `zed` | Windows | משתמש מערכת ההפעלה |

מגבלות הפלטפורמות מפורטות ב[טבלת התמיכה](../support-matrix.md). הפעילו את `multi-cli tools` כדי לבדוק את המחשב שלכם.

<a id="commands"></a>

## פקודות

### פרופילים

| פקודה | פעולה |
|---|---|
| `multi-cli new <tool>/<name>` | יצירת פרופיל עם פרטי אימות נפרדים ומצב רגיל משותף |
| `multi-cli new <tool>/<name> --isolated` | יצירת פרופיל עם תיקייה מבודדת במלואה כאשר כלי ה-AI תומך בכך; כינויים: `--isolate`, `-i` |
| `multi-cli new <tool>/<name> --from <template>` | יצירת פרופיל בסכמה v2 מתבנית בסכמה v2 |
| `multi-cli <tool>/<name>` | הפעלת פרופיל |
| `multi-cli launch <tool>/<name> [-- args...]` | הפעלה והעברת ארגומנטים לכלי |
| `multi-cli list [<tool>]` | הצגת פרופילים |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | העתקת פרופיל בסכמה v2 |
| `multi-cli rename <tool>/<old> <tool>/<new>` | שינוי שם של פרופיל |
| `multi-cli delete <tool>/<name>` | מחיקת פרופיל לאחר אישור |

### פרטי אימות וניידות

| פקודה | פעולה |
|---|---|
| `multi-cli auth set <tool>/<profile>` | שמירת סוד תהליך במאגר פרטי האימות של מערכת ההפעלה |
| `multi-cli auth status <tool>/<profile>` | בדיקה אם הסוד קיים |
| `multi-cli auth clear <tool>/<profile>` | הסרת הסוד |
| `multi-cli continue <tool> <src> <dest> [--dry-run] [--no-merge]` | העתקת מצב סשן נתמך, ללא פרטי אימות |
| `multi-cli template save <tool>/<profile> <name>` | שמירת תבנית בסכמה v2 ללא פרטי אימות |
| `multi-cli template list \| delete <name>` | הצגת תבניות או מחיקתן |
| `multi-cli export <tool>/<name> [path]` | ייצוא פרופיל בסכמה v2 |
| `multi-cli import <archive> <tool>/<name>` | ייבוא ארכיון בסכמה v2 |

### תחזוקה

| פקודה | פעולה |
|---|---|
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | העברת פרופיל ישן ל-schema v2 |
| `multi-cli status` | הצגת פרופילים וגדלים |
| `multi-cli stats` | הצגת נפח האחסון של הפרופילים |
| `multi-cli doctor [--deep]` | אבחון ההגדרות ובדיקה אופציונלית של סביבות ההרצה |
| `multi-cli completion {bash\|zsh\|powershell}` | הצגת הגדרות השלמה אוטומטית ל-shell |
| `multi-cli help` | הצגת כל הפקודות |
| `multi-cli version` | הצגת הגרסה המותקנת |

<a id="how-isolation-works"></a>

## איך הבידוד עובד

| מצב | מה נשאר נפרד | מה נשאר משותף |
|---|---|---|
| שכבת קבצים | קובצי פרטי האימות שהוגדרו | ההגדרות והשיחות הרגילות של הכלי |
| סוד תהליך | פרט אימות אחד שמוזרק לתהליך הבן | המצב הרגיל של הכלי |
| משתמש מערכת ההפעלה | זהות פרטי האימות הקבועה של המוצר | שום דבר, אלא אם כלי ה-AI מאפשר זאת |
| תיקיית בית מבודדת לכלי | כל תיקיית הבית של הכלי | שום דבר |

פרופילים משתמשים בגבול הנתמך המצומצם ביותר. `--isolated` יוצר תיקיית בית נפרדת לכלי. פרטי אימות קבועים של מערכת ההפעלה משתמשים במשתמש מערכת שמנוהל על ידי Multi-CLI ודורשים טרמינל עם הרשאות מנהל ב-Windows.

כלי AI שמשתמשים בסוד תהליך דורשים צעד נוסף לפני ההפעלה:

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work
multi-cli cursor-cli/work
```

פרופילים ישנים שומרים על בידוד תיקיית הבית המקורי. ניתן לראות תצוגה מקדימה של ההעברה באמצעות:

```bash
multi-cli migrate codex/work --dry-run
```

רק פרופילים, תבניות וארכיונים בסכמה v2 ניתנים להעברה. יש להעביר תחילה פרופילים ישנים.

<a id="move-sessions-between-accounts"></a>

## העברת סשנים בין חשבונות

העתיקו מצב שיחה נתמך כאשר חשבון מגיע למגבלה שלו:

```bash
multi-cli continue codex work personal --dry-run
multi-cli continue codex work personal
multi-cli codex/personal
codex resume
```

`base` מייצג את תיקיית הבית הרגילה של הכלי, לכן כל צד יכול להיות פרופיל או התקנת ברירת המחדל. פרטי אימות לעולם אינם מועתקים. העברת סשנים נתמכת עבור `codex`, `claude-cli`, `gemini-cli` ו-`commandcode`.

## כינויים ב-shell

כל פרופיל מקבל קיצור דרך כמו `claude-cli-work`.

| פלטפורמה | מיקום |
|---|---|
| macOS ו-Linux | `~/MultiCliProfiles/bin/` |
| Windows | `~/MultiCliProfiles/bin/`, וכן קיצורי דרך בתפריט ההתחלה עבור פרופילים גרפיים |

## הגדרות

| משתנה | ברירת מחדל | מטרה |
|---|---|---|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | אחסון פרופילים |
| `MULTICLI_OVERRIDE_BINARY` | לא מוגדר | עקיפת איתור קובץ ההפעלה להפעלה אחת |
| `MULTICLI_REPO` | מאגר GitHub | עקיפת מקור ההתקנה |
| `MULTICLI_INSTALL_DIR` | ברירת המחדל של הפלטפורמה | עקיפת תיקיית ההתקנה |

<a id="troubleshooting"></a>

## פתרון תקלות

```bash
multi-cli doctor
multi-cli doctor --deep
multi-cli tools
```

הפעילו מחדש את הטרמינל אם `multi-cli` או הכינוי של פרופיל חדש אינם נמצאים לאחר ההתקנה. [טבלת התמיכה](../support-matrix.md) כוללת דרישות ספציפיות לכל מוצר.

<a id="uninstall"></a>

## הסרת התקנה

macOS ו-Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/install/uninstall.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/install/uninstall.ps1 | iex
```

נתוני הפרופילים נשמרים אלא אם מאשרים את מחיקתם.

## קישורים

- [טבלת התמיכה](../support-matrix.md)
- [מדיניות אבטחה](../SECURITY.md)
- [תרומה](../CONTRIBUTING.md)
- [תמיכה](../SUPPORT.md)

## רישיון

[MIT](../../LICENSE)

</div>
