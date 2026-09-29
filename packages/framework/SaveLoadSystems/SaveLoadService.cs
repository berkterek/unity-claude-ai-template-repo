using Framework.Logging;

namespace Framework.SaveLoadSystems
{
    // *Service, not *Manager: this is a pure C# Tier 3 service wrapping a backend, with no
    // registry of sibling instances to coordinate. *Manager is a MonoBehaviour role — a
    // single-domain coordinator with Register/Unregister. See rules/solid-oop.md Card 1.
    public sealed class SaveLoadService : ISaveLoadService
    {
        #region Fields

        private readonly ISaveLoadDal _dal;

        #endregion

        #region Constructor

        public SaveLoadService(ISaveLoadDal dal)
        {
            _dal = dal;
        }

        #endregion

        #region ISaveLoadService

        public void Save<T>(string key, T data)
        {
            DLog.Log(LogTag.SaveLoad, $"Save key={key}");
            _dal.SaveData(key, data);
        }

        public T Load<T>(string key)
        {
            DLog.Log(LogTag.SaveLoad, $"Load key={key}");
            return _dal.LoadData<T>(key);
        }

        public bool HasKey(string key)
        {
            return _dal.HasKey(key);
        }

        public void Delete(string key)
        {
            _dal.DeleteData(key);
        }

        #endregion
    }
}
