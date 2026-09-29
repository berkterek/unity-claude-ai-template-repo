using System.IO;
using System.Linq;
using Newtonsoft.Json;
using UnityEditor;
using UnityEngine;

namespace Framework.Editors
{
    /// <summary>
    /// Thin shell over <see cref="SerializedOpsApplier"/>: file I/O plus logging, nothing else.
    /// That boundary is what lets the applier be tested without driving the Editor menu system.
    /// </summary>
    public static class SerializedOpsMenu
    {
        #region Fields

        private const string DEFAULT_MANIFEST_PATH = "Temp/serialized-ops.json";
        private const string RESULT_PATH = "Temp/serialized-ops-result.json";
        private const string MENU_ROOT = "Tools/Framework/Apply Serialized Ops";
        private const string LOG_PREFIX = "[SerializedOps]";

        #endregion

        #region Public Methods

        [MenuItem(MENU_ROOT)]
        public static void ApplyDefaultManifest()
        {
            Run(Path.Combine(Directory.GetCurrentDirectory(), DEFAULT_MANIFEST_PATH));
        }

        [MenuItem(MENU_ROOT + " (Choose File...)")]
        public static void ApplyChosenManifest()
        {
            string picked = EditorUtility.OpenFilePanel("Serialized ops manifest", "Temp", "json");
            if (string.IsNullOrEmpty(picked)) return; // cancelled — not an error

            Run(picked);
        }

        #endregion

        #region Private Methods

        private static void Run(string absolutePath)
        {
            // The result file is deleted FIRST. A caller that reads a stale file from the previous run
            // and believes it describes this one is the worst outcome available here — worse than no
            // file at all, because it reports success for work that never started.
            string resultPath = Path.Combine(Directory.GetCurrentDirectory(), RESULT_PATH);
            TryDeleteResult(resultPath);

            if (!File.Exists(absolutePath))
            {
                Debug.LogError($"{LOG_PREFIX} No manifest at {absolutePath}");
                WriteResult(resultPath, new SerializedOpsResult
                {
                    Success = false,
                    Aborted = true,
                    AbortReason = $"no manifest at {absolutePath}"
                });
                return;
            }

            SerializedOpsResult result = SerializedOpsApplier.Apply(File.ReadAllText(absolutePath));
            WriteResult(resultPath, result);

            if (result.Aborted)
            {
                Debug.LogError($"{LOG_PREFIX} Manifest refused — {result.AbortReason}");
                return;
            }

            int total = result.Statuses.Count;
            int ok = result.Statuses.Count(s => s.Success);

            if (result.Success)
            {
                Debug.Log($"{LOG_PREFIX} {ok}/{total} ops applied.");
                return;
            }

            string failures = string.Join("\n", result.Statuses
                .Where(s => !s.Success)
                .Select(s => $"  op {s.Index} ({s.Op}) on '{s.Asset}' [{s.Property}] — {s.Message}"));

            Debug.LogError($"{LOG_PREFIX} {ok}/{total} ops applied — failures:\n{failures}");
        }

        /// <summary>
        /// Writes the machine-readable result beside the manifest so a caller reads a file instead of
        /// parsing the console. A failure to write is reported and never silently swallowed — a caller
        /// waiting on this file would otherwise hang on a run that actually finished.
        /// </summary>
        private static void WriteResult(string resultPath, SerializedOpsResult result)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(resultPath));
                File.WriteAllText(resultPath, JsonConvert.SerializeObject(result, Formatting.Indented));
            }
            catch (IOException e)
            {
                Debug.LogError($"{LOG_PREFIX} could not write result to {resultPath} — {e.Message}");
            }
        }

        private static void TryDeleteResult(string resultPath)
        {
            try
            {
                if (File.Exists(resultPath)) File.Delete(resultPath);
            }
            catch (IOException e)
            {
                Debug.LogError($"{LOG_PREFIX} could not clear stale result at {resultPath} — {e.Message}");
            }
        }

        #endregion
    }
}
