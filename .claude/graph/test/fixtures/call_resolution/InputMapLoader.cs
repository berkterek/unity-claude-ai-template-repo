namespace Game.Concretes.Input
{
    public sealed class InputMapLoader
    {
        public void Load(string json)
        {
            var asset = InputActionAsset.FromJson(json);
            asset.FindActionMap("gameplay");
        }
    }
}
