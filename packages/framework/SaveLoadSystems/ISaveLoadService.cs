namespace Framework.SaveLoadSystems
{
    public interface ISaveLoadService
    {
        void Save<T>(string key, T data);

        /// <summary>Reads the value stored under a key.</summary>
        /// <remarks>
        /// Postcondition: default(T) when the key is absent OR when the stored payload does not
        /// deserialize. HasKey and Load therefore disagree by design on a corrupt save — HasKey
        /// answers "the file exists", never "the file parses" — so a caller must null-check the
        /// result even after HasKey returned true. See rules/save-load.md Card 6.
        /// </remarks>
        T Load<T>(string key);

        bool HasKey(string key);
        void Delete(string key);
    }
}
