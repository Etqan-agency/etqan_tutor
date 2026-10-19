. ./lib.sh; . ./ids.env
echo "== TC-008"
api tea qa GET reports/missing/; echo "[$CODE] missing has U1: $(j "any(x.get('id', x.get('session',{}).get('id') if isinstance(x.get('session'),dict) else None)==$U1 for x in (d['results'] if isinstance(d,dict) and 'results' in d else d))") sample: ${RESP:0:300}"
W=400 r tea qa PUT sessions/$U1/report/ '{"behaviour":5,"participation":4,"notes":"SCN good <b>bold</b>"}'
W=200 r tea qa PUT sessions/$U1/report/ '{"behaviour":0,"participation":4,"notes":"x"}'
W=200 r tea qa PUT sessions/$U1/report/ '{"behaviour":6,"participation":4,"notes":"x"}'
W=200 r tea qa PUT sessions/$U1/report/ '{"behaviour":"a","participation":4,"notes":"x"}'
api tea qa GET reports/missing/; echo "[$CODE] missing has U1 after: $(j "any(x.get('id', x.get('session',{}).get('id') if isinstance(x.get('session'),dict) else None)==$U1 for x in (d['results'] if isinstance(d,dict) and 'results' in d else d))")"
W=200 r t2 qa PUT sessions/$U1/report/ '{"behaviour":1,"participation":1,"notes":"T2"}'
W=200 r t2 qa GET sessions/$U1/report/
W=400 r sa1 qa GET sessions/$U1/report/
W=400 r pa qa GET sessions/$U1/report/
W=200 r pb qa GET sessions/$U1/report/
W=200 r sa2 qa GET sessions/$U1/report/
W=400 r adm qa GET sessions/$U1/report/
QQ "select session_id,behaviour,participation,notes from scheduling_sessionreport where session_id=$U1"
