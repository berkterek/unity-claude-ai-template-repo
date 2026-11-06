<!-- source: nile_bounce_legion_repo working tree, read at 12bb3911 (file untracked there) -->
Read at: 12bb3911

Base `S` = `BounceLegion/Assets/_GameFolders/Scripts/Games`. Line ranges are hints at `12bb3911`; the symbol is the reference.

| Task(s) | File (repo-relative) | Symbol | Lines (hint) | Why it matters |
|---|---|---|---|---|
| T001, T023d | `S/Concretes/Lobby/Lobby.asmdef` | `references` | 4-27 | Has no `PowerAbstracts`; T001 adds it |
| T002, T007 | `S/Concretes/GameHub/Controllers/CardController.cs` | `Damage`, `HitsPerShot`, `OnStatsChanged` | 61-67 | Inputs the total reads; `DealsDamage` goes next to `HitsPerShot` |
| T007 | `S/Concretes/GameHub/Controllers/CardController.cs` | `GetTriggerZones(List<Rect>)` | 297-309 | Clears the list; empty when `_triggers` is null (EditMode cards) |
| T006, T007 | `S/Concretes/GameHub/Controllers/CardController.cs` | `OnEnable`, `OnDisable`, `Init(ICardService)` | 102-129, 445-450 | Where cards enter/leave `CardsOnGame` (slot cards included) |
| T003 | `S/Concretes/GameHub/Controllers/DamageableCardController.cs` | `DamageableCardController` fields | 13-24 | Override `DealsDamage` after `_buffState` |
| T006 | `S/Concretes/GameHub/Controllers/PassiveCardController.cs` | `PassiveCardController` | 3 | Base of coin/heal/speed/direction cards; keeps `DealsDamage` false |
| T005, T006, T007 | `S/Concretes/GameHub/Abstracts/Services/ICardService.cs` | `ICardService.CardsOnGame` | 23 | The list the total iterates; substitute in T006 |
| T007, T008 | `S/Concretes/GameHub/Managers/CardManager.cs` | `CardsOnGame`, `AddCardToList`, `RemoveCardFromList` | 39, 195-208 | Production list; removal happens before `Destroy` |
| T004, T006, T007 | `S/Abstracts/Power/ISoldierDpsService.cs` | `Revision`, `TryGetExpectedDps` | 9-24 | Recompute trigger and per-card DPS |
| T007 | `S/Concretes/Power/SoldierDpsLabelView.cs` | `Refresh` | 43-48 | Same three inputs per card; must stay untouched |
| T008, T018 | `S/Concretes/Power/PowerModule.cs` | `PowerModule.Install(IContainerBuilder)` | 9-13 | Gains one line (T008) and an `InstallApp` sibling (T018) |
| T008 | `S/Concretes/Infrastructure/SceneModules.cs` | `InstallGame` (module 12 line) | 29-30 | Existing caller of `PowerModule.Install`; unchanged |
| T008, T011 | `S/Concretes/Infrastructure/GameScope.cs` | `RegisterComponentInHierarchy<CardManager>` | 59 | Source of `ICardService` in the Game scope |
| T011 | `S/Concretes/Infrastructure/GameScope.cs` | `RegisterComponentInHierarchy<XpLevelView>`, `SceneModules.InstallGame(builder)` | 150, 196-199 | Pattern for a scene-placed HUD view; insert before `InstallGame` |
| T009 | `S/Concretes/GameHub/Uis/InGameCoinView.cs` | `InGameCoinView` | 7-48 | Existing Game HUD view (TMP `_displayText`) |
| T010 | `BounceLegion/Assets/_Scenes/Game.unity` | `InGameCanvas`, `InGameCoinObject`, `InGameCoinDisplayText` | 6759, 8624, 19217 | HUD host and font/style source for `TotalPowerObject` |
| T012, T014, T017 | `S/Concretes/LevelRewards/LevelRewardChapterEntry.cs` | `LevelRewardChapterEntry` | 7-22 | Row shape to copy |
| T014, T020 | `S/Concretes/LevelRewards/LevelRewardConfiguration.cs` | `_chapters`, `Chapters` | 13-22 | Config shape to copy; T020 sizes rows from its asset |
| T017 | `S/Concretes/LevelRewards/ChapterRewardPreviewService.cs` | `GetForChapter` | 27-45 | Clamp + warning pattern |
| T016 | `BounceLegion/Assets/_GameFolders/Scripts/Tests/BounceLegionEditModeTest/ChapterRewardPreviewServiceTests.cs` | `BuildConfig`, `TearDown` | 22-35 | Config-building test pattern |
| T018, T022 | `S/Concretes/LevelRewards/LevelRewardModule.cs` | `Install`, `InstallGameScene` | 13-34 | App + scene install split precedent |
| T019, T021 | `S/Concretes/Infrastructure/ConfigCatalog.cs` | fields, properties, `Validate` | 18-60 | New field + property + null check |
| T021 | `BounceLegion/Assets/_GameFolders/Prefabs/Bootstrap/ConfigCatalog.asset` | `_powerConfig` (new) | — | Asset to assign |
| T022 | `S/Concretes/Infrastructure/AppModules.cs` | `AppModules.Install` | 17-33 | Insert after `PowerUpModule.Install` (31) |
| T023a | `BounceLegion/Assets/_GameFolders/Scripts/Tests/BounceLegionEditModeTest/BattleTabViewModelTests.cs` | `SetUp`, `Create` | 31-55 | 7th ctor arg; level stub chapter 2 / level 4 |
| T023b | `S/Abstracts/Lobby/IBattleTabViewModel.cs` | `IBattleTabViewModel` | 7-46 | Add `RecommendedPowerText` after `BossReward` |
| T023c | `S/Concretes/Lobby/BattleTabViewModel.cs` | constructor, `ChapterText`, `StageText`, `BossReward` | 35-60 | Ctor gains a param; computed-on-access pattern |
| T023d | `S/Concretes/Lobby/LobbyModule.cs` | `InstallMenu` → `RegisterFactory<IBattleTabViewModel>` | 41-44 | Factory gains `c.Resolve<IRecommendedPowerService>()` |
| T028 | `BounceLegion/Assets/_GameFolders/UI/Screens/Lobby/Lobby.uxml` | `panel-battle` → `boss-reward`, `next-unlock` | 10-39 | Insertion point for `recommended-power` |
| T026, T027 | `BounceLegion/Assets/_GameFolders/UI/Screens/Lobby/Lobby.uss` | `.next-unlock*` battle block | 263-590 | Style block / token family to follow |
| T029 | `BounceLegion/Assets/_GameFolders/Scripts/Tests/BounceLegionPlayModeTest/BattleTabViewTests.cs` | `LOBBY_UXML_PATH`, substitute view model | 25, 324-347 | Test pattern with real `Lobby.uxml` |
| T030 | `S/Concretes/Lobby/BattleTabView.cs` | `OnEnable`, `BindReward` | 55-101, 249-261 | Required-element check and show/hide shape |
| T031 | `S/Concretes/Lobby/ARCHITECTURE.md` | `## Boundary` | 6-10 | Add the recommended-power line |
| T032 | `S/Concretes/Power/ARCHITECTURE.md` | `## Boundary` | 6-10 | "Never sums … module 13 owns that" and "never a HUD element" become false |
