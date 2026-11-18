using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
using System.Reflection;
using Framework.Logging;

namespace Framework.DebugCommands
{
    public sealed class DebugCommandRegistry : IDebugCommandRegistry
    {
        #region Fields

        private const string CONTAINER_SUFFIX = "DebugCommands";
        private const BindingFlags MEMBER_FLAGS = BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly;

        private readonly List<object> _containers = new();

        public IReadOnlyList<object> Containers => _containers;

        public event Action<object> ContainerAdded;
        public event Action<object> ContainerRemoved;

        #endregion

        #region Public Methods

        public void Register(object container)
        {
            if (container == null || _containers.Contains(container))
            {
                return;
            }

            _containers.Add(container);
            DLog.Log(LogTag.DebugCommands, $"Registered {container.GetType().Name}");
            ContainerAdded?.Invoke(container);
        }

        public void Unregister(object container)
        {
            if (container == null || !_containers.Remove(container))
            {
                return;
            }

            DLog.Log(LogTag.DebugCommands, $"Unregistered {container.GetType().Name}");
            ContainerRemoved?.Invoke(container);
        }

        public IReadOnlyList<DebugCommandInfo> List()
        {
            var result = new List<DebugCommandInfo>();
            for (var i = 0; i < _containers.Count; i++)
            {
                var container = _containers[i];
                var type = container.GetType();
                var prefix = PrefixOf(type);

                foreach (var property in type.GetProperties(MEMBER_FLAGS))
                {
                    if (property.GetIndexParameters().Length > 0 || property.GetGetMethod() == null || IsHidden(property))
                    {
                        continue;
                    }

                    var kind = property.GetSetMethod() != null ? DebugCommandKind.Parameter : DebugCommandKind.Value;
                    result.Add(new DebugCommandInfo(
                        $"{prefix}.{property.Name}",
                        CategoryOf(property, prefix),
                        kind,
                        property.PropertyType.Name,
                        ReadValue(container, property)));
                }

                foreach (var method in CommandMethods(type))
                {
                    result.Add(new DebugCommandInfo(
                        $"{prefix}.{method.Name}",
                        CategoryOf(method, prefix),
                        DebugCommandKind.Command,
                        "void",
                        string.Empty));
                }
            }

            return result;
        }

        public bool TryRun(string commandId, IReadOnlyDictionary<string, string> set, out string message)
        {
            if (!TryFindCommand(commandId, out var container, out var method))
            {
                message = $"'{commandId}' is not registered in the current scene. Registered: {RegisteredCommandIds()}";
                return false;
            }

            var type = container.GetType();
            var applied = new List<string>();

            // Convert every value before setting any, so a bad value never leaves the container half-updated.
            var pending = new List<(PropertyInfo Property, object Value)>();
            if (set != null)
            {
                foreach (var pair in set)
                {
                    var property = type.GetProperty(pair.Key, MEMBER_FLAGS);
                    if (property == null || property.GetSetMethod() == null || property.GetGetMethod() == null
                        || property.GetIndexParameters().Length > 0 || IsHidden(property))
                    {
                        message = $"'{pair.Key}' is not a settable parameter of {PrefixOf(type)}.";
                        return false;
                    }

                    if (!TryConvert(pair.Value, property.PropertyType, out var value))
                    {
                        message = $"'{pair.Value}' is not a valid {property.PropertyType.Name} for {PrefixOf(type)}.{pair.Key}.";
                        return false;
                    }

                    pending.Add((property, value));
                    applied.Add($"{pair.Key}={pair.Value}");
                }
            }

            // A setter that throws rolls back the ones already applied, so a failed run never leaves the
            // container half-updated either.
            var previous = new object[pending.Count];
            var setCount = 0;
            try
            {
                for (; setCount < pending.Count; setCount++)
                {
                    previous[setCount] = pending[setCount].Property.GetValue(container);
                    pending[setCount].Property.SetValue(container, pending[setCount].Value);
                }

                method.Invoke(container, null);
            }
            catch (Exception exception)
            {
                // Dev-only boundary: a command (or a setter it exposes) may throw anything, and the caller is a
                // menu callback that must always get an answer back instead of an exception.
                if (setCount < pending.Count)
                {
                    Restore(container, pending, previous, setCount);
                }

                return Fail(commandId, Unwrap(exception), out message);
            }

            message = applied.Count == 0 ? commandId : $"{commandId} ({string.Join(", ", applied)})";
            return true;
        }

        #endregion

        #region Private Methods

