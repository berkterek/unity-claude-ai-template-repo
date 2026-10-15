#!/usr/bin/env python3
# check-unity-cli.py — judge for .claude/hooks/check-unity-cli.sh (invoked by it, via `python3 -I`).
# Input: the Bash command in env CHECK_UNITY_CLI_CMD (never argv). Output: exactly one stdout line,
# "ALLOW" or "BLOCK <reason>"; exit code 0. Any other outcome (crash, no output) makes the hook
# fall back to its narrow regex, i.e. fail closed.
import os, re, shlex

SHELLS   = {"bash", "sh", "zsh", "dash", "ksh"}
KEYWORDS = {"do", "then", "else", "elif", "{", "!", "while", "until", "if", "for", "coproc"}   # segment starts
# wrapper -> (its flags that take a separate value, positional operands to skip before the command)
WRAPPERS = {
    "env":     ({"-u", "--unset", "-C", "--chdir", "-P"}, 0),
    "command": (set(), 0),
    "builtin": (set(), 0),
    "exec":    ({"-a"}, 0),
    "time":    ({"-f", "--format", "-o", "--output"}, 0),
    "nohup":   (set(), 0),
    "nice":    ({"-n", "--adjustment"}, 0),
    "sudo":    ({"-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt", "-C", "--close-from",
                 "-D", "--chdir", "-r", "--role", "-t", "--type", "-U", "--other-user",
                 "-T", "--command-timeout"}, 0),
    "timeout": ({"-s", "--signal", "-k", "--kill-after"}, 1),                    # then DURATION
    "stdbuf":  ({"-i", "--input", "-o", "--output", "-e", "--error"}, 0),
    "xargs":   ({"-n", "--max-args", "-I", "-L", "--max-lines", "-P", "--max-procs", "-s",
                 "--max-chars", "-d", "--delimiter", "-E", "-a", "--arg-file"}, 0),
}
WRAPPERS["gtimeout"] = WRAPPERS["timeout"]
ALIASES      = {"cmd": "command", "pipe": "pipeline"}
GLOBAL_VALUE = {"--format", "--color", "--proxy", "--project-path"}
CMD_VALUE    = {"--project-path", "--runtime", "--runtime-path", "--timeout", "--format", "--color", "--proxy"}
CMD_OPTVALUE = {"--detail", "--query", "--tag", "--group_by", "--sort", "--order",
                "--offset", "--limit", "--caller", "--skill"}                     # `unity command --help`
MCP_VALUE    = {"--project-path", "--runtime", "--runtime-path", "--server", "--format", "--color", "--proxy"}
ASSIGN  = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
HEREDOC = re.compile(r"<<-?[ \t]*(['\"\\]?)(\w+)['\"]?([^\n]*)\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", re.S)

def substitutions(s, quotes=True):          # $(...) and `...` outside single quotes (quotes=False: heredoc body)
    out, i, n, sq, dq = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if c == "\\" and not sq: i += 2; continue
        if quotes and c == "'" and not dq: sq = not sq
        elif quotes and c == '"' and not sq: dq = not dq
        elif not sq and c == "`":
            j = s.find("`", i + 1)
            if j < 0: break
            out.append(s[i+1:j]); i = j
        elif not sq and s.startswith("$(", i):
            d, j = 1, i + 2
            while j < n and d:
                d += {"(": 1, ")": -1}.get(s[j], 0); j += 1
            out.append(s[i+2:j-1]); i = j - 1
        i += 1
    return out

def positional(args, value=frozenset(), optvalue=frozenset()):
    # Optional-value flags take the next token unless it starts with "-" (Commander-style; inferred
    # from the --help format, not measured). After "--" the next token IS the positional.
    k = 0
    while k < len(args):
        a = args[k]
        if a == "--": return k + 1 if k + 1 < len(args) else None
        if a.startswith("-"):
            if "=" not in a and a in value: k += 2; continue
            if "=" not in a and a in optvalue and k + 1 < len(args) and not args[k+1].startswith("-"): k += 2; continue
            k += 1; continue
        return k
    return None

