using Framework.Logging;
using Newtonsoft.Json;
using UnityEngine;

namespace Framework.SaveLoadSystems
{
    public sealed class PlayerPrefsSaveLoadDal : ISaveLoadDal
    {
        #region ISaveLoadDal

        /// <remarks>
        /// One PlayerPrefs string per key, holding the JSON payload. PlayerPrefs has no
        /// File.Replace equivalent, so rules/save-load.md Card 7's atomic swap cannot be
        /// implemented here; Save() flushes right away so a killed process loses at most the
        /// write in flight.
        /// </remarks>
        public void SaveData(string key, object value)
        {
            PlayerPrefs.SetString(key, JsonConvert.SerializeObject(value));
            PlayerPrefs.Save();
        }

        public T LoadData<T>(string key)
        {
            if (!PlayerPrefs.HasKey(key)) return default;

            string json = PlayerPrefs.GetString(key);
            if (string.IsNullOrEmpty(json)) return default;

            try
            {
                return JsonConvert.DeserializeObject<T>(json);
            }
            catch (JsonException exception)
            {
                // Same contract as LocalSaveLoadDal (rules/save-load.md Card 8): log, return
                // default, let the caller take its first-run branch.
                DLog.Error(LogTag.SaveLoad, $"Corrupt save for key={key}, falling back to default.", exception);
                return default;
            }
        }

        public bool HasKey(string key)
        {
            return PlayerPrefs.HasKey(key);
        }

        public void DeleteData(string key)
        {
            PlayerPrefs.DeleteKey(key);
            PlayerPrefs.Save();
        }

        #endregion
    }
}
