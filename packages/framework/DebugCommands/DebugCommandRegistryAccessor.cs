using Framework.Logging;

namespace Framework.DebugCommands
{
    /// <summary>
    /// Second approved static accessor after the event bus one. Set once by the game's debug module in its
    /// build callback; read only by the framework's Editor menu, which runs outside the container's reach.
    /// Game code injects the registry interface instead — check-debug-commands.sh blocks any other reader.
    /// </summary>
    public static class DebugCommandRegistryAccessor
    {
        #region Fields

        private static IDebugCommandRegistry _instance;

        #endregion

        #region Public Properties

        /// <summary>The registry, or null when no debug module installed it (not in Play Mode, or not wired).</summary>
        public static IDebugCommandRegistry Instance => _instance;

        #endregion

        #region Public Methods

        public static void Set(IDebugCommandRegistry registry)
        {
            if (_instance != null && registry != null && !ReferenceEquals(_instance, registry))
            {
                // A second container build in one domain (Enter Play Mode without domain reload) replaces
                // the stale registry; the warning makes an unexpected second build visible.
                DLog.Warning(LogTag.DebugCommands, "Registry accessor set twice — replacing the previous registry.");
            }

            _instance = registry;
        }

        #endregion
    }
}
