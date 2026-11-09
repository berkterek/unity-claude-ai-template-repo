# pipeline-breakdown.py — per-command cost split for /plan-module and /orchestrate runs.
# Main session vs subagents, per agent type, uncached startup share.
# Units = cacheRead*0.1 + cacheWrite*1.25 + input + output*5 (token-weighted, not $).
#
# Usage: python3 -I .claude/scripts/pipeline-breakdown.py ~/.claude/projects/<project-dir> [since-ISO-date]
#   since: only runs that started on/after this date, e.g. 2026-11-07 (to compare new runs vs the baseline)
# Baseline (nile, measured 2026-11-06, all runs before the fixes):
#   /orchestrate 17 runs avg 14.4M, main 66%, 214 turns/run, peak ctx 504k
#   /plan-module 20 runs avg 3.7M, opus planner 49%, reviewer 19%, main 31%
import json,glob,os,re,sys,collections,datetime
root=sys.argv[1]; WANT=('plan-module','orchestrate')
SINCE=datetime.datetime.fromisoformat(sys.argv[2]+'T00:00:00+00:00') if len(sys.argv)>2 else None
def U(u): return u.get('cache_read_input_tokens',0)*.1+u.get('cache_creation_input_tokens',0)*1.25+u.get('input_tokens',0)+u.get('output_tokens',0)*5
def T(s): return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
def txt(c):
    if isinstance(c,str): return c
    return '\n'.join(x.get('text','') for x in c or [] if isinstance(x,dict) and x.get('type')=='text')
# subagents: (start ts, type, model, units, startup units, turns)
def subs(sess):
    out=[]
    for m in glob.glob(sess[:-6]+'/subagents/*.meta.json'):
        meta=json.load(open(m)); seen=set(); u=0; su=None; first=None; turns=0
        for line in open(m[:-10]+'.jsonl',errors='ignore'):
            try:o=json.loads(line)
            except:continue
            first=first or o.get('timestamp')
            mm=o.get('message') or {}
            if o.get('type')=='assistant' and mm.get('id') and mm['id'] not in seen and 'usage' in mm:
                seen.add(mm['id']); x=U(mm['usage']); u+=x; turns+=1
                if su is None: su=x
        if first: out.append((T(first),meta.get('agentType'),meta.get('model') or 'default',u,su or 0,turns))
    return out
agg={c:collections.defaultdict(float) for c in WANT}; byagent={c:collections.defaultdict(lambda:[0,0.0,0.0,0]) for c in WANT}; nruns=collections.Counter()
for sess in glob.glob(root+'/*.jsonl'):
    S_=subs(sess); runs=[]; cur=None; seen=set(); last_asst=None
    for line in open(sess,errors='ignore'):
        try:o=json.loads(line)
        except:continue
        t=o.get('timestamp'); mm=o.get('message') or {}; c=mm.get('content')
        if o.get('type')=='user':
            s=c if isinstance(c,str) else txt(c)
            cmd=re.search(r'<command-name>/?([\w:-]+)</command-name>',s or '')
            if cmd and cmd.group(1) not in('model','context','cost','status','compact','clear'):
                if cur: runs.append(cur)
                cur=dict(cmd=cmd.group(1),start=T(t),end=T(t),main=0.0,turns=0,peak=0,human=0.0,startup=None) if cmd.group(1) in WANT else None
                last_asst=None; continue
            is_tool=isinstance(c,list) and any(isinstance(x,dict) and x.get('type')=='tool_result' for x in c)
            if cur and not is_tool and s and not s.startswith('<task-notification') and '<system-reminder>' not in s[:20] and last_asst:
                cur['human']+=(T(t)-last_asst).total_seconds()/60
        if not cur: continue
        if t: cur['end']=T(t)
        if o.get('type')=='assistant':
            if t: last_asst=T(t)
            if mm.get('id') and mm['id'] not in seen and 'usage' in mm:
                seen.add(mm['id']); u=mm['usage']; x=U(u); cur['main']+=x; cur['turns']+=1
                ctx=u.get('cache_read_input_tokens',0)+u.get('cache_creation_input_tokens',0)+u.get('input_tokens',0)
                cur['peak']=max(cur['peak'],ctx)
                if cur['startup'] is None: cur['startup']=x
    if cur: runs.append(cur)
    for r in runs:
        if SINCE and r['start']<SINCE: continue
        mine=[s for s in S_ if r['start']<=s[0]<=r['end']]
        c=r['cmd']; a=agg[c]; nruns[c]+=1
        a['main']+=r['main']; a['main_turns']+=r['turns']; a['peak']+=r['peak']; a['main_startup']+=r['startup'] or 0
        a['minutes']+=(r['end']-r['start']).total_seconds()/60; a['human']+=r['human']
        for (st,ty,mo,u,su,tu) in mine:
            a['agents']+=u; a['agent_startup']+=su
            b=byagent[c][f'{ty} [{mo}]']; b[0]+=1; b[1]+=u; b[2]+=su; b[3]+=tu
for c in WANT:
    a=agg[c]; n=nruns[c]; tot=a['main']+a['agents']
    if not n: print(f'\n===== {c}: no runs'); continue
    print(f"\n===== {c}: {n} runs   total {tot/1e6:.1f}M units   avg {tot/n/1e6:.1f}M/run   avg {a['minutes']/n:.0f} min/run (human wait {a['human']/n:.0f} min, unreliable)")
    print(f"  main session : {a['main']/1e6:6.1f}M ({100*a['main']/tot:3.0f}%)  avg {a['main_turns']/n:.0f} turns/run, avg peak ctx {a['peak']/n/1000:.0f}k")
    print(f"  subagents    : {a['agents']/1e6:6.1f}M ({100*a['agents']/tot:3.0f}%)  of which first-turn startup {a['agent_startup']/1e6:.1f}M ({100*a['agent_startup']/tot:.0f}% of total)")
    for k,(sp,u,su,tu) in sorted(byagent[c].items(),key=lambda x:-x[1][1])[:10]:
        print(f"     {k:38} spawns {sp:4}  {u/1e6:6.1f}M ({100*u/tot:3.0f}%)  turns/spawn {tu/sp:4.0f}  startup {100*su/u if u else 0:3.0f}%")
