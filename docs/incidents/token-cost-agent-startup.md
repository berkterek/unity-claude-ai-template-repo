# Token maliyeti: şişen oturumlar, agent başlangıç bedeli ve 5 dakikalık cache

Tarih: 2026-10-20 · Claude Code 2.1.304 · Durum: **araştırıldı, düzeltme uygulanmadı** · Kapsam: bu repo ve `match-block`

## Özet

Token harcaması üç kaynaktan geliyor. Hiçbiri tek başına "bug" değil; ikisi tasarım, biri Claude Code'un bilinen ve açık bir davranışı.

1. **Ana oturumlar şişiyor.** Çağrı başına ortalama bağlam ~285k (bu repo) ve ~329k (match-block). Her istekte konuşmanın tamamı yeniden gönderiliyor.
2. **Her agent ~61-70k token yazarak başlıyor**, tek satırlık doküman düzeltmesi için bile. Sebep: özel agent'lar CLAUDE.md hiyerarşisinin tamamını (rule'lar dahil, ~58k) yüklüyor. match-block'ta 184 agent çalışmış, maliyetin ~%47'si agent tarafında.
3. **Agent'lar 5 dakikalık prompt cache kullanıyor, ana oturum 1 saatlik.** Bir agent 5 dakikadan uzun beklerse (uzun Bash, Unity derleme/test, yavaş yanıt) bütün bağlamı yeniden yazıyor. GitHub'da açık issue'larla birebir aynı imza.

Disk kullanımıyla (Claude uygulamasının Storage ekranındaki 11.9 GB, çoğu Cowork VM imajı) ilgisi yok.

## Yöntem

`~/.claude/projects/<proje>/` altındaki transcript'ler okundu: ana oturumlar `*.jsonl`, agent'lar `<oturum>/subagents/*.jsonl`. `usage` alanları (`input`, `output`, `cache_creation_input`, `cache_read_input`, `cache_creation.ephemeral_5m/1h`) toplandı, `message.id` ile tekilleştirildi. Agent tipi `*.meta.json` → `agentType`.

Maliyet eşdeğeri için yaklaşık ağırlıklar: cache read 0.1×, cache write 1.25×, input 1×, output 5×. Oranlar yön gösterir, fatura değildir. Sadece diskte kalan transcript'ler sayıldı (Claude Code 30 günden eskileri siler); başka repolar dahil değil.

## Bulgu 1: Sabit yük = memory

`/context` (1M pencere): memory 58.1k, system tools 17.5k, skills 9.9k, custom agents 3.7k, system prompt 2.4k, MCP instructions 1.4k, **messages 250-363k**.

Memory: `.claude/CLAUDE.md` 8.9k, `architecture.md` 14.7k, `solid-oop.md` 11.7k, `csharp-unity.md` 11.1k, `bootstrap-pattern.md` 10.5k, `orchestrate-rules.md` 0.9k, global 0.3k. Dört rule dosyasında `paths:` frontmatter yok, bu yüzden resmi dokümana göre "launch'ta CLAUDE.md ile aynı öncelikte" yükleniyorlar.

Skill/agent/MCP listeleri toplam ~35k; budamaya değmez.

## Bulgu 2: Ana oturumlar

| Repo | Ana oturum | Çağrı | Ort. bağlam/çağrı | Cache TTL |
|---|---|---|---|---|
| template | 91 | 1730 | ~285k | — |
| match-block | 12 | 1258 | ~329k | %100 1h |

match-block'ta iki oturum (`b6d02bc3`, `21f272c5`; 425 ve 418 çağrı) ana oturum maliyetinin ~%69'u. Resmi doküman: *"Unexpectedly high spend … usually traces back to long sessions that were never cleared or to Opus left as the default model."*

## Bulgu 3: Agent başlangıç bedeli

| Repo | Agent | Çağrı | Cache write | Maliyet payı |
|---|---|---|---|---|
| template | 59 | 613 | 8.7M | ~%18 |
| match-block | 184 | 1545 | 25.1M | ~%47 |

Resmi doküman bunu doğruluyor: Explore ve Plan dışındaki built-in ve **özel agent'lar** *"every level of the CLAUDE.md hierarchy the main conversation loads, including … project rules"* ile başlıyor. 38 `coder` agent'ının ilk çağrı ortancası 61k fresh token; cache read çoğunlukla 0. Örnek görevler: "one tiny documentation edit" (4 çağrı), "Fix exactly one review finding" (23 çağrı).

