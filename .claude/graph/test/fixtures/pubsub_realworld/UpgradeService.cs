// Harvested (minimized) from:
// Assets/_GameFolders/Scripts/Games/Concretes/Economy/UpgradeService.cs
// Real shape: TWO non-generic (type-inferred) Publish call sites in the same class.
// See EXPECTED.md for the asserted facts.
using Game.Abstracts.Events;

namespace Game.Concretes.Economy
{
    public sealed class UpgradeService
    {
        private IEventBus _eventBus;

        public void Purchase(UpgradeType type, byte level)
        {
            _eventBus.Publish(new UpgradePurchasedEvent(type, level));
        }

        public void ApplySaveData(UpgradeSaveData data)
        {
            _eventBus.Publish(new UpgradePurchasedEvent(UpgradeType.IncomeRate, (byte)data.IncomeLevel));
        }
    }
}
