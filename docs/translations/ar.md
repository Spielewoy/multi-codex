<div dir="rtl">

<p align="center">
  <img src="../../assets/i18n/ar/banner.svg" alt="Multi-CLI. استخدم عدة حسابات في الوقت نفسه دون التبديل بينها." width="760"/>
</p>

<p align="center">استخدم عدة حسابات في الوقت نفسه دون التبديل بينها.</p>

<p align="center">
  <a href="#supported-ai-tools"><img src="https://img.shields.io/badge/%D8%A7%D9%84%D8%AF%D8%B9%D9%85-17%20%D8%A3%D8%AF%D8%A7%D8%A9%20%D8%B0%D9%83%D8%A7%D8%A1%20%D8%A7%D8%B5%D8%B7%D9%86%D8%A7%D8%B9%D9%8A-255C60?style=flat-square&labelColor=14101F" alt="17 أداة ذكاء اصطناعي مدعومة"/></a>
  <a href="../../release/VERSION"><img src="https://img.shields.io/badge/%D8%A7%D9%84%D8%A5%D8%B5%D8%AF%D8%A7%D8%B1-v1.0.0-255C60?style=flat-square&labelColor=14101F" alt="الإصدار v1.0.0"/></a>
  <a href="#install"><img src="https://img.shields.io/badge/%D8%A7%D9%84%D9%85%D9%86%D8%B5%D8%A7%D8%AA-macOS%20%7C%20Linux%20%7C%20Windows-255C60?style=flat-square&labelColor=14101F" alt="macOS وLinux وWindows"/></a>
  <a href="../../LICENSE"><img src="https://img.shields.io/badge/%D8%A7%D9%84%D8%AA%D8%B1%D8%AE%D9%8A%D8%B5-MIT-255C60?style=flat-square&labelColor=14101F" alt="رخصة MIT"/></a>
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

