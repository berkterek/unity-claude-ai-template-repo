using System;
using System.IO;
using System.Reflection;
using System.Text;
using UnityEditor;
using UnityEngine;

namespace Framework.Editors
{
    [InitializeOnLoad]
    public static class LogDumpOnStop
    {
        const string FileName = "last_logs_on_console.txt";
        const BindingFlags StaticFlags = BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
        const BindingFlags InstanceFlags = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

        static LogDumpOnStop()
        {
            EditorApplication.playModeStateChanged -= OnPlayModeStateChanged;
            EditorApplication.playModeStateChanged += OnPlayModeStateChanged;
        }

        static void OnPlayModeStateChanged(PlayModeStateChange state)
        {
            if (state != PlayModeStateChange.ExitingPlayMode) return;
            DumpConsoleLogs();
        }

        // ──────────────────────────────────────────────────────────────────────────
        static void DumpConsoleLogs()
        {
            string logsRoot = Path.Combine(Application.dataPath, "..", "Logs");
            Directory.CreateDirectory(logsRoot);
            string filePath = Path.GetFullPath(Path.Combine(logsRoot, FileName));

            Type logEntriesType = typeof(Editor).Assembly.GetType("UnityEditor.LogEntries");
            Type logEntryType = typeof(Editor).Assembly.GetType("UnityEditor.LogEntry");

            if (logEntriesType == null || logEntryType == null)
            {
                File.WriteAllText(filePath, "Log dump failed: UnityEditor.LogEntries type not found.");
                return;
            }

            // GetCount — both versions expose this as a static method
            MethodInfo getCount = logEntriesType.GetMethod("GetCount", StaticFlags)
                                  ?? logEntriesType.GetMethod("GetCount"); // fallback (public only)

            // GetEntryInternal (Unity 2022) / GetEntry (Unity 6)
            MethodInfo getEntry = logEntriesType.GetMethod("GetEntryInternal", StaticFlags)
                                  ?? logEntriesType.GetMethod("GetEntry", StaticFlags)
                                  ?? logEntriesType.GetMethod("GetEntryInternal") // public-only fallbacks
                                  ?? logEntriesType.GetMethod("GetEntry");

            if (getCount == null || getEntry == null)
            {
                File.WriteAllText(filePath, "Log dump failed: LogEntries methods not found.");
                return;
            }

            int count = (int)getCount.Invoke(null, null);
            StringBuilder sb = new StringBuilder(Mathf.Max(256, count * 100));

            object entry = Activator.CreateInstance(logEntryType);

            // Field discovery: try both naming conventions used across Unity versions
            FieldInfo conditionField = FindField(logEntryType, "condition", "m_Condition");
            FieldInfo messageField = FindField(logEntryType, "message", "m_Message");
            FieldInfo textField = FindField(logEntryType, "text", "m_Text");
            FieldInfo stackField = FindField(logEntryType, "stackTrace", "m_StackTrace");
            FieldInfo modeField = FindField(logEntryType, "mode", "m_Mode");

            for (int i = 0; i < count; i++)
            {
                if (!TryGetEntry(getEntry, logEntryType, i, ref entry)) continue;

                string condition = ReadString(conditionField, entry);
                string message = ReadString(messageField, entry);
                string text = ReadString(textField, entry);
                string stack = ReadString(stackField, entry);
                string mode = ReadString(modeField, entry);

                // Pick the best available content field
                string content = !string.IsNullOrEmpty(condition) ? condition
                    : !string.IsNullOrEmpty(message) ? message
                    : text;

                // Keep only the first meaningful line
                content = FirstLine(content);

                if (string.IsNullOrEmpty(content) && string.IsNullOrEmpty(stack)) continue;

                string timestamp = DateTime.Now.ToString("HH:mm:ss.fff");
                sb.AppendLine($"[{timestamp}] {mode}: {content}");
            }

            File.WriteAllText(filePath, sb.ToString());
        }

        // ── Helpers ───────────────────────────────────────────────────────────────

        static FieldInfo FindField(Type type, params string[] names)
        {
            foreach (string name in names)
            {
                FieldInfo f = type.GetField(name, InstanceFlags);
                if (f != null) return f;
            }

            return null;
        }

        static string ReadString(FieldInfo field, object instance)
        {
            if (field == null || instance == null) return string.Empty;
            return field.GetValue(instance)?.ToString() ?? string.Empty;
        }

        static string FirstLine(string value)
        {
            if (string.IsNullOrEmpty(value)) return string.Empty;
            using (var reader = new StringReader(value))
            {
                string line;
                while ((line = reader.ReadLine()) != null)
                    if (!string.IsNullOrWhiteSpace(line))
                        return line.Trim();
            }

            return string.Empty;
        }

        /// <summary>
        /// Calls getEntry in a version-agnostic way.
        /// Unity 2022 signature: GetEntryInternal(int index, LogEntry entry) : bool
        /// Unity 6      signature: GetEntry(int/long index, ref LogEntry entry, ...) : bool
        /// </summary>
        static bool TryGetEntry(MethodInfo getEntry, Type logEntryType, int index, ref object entry)
        {
            ParameterInfo[] parameters = getEntry.GetParameters();
            if (parameters.Length == 0) return false;

            object[] args = new object[parameters.Length];
            int entryArgIndex = -1;

            for (int p = 0; p < parameters.Length; p++)
            {
                Type paramType = parameters[p].ParameterType;
                Type targetType = paramType.IsByRef ? paramType.GetElementType() : paramType;

                if (p == 0 && (targetType == typeof(int) || targetType == typeof(long)))
                {
                    args[p] = targetType == typeof(long) ? (object)(long)index : index;
                    continue;
                }

                if (targetType == logEntryType)
                {
                    args[p] = entry;
                    entryArgIndex = p;
                    continue;
                }

                args[p] = GetDefaultValue(targetType);
            }

            object result;
            try
            {
                result = getEntry.Invoke(null, args);
            }
            catch
            {
                return false;
            }

            // Write back ref/out entry argument if present
            if (entryArgIndex >= 0) entry = args[entryArgIndex];

            if (result is bool ok) return ok;
            return true; // void-return methods are treated as success
        }

        static object GetDefaultValue(Type type)
        {
            if (type == typeof(string)) return string.Empty;
            if (type.IsValueType) return Activator.CreateInstance(type);
            return null;
        }
    }
}
