# Plan Summary Skill & Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `/plan-summary <file>` command — a standalone skill that reads a plan file and produces a fixed 3-section human-readable summary to align intent before execution.

**Architecture:** A skill file defines the behavior; a command entry in `commands.md` exposes it as a slash command; no agents are spawned, no source code is read, no gate is added.

**Tech Stack:** Markdown skill definition, Claude Code slash command convention.

## Global Constraints

- Skill reads ONLY the plan file argument — no source code file reads
- No agent spawning
- No gate / approval wait
- No modification to the plan file
- Output must follow the exact 3-section format defined in the spec
- Error messages must be in Turkish (matching project convention)

---

### Task 1: Create plan-summary skill file

**Files:**
- Create: `.claude/skills/core/plan-summary.md`

**Interfaces:**
- Produces: skill invocable via `Skill` tool with name `plan-summary`

- [ ] **Step 1: Create the skill file**

Create `.claude/skills/core/plan-summary.md` with this exact content:

```markdown
---
name: plan-summary
description: Plan dosyasını okuyup 3 bölümlü insan dilinde özet üretir — ne yapıyoruz, nasıl, sonunda ne görürüz. Gate yok, agent spawn yok.
---

# Plan Summary

Verilen plan dosyasını okuyup sabit 3 bölümlü özet üret. Bu skill'i çalıştırmak demek:

1. `<file>` parametresini oku
2. Dosya yoksa: `"Dosya bulunamadı: <path>. Önce /create-plan çalıştırın."` yaz ve dur
3. Dosyada task yoksa: `"Plan dosyası task içermiyor. /update-plan ile içerik ekleyin."` yaz ve dur
4. Aşağıdaki formatta özet üret — başka bir şey yazma

## Çıktı Formatı (değiştirme)

```
## Plan Özeti — <dosya adı>

### Ne yapıyoruz?
[1-2 cümle. Projenin hangi parçasına dokunuyoruz ve amacı ne. Teknik detay değil.]

### Nasıl yapıyoruz?
[Bullet list. Her task için 1 satır, insan dilinde. "AudioInstaller'a Register<T> ekle" değil → "Ses sistemi bağımlılık enjeksiyonuna bağlanacak".]

### Sonunda ne göreceğiz?
[Observable çıktılar. Her madde gözlemlenebilir bir sonuç. "kod yazılacak" değil → "Oyunu çalıştırdığında ses duyulacak". Format: "X çalışacak / Y Inspector'da görünecek / Z testi geçecek".]
```

## Kurallar

- Sadece plan dosyasını oku — kaynak kod dosyalarını açma
- Özet bölümlerinin dışına hiçbir şey yazma (giriş cümlesi, açıklama, öneri yok)
- Sonuç bölümündeki her madde mutlaka gözlemlenebilir olmalı
- Tone: sade Türkçe, teknik jargon minimum
```

- [ ] **Step 2: Verify the file was created correctly**

```bash
cat .claude/skills/core/plan-summary.md
```

Expected: file content printed, frontmatter `name: plan-summary` visible.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/core/plan-summary.md
git commit -m "feat(skills): add plan-summary skill for pre-execution alignment"
```

---

### Task 2: Register command in commands.md

**Files:**
- Modify: `.claude/docs/commands.md` — add `/plan-summary` entry under "Session & Context"

**Interfaces:**
- Consumes: skill file from Task 1 (name: `plan-summary`)
- Produces: `/plan-summary` slash command visible in commands reference

- [ ] **Step 1: Add the command entry**

In `.claude/docs/commands.md`, find the `### Session & Context` section. Add this line after `/dry-run`:

```
- `/plan-summary <file>` — Plan dosyasını okur ve 3 bölümlü özet üretir: ne yapıyoruz, nasıl yapıyoruz, sonunda ne göreceğiz. `/orchestrate` veya `/implement` öncesinde planın beklentinizle örtüştüğünü doğrulamak için kullanın.
```

- [ ] **Step 2: Verify placement**

```bash
grep -A 2 "plan-summary" .claude/docs/commands.md
```

Expected: the new line appears under `### Session & Context`.

- [ ] **Step 3: Commit**

```bash
git add .claude/docs/commands.md
git commit -m "docs(commands): register /plan-summary slash command"
```

---

### Task 3: Add hint lines to /create-plan and /update-plan entries

**Files:**
- Modify: `.claude/docs/commands.md` — append hint to `/create-plan` and `/update-plan` entries

**Interfaces:**
- Consumes: existing `/create-plan` and `/update-plan` lines in commands.md

- [ ] **Step 1: Locate the lines**

```bash
grep -n "create-plan\|update-plan" .claude/docs/commands.md | head -10
```

Note the line numbers.

- [ ] **Step 2: Add hint to /create-plan entry**

Find the `/create-plan <file> <what>` line. Append at the end of that line (before the newline):

```
 Plan hazır olduğunda `/plan-summary <file>` ile özet alabilirsiniz.
```

Full result should look like:
```
- `/create-plan <file> <what>` — researcher → **complexity-aware planner** ... Plan hazır olduğunda `/plan-summary <file>` ile özet alabilirsiniz.
```

- [ ] **Step 3: Add hint to /update-plan entry**

Same append to the `/update-plan <file> <change>` line:

```
 Plan güncellendikten sonra `/plan-summary <file>` ile özet alabilirsiniz.
```

- [ ] **Step 4: Verify**

```bash
grep "plan-summary" .claude/docs/commands.md
```

Expected: 3 lines — the new command entry + hint on create-plan + hint on update-plan.

- [ ] **Step 5: Commit**

```bash
git add .claude/docs/commands.md
git commit -m "docs(commands): add plan-summary hints to create-plan and update-plan"
```

---

### Task 4: Smoke test the skill

**Files:**
- No new files — manual invocation test

- [ ] **Step 1: Invoke with the spec file as a quick test target**

In the Claude Code session, run:

```
/plan-summary docs/superpowers/specs/2026-06-17-plan-summary-design.md
```

Expected output structure:
```
## Plan Özeti — 2026-06-17-plan-summary-design.md

### Ne yapıyoruz?
...

### Nasıl yapıyoruz?
- ...

### Sonunda ne göreceğiz?
- ...
```

- [ ] **Step 2: Test error case — missing file**

```
/plan-summary docs/nonexistent.md
```

Expected: `"Dosya bulunamadı: docs/nonexistent.md. Önce /create-plan çalıştırın."`

- [ ] **Step 3: Confirm and done**

If both outputs match expectations, implementation is complete.