Oturum başına ~70 agent spawn edilmiş (`b6d02bc3`: 19 `coder`, 11 `unity-setup`, 10 `codex-rescue`, 6 `tester`). Pipeline bunu zorluyor: gate açıkken `guard-pipeline-direct-work.sh` doğrudan `.cs` yazımını engelliyor.

## Bulgu 4: Agent'lar 5 dakikalık cache kullanıyor (yeni)

match-block ölçümü:

| | 5m TTL write | 1h TTL write |
|---|---|---|
| Ana oturumlar | 0 | 14.9M (%100) |
| Agent'lar | 25.1M (%100) | 0 |

Agent cache write'larının dağılımı:
- **Başlangıç (ilk çağrı): 13.6M (%54)**. Bulgu 3.
- **Çalışma ortasında tam yeniden yazma: 21 kez, 3.1M (%12)**. Bunların 12'si 5 dakikadan uzun aradan sonra; ortanca boşluk 442 sn. Unity refresh/derleme/test beklemesi bu senaryoya tam uyuyor.
- Geri kalan ~8.4M normal artımlı yazma.

GitHub'da aynı imza (hepsi açık):
- [#99360](https://github.com/anthropics/claude-code/issues/99360): agent'lar 5m, ana oturum 1h; 5 dakikadan yavaş yanıtlar tam yeniden yazmaya yol açıyor.
- [#103309](https://github.com/anthropics/claude-code/issues/103309): uzun Bash bekleyen agent'lar cache'i kaybediyor; haftalık limitin %54'ü 24 saatte.
- [#87215](https://github.com/anthropics/claude-code/issues/87215): uyandırılan agent yalnızca system prefix'i cache'ten okuyor.
- [#84289](https://github.com/anthropics/claude-code/issues/84289): dokümanın 5m/1h ifadesi ile gözlemler çelişiyor; Anthropic yanıtı: *"Claude Code itself requests the five-minute TTL for subagent requests on a subscription."*

Bizde bu kalem şimdilik %12; başlangıç bedeli (%54) daha büyük. Ama Unity iş akışında uzun beklemeler arttıkça bu pay büyür.

## Bulgu 5: Agent modelleri

match-block agent çağrıları: Sonnet 5.5 996, **Opus 5.5 419**, Haiku 4.5 142. Resmi model çözümleme sırası: çağrıdaki `model` parametresi → agent frontmatter `model` → `CLAUDE_CODE_SUBAGENT_MODEL` → ana oturum modeli. Model belirtilmeyen agent'lar ana oturumun modelini alır; ana oturum Opus'a alındıysa onlar da Opus'ta çalışır. GitHub'da model yönlendirmesinin bazı sürümlerde yok sayıldığına dair açık issue'lar var ([#43869](https://github.com/anthropics/claude-code/issues/43869), [#80902](https://github.com/anthropics/claude-code/issues/80902)); bizim transcript'lerdeki model alanı her agent'ın gerçekte hangi modelde çalıştığını gösteriyor.

## Önceki sürümdeki düzeltmeler

- **Path-scoped rule'lar `Write`'ta da yükleniyor.** Resmi doküman: *"A path-scoped rule loads when Claude uses the Read, Write, or Edit tool on a matching file."* `.claude/CLAUDE.md`'deki "not on a new-file Write" ifadesi bu sürümle çelişiyor; eski bir ölçüme dayanıyor olabilir. Doğrulanmadı. Not: rule, Write çağrısı yapıldıktan sonra bağlama girdiği için ilk yazılan içerik rule'u görmeden üretilmiş olabilir. Bu da doğrulanmadı.
- **"Agent'lar ~7× token" rakamı subagent'lar için değil**, plan modundaki *agent teams* için resmi rakam.
- **Explore ve Plan CLAUDE.md yüklemiyor.** Resmi dokümanla doğrulandı. match-block'ta `Plan` en pahalı agent (9.6M), ama sebebi başlangıç değil, çağrı sayısı (10 çalıştırmada 357 çağrı).

## Resmi doküman ne öneriyor

- CLAUDE.md'yi 200 satırın altında tut; iş akışına özel talimatları skill'e taşı.
- Konular arasında `/clear`. `/compact` büyük bağlamda kendisi büyük bir istek; süreklilik gerekmiyorsa `/clear` bedava.
- Basit agent görevleri için `model: haiku`. Tümünü zorlamak için `CLAUDE_CODE_SUBAGENT_MODEL` + `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`.
- Agent frontmatter `omitClaudeMd: true`: agent CLAUDE.md'yi yüklemeden başlar; eşleşen path-scoped rule'lar dosyaya dokununca yine yüklenir.
- Agent frontmatter `experimental.cacheTtl: 1h`: agent'ın cache ömrünü 1 saate çıkarır.
- `/usage` planlı hesaplarda skill/subagent/plugin bazında pay ve "long context", "cache misses" gibi davranış bayrakları gösteriyor. Bu ölçümün yerel sürümü.

## Seçenekler

| # | Seçenek | Hedeflediği bulgu | Risk |
|---|---|---|---|
| A | İş başına yeni oturum, `/clear`; uzun oturumdan kaçın | 2 | Yok |
| B | Dosyaya dokunmayan agent'lara `omitClaudeMd: true` (`committer`, `unity-scout`, `unity-linter`, `unity-git-master` gibi) | 3 | Hook'lar yine çalışır; ama agent'ın prompt'unda olmayan genel kurallar (etkileşim stili, gate kuralları) ulaşmaz. Agent başına karar ver |
| C | Uzun Unity beklemesi yapan agent'lara `experimental.cacheTtl: 1h` (`unity-setup`, `reviewer`, `unity-verifier`, `tester`) | 4 | Deneysel alan; 1h write 5m'den pahalı. Sadece uzun bekleyen agent'larda kazandırır |
| D | Dört rule dosyasına `paths:` ekle | 1, 3 | Doküman Write'ta yüklendiğini söylüyor; ama ilk yazımın rule'suz yapılıp yapılmadığı belirsiz. `rule-awareness-probe` ile ölçülmeli |
| E | Rule'larda `## Cards` kalsın, prose ayrı dosyaya | 1, 3 | Ek iş; kural kaybı yok |
| F | Agent'ların `model` alanını gözden geçir (`haiku` uygun olanlar için) | 5 | Kalite düşüşü; agent başına karar |

**Öneri:** A hemen. Sonra B ve C: ikisi de agent dosyası başına tek satır, geri alması kolay ve en büyük iki agent kalemini (başlangıç %54, TTL yeniden yazma %12) doğrudan hedefliyor. D/E memory'yi ana oturum için de küçültür ama kural davranışını değiştirir; önce `rule-awareness-probe` ile taban ölçümü alınmalı.

## Açık sorular

- Hangi pipeline komutu agent sayısını en çok artırıyor? Komut bazında ayrılmadı.
- `omitClaudeMd` ve `cacheTtl` bu sürümde (2.1.304) gerçekten etkili mi? Uygulandıktan sonra transcript'lerde `ephemeral_1h` ve ilk çağrı write boyutu ölçülmeli.
- CLAUDE.md'deki "path-scoped rules … not on a new-file Write" ifadesi güncel mi?

## Kaynaklar

Resmi: [Subagents](https://code.claude.com/docs/en/sub-agents) · [Memory / rules](https://code.claude.com/docs/en/memory) · [Manage costs](https://code.claude.com/docs/en/costs)

GitHub (anthropics/claude-code, hepsi açık): [#99360](https://github.com/anthropics/claude-code/issues/99360) · [#103309](https://github.com/anthropics/claude-code/issues/103309) · [#87215](https://github.com/anthropics/claude-code/issues/87215) · [#84289](https://github.com/anthropics/claude-code/issues/84289) · [#43869](https://github.com/anthropics/claude-code/issues/43869) · [#80902](https://github.com/anthropics/claude-code/issues/80902)

Üçüncü taraf (doğrulanmamış): [MindStudio](https://www.mindstudio.ai/blog/claude-code-subagents-cost-tokens) · [KDnuggets](https://kdnuggets.com/7-practical-ways-to-reduce-claude-code-token-usage) · [Analytics Vidhya](https://www.analyticsvidhya.com/blog/2026/05/tips-for-claude-code-token-saving/) · [Unblocked](https://getunblocked.com/blog/claude-code-context-window/)
