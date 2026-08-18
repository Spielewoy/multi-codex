<div dir="rtl">

<p align="center">
  <img src="../../assets/i18n/ar/banner.svg" alt="Multi-CLI. استخدم عدة حسابات في الوقت نفسه دون التبديل بينها." width="760"/>
</p>

<p align="center">استخدم عدة حسابات في الوقت نفسه دون التبديل بينها.</p>

<p align="center">
  <a href="#supported-tools"><img src="https://img.shields.io/badge/support-17%20adapters-255C60?style=flat-square&labelColor=14101F" alt="17 محولًا"/></a>
  <a href="https://github.com/Spielewoy/multi-cli/releases/latest"><img src="https://img.shields.io/github/v/release/Spielewoy/multi-cli?style=flat-square&label=version&color=255C60&labelColor=14101F" alt="الإصدار 1.0.0"/></a>
  <a href="#install"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-255C60?style=flat-square&labelColor=14101F" alt="macOS وLinux وWindows"/></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/license-MIT-255C60?style=flat-square&labelColor=14101F" alt="رخصة MIT"/></a>
</p>

<p align="center">
  <a href="../../README.md">English</a> |
  <a href="es.md">Español</a> |
  <a href="ar.md"><b>العربية</b></a> |
  <a href="zh.md">中文</a> |
  <a href="ru.md">Русский</a> |
  <a href="he.md">עברית</a>
</p>

## المحتويات

