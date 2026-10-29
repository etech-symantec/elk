
/* 00 · Browser fetches pinned GitHub revision, shell snippets never download. */
const ADOPT_LATEST_FILES=[
 'elk-oneclick-adopt.sh','elk-patch.sh','elk-report.sh','elk-report-web.py',
 'elk-oneclick-update.sh','proxysg-log-process.sh','proxysg-log-filter.conf',
 'proxysg-lib.sh','elk-tls-lib.sh','elk-color.sh','elk-stack-upgrade.sh'
];
let ADOPT_LATEST_SNAPSHOT=null;
const ADOPT_DESCRIPTIONS=['기존 ELK 관리 등록·웹 복구','패치 및 설정 관리','상태 진단 및 HTML 리포트','5602 포트 리포트 웹 서버','GitHub 업데이트 도구','ProxySG 로그 후처리','ProxySG 필터 규칙','ProxySG 공통 함수','인증서/TLS 공통 함수','컬러 출력 공통 함수','ELK 스택 업그레이드'];
function adoptLimit(){const n=Number(document.getElementById('adoptMaxChars')?.value||2500);return Number.isFinite(n)?Math.max(500,Math.min(10000,Math.floor(n))):2500;}
async function adoptCopyCommand(cmd){
 try{
  if(navigator.clipboard && window.isSecureContext){await navigator.clipboard.writeText(cmd);return true;}
 }catch(e){}
 const ta=document.createElement('textarea');ta.value=cmd;ta.setAttribute('readonly','');ta.style.cssText='position:fixed;left:-9999px;top:0;opacity:0';document.body.appendChild(ta);
 try{ta.focus();ta.select();ta.setSelectionRange(0,ta.value.length);return document.execCommand('copy')===true;}catch(e){return false;}finally{ta.remove();}
}
function adoptCopyButton(label,cmd){
 const b=document.createElement('button');b.className='ubtn adopt-copy-btn';b.type='button';b.textContent=label;b.title='클릭하여 명령어 복사 · '+cmd.length+'자';b.dataset.originalLabel=label;
 b.onclick=async()=>{
  if(b.disabled)return;b.disabled=true;
  const ok=await adoptCopyCommand(cmd);b.disabled=false;
  if(ok){b.classList.add('adopt-copied');b.textContent='✓ 복사 완료';clearTimeout(b.labelTimer);clearTimeout(b.copyTimer);b.labelTimer=setTimeout(()=>{b.textContent=label},1500);b.copyTimer=setTimeout(()=>{b.classList.remove('adopt-copied');b.textContent=label},60000);}
  else{b.textContent='복사 실패 · 다시 시도';adoptStatus('클립보드 복사 실패: HTTPS 또는 브라우저 권한 확인',true);setTimeout(()=>{if(!b.classList.contains('adopt-copied'))b.textContent=label},4000);}
 };
 return b;
}
function adoptRenderSnapshot(){
 const area=document.getElementById('adoptLatestFiles'),s=ADOPT_LATEST_SNAPSHOT;if(!area||!s)return;
 const limit=adoptLimit();area.innerHTML='<div class="adopt-offline-steps">① 준비 → ② 본문 순서대로 → ③ 복원·검증 <small>복사 후 60초간 녹색 표시</small></div>';
 s.files.forEach((f,i)=>{
  const dst='/root/elk-adopt/'+f.name,tmp='/root/elk-adopt/.'+f.name+'.b64';
  const overhead=("printf '%s' '' | sudo tee -a "+tmp+" >/dev/null").length;
  const chunk=Math.floor((limit-overhead)/4)*4;if(chunk<4)throw Error('명령 제한 글자 수가 너무 작습니다');
  const pieces=f.b64.match(new RegExp('.{1,'+chunk+'}','g'))||[];
  const d=document.createElement('details');d.className='adoptlatestfile';
  const summary=document.createElement('summary');summary.innerHTML='<span class="adopt-file-meta"><strong>'+String(i+1).padStart(2,'0')+' · '+adoptHtml(f.name)+'</strong><span>'+adoptHtml(ADOPT_DESCRIPTIONS[i])+'</span></span><small class="adopt-piece-count">'+pieces.length+'조각</small>';
  d.appendChild(summary);
  const row=document.createElement('div');row.className='adoptlatestbtns';row.classList.add('adopt-preview-actions');
  row.appendChild(adoptCopyButton('① 준비',"sudo install -d -m 700 /root/elk-adopt && sudo sh -c ': > "+tmp+"'"));
  pieces.forEach((x,j)=>row.appendChild(adoptCopyButton('② '+(j+1)+'/'+pieces.length,"printf '%s' '"+x+"' | sudo tee -a "+tmp+" >/dev/null")));
  const decode="base64 -d '"+tmp+"'"+(f.gz?' | gzip -dc':'')+" > '"+dst+"'";
  const finish="sudo sh -c '"+decode+"' && echo '"+f.hash+"  "+dst+"' | sudo sha256sum -c - && sudo chmod "+(/\.(sh|py)$/.test(f.name)?'755':'644')+" '"+dst+"'"+(/\.sh$/.test(f.name)?" && sudo bash -n '"+dst+"'":"")+" && sudo rm -f '"+tmp+"'";
  row.appendChild(adoptCopyButton('③ 복원·검증',finish));d.appendChild(row);
  const hash=document.createElement('small');hash.textContent='SHA256 '+f.hash;d.appendChild(hash);area.appendChild(d);
 });
 const final=document.createElement('div');final.className='adoptlatestfinal';
 const actions=[
  ['등록 스크립트·환경 검사','스크립트 문법과 ELK 상태를 읽기 전용으로 확인','sudo bash -n /root/elk-adopt/elk-oneclick-adopt.sh && sudo bash /root/elk-adopt/elk-oneclick-adopt.sh --inspect'],
  ['기존 서버 · 웹 복구','기존 설정은 유지하고 5602 웹 서비스만 복구','sudo bash /root/elk-adopt/elk-oneclick-adopt.sh --repair-report-web --source-dir /root/elk-adopt'],
  ['OneClick 미등록 서버 등록','기존 ELK를 OneClick 관리 대상으로 최초 등록','sudo bash /root/elk-adopt/elk-oneclick-adopt.sh --apply --source-dir /root/elk-adopt --enable-report-web']
 ];
 actions.forEach(([title,description,command])=>{const item=document.createElement('div');item.className='adopt-final-action';item.appendChild(adoptCopyButton(title,command));const desc=document.createElement('small');desc.textContent=description;item.appendChild(desc);final.appendChild(item)});
 area.appendChild(final);adoptStatus('GitHub '+s.sha.slice(0,12)+' · '+s.files.length+'개 · 최대 '+limit+'자');
}

