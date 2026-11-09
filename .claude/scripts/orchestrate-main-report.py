# orchestrate-main-report.py — what the /orchestrate MAIN session spends its turns on.
# Cost per phase (pre-spawn / between spawns / tail) and per tool the turn calls.
# Units = cacheRead*0.1 + cacheWrite*1.25 + input + output*5.
#
# Usage: python3 -I .claude/scripts/orchestrate-main-report.py ~/.claude/projects/<project-dir> [since-ISO-date]
# Baseline (nile, 17 runs before the 2026-11-06 fixes): 214 turns/run, ~44k units/turn;
#   74% between spawns; Bash 45/run, Unity MCP ~84/run (get_test_job 13, run_tests 8), Edit 13, Read 11, Agent 14.
# Target after fixes: ~5 main turns per task, no run_tests/get_test_job rows.
import json,glob,re,sys,collections,datetime
root=sys.argv[1]
SINCE=sys.argv[2] if len(sys.argv)>2 else None
def U(u): return u.get('cache_read_input_tokens',0)*.1+u.get('cache_creation_input_tokens',0)*1.25+u.get('input_tokens',0)+u.get('output_tokens',0)*5
def txt(c):
    if isinstance(c,str): return c
    return '\n'.join(x.get('text','') for x in c or [] if isinstance(x,dict) and x.get('type')=='text')
bytool=collections.defaultdict(lambda:[0,0.0]); phase=collections.defaultdict(lambda:[0,0.0])
runs=[]
for sess in glob.glob(root+'/*.jsonl'):
    cur=None; seen=set(); turns=[]
    for line in open(sess,errors='ignore'):
        try:o=json.loads(line)
        except:continue
        mm=o.get('message') or {}; c=mm.get('content')
        if o.get('type')=='user':
            s=c if isinstance(c,str) else txt(c)
            cmd=re.search(r'<command-name>/?([\w:-]+)</command-name>',s or '')
            if cmd and cmd.group(1) not in('model','context','cost','status','compact','clear'):
                if cur and turns: runs.append(turns)
                cur=cmd.group(1)=='orchestrate' and (not SINCE or (o.get('timestamp') or '')>=SINCE); turns=[]; continue
        if not cur or o.get('type')!='assistant': continue
        tools=[y['name'] for y in (c if isinstance(c,list) else []) if isinstance(y,dict) and y.get('type')=='tool_use']
        if mm.get('id') and mm['id'] not in seen and 'usage' in mm:
            seen.add(mm['id']); x=U(mm['usage']); turns.append(['text-only',x])
        if tools and turns and turns[-1][0]=='text-only':
            k=tools[0]
            if k.startswith('mcp__UnityMCP'): k='MCP:'+k.split('__')[-1]
            turns[-1][0]=k
    if cur and turns: runs.append(turns)
n=len(runs); tot=0
if not n: print('no /orchestrate runs'); sys.exit(0)
for turns in runs:
    last_spawn=max([i for i,(k,_) in enumerate(turns) if k=='Agent'] or [-1]); first_spawn=min([i for i,(k,_) in enumerate(turns) if k=='Agent'] or [len(turns)])
    for i,(k,x) in enumerate(turns):
        bytool[k][0]+=1; bytool[k][1]+=x; tot+=x
        p='pre-spawn' if i<first_spawn else ('tail after last spawn' if i>last_spawn else 'between spawns')
        phase[p][0]+=1; phase[p][1]+=x
print('runs',n,' main total',round(tot/1e6,1),'M  avg',round(tot/n/1e6,2),'M/run  avg turns/run',round(sum(len(t) for t in runs)/n))
print('\nphase                  turns/run   M/run   share')
for k,(t,x) in sorted(phase.items(),key=lambda z:-z[1][1]): print(f'{k:22s} {t/n:7.1f} {x/n/1e6:7.2f} {x/tot*100:5.1f}%')
print('\nturn first-tool              turns/run   M/run   share  avg units/turn')
for k,(t,x) in sorted(bytool.items(),key=lambda z:-z[1][1])[:25]: print(f'{k:28s} {t/n:7.1f} {x/n/1e6:7.2f} {x/tot*100:5.1f}%  {x/t/1e3:6.0f}k')
