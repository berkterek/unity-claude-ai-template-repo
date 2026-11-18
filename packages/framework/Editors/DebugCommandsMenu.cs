using System;
using System.Collections.Generic;
using System.IO;
using Framework.DebugCommands;
using Newtonsoft.Json;
using UnityEditor;
using UnityEngine;

namespace Framework.Editors
{
    /// <summary>
    /// Agent-facing shell over the debug command registry: reads a request file, runs or lists through the
    /// registry accessor, writes a result file and logs one line. All decisions live in the registry.
    /// </summary>
    public static class DebugCommandsMenu
    {
        #region Fields

        private const string REQUEST_PATH = "Temp/debug-command.json";
        private const string RESULT_PATH = "Temp/debug-command-result.json";
        private const string MENU_ROOT = "Tools/Framework/Debug Commands/";
        private const string LOG_PREFIX = "[DebugCommands]";

        #endregion

        #region Public Methods

        [MenuItem(MENU_ROOT + "Run")]
        public static void Run()
        {
            var requestPath = Path.Combine(Directory.GetCurrentDirectory(), REQUEST_PATH);
            var resultPath = Path.Combine(Directory.GetCurrentDirectory(), RESULT_PATH);
            TryDelete(resultPath); // a stale result must never describe this run

            var hasRegistry = TryGetRegistry(out var registry, out var reason);
            var hasRequest = TryReadRequest(requestPath, out var request, out var requestReason);

            // Consumed on every path, so a call that failed (not in Play Mode, no registry) never leaves a
            // request behind for the next Run to replay.
            TryDelete(requestPath);

            if (!hasRegistry || !hasRequest)
            {
                Report(resultPath, false, hasRegistry ? requestReason : reason, null);
                return;
            }

            var ok = registry.TryRun(request.Command, request.Set ?? new Dictionary<string, string>(), out var message);
            Report(resultPath, ok, message, ok ? null : registry.List());
        }

        [MenuItem(MENU_ROOT + "List")]
        public static void List()
        {
            var resultPath = Path.Combine(Directory.GetCurrentDirectory(), RESULT_PATH);
            TryDelete(resultPath);

            if (!TryGetRegistry(out var registry, out var reason))
            {
                Report(resultPath, false, reason, null);
                return;
            }

            var commands = registry.List();
            Report(resultPath, true, $"{commands.Count} members registered", commands);
        }

        #endregion

        #region Private Methods

        private static bool TryGetRegistry(out IDebugCommandRegistry registry, out string reason)
        {
            registry = DebugCommandRegistryAccessor.Instance;
            if (!EditorApplication.isPlaying)
            {
                reason = "not in Play Mode";
                return false;
            }

            if (registry == null)
            {
                reason = "registry not set — is DebugCommandsModule installed in AppModules?";
                return false;
            }

            reason = null;
            return true;
        }

        private static bool TryReadRequest(string path, out DebugCommandRequest request, out string reason)
        {
            request = null;
            if (!File.Exists(path))
            {
                reason = $"no request at {path}";
                return false;
            }

            try
            {
                request = JsonConvert.DeserializeObject<DebugCommandRequest>(File.ReadAllText(path));
            }
            catch (JsonException exception)
            {
                reason = $"unparseable request at {path}: {exception.Message}";
                return false;
            }

            if (request == null || string.IsNullOrEmpty(request.Command))
            {
                reason = $"request at {path} has no \"command\"";
                return false;
            }

            reason = null;
            return true;
        }

        private static void Report(string resultPath, bool ok, string message, IReadOnlyList<DebugCommandInfo> commands)
        {
            var result = new DebugCommandResult { Ok = ok, Message = message };
            if (commands != null)
            {
                for (var i = 0; i < commands.Count; i++)
                {
                    var info = commands[i];
                    result.Commands.Add(new DebugCommandResultEntry
                    {
                        Id = info.Id,
                        Category = info.Category,
                        Kind = info.Kind.ToString(),
                        ValueType = info.ValueType,
                        CurrentValue = info.CurrentValue
                    });
                }
            }

            try
            {
                File.WriteAllText(resultPath, JsonConvert.SerializeObject(result, Formatting.Indented));
            }
            catch (Exception exception) when (exception is IOException || exception is UnauthorizedAccessException)
            {
                Debug.LogError($"{LOG_PREFIX} Could not write {resultPath}: {exception.Message}");
            }

            var line = $"{LOG_PREFIX} {(ok ? "OK" : "FAIL")} {message}";
            if (ok)
            {
                Debug.Log(line);
            }
            else
            {
                Debug.LogWarning(line);
            }
        }

        private static void TryDelete(string path)
        {
            try
            {
                if (File.Exists(path))
                {
                    File.Delete(path);
                }
            }
            catch (Exception exception) when (exception is IOException || exception is UnauthorizedAccessException)
            {
                Debug.LogWarning($"{LOG_PREFIX} Could not delete {path}: {exception.Message}");
            }
        }

        #endregion

        #region Nested Types

        [Serializable]
        private sealed class DebugCommandRequest
        {
            [JsonProperty("command")] public string Command;
            [JsonProperty("set")] public Dictionary<string, string> Set;
        }

        [Serializable]
        private sealed class DebugCommandResult
        {
            [JsonProperty("ok")] public bool Ok;
            [JsonProperty("message")] public string Message;
            [JsonProperty("commands")] public List<DebugCommandResultEntry> Commands = new();
        }

        [Serializable]
        private sealed class DebugCommandResultEntry
        {
            [JsonProperty("id")] public string Id;
            [JsonProperty("category")] public string Category;
            [JsonProperty("kind")] public string Kind;
            [JsonProperty("valueType")] public string ValueType;
            [JsonProperty("currentValue")] public string CurrentValue;
        }

        #endregion
    }
}
