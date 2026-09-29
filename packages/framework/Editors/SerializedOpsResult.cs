using System.Collections.Generic;

namespace Framework.Editors
{
    public sealed class SerializedOpStatus
    {
        public int Index;
        public string Op;
        public string Asset;
        public string Property;
        public bool Success;
        public string Message;
    }

    public sealed class SerializedOpsResult
    {
        public bool Success;          // false if ANY op failed or the manifest aborted
        public bool Aborted;          // true = whole manifest rejected, Statuses may be empty
        public string AbortReason;
        public List<SerializedOpStatus> Statuses = new List<SerializedOpStatus>();
    }
}
