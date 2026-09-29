using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;

namespace Framework.Logging
{
    public static class DLog
    {
        #region Private Fields

        // Seeded from the enum itself, deliberately: a tag added to LogTag is live the moment
        // it is declared. A hand-written literal list here means a new tag is silent by default
        // for Log/Warning — the call compiles, runs, matches nothing and returns, which reads as
        // "logging is broken" rather than "this tag is off". See rules/logging.md Card 3.
        private static readonly HashSet<LogTag> _enabledTags =
            new(Enum.GetValues(typeof(LogTag)).Cast<LogTag>());

        #endregion

        #region Public Methods

        [Conditional("UNITY_EDITOR")]
        [Conditional("DEVELOPMENT_BUILD")]
        public static void Log(LogTag tag, string message)
        {
            if (!_enabledTags.Contains(tag))
            {
                return;
            }

            UnityEngine.Debug.Log($"[{tag}] {message}");
        }

        [Conditional("UNITY_EDITOR")]
        [Conditional("DEVELOPMENT_BUILD")]
        public static void Warning(LogTag tag, string message)
        {
            if (!_enabledTags.Contains(tag))
            {
                return;
            }

            UnityEngine.Debug.LogWarning($"[{tag}] {message}");
        }

        // Deliberate and load-bearing: NO [Conditional] and NO _enabledTags gate on Error.
        // An error is a defect report, not a diagnostic — it must survive into release
        // builds and must never be silenced by DLog.Disable(tag). Do not "tidy" these back in.
        public static void Error(LogTag tag, string message)
        {
            UnityEngine.Debug.LogError($"[{tag}] {message}");
        }

        // Deliberate and load-bearing: NO [Conditional] and NO _enabledTags gate on Error.
        // An error is a defect report, not a diagnostic — it must survive into release
        // builds and must never be silenced by DLog.Disable(tag). Do not "tidy" these back in.
        //
        // Prefer this overload wherever an exception object exists: LogException is what makes
        // the stack trace clickable in the console. Passing exception.Message to the 2-argument
        // overload instead loses the file and the line. See rules/logging.md Card 4.
        public static void Error(LogTag tag, string message, Exception exception)
        {
            UnityEngine.Debug.LogError($"[{tag}] {message}");
            UnityEngine.Debug.LogException(exception);
        }

        [Conditional("UNITY_EDITOR")]
        [Conditional("DEVELOPMENT_BUILD")]
        public static void Enable(LogTag tag)
        {
            _enabledTags.Add(tag);
        }

        [Conditional("UNITY_EDITOR")]
        [Conditional("DEVELOPMENT_BUILD")]
        public static void Disable(LogTag tag)
        {
            _enabledTags.Remove(tag);
        }

        #endregion
    }
}