def judge_unity(args):
    k = positional(args, GLOBAL_VALUE)
    if k is None: return None
    sub, rest = ALIASES.get(args[k], args[k]), args[k+1:]
    helping = any(a in ("-h", "--help") for a in rest)
    if sub == "command":
        j = positional(rest, CMD_VALUE, CMD_OPTVALUE)
        if j is not None: return f"`unity command {rest[j]}` runs Editor-side code (eval/eval_file run arbitrary C#) in a live Editor"
    if sub == "pipeline":
        j = positional(rest, GLOBAL_VALUE)
        if j is not None and rest[j] in ("install", "upgrade"):
            return f"`unity pipeline {rest[j]}` installs com.unity.pipeline (opens the eval channel) by writing Packages/manifest.json from Bash"
    if sub == "run":
        pre = rest[:rest.index("--")] if "--" in rest else rest
        if any(a == "--command" or a.startswith("--command=") for a in pre):
            return "`unity run --command` is the same Pipeline command channel and reuses an Editor already open on the project"
    if sub == "shell" and not helping:
        return "`unity shell` is a REPL whose commands arrive on stdin, where no hook can read them"
    if sub == "mcp" and not helping:
        j = positional(rest, MCP_VALUE)
        if j is None:
            return "bare `unity mcp` starts a stdio MCP server exposing the live Editor's commands as tools (a second Unity MCP channel)"
        if rest[j] == "configure" and any(a in ("--list", "--dry-run") for a in rest):
            return None
        return f"`unity mcp {rest[j]}` writes MCP server config for an AI client (only `configure --list` / `--dry-run` are read-only)"
    return None

def judge_segment(t, depth):
    i = 0
    while i < len(t):
        w = t[i]
        if w.lower() in ("coproc", "function") and i + 2 < len(t) and t[i+2] == "{": i += 2; continue   # coproc NAME { … }
        if w.lower() in KEYWORDS or ASSIGN.match(w): i += 1; continue
        name = os.path.basename(w).lower()
        if name not in WRAPPERS: break
        vflags, operands = WRAPPERS[name]
        i += 1
        while i < len(t) and t[i].startswith("-"):
            f = t[i]; i += 1
            if f == "--": break
            if name == "command" and f in ("-v", "-V"): return None      # `command -v unity` is a lookup
            if "=" not in f and f in vflags: i += 1
        i += operands                                                    # timeout's DURATION
    if i >= len(t): return None
    head, rest = os.path.basename(t[i]).lower(), t[i+1:]   # case-insensitive FS: `Unity` runs unity
    if head in SHELLS:
        for k, a in enumerate(rest):
            if re.match(r"^-[A-Za-z]*c[A-Za-z]*$", a) and k + 1 < len(rest):
                n = k + 2 if k + 1 < len(rest) and rest[k+1] == "--" else k + 1
                return judge(rest[n], depth + 1) if n < len(rest) else None
        return None
    if head == "eval": return judge(" ".join(rest), depth + 1)
    return judge_unity(rest) if head == "unity" else None

def judge(s, depth=0):
    if depth > 4: return None
    s = s.replace("\\\n", "")               # line continuation joins tokens, even inside quotes handed to -c
    bodies = [m.group(4) for m in HEREDOC.finditer(s) if not m.group(1)]   # unquoted: bash expands $( ) / ` `
    s = HEREDOC.sub(lambda m: "<<HEREDOC" + m.group(3), s)   # body = data; rest of the opener line stays commands (gap: `bash <<EOF`)
    for sub in substitutions(s) + [x for b in bodies for x in substitutions(b, quotes=False)]:
        r = judge(sub, depth + 1)
        if r: return r
    lx = shlex.shlex(s.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
    lx.whitespace_split, lx.commenters = True, ""
    seg = []
    for tok in list(lx) + [";"]:
        if tok and set(tok) <= set(";&|()"):
            r = judge_segment(seg, depth); seg = []
            if r: return r
        else:
            seg.append(tok)
    return None

def main():
    raw = os.environ.get("CHECK_UNITY_CLI_CMD", "")
    try:
        r = judge(raw)
    except ValueError:                       # unbalanced quotes: fail closed on the narrow pattern
        r = ("unparseable command naming a banned unity subcommand - blocked conservatively"
             if re.search(r"\bunity\b.*\b(command|cmd|shell|pipeline|pipe|mcp)\b", raw, re.S | re.I) else None)
    print("BLOCK " + r if r else "ALLOW")

main()
