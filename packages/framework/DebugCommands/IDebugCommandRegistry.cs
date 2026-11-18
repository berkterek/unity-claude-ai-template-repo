using System;
using System.Collections.Generic;

namespace Framework.DebugCommands
{
    /// <summary>
    /// Holds the dev-only command containers that are alive right now and runs their members by id.
    /// A command id is the container's type name without its "DebugCommands" suffix, a dot, and the
    /// member name — LevelDebugCommands.GoToLevel is "Level.GoToLevel".
    /// </summary>
    public interface IDebugCommandRegistry
    {
        IReadOnlyList<object> Containers { get; }

        event Action<object> ContainerAdded;
        event Action<object> ContainerRemoved;

        /// <remarks>Idempotent: a null or an already registered container is ignored.</remarks>
        void Register(object container);

        /// <remarks>Idempotent: an unknown container is ignored and raises nothing.</remarks>
        void Unregister(object container);

        IReadOnlyList<DebugCommandInfo> List();

        /// <summary>Sets the given parameters on the command's container, then invokes the command.</summary>
        /// <remarks>
        /// Precondition: every key in <paramref name="set"/> is a Parameter of the same container.
        /// Postcondition: on false the command was NOT invoked, unless the command itself threw.
        /// Throws: never — failures come back as false with a reason in <paramref name="message"/>.
        /// </remarks>
        bool TryRun(string commandId, IReadOnlyDictionary<string, string> set, out string message);
    }
}
