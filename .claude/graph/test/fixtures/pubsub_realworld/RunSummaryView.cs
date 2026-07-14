// Harvested (minimized) from:
// nile_hole_sphere_repo/HoleSphere/Assets/_GameFolders/Scripts/Games/Concretes/UI/RunSummaryView.cs
// Real shape: null-conditional Publish with a constructor argument that is
// itself a member access (_walletService.CommittedGold) — the event type must
// still resolve from the `new T(...)` node regardless of the arguments passed
// to the event's own constructor.
// See EXPECTED.md for the asserted facts.
using Game.Abstracts.Events;

namespace Game.Concretes.UI
{
    public sealed class RunSummaryView
    {
        private IEventBus _eventBus;
        private IWalletService _walletService;

        private void OnCollectGold()
        {
            _eventBus?.Publish(new GoldChangedEvent(_walletService.CommittedGold));
        }

        private void OnContinuePressed()
        {
            _eventBus?.Publish(new ContinueButtonPressedEvent());
        }
    }
}
