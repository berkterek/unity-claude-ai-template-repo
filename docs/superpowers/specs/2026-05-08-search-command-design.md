# /search Command Design

**Date:** 2026-05-08  
**Status:** Approved

---

## Purpose

A research pipeline that investigates any query (bug, architectural question, codebase exploration) using multiple agents, then validates findings with a reviewer before presenting results to the user.

---

## Usage

```
/search <query>
/search "AudioService inject olmuyor"
/search "EnemyMoveSystem bazen çalışmıyor"
/search "bu projede event bus nasıl kullanılmış"
```

---

## Pipeline

```
/search <query>
    ↓
[Phase 1] Research
    - Explore agent      → codebase tarama, dosya okuma, pattern analizi
    - unity-scout agent  → Unity-spesifik risk, lifecycle, ECS, DI sorunları
    - Web search         → Unity docs, bilinen bug'lar (opsiyonel, query'e göre)
    → Çıktı: ROOT_CAUSE + PROPOSED_SOLUTION

    ↓
[Phase 2] Review
    - unity-reviewer agent
    → Soruları: Sorun gerçekten bu mu? Çözüm mimari kurallara uygun mu?
    → APPROVED veya MISMATCH kararı + gerekçe

    ↓ MISMATCH (max 5 iterasyon)
    → Research'e geri dön, reviewer feedback'i eklenmiş prompt ile

    ↓ APPROVED
[Phase 3] Present to User
    PROBLEM:     [ne bulundu, hangi dosya/satır]
    SOLUTION:    [ne yapılmalı]
    CONFIDENCE:  [APPROVED - N. iterasyonda]
    NEXT:        [önerilen komut: /fix, /fix-deep, /implement]
```

---

## Iteration Loop

- Her iterasyonda research agent, bir önceki reviewer feedback'ini alır.
- Araştırma kapsamını genişletir veya derinleştirir.
- **5. iterasyonda hâlâ MISMATCH** → pipeline durur:
  ```
  INCONCLUSIVE: 5 iterasyon sonunda kesin sonuç bulunamadı.
  BEST_GUESS: [en son research bulguları ham halde]
  REVIEWER_CONCERN: [reviewer'ın çözümlenmemiş itirazı]
  ```

---

## Research Agent Prompt Template

```
You are a research agent investigating the following query in a Unity project.

QUERY: $QUERY
ITERATION: $N / 5
PREVIOUS_REVIEWER_FEEDBACK: $FEEDBACK  (empty on first iteration)

## Instructions

1. Use Explore agent to scan the codebase for relevant files, patterns, and dependencies.
2. Use unity-scout to identify Unity-specific risks (lifecycle, VContainer, ECS, UniTask, Input).
3. If the query involves a known Unity API, package, or error pattern — use web search for Unity docs or known issues.

## Output Format (REQUIRED)

ROOT_CAUSE: [one sentence — what is the actual problem or answer]
EVIDENCE:
  - [file:line or pattern that supports the root cause]
  - [...]
PROPOSED_SOLUTION: [concrete steps to fix or address]
CONFIDENCE: low | medium | high
```

---

## Reviewer Agent Prompt Template

```
You are a code reviewer validating a research finding in a Unity project.

ORIGINAL_QUERY: $QUERY
ROOT_CAUSE: $ROOT_CAUSE
EVIDENCE: $EVIDENCE
PROPOSED_SOLUTION: $PROPOSED_SOLUTION

## Your Job

1. Is ROOT_CAUSE plausible given the EVIDENCE? Does the evidence actually support the claim?
2. Is PROPOSED_SOLUTION consistent with the project's architecture rules?
   - No singletons, no coroutines, no legacy Input, VContainer DI, UniTask async, IEventBus for cross-module comms
3. Does PROPOSED_SOLUTION fully address ROOT_CAUSE, or does it only fix a symptom?

## Output Format (REQUIRED)

VERDICT: APPROVED | MISMATCH
REASON: [one sentence explaining the verdict]
FEEDBACK_FOR_RESEARCH: [if MISMATCH — specific gap or contradiction the research agent must address next iteration]
```

---

## Final Presentation Format (APPROVED)

```
SEARCH COMPLETE ✓ (approved in N iteration(s))

PROBLEM
  [root cause — one clear sentence]
  Files: [relevant file paths]

SOLUTION
  [concrete steps]

NEXT STEPS
  → /fix <description>          (if it's a bug with clear root cause)
  → /fix-deep <description>     (if it's a complex or intermittent bug)
  → /implement <description>    (if it's a missing feature or refactor)
  → no action needed            (if it was a pure exploration query)
```

---

## Constraints

- Web search is only used when the query involves a Unity API, package version, or error message that benefits from external docs.
- Research agent never modifies files — read-only.
- Reviewer agent never modifies files — evaluation only.
- Pipeline never auto-fixes — it stops at APPROVED and lets the user decide the next step.
