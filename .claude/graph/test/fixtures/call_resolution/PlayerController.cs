namespace Game.Concretes.Players
{
    public sealed class PlayerController
    {
        private Game.Abstracts.Audio.ISoundService _soundService;

        public void OnJump()
        {
            _soundService.Play("jump");
        }
    }
}
