using System;

namespace Fixtures.MembersDocs
{
    public interface IShape
    {
        float Area { get; }
        void Scale(float factor);
    }

    public sealed class Members
    {
        public const int MAX_COUNT = 10;
        private static readonly string Label = "members";
        private int _a, _b;
        public event Action Changed;

        public int Count { get; private set; }
        public string Name => "fixture";
        public int Value
        {
            get { return _a; }
            set { _a = value; }
        }

        public Members()
        {
            _b = 0;
        }

        public int Sum(int x, int y) => x + y;

        public static int Combine(
            int left,
            int right)
        {
            return left * right;
        }

        [ContextMenu("Reset")]
        private void Reset()
        {
            _a = 0;
            Changed?.Invoke();
        }

#if UNITY_EDITOR
        private void EditorOnly()
        {
            _b = 1;
        }
#endif

        private sealed class Inner
        {
            private int _hidden;
            public int Hidden => _hidden;

            public void InnerMethod()
            {
            }
        }
    }

    public sealed class ContextMenuAttribute : Attribute
    {
        public ContextMenuAttribute(string name)
        {
        }
    }
}
