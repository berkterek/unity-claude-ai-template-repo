# Unity Engine Reference — Version Info

**Engine:** Unity 6 LTS (6000.0.x)
**LLM Training Cutoff:** August 2025
**Post-Cutoff Risk Level:** Low — Unity 6 LTS was released before cutoff, core APIs are stable.

## Risk Assessment

| Area | Risk | Notes |
|------|------|-------|
| URP core APIs | Low | Stable since Unity 2022 LTS |
| DOTS/ECS | Medium | Rapid iteration; verify IJobEntity, SystemAPI patterns |
| UI Toolkit | Medium | Actively evolving; verify runtime UI binding APIs |
| Addressables | Low | Stable since 1.19+ |
| Netcode for GameObjects | Medium | 1.x → 2.x had breaking changes; verify version |
| Input System | Low | Stable since 1.5+ |
| Physics | Low | Core PhysX unchanged |
| Burst / Job System | Low | Stable, but verify latest NativeContainer types |

## How to Use This File

Before any architectural decision touching Unity APIs:
1. Check the risk level for the area
2. If Medium or High: read `breaking-changes.md` and `current-best-practices.md`
3. Apply gate `TD-UNITY-RISK` from `.claude/docs/director-gates.md`
4. Stamp TDD decisions with: `> Engine: Unity 6 LTS — risk assessed via TD-UNITY-RISK`
