using System.IO;
using Framework.Logging;
using Newtonsoft.Json;
using UnityEngine;

namespace Framework.SaveLoadSystems
{
    public sealed class LocalSaveLoadDal : ISaveLoadDal
    {
        #region Private Methods

        private static string GetFilePath(string key)
        {
            return Path.Combine(Application.persistentDataPath, key + ".json");
        }

        private static string GetTempFilePath(string key)
        {
            return GetFilePath(key) + ".tmp";
        }

        #endregion

        #region ISaveLoadDal

        /// <remarks>
        /// The payload is written to a sibling temp file and swapped in, never written over the
        /// live save. WriteAllText truncates before it writes, so writing straight to the target
        /// leaves neither the old state nor the new when the process dies in between — and a
        /// mobile OS kills a backgrounded process without warning, which makes that routine
        /// rather than exotic. A stale temp left by such a kill is overwritten here rather than
        /// treated as an error: the crash already cost one write, it must not cost every future
        /// one. See rules/save-load.md Card 7.
        /// </remarks>
        public void SaveData(string key, object value)
        {
            string path = GetFilePath(key);
            string tempPath = GetTempFilePath(key);
            string json = JsonConvert.SerializeObject(value);

            File.WriteAllText(tempPath, json);

            if (File.Exists(path))
            {
                File.Replace(tempPath, path, null);
            }
            else
            {
                File.Move(tempPath, path);
            }
        }

        public T LoadData<T>(string key)
        {
            string path = GetFilePath(key);
            if (!File.Exists(path)) return default;

            string json = File.ReadAllText(path);
            if (string.IsNullOrEmpty(json)) return default;

            try
            {
                return JsonConvert.DeserializeObject<T>(json);
            }
            catch (JsonException exception)
            {
                // Narrow on purpose. An IOException — locked file, permissions — is a different
                // problem with a different fix, and absorbing it into this default-value path
                // would be an empty catch block wearing a log statement. See rules/save-load.md
                // Card 8. The caller sees default and takes its first-run branch, which is why
                // HasKey and Load disagree here by design: HasKey answers "the file exists",
                // never "the file parses".
                DLog.Error(LogTag.SaveLoad, $"Corrupt save for key={key}, falling back to default.", exception);
                return default;
            }
        }

        public bool HasKey(string key)
        {
            return File.Exists(GetFilePath(key));
        }

        public void DeleteData(string key)
        {
            string path = GetFilePath(key);
            if (File.Exists(path)) File.Delete(path);
        }

        #endregion
    }
}
