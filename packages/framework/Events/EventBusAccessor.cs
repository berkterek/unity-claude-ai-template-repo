using System;

namespace Framework.Events
{
    public static class EventBusAccessor
    {
        #region Fields

        private static IEventBus _instance;

        #endregion

        #region Public Properties

        public static IEventBus Instance => _instance
            ?? throw new InvalidOperationException("EventBusAccessor not initialized. Call Initialize() in AppScope.");

        #endregion

        #region Public Methods

        public static void Initialize(IEventBus bus) => _instance = bus;

        #endregion
    }
}
