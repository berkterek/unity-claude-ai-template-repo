using System;
using SRDebugger.Services;

namespace Framework.DebugCommands.SRDebugger
{
    /// <summary>
    /// Mirrors every container in the debug command registry into SRDebugger's options panel, so the same
    /// containers an agent runs by id are buttons and fields for a human on device.
    /// </summary>
    public sealed class SRDebuggerDebugCommandsBridge : IDisposable
    {
        #region Fields

        private readonly IDebugCommandRegistry _registry;
        private readonly IDebugService _debugService;
        private bool _disposed;

        #endregion

        #region Constructor

        public SRDebuggerDebugCommandsBridge(IDebugCommandRegistry registry, IDebugService debugService)
        {
            _registry = registry;
            _debugService = debugService;
            var containers = _registry.Containers;
            for (var i = 0; i < containers.Count; i++)
            {
                HandleContainerAdded(containers[i]);
            }

            _registry.ContainerAdded += HandleContainerAdded;
            _registry.ContainerRemoved += HandleContainerRemoved;
        }

        #endregion

        #region Public Methods

        public void Dispose()
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            _registry.ContainerAdded -= HandleContainerAdded;
            _registry.ContainerRemoved -= HandleContainerRemoved;

            var containers = _registry.Containers;
            for (var i = 0; i < containers.Count; i++)
            {
                HandleContainerRemoved(containers[i]);
            }
        }

        #endregion

        #region Private Methods

        private void HandleContainerAdded(object container) => _debugService.AddOptionContainer(container);

        private void HandleContainerRemoved(object container) => _debugService.RemoveOptionContainer(container);

        #endregion
    }
}
