namespace Framework.Logging
{
    // Framework-level tags only. A game's own domains (UI, Economy, a specific mechanic)
    // do NOT belong here — this enum ships to every project that consumes the package, and
    // one project's domain name is noise in every other one. Per-project tags are declared
    // on the game side; see rules/logging.md Card 3.
    public enum LogTag
    {
        General,
        EventBus,
        SaveLoad
    }
}
