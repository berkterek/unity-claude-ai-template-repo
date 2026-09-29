using System;
using System.Collections.Generic;
using Framework.Logging;

namespace Framework.Events
{
    public sealed class EventBus : IEventBus
    {
        #region Private Fields

        private readonly Dictionary<Type, List<object>> _handlers = new();

        #endregion

        #region IEventBus

        public void Subscribe<TEvent>(Action<TEvent> handler) where TEvent : struct, IEvent
        {
            var eventType = typeof(TEvent);
            if (!_handlers.ContainsKey(eventType))
            {
                _handlers[eventType] = new List<object>();
            }

            _handlers[eventType].Add(handler);
            DLog.Log(LogTag.EventBus, $"Subscribe<{eventType.Name}> count={_handlers[eventType].Count}");
        }

        public void Unsubscribe<TEvent>(Action<TEvent> handler) where TEvent : struct, IEvent
        {
            var eventType = typeof(TEvent);
            if (!_handlers.TryGetValue(eventType, out var handlers))
            {
                DLog.Warning(LogTag.EventBus, $"Unsubscribe failed. Event={eventType.Name}");
                return;
            }

            handlers.Remove(handler);
            DLog.Log(LogTag.EventBus, $"Unsubscribe<{eventType.Name}> remaining={handlers.Count}");
            if (handlers.Count == 0) _handlers.Remove(eventType);
        }

        public void Publish<TEvent>(TEvent eventData) where TEvent : struct, IEvent
        {
            var eventType = typeof(TEvent);
            if (!_handlers.TryGetValue(eventType, out var handlers))
            {
                DLog.Log(LogTag.EventBus, $"Publish<{eventType.Name}> skipped. No handler.");
                return;
            }

            DLog.Log(LogTag.EventBus, $"Publish<{eventType.Name}> handlers={handlers.Count}");

            // Iterate by index (reverse) — no snapshot allocation, no foreach boxing
            for (var i = handlers.Count - 1; i >= 0; i--)
            {
                try
                {
                    ((Action<TEvent>)handlers[i]).Invoke(eventData);
                }
                catch (Exception exception)
                {
                    // catch (Exception) is correct HERE and nowhere else in this package: the bus
                    // cannot know what a subscriber may throw, and one subscriber's failure must
                    // not become another's. Nearly all game logic runs inside subscribers, so this
                    // catch is where a whole class of defect gets reported — which is also what
                    // makes DLog.Error's unconditional, unfiltered behaviour load-bearing.
                    //
                    // The exception OBJECT is passed, not exception.Message: the 3-argument
                    // overload routes through Debug.LogException, which is what makes the stack
                    // trace clickable. Message alone names the failure but not the file or the
                    // line, which in this catch means "a handler threw" with no way to find it.
                    // See rules/logging.md Card 4.
                    DLog.Error(LogTag.EventBus, $"Handler exception in Publish<{eventType.Name}>", exception);
                }
            }
        }

        #endregion
    }
}
