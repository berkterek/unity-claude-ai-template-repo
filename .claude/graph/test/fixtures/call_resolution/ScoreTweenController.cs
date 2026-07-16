namespace Game.Concretes.Score
{
    public sealed class ScoreTweenController
    {
        private float _value;

        public void AnimateTo(float target)
        {
            DOTween.To(() => _value, x => _value = x, target, 1f).SetEase(Ease.Linear);
        }
    }
}
