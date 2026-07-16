# pubsub_realworld fixtures — expected extraction facts

Each `.cs` file here is a minimal, self-contained snippet stripped from a real
call shape found in `Assets/_GameFolders`
(harvested once, per Grill decision D2 — see
`Docs/PLAN_graph_extractor_pubsub_and_viz.md`). None of these fixtures depend
on the external repo at test run time; they are committed here and asserted
against directly by `test_extractor_pubsub.py`.

| Fixture | Real source (harvested from) | Expected facts |
|---|---|---|
| `SettingsPanel.cs` | `Scripts/Games/Concretes/UI/SettingsPanel.cs` | `classes[0].events_subscribed == ["SettingsOpenedEvent", "SettingsClosedEvent"]` (any order); `classes[0].events_published == ["SettingsClosedEvent"]`. Covers null-conditional (`_eventBus?.`) generic Subscribe and null-conditional non-generic Publish. |
| `UpgradeService.cs` | `Scripts/Games/Concretes/Economy/UpgradeService.cs` | `classes[0].events_published == ["UpgradePurchasedEvent", "UpgradePurchasedEvent"]` — two non-generic (type-inferred) publish call sites in one class, both must resolve. |
| `AudioModule.cs` | `Scripts/Games/Concretes/Audio/AudioModule.cs` | `vcontainer.installers[0].registrations` has exactly 2 entries: `{"type": "AudioConfiguration"}` (from `builder.RegisterInstance(config)`, resolved via the `Install` method's own `AudioConfiguration config` parameter) and `{"type": "AudioService"}` (from `builder.Register<AudioService>(Lifetime.Singleton)` — the chained `.AsSelf().As<IAudioService>()` calls must NOT add extra registrations). |
| `RunSummaryView.cs` | `Scripts/Games/Concretes/UI/RunSummaryView.cs` | `classes[0].events_published` (sorted) `== ["ContinueButtonPressedEvent", "GoldChangedEvent"]` — covers a null-conditional publish whose event constructor argument is itself a member access (`_walletService.CommittedGold`), which must not confuse event-type resolution. |

## Pre-fix vs post-fix behavior

Before Task 1's AST fix, `_detect_vcontainer` regexes only the **generic**
call form (`\w+\.(Publish|Subscribe|Unsubscribe)<T>`) and explicitly skips
`RegisterInstance(var)`. Against these fixtures that means:

- `SettingsPanel.cs` — subscribes resolve (already generic), **publish does
  not** (non-generic, plus null-conditional changes the AST shape further).
- `UpgradeService.cs` — **neither** publish resolves (both non-generic).
- `AudioModule.cs` — only the `Register<AudioService>` half resolves;
  `RegisterInstance(config)` is silently dropped, so today's registrations
  list has length 1, not 2.
- `RunSummaryView.cs` — **neither** publish resolves.

After the fix, all four fixtures assert exactly as documented above.
