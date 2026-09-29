using System;

namespace Framework.Events
{
    public interface IEventBus
    {
        /// <summary>Registers a handler for TEvent.</summary>
        /// <remarks>
        /// Side effect: The same delegate may be registered more than once; each registration
        /// receives its own invocation on Publish.
        /// </remarks>
        void Subscribe<TEvent>(Action<TEvent> handler) where TEvent : struct, IEvent;

        /// <summary>Removes one registration of a handler for TEvent.</summary>
        /// <remarks>
        /// Precondition: None — unsubscribing an unregistered handler is a no-op and is logged.
        /// </remarks>
        void Unsubscribe<TEvent>(Action<TEvent> handler) where TEvent : struct, IEvent;

        /// <summary>Delivers an event to every registered handler.</summary>
        /// <remarks>
        /// Postcondition: Every subscriber is invoked even if an earlier one threw — an
        /// exception is caught and reported, never propagated.
        /// Side effect: None beyond what the subscribers themselves do.
        /// Throws: Never. A subscriber's exception does not reach the publisher, so wrapping a
        /// Publish call in try/catch buys nothing.
        /// </remarks>
        void Publish<TEvent>(TEvent eventData) where TEvent : struct, IEvent;
    }
}