[التثبيت](#install) · [البدء السريع](#quick-start) · [أدوات الذكاء الاصطناعي](#supported-ai-tools) · [الأوامر](#commands) · [العزل](#how-isolation-works) · [نقل الجلسات](#move-sessions-between-accounts) · [استكشاف الأخطاء](#troubleshooting) · [إلغاء التثبيت](#uninstall)

<a id="install"></a>

## التثبيت

### المتطلبات

- macOS أو Linux: الإصدار 3.2 أو أحدث من [Bash](https://www.gnu.org/software/bash/)
- Windows: الإصدار 5.1 من [Windows PowerShell](https://www.microsoft.com/download/details.aspx?id=54616)
- الإصدار 1.7.1 من [jq](https://jqlang.github.io/jq/download/)؛ يُثبّت تلقائيًا عند غيابه
- إحدى [أدوات الذكاء الاصطناعي المدعومة](#supported-ai-tools)

### التثبيت من المصدر

تتطلب هذه الطريقة [Git](https://git-scm.com/downloads).

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

## البدء السريع

```bash
multi-cli doctor
multi-cli new claude-cli/work
multi-cli claude-cli/work
```

<a id="supported-ai-tools"></a>

## أدوات الذكاء الاصطناعي المدعومة

| أداة الذكاء الاصطناعي | المعرّف | المنصات | حد الحساب |
|---|---|---|---|
| [AGY CLI](../adapters/agy-cli.md) | `agy-cli` | Windows | مستخدم نظام التشغيل |
| [Antigravity](../adapters/antigravity.md) | `antigravity` | Windows | مستخدم نظام التشغيل |
| [Claude Code](../adapters/claude-cli.md) | `claude-cli` | Windows وLinux ومفاتيح API على macOS | تراكب الملفات |
| [Codex CLI](../adapters/codex.md) | `codex` | Windows وmacOS وLinux | تراكب الملفات |
| [Codex Desktop](../adapters/codex-gui.md) | `codex-gui` | Windows | مستخدم نظام التشغيل |
| [Command Code](../adapters/commandcode.md) | `commandcode` | Windows وmacOS وLinux | تراكب الملفات |
| [GitHub Copilot CLI](../adapters/copilot-cli.md) | `copilot-cli` | Windows وmacOS وLinux | سر العملية |
| [GitHub Copilot في VS Code](../adapters/copilot-vscode.md) | `copilot-vscode` | Windows | مستخدم نظام التشغيل |
| [Cursor CLI](../adapters/cursor-cli.md) | `cursor-cli` | Windows وmacOS وLinux | سر العملية |
| [Cursor Desktop](../adapters/cursor.md) | `cursor` | Windows وmacOS وLinux | مجلد رئيسي معزول للأداة |
| [Gemini CLI](../adapters/gemini-cli.md) | `gemini-cli` | Windows وmacOS وLinux | تراكب الملفات |
| [Grok Build CLI](../adapters/grok-cli.md) | `grok-cli` | Windows وmacOS وLinux | سر العملية |
| [Kimi Code CLI](../adapters/kimi-cli.md) | `kimi-cli` | Windows وmacOS وLinux | سر العملية |
| [Kiro](../adapters/kiro.md) | `kiro` | Windows وmacOS وLinux | مستخدم نظام التشغيل |
| [OpenCode](../adapters/opencode.md) | `opencode` | Windows وmacOS وLinux | مجلد رئيسي معزول للأداة |
| [Windsurf](../adapters/windsurf.md) | `windsurf` | Windows وmacOS وLinux | مستخدم نظام التشغيل |
| [Zed](../adapters/zed.md) | `zed` | Windows | مستخدم نظام التشغيل |

راجع قيود المنصات في [مصفوفة الدعم](../support-matrix.md). شغّل `multi-cli tools` للتحقق من جهازك.

<a id="commands"></a>

## الأوامر

### ملفات التعريف

| الأمر | الإجراء |
|---|---|
| `multi-cli new <tool>/<name>` | إنشاء ملف تعريف ببيانات اعتماد منفصلة وحالة عادية مشتركة |
| `multi-cli new <tool>/<name> --isolated` | إنشاء ملف تعريف يعزل المجلد بالكامل عندما تدعم أداة الذكاء الاصطناعي ذلك؛ الأسماء البديلة: `--isolate` و`-i` |
| `multi-cli new <tool>/<name> --from <template>` | إنشاء ملف تعريف بالمخطط v2 من قالب بالمخطط v2 |
| `multi-cli <tool>/<name>` | تشغيل ملف تعريف |
| `multi-cli launch <tool>/<name> [-- args...]` | تشغيل الأداة وتمرير الوسائط إليها |
| `multi-cli list [<tool>]` | عرض ملفات التعريف |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | نسخ ملف تعريف بالمخطط v2 |
| `multi-cli rename <tool>/<old> <tool>/<new>` | إعادة تسمية ملف تعريف |
| `multi-cli delete <tool>/<name>` | حذف ملف تعريف بعد التأكيد |

### بيانات الاعتماد وقابلية النقل

| الأمر | الإجراء |
|---|---|
| `multi-cli auth set <tool>/<profile>` | حفظ سر العملية في مخزن بيانات اعتماد نظام التشغيل |
| `multi-cli auth status <tool>/<profile>` | التحقق من وجود السر |
| `multi-cli auth clear <tool>/<profile>` | حذف السر |
| `multi-cli continue <tool> <src> <dest> [--dry-run] [--no-merge]` | نسخ حالة الجلسة المدعومة دون نسخ بيانات الاعتماد |
| `multi-cli template save <tool>/<profile> <name>` | حفظ قالب بالمخطط v2 خالٍ من بيانات الاعتماد |
| `multi-cli template list \| delete <name>` | عرض القوالب أو حذفها |
| `multi-cli export <tool>/<name> [path]` | تصدير ملف تعريف بالمخطط v2 |
| `multi-cli import <archive> <tool>/<name>` | استيراد أرشيف بالمخطط v2 |

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
| مستخدم نظام التشغيل | هوية بيانات الاعتماد الثابتة للمنتج | لا شيء ما لم تسمح أداة الذكاء الاصطناعي بغير ذلك |
| مجلد رئيسي معزول للأداة | المجلد الرئيسي للأداة بالكامل | لا شيء |

تستخدم ملفات التعريف أضيق حد مدعوم. ينشئ `--isolated` مجلدًا رئيسيًا منفصلًا للأداة. تستخدم بيانات اعتماد نظام التشغيل الثابتة مستخدم نظام تشغيل تديره Multi-CLI، ويتطلب ذلك طرفية بصلاحيات مرتفعة على Windows.

تحتاج أدوات الذكاء الاصطناعي التي تستخدم سر العملية إلى خطوة إضافية قبل التشغيل:

```bash
multi-cli new cursor-cli/work
multi-cli auth set cursor-cli/work
multi-cli cursor-cli/work
```

تحتفظ ملفات التعريف القديمة بعزل المجلد الرئيسي الكامل الأصلي. عاين الترحيل باستخدام:

```bash
multi-cli migrate codex/work --dry-run
```

لا يمكن نقل إلا ملفات التعريف والقوالب والأرشيفات التي تستخدم المخطط v2. رحّل ملفات التعريف القديمة أولًا.

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
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/install/uninstall.sh | bash
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/install/uninstall.ps1 | iex
```

تُحفظ بيانات ملفات التعريف ما لم تؤكد حذفها.

## الروابط

- [مصفوفة الدعم](../support-matrix.md)
- [سياسة الأمان](../SECURITY.md)
- [المساهمة](../CONTRIBUTING.md)
- [الدعم](../SUPPORT.md)

## الرخصة

[MIT](../../LICENSE)

</div>
