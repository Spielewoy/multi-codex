[English](README.md) | [Español](README.es.md) | **العربية** | [中文](README.zh.md) | [Русский](README.ru.md) | [עברית](README.he.md)

<div dir="rtl">

# multi-cli

**شغّل عدة ملفات تعريف لحسابات أدوات البرمجة بالذكاء الاصطناعي في وقت واحد.**

يعزل ملف schema-v2 بيانات اعتماد الحساب وحصته، ويشارك المحادثات والإعدادات والإضافات عندما يكون الحد آمنًا. إذا دمج المورّد المصادقة مع الجلسات، يستخدم multi-cli مستخدم نظام تشغيل مستقلًا أو ملف جذر كاملًا عبر `--isolated`. توضّح [مصفوفة الدعم](docs/support-matrix.md) الوضع والمتطلبات الدقيقة لكل منصة.

تظل ملفات التعريف schema-v1 الحالية ملفات تعريف قديمة ذات جذر كامل حتى يتم ترحيلها — راجع [ملفات التعريف القديمة](#legacy-profiles).

[![GitHub repository](https://img.shields.io/badge/GitHub-Repository-blue?logo=github)](https://github.com/Spielewoy/multi-cli)
[![GitHub profile](https://img.shields.io/badge/GitHub-Spielewoy-lightgrey?logo=github)](https://github.com/Spielewoy)
[![GitHub stars](https://img.shields.io/github/stars/Spielewoy/multi-cli?style=social)](https://github.com/Spielewoy/multi-cli/stargazers)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](#install)
[![License](https://img.shields.io/badge/license-MIT-green)](#license)

---

## الأدوات المدعومة

يتضمن هذا المستودع 17 محوّلًا. تعني `supported` أن multi-cli يوفر وضع عزل عاملًا واحدًا على الأقل في ذلك النظام، وتعني `experimental` أن التنفيذ متاح لكنه لا يزال يتطلب التحقق المحدد على نظام حقيقي، وتعني `unsupported` أن المنتج أو وضع العزل غير متاح هناك. المصدر المعتمد هو [docs/support-matrix.md](docs/support-matrix.md).

| الأداة | النوع | Windows | macOS | Linux |
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

لكل أداة مجلد خاص بها في جذر المستودع يحتوي على ملف `adapter.json` يصف حد الحساب والحالة العادية المشتركة والأدلة المطلوبة للترقية إلى حالة موثَّقة.

---

<a id="install"></a>

## التثبيت

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.sh | bash
```

**Windows** — افتح PowerShell:

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/install.ps1 | iex
```

> بعد التثبيت، **أعد تشغيل الطرفية** لتسري التغييرات على PATH.

### من المصدر

```bash
git clone https://github.com/Spielewoy/multi-cli.git
cd multi-cli
./scripts/install.sh --local        # macOS/Linux
.\scripts\install.ps1 -Local        # Windows
```

> بعد التثبيت، **أعد تشغيل الطرفية** لتسري التغييرات على PATH.

> يتم **تثبيت** [jq](https://jqlang.github.io/jq/) **تلقائيًا** بواسطة المثبِّت على جميع المنصات — لا حاجة لأي إعداد يدوي.

---

## البدء السريع

```bash
# Create a profile
multi-cli new claude-cli/work

# Launch it
multi-cli launch claude-cli/work

# Or use the shorthand
multi-cli claude-cli/work
```

يحصل كل ملف تعريف على اسم مستعار تلقائي في الصدفة:

| المنصة | الموقع |
|----------|----------|
| macOS / Linux | `~/MultiCliProfiles/bin/` (أضِفه إلى `PATH`) |
| Windows | تُنشأ اختصارات قائمة ابدأ تلقائيًا |

---

## الأوامر

### إدارة ملفات التعريف

| الأمر | الوصف |
|---------|-------------|
| `multi-cli new <tool>/<name>` | إنشاء ملف تعريف حساب (بيانات اعتماد منفصلة وحالة عادية مشتركة) |
| `multi-cli new <tool>/<name> --isolated` | إنشاء ملف جذر كامل بلا حالة مشتركة |
| `multi-cli new <tool>/<name> --shared` | ملف مشترك قديم من schema-v1؛ تشارك ملفات schema-v2 الحالة العادية المعلنة افتراضيًا |
| `multi-cli new <tool>/<name> --from <tpl>` | الإنشاء من قالب محفوظ |
| `multi-cli <tool>/<name>` | تشغيل ملف تعريف (صيغة مختصرة) |
| `multi-cli launch <tool>/<name>` | تشغيل ملف تعريف |
| `multi-cli list [<tool>]` | عرض جميع ملفات التعريف |
| `multi-cli status` | List profiles with their type and disk size |
| `multi-cli clone <tool>/<src> <tool>/<dest>` | نسخ ملف تعريف موجود |
| `multi-cli rename <tool>/<old> <tool>/<new>` | إعادة تسمية ملف تعريف |
| `multi-cli delete <tool>/<name>` | حذف ملف تعريف وجميع بياناته |

### مصادقة الحسابات والترحيل

| الأمر | الوصف |
|---------|-------------|
| `multi-cli auth set <tool>/<profile>` | تخزين بيانات اعتماد السر التشغيلي لملف التعريف في مخزن بيانات الاعتماد الخاص بنظام التشغيل (يسأل تفاعليًا أو يقرأ سطرًا واحدًا من stdin) |
| `multi-cli auth status <tool>/<profile>` | الإبلاغ عما إذا كانت بيانات الاعتماد مخزنة لملف التعريف |
| `multi-cli auth clear <tool>/<profile>` | إزالة بيانات الاعتماد المخزنة |
| `multi-cli migrate <tool>/<name> [--dry-run] [--prefer-profile]` | ترحيل ملف تعريف قديم schema-v1 إلى schema-v2 |

ينطبق `auth` فقط على المحوّلات التي تستخدم آلية `processSecret` ‏(`cursor-cli` و`copilot-cli` و`kimi-cli` و`grok-cli`). يظل التشغيل معطَّلًا حتى يتم تخزين بيانات الاعتماد. راجع [ملفات التعريف القديمة](#legacy-profiles) للاطلاع على `migrate`.

### القوالب

| الأمر | الوصف |
|---------|-------------|
| `multi-cli template save <tool>/<profile> <name>` | حفظ ملف تعريف كقالب قابل لإعادة الاستخدام |
| `multi-cli template list` | عرض القوالب المحفوظة |
| `multi-cli template delete <name>` | إزالة قالب |

### النسخ الاحتياطي والنقل

| الأمر | الوصف |
|---------|-------------|
| `multi-cli export <tool>/<name> [path]` | أرشفة ملف تعريف إلى `.tar.gz` ‏(`.zip` على Windows) |
| `multi-cli import <archive> <tool>/<name>` | استعادة ملف تعريف من أرشيف |

### الجلسات

| الأمر | الوصف |
|---------|-------------|
| `multi-cli continue <tool> <src> <dest>` | نسخ حالة المحادثة (الجلسات/النصوص/السجل) من ملف تعريف إلى آخر — لا تُنسخ بيانات الاعتماد أبدًا |
| `multi-cli continue <tool> <src> <dest> --no-merge` | استبدال ملفات الوجهة بدلًا من الاحتفاظ بالأحدث |
| `multi-cli continue <tool> <src> <dest> --dry-run` | معاينة ما سيتم نسخه دون تغيير أي شيء |

يعمل `base` كاسم ملف تعريف في أي من الطرفين ويعني مجلد المنزل الحقيقي للأداة (`~/.codex` و`~/.claude` و…). مدعوم لـ `codex` و`claude-cli` و`gemini-cli` و`commandcode`. راجع [متابعة محادثة عبر الحسابات](#continue-a-chat-across-accounts).

### الأدوات المساعدة

| الأمر | الوصف |
|---------|-------------|
| `multi-cli tools` | عرض جميع الأدوات المدعومة وحالة تثبيتها |
| `multi-cli stats` | عرض استخدام القرص لكل ملف تعريف |
| `multi-cli doctor` | تشخيص بيئتك |
| `multi-cli completion {bash\|zsh\|powershell}` | إعداد الإكمال التلقائي للصدفة |
| `multi-cli help` | عرض المساعدة |
| `multi-cli version` | عرض الإصدار |

---

## كيف يعمل العزل

تعلن محوّلات schema-v2 عن آلية حساب منفصلة عن الحالة العادية:

| الآلية | كيف تعمل |
|-----------|--------------|
| `fileOverlay` | تبقى بيانات الاعتماد داخل ملف التعريف؛ وترتبط الحالة العادية المعلنة بمنزل الأداة الأصلي المشترك. |
| `processSecret` | تُحقن بيانات اعتماد خاصة بكل ملف تعريف وذات أولوية قصوى في العملية الفرعية فقط. يظل التشغيل معطَّلًا حتى يتم تكوين تخزين آمن للأسرار. |
| `osUserCredentialStore` | تُفصل الهويات الثابتة في سلسلة المفاتيح بمستخدم نظام تشغيل مملوك لـ multi-cli. يظل هذا معطَّلًا حتى يتم التحقق من الملكية والتنظيف. |
| `inseparable` | يدمج المورّد المصادقة والحالة العادية؛ يفشل التشغيل المتوافق بشكل مغلق وتُعرَض المحدودية. |

تحتفظ ملفات تعريف الإصدار 1 بالسلوك السابق ذي الجذر الكامل (`env` و`userDataDir` و`redirectHome` و`appdata` و`sandboxUser`) للتوافق. يحدد كل `<id>/adapter.json` قدرات المنتج/المنصة ومتطلبات الأدلة.

---

<a id="continue-a-chat-across-accounts"></a>

## متابعة محادثة عبر الحسابات

هل بلغت حد المعدل على الحساب A في منتصف محادثة؟ بدّل إلى ملف تعريف مسجَّل الدخول بالحساب B واستأنف المحادثة من حيث توقفت. ينسخ `multi-cli continue` حالة المحادثة القابلة للنقل — الجلسات والنصوص والسجل — بين ملفات التعريف. **لا تُنسخ بيانات الاعتماد أبدًا.**

```bash
# You were working in codex/work (account A) and got rate-limited.
# codex/personal is logged into account B.
multi-cli continue codex work personal          # copy the conversation state
multi-cli continue codex work personal --dry-run  # preview first, if you like

codex-personal                                  # launch account B's profile
codex resume <session-id>                        # resume the same chat (codex ≥ 0.30)
```

شغّل `codex resume` دون وسيطة لفتح منتقي تفاعلي للجلسات السابقة، فلن تحتاج أبدًا إلى البحث عن معرّف. وإذا احتجته، فمعرّف الجلسة هو UUID الموجود في اسم ملف rollout ضمن `sessions/YYYY/MM/DD/`.

`base` اسم ملف تعريف صالح في أي من الطرفين ويشير إلى مجلد المنزل الحقيقي للأداة (`~/.codex` و`~/.claude` و…)، لذا يمكنك المتابعة من تثبيتك الافتراضي أو إليه.

افتراضيًا، يتم **دمج** الملفات — تُحتفظ بالملفات الأحدث في الوجهة. مرّر `--no-merge` لاستبدال الوجهة بدلًا من ذلك، أو `--dry-run` للمعاينة دون تغيير أي شيء.

بعد النسخ، استأنف داخل ملف التعريف الوجهة باستخدام أمر الأداة نفسه:

| الأداة | أمر الاستئناف |
|------|----------------|
| codex | `codex resume <session-id>` ‏(≥ 0.30) |
| claude-cli | `claude --resume <session-id>` (يُشغَّل من نفس مجلد المشروع) |
| gemini-cli | `gemini --resume` (آخر جلسة محفوظة تلقائيًا) أو `/chat resume <tag>` لنقاط التفتيش المحفوظة |
| commandcode | التشغيل من نفس مجلد العمل |

**غير مدعوم:** `opencode` (الجلسات وبيانات الاعتماد في قاعدة بيانات SQLite واحدة مشتركة) و`cursor` (تُخزَّن المحادثات في SQLite مفهرسة بمسار مساحة العمل).

> تُبذَر ملفات تعريف schema-v1 القديمة من `base` افتراضيًا. تقرأ ملفات تعريف حساب schema-v2 المحادثات والإعدادات المعلنة من الجذر الأصلي المشترك، بينما تبدأ الملفات المعزولة فارغة. استخدم `multi-cli continue` لنسخ المحادثات المدعومة إلى ملف معزول أو منه.

---

## أنواع ملفات التعريف

| العلامة | المعنى |
|------|---------|
| *(لا شيء)* | **مشترك افتراضيًا** — بيانات الاعتماد منفصلة، وتُشارك المحادثات والإعدادات عندما يسمح المحوّل. |
| `-i` أو `--isolate` أو `--isolated` | **معزول** — يعيش جذر الأداة كاملًا داخل ملف التعريف ولا يُشارك شيء. |
| `--shared` | اسم قديم للوضع المشترك عندما يدعمه المحوّل. |
| `--cli` | **CLI** — تشغيل من الطرفية فقط. |
| `--from <tpl>` | الاستنساخ من قالب محفوظ. |

---

## متغيرات البيئة

| المتغير | الافتراضي | الغرض |
|----------|---------|---------|
| `MULTICLI_HOME` | `~/MultiCliProfiles` | مكان تخزين جميع ملفات التعريف |
| `MULTICLI_OVERRIDE_BINARY` | *(غير معيَّن)* | فرض مسار ثنائي محدد للتشغيل التالي |
| `MULTICLI_REPO` | *(غير معيَّن)* | رابط Git للتثبيت عن بُعد |
| `MULTICLI_PLATFORM` | *(تلقائي)* | تجاوز كشف المنصة (`darwin` و`linux`) |

---

<a id="legacy-profiles"></a>

## ملفات التعريف القديمة

ملفات التعريف التي أُنشئت قبل schema-v2 هي ملفات تعريف قديمة ذات جذر كامل: تحتفظ بالسلوك السابق لـ `env` و`userDataDir` و`redirectHome` و`appdata` و`sandboxUser` للتوافق. يُعامَل مجلد ملف التعريف الذي لا يحتوي على ملف `.profile.json` كملف قديم.

يحوّل `multi-cli migrate <tool>/<name>` ملف التعريف القديم إلى schema-v2: تنتقل بيانات الاعتماد المعلنة إلى ملف التعريف، وترتبط الحالة العادية المعلنة بمنزل الأداة المشترك. استخدم `--dry-run` لمعاينة خطة النقل دون تغيير أي شيء، و`--prefer-profile` لاستبدال الملفات المشتركة المتعارضة بنسخة ملف التعريف — لا تُستبدَل أهداف بيانات الاعتماد أبدًا. يجب أن يكون تخزين ملفات التعريف وجذر الحالة المشتركة على نفس وحدة التخزين، لأن الترحيل يستخدم نقلًا ذريًا ضمن نفس وحدة التخزين.

---

## التشخيص

```bash
multi-cli doctor
```

يتحقق من وجود تخزين ملفات التعريف، وأن مجلد الأسماء المستعارة موجود في PATH، وأن ثنائي كل أداة مكتشَف (أو يعرض تلميح تثبيت).

---

## الإكمال التلقائي للصدفة

```bash
multi-cli completion bash   # or zsh, powershell
```

اتبع التعليمات لإضافته إلى `.zshrc` أو `.bashrc` أو `$PROFILE` في PowerShell.

---

## إلغاء التثبيت

**macOS / Linux**

```bash
curl -fsSL https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.sh | bash
```

**Windows**

```powershell
irm https://raw.githubusercontent.com/Spielewoy/multi-cli/main/scripts/uninstall.ps1 | iex
```

سُتسأل عمّا إذا كنت تريد إزالة بيانات ملفات التعريف — لا يُحذَف أي شيء دون تأكيد.

---

## روابط

- [مصفوفة الدعم](docs/support-matrix.md) — حالة العزل لكل منتج ونظام تشغيل وبوابة التحقق
- [سياسة الأمان](SECURITY.md)
- [الرخصة](LICENSE)
- [مستودع GitHub](https://github.com/Spielewoy/multi-cli)

---

## شكر وتقدير

- **المؤلف** — [Spielewoy](https://github.com/Spielewoy)

---

<a id="license"></a>

## الرخصة

[MIT](LICENSE)

</div>
