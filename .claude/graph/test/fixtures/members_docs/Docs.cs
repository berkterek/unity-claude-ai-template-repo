using System;

namespace Fixtures.MembersDocs
{
    /// <summary>Contract for a doc-carrying service.</summary>
    public interface IDocService
    {
        /// <summary>Current total.</summary>
        int Total { get; }
    }

    /// <summary>
    /// Holds documented members
    /// across several lines.
    /// </summary>
    /// <remarks>Implements <see cref="IDocService"/> for the fixture.</remarks>
    public sealed class Docs : IDocService
    {
        /// <summary>Backing value for <see cref="Total"/>.</summary>
        private int _total;

        /// <summary>Current total.</summary>
        public int Total => _total;

        /// <summary>Adds <paramref name="amount"/> to the total.</summary>
        /// <remarks>Side effect: raises nothing.</remarks>
        public void Add(int amount)
        {
            _total += amount;
        }

        /// <summary>Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis.</summary>
        public void Long()
        {
        }

        // A plain comment, not a doc comment.
        public void PlainComment()
        {
        }

        /// <summary>Detached by a blank line.</summary>

        public void Detached()
        {
        }

        /// <summary>Attribute sits between doc and method.</summary>
        [Obsolete("fixture")]
        public void Attributed()
        {
        }

        public void Undocumented()
        {
        }
    }
}
