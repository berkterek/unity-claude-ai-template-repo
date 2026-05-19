# /fix-codex — Codex-Driven Fix Pipeline

**Pipeline:** Codex Analysis → Human Gate → Codex Implementation → Codex Review → Committer

## Usage

```
/fix-codex <bug description>
/fix-codex --files GameManager.cs,LevelController.cs "items drop etmiyor"
```

If no argument is given, ask: "Describe the bug. Include any error messages, stack traces, and reproduction steps."

## When to use

| Command | Use when |
|---------|----------|
| `/fix` | Stack trace net, dosyalar küçük (<500 satır), root cause açık |
| `/fix-deep` | Logic bug, "bazen oluyor", kaynak belirsiz |
| `/fix-codex` | Legacy/büyük codebase (2000+ satır dosyalar), `/fix` veya `/fix-deep` takıldıysa, 30+ dakika sarman içindeysen — Codex kodu hipotez kurmadan direkt okur |

> **Neden fix-codex farklı?** Claude Code analiz sırasında bir hipotez kurar ve sonraki okumalarda o hipotezi doğrular. `/clear` + yeniden başlamak bile aynı dosyaları aynı sırayla okuyunca aynı yanlış sonuca varabilir. Codex bu önyargı olmadan kodu literal olarak takip eder.

---

## Step 0 — Plugin Preflight

`codex:codex-rescue` skill'inin mevcut olduğunu kontrol et. Yoksa dur ve kullanıcıya `/codex:setup` çalıştırmasını söyle.

---

## Step 1 — Codex Analysis Pass

Codex'e kodu direkt analiz ettir. Claude bu aşamada **hiçbir ön analiz yapmamalı** — dosya okuma, hipotez kurma, "muhtemelen şu dosya" deme yok. Codex fresh eyes ile başlar.

`--files` argümanı verilmişse o dosyaları Codex'e pinle. Verilmemişse Codex kendi bulur.

`codex:codex-rescue` skill'ini şu prompt ile çağır:

```
TASK: Analysis only — do NOT fix yet.

BUG: <kullanıcının tam tanımı>
REPRODUCTION: <nasıl tetikleniyor>
FILES (if specified): <--files argümanı varsa listele, yoksa "discover yourself">

Read the codebase directly. Trace the execution path from the symptom backward to the root cause.
Do NOT form a hypothesis first — read the code literally and follow the data/call flow.

Report:
1. ROOT CAUSE: exact file + line number + what is wrong
2. WHY: why this causes the reported symptom (execution trace)
3. AFFECTED SCOPE: what else might be affected by the fix
4. FIX APPROACH: what should change and why (do not implement yet)
```

Codex'in analiz çıktısını kullanıcıya göster.

---

## Step 2 — Human Gate

Codex'in analizini kullanıcıya göster:

```
CODEX ANALİZİ
=============
Root Cause: <dosya:satır — ne yanlış>
Neden bu semptomu yaratıyor: <execution trace>
Etkilenen kapsam: <başka ne etkilenebilir>
Önerilen fix: <ne değişmeli>

Devam mı? (go / yönlendir)
```

Kullanıcı `go` derse Step 3'e geç.
Yönlendirme gelirse (ör. "hayır, asıl sorun X") → Codex'e düzeltilmiş bilgiyle yeniden Step 1'e dön.

---

## Step 3 — Codex Implementation

Aynı Codex analiz bağlamını kullanarak implementasyona geç. Çeviri kaybı olmaması için analizi yapan Codex implement de eder.

`codex:codex-rescue` skill'ini şu prompt ile çağır:

```
TASK: Implement the fix based on your previous analysis.

ROOT CAUSE CONFIRMED: <Step 1 çıktısından root cause>
FIX APPROACH CONFIRMED: <Step 1 çıktısından fix yaklaşımı>

Now implement the fix. Fix at root cause — not at symptom.

PROJECT RULES (non-negotiable):
- Dependency injection: VContainer only. No singletons, no FindObjectOfType, no static mutable state.
- Async: UniTask only. No coroutines, no async Task.
- Input: New Input System only. No Input.GetKey / Input.GetAxis.
- Events: IEventBus for cross-module. C# event for intra-module. UnityEvent forbidden.
- MonoBehaviour components: assigned via [SerializeField] in Inspector, not GetComponent in Awake.
- Sealed classes by default.
- No LINQ in gameplay code.
- Unity null check: use == null, not is null or ?. on UnityEngine.Object types.

After implementing, verify: does the fix address the root cause, not just suppress the symptom?
```

---

## Step 4 — Codex Review

Implementasyondan sonra **ayrı bir Codex çağrısı** ile review yap. Bu fresh eyes ile yapılır — implementasyonu yapan Codex'ten bağımsız.

`codex:codex-rescue` skill'ini şu prompt ile çağır:

```
TASK: Review the fix — do NOT make changes.

ORIGINAL BUG: <kullanıcının tanımı>
CLAIMED ROOT CAUSE: <Step 1'den root cause>
CHANGED FILES: <implementasyonda değişen dosyalar>

Review the changes and answer:
1. CORRECT LOCATION? Was the fix applied to the actual root cause location, or a symptom?
2. ROOT CAUSE UNDERSTOOD? Does the fix address why the bug occurs, not just what it produces?
3. COMPLETE? Are there edge cases or related paths that also need fixing?
4. ARCHITECTURE: Any VContainer / UniTask / Input / event rule violations introduced?
5. VERDICT: APPROVED / NEEDS REVISION

If NEEDS REVISION: list exactly what must change (file + line + reason).
```

**APPROVED → Step 5.**
**NEEDS REVISION → Codex'e revision prompt ile geri dön (max 2 iteration). Hâlâ çözülmezse kullanıcıya rapor et.**

---

## Step 5 — Committer

Review APPROVED ise committer agent'ı çalıştır. Commit mesajı şu formatı takip eder:

```
fix(<scope>): <root cause'u çözen kısa açıklama>

Root cause: <tek cümle>
```

---

## Output Format

Review APPROVED olduğunda:

```
ROOT CAUSE: <dosya:satır — ne yanlıştı>
FIX: <ne değişti ve neden>
CODEX REVIEW: APPROVED
COMMIT: <hash> — <mesaj>
```

Revision loop sonunda çözülemezse:

```
ROOT CAUSE: <Codex'in bulduğu>
FIX APPLIED: <ne değişti>
REVIEW VERDICT: NEEDS REVISION
REMAINING ISSUES: <dosya:satır listesi>
NEXT STEP: Manuel olarak belirtilen satırları düzelt
```