[التثبيت](#install) · [البدء السريع](#quick-start) · [الأدوات المدعومة](#supported-tools) · [الأوامر](#commands) · [العزل](#how-isolation-works) · [نقل الجلسات](#move-sessions-between-accounts) · [استكشاف الأخطاء](#troubleshooting) · [إلغاء التثبيت](#uninstall)

<a id="install"></a>

## التثبيت

استخدم نص التثبيت الخاص بمنصتك أدناه، أو نزّل حزمة جاهزة من [إصدارات GitHub](https://github.com/Spielewoy/multi-cli/releases).

### macOS وLinux

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

### Windows

افتح PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

ينسخ المثبّت Multi-CLI أو يحدّثه، ويثبّت `jq` عند الحاجة. أعد تشغيل الأمر نفسه للتحديث. أعد تشغيل الطرفية بعد التثبيت. على macOS وLinux، اتبع تعليمات PATH المطبوعة إن ظهرت.

<details>
<summary><strong>التثبيت من المصدر</strong></summary>

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

المتطلبات: Git واتصال بالإنترنت وBash على macOS أو Linux، أو PowerShell على Windows. يحصل المثبّت تلقائيًا على ملف `jq` التنفيذي المطلوب متى أمكن.

<a id="quick-start"></a>

## البدء السريع

```bash
# افحص إعدادك واكتشف الأدوات المثبّتة
multi-cli doctor
multi-cli tools

# أنشئ ملف تعريف وشغّله
multi-cli new claude-cli/work
multi-cli launch claude-cli/work

# صيغة التشغيل المختصرة
multi-cli claude-cli/work
```

تبقى بيانات الاعتماد داخل ملف التعريف افتراضيًا، بينما تظل الإعدادات والمحادثات والوكلاء والمهارات والإضافات المدعومة مشتركة. أضف `--isolated` عندما تريد فصل المجلد الرئيسي للأداة بالكامل.

<a id="supported-tools"></a>

## الأدوات المدعومة

| الأداة | المحوّل | المنصات | حد الحساب |
|---|---|---|---|
| AGY CLI | `agy-cli` | Windows | مستخدم نظام التشغيل |
| Antigravity | `antigravity` | Windows | مستخدم نظام التشغيل |
| Claude Code | `claude-cli` | Windows وLinux ومفاتيح API على macOS | تراكب الملفات |
| Codex CLI | `codex` | Windows وmacOS وLinux | تراكب الملفات |
| Codex Desktop | `codex-gui` | Windows | مستخدم نظام التشغيل |
| Command Code | `commandcode` | Windows وmacOS وLinux | تراكب الملفات |
| GitHub Copilot CLI | `copilot-cli` | Windows وmacOS وLinux | سر العملية |
| GitHub Copilot في VS Code | `copilot-vscode` | Windows | مستخدم نظام التشغيل |
| Cursor CLI | `cursor-cli` | Windows وmacOS وLinux | سر العملية |
| Cursor Desktop | `cursor` | Windows وmacOS وLinux | مجلد رئيسي معزول للأداة |
| Gemini CLI | `gemini-cli` | Windows وmacOS وLinux | تراكب الملفات |
| Grok Build CLI | `grok-cli` | Windows وmacOS وLinux | سر العملية |
| Kimi Code CLI | `kimi-cli` | Windows وmacOS وLinux | سر العملية |
| Kiro | `kiro` | Windows وmacOS وLinux | مستخدم نظام التشغيل أو مجلد رئيسي معزول |
| OpenCode | `opencode` | Windows وmacOS وLinux | مجلد رئيسي معزول للأداة |
| Windsurf | `windsurf` | Windows وmacOS وLinux | مستخدم نظام التشغيل أو مجلد رئيسي معزول |
| Zed | `zed` | Windows | مستخدم نظام التشغيل |

توجد متطلبات المنصات والقيود المعروفة في [مصفوفة الدعم](../support-matrix.md). شغّل `multi-cli tools` لمعرفة الأدوات المتاحة على جهازك.

<a id="commands"></a>

## الأوامر

### ملفات التعريف

| الأمر | الإجراء |
|---|---|
| `multi-cli new <tool>/<name>` | إنشاء ملف تعريف ببيانات اعتماد منفصلة وحالة عادية مشتركة |
| `multi-cli new <tool>/<name> --isolated` | إنشاء ملف تعريف يعزل المجلد الرئيسي بالكامل؛ الأسماء البديلة: `--isolate` و`-i` |
| `multi-cli new <tool>/<name> --from <template>` | إنشاء ملف تعريف من قالب محفوظ |
| `multi-cli <tool>/<name>` | تشغيل ملف تعريف |
| `multi-cli launch <tool>/<name> [-- args...]` | تشغيل الأداة وتمرير الوسائط إليها |
| `multi-cli list [<tool>]` | عرض ملفات التعريف |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | نسخ ملف تعريف |
| `multi-cli rename <tool>/<old> <tool>/<new>` | إعادة تسمية ملف تعريف |
| `multi-cli delete <tool>/<name>` | حذف ملف تعريف بعد التأكيد |

### بيانات الاعتماد وقابلية النقل

| الأمر | الإجراء |
|---|---|
| `multi-cli auth set <tool>/<profile>` | حفظ سر العملية في مخزن بيانات اعتماد نظام التشغيل |
| `multi-cli auth status <tool>/<profile>` | التحقق من وجود السر |
| `multi-cli auth clear <tool>/<profile>` | حذف السر |
| `multi-cli continue <tool> <src> <dest> [--dry-run] [--no-merge]` | نسخ حالة الجلسة المدعومة دون نسخ بيانات الاعتماد |
| `multi-cli template save <tool>/<profile> <name>` | حفظ قالب خالٍ من بيانات الاعتماد |
| `multi-cli template list \| delete <name>` | عرض القوالب أو حذفها |
| `multi-cli export <tool>/<name> [path]` | تصدير ملف تعريف |
| `multi-cli import <archive> <tool>/<name>` | استيراد ملف تعريف |

### الصيانة

| الأمر | الإجراء |
|---|---|
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | ترحيل ملف تعريف قديم إلى schema v2 |
| `multi-cli status` | عرض ملفات التعريف وأحجامها |
| `multi-cli stats` | عرض مساحة التخزين التي تستخدمها ملفات التعريف |
| `multi-cli doctor [--deep]` | تشخيص الإعداد وتدقيق بيئات التشغيل اختياريًا |
| `multi-cli completion {bash\|zsh\|powershell}` | طباعة إعداد الإكمال التلقائي للصدفة |
| `multi-cli help` | عرض جميع الأوامر |
| `multi-cli version` | عرض الإصدار المثبّت |

<a id="how-isolation-works"></a>

## كيف يعمل العزل

| الوضع | ما يبقى منفصلًا | ما يبقى مشتركًا |
|---|---|---|
| تراكب الملفات | ملفات بيانات الاعتماد المحددة | إعدادات الأداة الأصلية ومحادثاتها |
| سر العملية | بيانات اعتماد واحدة تُحقن في العملية الفرعية | الحالة العادية للأداة |
| مستخدم نظام التشغيل | هوية بيانات الاعتماد الثابتة للمنتج | لا شيء ما لم يحدد المحوّل غير ذلك |
| مجلد رئيسي معزول للأداة | المجلد الرئيسي للأداة بالكامل | لا شيء |

تستخدم ملفات تعريف الحساب أضيق حد آمن. ينشئ `--isolated` مجلدًا رئيسيًا منفصلًا للأداة ولا يشارك شيئًا. تستخدم المنتجات المرتبطة بهوية ثابتة لبيانات اعتماد نظام التشغيل مستخدم Windows يديره Multi-CLI، وتتطلب طرفية بصلاحيات مرتفعة.

تحتاج المحوّلات التي تستخدم سر العملية إلى خطوة إضافية قبل التشغيل:

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work
multi-cli cursor-cli/work
```

تحتفظ ملفات التعريف التي أنشأتها إصدارات Multi-CLI السابقة بعزل المجلد الرئيسي الكامل الأصلي. عاين الترحيل باستخدام:

```bash
multi-cli migrate codex/work --dry-run
```

<a id="move-sessions-between-accounts"></a>

## نقل الجلسات بين الحسابات

انسخ حالة المحادثة المدعومة عندما يصل أحد الحسابات إلى حده:

```bash
multi-cli continue codex work personal --dry-run
multi-cli continue codex work personal
multi-cli codex/personal
codex resume
```

يشير `base` إلى المجلد الرئيسي العادي للأداة، لذلك يمكن أن يكون أي طرف ملف تعريف أو التثبيت الافتراضي. لا تُنسخ بيانات الاعتماد مطلقًا. يدعم نقل الجلسات كل من `codex` و`claude-cli` و`gemini-cli` و`commandcode`.

## الأسماء المستعارة للصدفة

يحصل كل ملف تعريف على اختصار مثل `claude-cli-work`.

| المنصة | الموقع |
|---|---|
| macOS وLinux | `~/MultiCliProfiles/bin/` |
| Windows | `~/MultiCliProfiles/bin/`، بالإضافة إلى اختصارات قائمة ابدأ لملفات التعريف الرسومية |

## الإعداد

| المتغير | القيمة الافتراضية | الغرض |
|---|---|---|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | مساحة تخزين ملفات التعريف |
| `MULTICLI_OVERRIDE_BINARY` | غير محدد | تجاوز اكتشاف الملف التنفيذي لعملية تشغيل واحدة |
| `MULTICLI_REPO` | مستودع GitHub | تجاوز مصدر التثبيت |
| `MULTICLI_INSTALL_DIR` | القيمة الافتراضية للمنصة | تجاوز مجلد التثبيت |

<a id="troubleshooting"></a>

## استكشاف الأخطاء وإصلاحها

```bash
multi-cli doctor
multi-cli doctor --deep
multi-cli tools
```

أعد تشغيل الطرفية إذا لم يُعثر على `multi-cli` أو الاسم المستعار لملف تعريف جديد بعد التثبيت. تغطي [مصفوفة الدعم](../support-matrix.md) المتطلبات الخاصة بكل منتج.

<a id="uninstall"></a>

## إلغاء التثبيت

macOS وLinux:

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

تُحفظ بيانات ملفات التعريف ما لم تؤكد حذفها.

## الروابط

- [مصفوفة الدعم](../support-matrix.md)
- [سياسة الأمان](../SECURITY.md)
- [المساهمة](../CONTRIBUTING.md)
- [الدعم](../SUPPORT.md)
- [إصدارات GitHub](https://github.com/Spielewoy/multi-cli/releases)

## الرخصة

[MIT](../../LICENSE)

</div>