function adoptHtml(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}
function adoptStatus(message,error=false){const e=document.getElementById('adoptLatestStatus');if(e){e.textContent=message;e.style.background=error?'#fee2e2':'#e0f2fe';e.style.color=error?'#991b1b':'#075985';}}
function adoptBytesToB64(arr){let s='';for(let i=0;i<arr.length;i+=16384)s+=String.fromCharCode(...arr.subarray(i,i+16384));return btoa(s);}
async function adoptSHA256(buf){let bytes=new Uint8Array(await crypto.subtle.digest('SHA-256',buf));return Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('');}
async function adoptLatestFetch(){
 const btn=document.getElementById('adoptFetchLatest'),area=document.getElementById('adoptLatestFiles');
 if(!btn||!area)return;
 btn.disabled=true;area.innerHTML='';ADOPT_LATEST_SNAPSHOT=null;
 try{
  adoptStatus('GitHub main 최신 커밋을 조회하고 있습니다…');
  const r=await fetch('https://api.github.com/repos/etech-symantec/elk/commits/main',{cache:'no-store',headers:{Accept:'application/vnd.github+json'}});
  if(!r.ok)throw new Error('GitHub API HTTP '+r.status);
  const info=await r.json(),sha=String(info.sha||'');if(!/^[a-f0-9]{40}$/.test(sha))throw new Error('최신 커밋 SHA 조회 실패');
  const files=[];
  for(let i=0;i<ADOPT_LATEST_FILES.length;i++){
   const name=ADOPT_LATEST_FILES[i];adoptStatus('최신 커밋 '+sha.slice(0,10)+' · 파일 수집 '+(i+1)+'/'+ADOPT_LATEST_FILES.length+' : '+name);
   const u='https://raw.githubusercontent.com/etech-symantec/elk/'+sha+'/_internal/core/'+name;
   const res=await fetch(u,{cache:'no-store'});
   if(!res.ok)throw new Error(name+' 다운로드 실패: HTTP '+res.status+' (현재 GitHub에 없는 파일일 수 있음)');
   const data=await res.arrayBuffer();if(data.byteLength<10)throw new Error(name+' 파일이 비정상적으로 작습니다.');
   const hash=await adoptSHA256(data);let bytes=new Uint8Array(data),compressed=bytes;
   if(typeof CompressionStream==='function'){
    const stream=new Blob([bytes]).stream().pipeThrough(new CompressionStream('gzip'));
    compressed=new Uint8Array(await new Response(stream).arrayBuffer());
   }
   const gz=compressed!==bytes,b64=adoptBytesToB64(compressed);
   files.push({name,hash,bytes:data.byteLength,gz,b64});
  }
  ADOPT_LATEST_SNAPSHOT={sha,files,loadedAt:new Date().toLocaleString('ko-KR')};
  adoptRenderSnapshot();
  adoptStatus('최신 GitHub 커밋 '+sha.slice(0,12)+' · '+files.length+'개 파일 확인 · 조회 시각 '+ADOPT_LATEST_SNAPSHOT.loadedAt+' (이 커밋으로 고정)');
 }catch(e){adoptStatus('최신 파일을 검증할 수 없습니다: '+(e&&e.message||e)+'. 오래된 내장본 대신 명령어 생성이 중단되었습니다.',true);}
 finally{btn.disabled=false;}
}
function wireAdoptLatestCommands(){const b=document.getElementById('adoptFetchLatest');if(!b)return;b.onclick=adoptLatestFetch;const label=document.createElement('label');label.textContent='명령어 최대 글자 수 ';const inp=document.createElement('input');inp.id='adoptMaxChars';inp.type='number';inp.min='500';inp.max='10000';inp.step='100';inp.value='2500';inp.style.width='90px';inp.onchange=()=>{if(ADOPT_LATEST_SNAPSHOT)adoptRenderSnapshot()};label.appendChild(inp);b.insertAdjacentElement('beforebegin',label);}
