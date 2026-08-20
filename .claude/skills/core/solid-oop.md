---
name: solid-oop
description: SOLID & OOP rules — the Card 0 MonoBehaviour gate, the four MonoBehaviour roles (View/Provider/Controller/Manager), the 4-tier architecture (Mono Shell / Handler / Service+EntryPoint / Provider), SRP one-sentence test, OCP polymorphism, DIP constructor-interface rule. Use when writing code, designing a class, or adding logic to a MonoBehaviour.
model-tier: normal
---

# SOLID & OOP Rules (NON-NEGOTIABLE)

> **`.claude/rules/solid-oop.md` is the authority.** Read it before designing a class — this skill is the short form; the rule file carries the cards, the worked N-enemies example, the Handler/Controller listings and the EntryPoint table. On any conflict, the rule file wins.

## Card 0 — the first question, always

Before writing any class: **does this need to be a MonoBehaviour?** It may be one only if at least one holds:

| Justification | Example |
|---|---|
| (a) Caches scene/prefab references via `[SerializeField]` | Controller shell |
| (b) Receives Unity callbacks (collision, trigger, UGUI events) | Controller, View |
| (c) Cross-module Unity API boundary | Provider |
| (d) Canvas UI | View |

**"I need Update" is not a valid reason.** A pure C# service that needs a frame tick exposes `Tick(float deltaTime)` and its domain's Mono shell forwards Unity's callback into it. `ITickable` / `IFixedTickable` are **not used in this project** — VContainer publishes no ordering guarantee against `MonoBehaviour.Update`, so a container-driven tick is correct only by accident of PlayerLoop insertion order.

Enforcement is **structural, not name-based**: `check-no-monobehaviour-in-services.sh` judges a class by whether it has its own `[SerializeField]` or a Unity lifecycle callback — the suffix documents the role, it is not what the hook checks.

## The four MonoBehaviour roles

| Role | Suffix | Does | Does NOT |
|---|---|---|---|
| **View** | `*View` | Canvas/UI only — updates UI, reads input events, triggers animation | Business logic, calculation, state |
| **Provider** | `*Provider` | Wraps one Unity API group on behalf of a Service | Service coordination, event publishing |
| **Controller** | `*Controller` | Gameplay/character shell — caches refs, builds Handlers, forwards lifecycle. Zero branching | Game logic, publishing IEventBus |
| **Manager** | `*Manager` | Single-domain registry — Register/Unregister across N sibling instances | Span more than one domain (no `GameManager`) |

`*Handler` and `*Service` are **never** MonoBehaviours. A `MoveHandler : MonoBehaviour` is a violation.

## The 4 tiers

```
Tier 1  Mono Shell (Controller/View)  ≤ ~80 lines, forwards only, no state fields
Tier 2  Handler                       pure C#, prefab-local, Unity refs via constructor, always I*Handler
Tier 3  Service + EntryPoint          pure C#, no UnityEngine API (math types and Debug allowed), interface-first
Tier 4  Provider                      cross-module Unity API boundary — not for prefab-local access
```

A Handler may not be referenced from outside its prefab; when a second consumer appears, promote it to a Service.

## SRP / OCP / DIP

- **SRP:** every class describable in one sentence, and that sentence must not contain `AND`. "PlayerService calculates movement AND updates score AND publishes events" is three classes.
- **OCP:** an `if/else if` chain on type is almost always a violation — use polymorphism. New enemy = new class, existing code untouched.
- **DIP:** constructors take interfaces only. The one intended exception is a Handler receiving Unity component refs (`Rigidbody`, `Transform`) by design.

## Interface scope

Handler, Service and Provider **always** get an interface — the test suite is the second caller. Controller shells, Views, config ScriptableObjects, event structs and models do not. The one-caller rule postpones **module ceremony**, never the interface.

Full cards, the worked example and the forbidden-patterns table: `.claude/rules/solid-oop.md`.
