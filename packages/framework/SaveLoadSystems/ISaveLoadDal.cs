namespace Framework.SaveLoadSystems
{
    // One implementation per backend mechanism. LocalSaveLoadDal is the default; a
    // PlayerPrefs-backed or cloud-backed sibling swaps in without SaveLoadService changing.
    // See rules/architecture.md Card 2.1.
    public interface ISaveLoadDal
    {
        // object, not a generic: the value is boxed here, which is why a persisted type is a
        // [Serializable] class and never a struct. See rules/save-load.md Card 2.
        void SaveData(string key, object value);

        T LoadData<T>(string key);
        bool HasKey(string key);
        void DeleteData(string key);
    }
}
