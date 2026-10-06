#!/usr/bin/env python3
"""ELK report web viewer/refresh endpoint. Only whitelisted elk-report options are accepted."""
import argparse, json, os, shlex, subprocess
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path

ap=argparse.ArgumentParser()
ap.add_argument('--host',default='0.0.0.0'); ap.add_argument('--port',type=int,default=5602)
ap.add_argument('--report',default='/usr/local/sbin/elk-report'); ap.add_argument('--html',default='/var/lib/elk-report/report.html')
ap.add_argument('--env',default='/etc/elk-auto/elk.env')
a=ap.parse_args()
HTML=Path(a.html); REPORT=a.report
ALLOWED_FLAGS={'--no-color','--no-html'}
VALUE_FLAGS={'--only','--skip','--stale-hours','--env','--html'}

def parse_command(text):
    try: parts=shlex.split(text)
    except ValueError as e: raise ValueError(str(e))
    if parts[:2]==['sudo','elk-report']: parts=parts[1:]
    if not parts or parts[0] not in ('elk-report',REPORT): raise ValueError('elk-report 명령만 실행할 수 있습니다.')
    out=[REPORT]; i=1
    while i<len(parts):
        x=parts[i]
        if x in ALLOWED_FLAGS: out.append(x); i+=1; continue
        if x in VALUE_FLAGS:
            if i+1>=len(parts): raise ValueError(f'{x} 뒤에 값이 필요합니다.')
            v=parts[i+1]
            if x=='--stale-hours' and (not v.isdigit() or not 1<=int(v)<=8760): raise ValueError('--stale-hours 범위는 1~8760입니다.')
            if x in ('--only','--skip') and any(ch not in 'abcdefghijklmnopqrstuvwxyz0123456789_,-' for ch in v.lower()): raise ValueError(f'{x} 값 형식이 올바르지 않습니다.')
            # Browser에서 출력 경로/환경파일을 임의로 바꾸지 못하게 고정
            if x in ('--env','--html'): raise ValueError(f'웹에서는 {x} 옵션을 사용할 수 없습니다.')
            out += [x,v]; i+=2; continue
        raise ValueError(f'허용되지 않은 옵션: {x}')
    out += ['--html',str(HTML),'--env',a.env]
    return out

def run_report(cmd=None):
    args=cmd or [REPORT,'--html',str(HTML),'--env',a.env,'--no-color']
    p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=180,env={**os.environ,'NO_COLOR':'1'})
    # elk-report 0/1/2 = 정상/주의/이상이고 모두 정상 실행으로 취급
    if p.returncode not in (0,1,2): raise RuntimeError((p.stdout or 'elk-report 실행 실패')[-2000:])
    return p.returncode,p.stdout

class H(BaseHTTPRequestHandler):
    server_version='ELKReportWeb/2.9.5'
    def log_message(self,fmt,*args): print('[elk-report-web]',fmt%args,flush=True)
    def send_json(self,status,obj):
        b=json.dumps(obj,ensure_ascii=False).encode(); self.send_response(status); self.send_header('Content-Type','application/json; charset=utf-8'); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path not in ('/','/report.html'):
            self.send_error(404); return
        if not HTML.exists():
            try: run_report()
            except Exception as e: self.send_error(503,str(e)); return
        b=HTML.read_bytes(); self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        if self.path!='/api/run': self.send_error(404); return
        try:
            n=min(int(self.headers.get('Content-Length','0') or 0),8192); body=json.loads(self.rfile.read(n) or b'{}'); cmd=parse_command(str(body.get('command','elk-report'))); rc,out=run_report(cmd)
            self.send_json(200,{'ok':True,'status':rc,'message':'최신 점검 결과를 생성했습니다.','tail':'\n'.join(out.splitlines()[-8:])})
        except ValueError as e: self.send_json(400,{'ok':False,'error':str(e)})
        except subprocess.TimeoutExpired: self.send_json(504,{'ok':False,'error':'elk-report 실행 시간이 180초를 초과했습니다.'})
        except Exception as e: self.send_json(500,{'ok':False,'error':str(e)})

if __name__=='__main__':
    HTML.parent.mkdir(parents=True,exist_ok=True)
    try: run_report()
    except Exception as e: print('[WARN] initial report:',e,flush=True)
    print(f'[INFO] ELK report web: http://{a.host}:{a.port}/',flush=True)
    ThreadingHTTPServer((a.host,a.port),H).serve_forever()
