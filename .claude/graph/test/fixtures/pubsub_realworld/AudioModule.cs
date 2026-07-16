// Harvested (minimized) from:
// Assets/_GameFolders/Scripts/Games/Concretes/Audio/AudioModule.cs
// Real shape: non-generic builder.RegisterInstance(config) (resolvable via the
// enclosing method's own parameter type) + a chained builder.Register<T>(...)
// with extra chained calls (.AsSelf().As<IAudioService>()) that must not be
// mistaken for additional registrations.
// See EXPECTED.md for the asserted facts.
using Game.Abstracts.Audio;
using UnityEngine;
using VContainer;

namespace Game.Concretes.Audio
{
    public static class AudioModule
    {
        public static void Install(IContainerBuilder builder, AudioConfiguration config)
        {
            if (config == null)
            {
                Debug.LogError("[AudioModule] AudioConfiguration missing.");
                return;
            }

            builder.RegisterInstance(config);
            builder.Register<AudioService>(Lifetime.Singleton).AsSelf().As<IAudioService>();
        }
    }
}
