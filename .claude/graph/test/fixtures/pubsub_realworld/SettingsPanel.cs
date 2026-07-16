// Harvested (minimized) from:
// Assets/_GameFolders/Scripts/Games/Concretes/UI/SettingsPanel.cs
// Real shape: null-conditional generic Subscribe + null-conditional non-generic Publish.
// See EXPECTED.md for the asserted facts.
using Game.Abstracts.Events;

namespace Game.Concretes.UI
{
    public sealed class SettingsPanel
    {
        private IEventBus _eventBus;

        private void OnEnable()
        {
            _eventBus?.Subscribe<SettingsOpenedEvent>(OnSettingsOpened);
            _eventBus?.Subscribe<SettingsClosedEvent>(OnSettingsClosed);
        }

        private void OnSettingsOpened(SettingsOpenedEvent e) { }

        private void OnSettingsClosed(SettingsClosedEvent e) { }

        private void CloseSettings()
        {
            _eventBus?.Publish(new SettingsClosedEvent());
        }
    }
}