        private static void Restore(object container, List<(PropertyInfo Property, object Value)> pending,
            object[] previous, int setCount)
        {
            for (var i = setCount - 1; i >= 0; i--)
            {
                try
                {
                    pending[i].Property.SetValue(container, previous[i]);
                }
                catch (Exception exception)
                {
                    DLog.Error(LogTag.DebugCommands, $"Could not roll back {pending[i].Property.Name}", Unwrap(exception));
                }
            }
        }

        private static Exception Unwrap(Exception exception) =>
            exception is TargetInvocationException { InnerException: not null } wrapped ? wrapped.InnerException : exception;

        private static bool IsHidden(MemberInfo member) =>
            member.GetCustomAttribute<BrowsableAttribute>() is { Browsable: false };

        private static bool Fail(string commandId, Exception exception, out string message)
        {
            DLog.Error(LogTag.DebugCommands, $"{commandId} threw", exception);
            message = $"{exception.GetType().Name}: {exception.Message}";
            return false;
        }

        private bool TryFindCommand(string commandId, out object container, out MethodInfo method)
        {
            container = null;
            method = null;
            if (string.IsNullOrEmpty(commandId))
            {
                return false;
            }

            var dot = commandId.LastIndexOf('.');
            if (dot <= 0 || dot == commandId.Length - 1)
            {
                return false;
            }

            var prefix = commandId.Substring(0, dot);
            var memberName = commandId.Substring(dot + 1);
            for (var i = 0; i < _containers.Count; i++)
            {
                var type = _containers[i].GetType();
                if (PrefixOf(type) != prefix)
                {
                    continue;
                }

                foreach (var candidate in CommandMethods(type))
                {
                    if (candidate.Name == memberName)
                    {
                        container = _containers[i];
                        method = candidate;
                        return true;
                    }
                }
            }

            return false;
        }

        private string RegisteredCommandIds()
        {
            var ids = new List<string>();
            for (var i = 0; i < _containers.Count; i++)
            {
                var type = _containers[i].GetType();
                foreach (var method in CommandMethods(type))
                {
                    ids.Add($"{PrefixOf(type)}.{method.Name}");
                }
            }

            return ids.Count == 0 ? "(none)" : string.Join(", ", ids);
        }

        // Public parameterless void methods declared on the container, minus property accessors, interface
        // implementations (Initialize/Dispose are not commands) and [Browsable(false)] — the same rules the
        // playtest generator applies statically, and the attribute SRDebugger's panel honours too.
        private static IEnumerable<MethodInfo> CommandMethods(Type type)
        {
            var interfaceMethods = new HashSet<MethodInfo>();
            foreach (var contract in type.GetInterfaces())
            {
                var map = type.GetInterfaceMap(contract);
                for (var i = 0; i < map.TargetMethods.Length; i++)
                {
                    interfaceMethods.Add(map.TargetMethods[i]);
                }
            }

            foreach (var method in type.GetMethods(MEMBER_FLAGS))
            {
                if (method.IsSpecialName || method.ReturnType != typeof(void) || method.GetParameters().Length > 0
                    || method.IsGenericMethodDefinition || interfaceMethods.Contains(method) || IsHidden(method))
                {
                    continue;
                }

                yield return method;
            }
        }

        private static string PrefixOf(Type type)
        {
            var name = type.Name;
            return name.EndsWith(CONTAINER_SUFFIX, StringComparison.Ordinal) && name.Length > CONTAINER_SUFFIX.Length
                ? name.Substring(0, name.Length - CONTAINER_SUFFIX.Length)
                : name;
        }

        private static string CategoryOf(MemberInfo member, string fallback)
        {
            var category = member.GetCustomAttribute<CategoryAttribute>();
            return category != null ? category.Category : fallback;
        }

        private static string ReadValue(object container, PropertyInfo property)
        {
            try
            {
                var value = property.GetValue(container);
                return value == null ? "null" : Convert.ToString(value, CultureInfo.InvariantCulture);
            }
            catch (Exception exception)
            {
                // A getter that throws must not hide every other member from the listing.
                return $"<{Unwrap(exception).GetType().Name}>";
            }
        }

        private static bool TryConvert(string raw, Type target, out object value)
        {
            value = null;
            if (target == typeof(string))
            {
                value = raw;
                return true;
            }

            if (raw == null)
            {
                return false;
            }

            if (target == typeof(int) && int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var i))
            {
                value = i;
                return true;
            }

            if (target == typeof(float) && float.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var f))
            {
                value = f;
                return true;
            }

            if (target == typeof(bool) && bool.TryParse(raw, out var b))
            {
                value = b;
                return true;
            }

            if (!target.IsEnum)
            {
                return false;
            }

            try
            {
                value = Enum.Parse(target, raw.Trim(), true);
                return Enum.IsDefined(target, value);
            }
            catch (ArgumentException)
            {
                return false;
            }
        }

        #endregion
    }
}
