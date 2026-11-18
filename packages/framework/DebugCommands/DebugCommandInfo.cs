namespace Framework.DebugCommands
{
    /// <summary>What a member of a registered command container is, as seen by a caller.</summary>
    public enum DebugCommandKind
    {
        /// <summary>A public parameterless void method — runs when invoked.</summary>
        Command,

        /// <summary>A public get+set property — a value a command reads, set before running it.</summary>
        Parameter,

        /// <summary>A public get-only property — state to read back after a command ran.</summary>
        Value
    }

    /// <summary>One member of a registered command container, snapshotted at list time.</summary>
    public readonly struct DebugCommandInfo
    {
        public string Id { get; }
        public string Category { get; }
        public DebugCommandKind Kind { get; }
        public string ValueType { get; }
        public string CurrentValue { get; }

        public DebugCommandInfo(string id, string category, DebugCommandKind kind, string valueType, string currentValue)
        {
            Id = id;
            Category = category;
            Kind = kind;
            ValueType = valueType;
            CurrentValue = currentValue;
        }
    }
}
