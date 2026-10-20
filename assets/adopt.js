
/* 00 · Browser fetches pinned GitHub revision, shell snippets never download. */
const ADOPT_LATEST_FILES=[
 'elk-oneclick-adopt.sh','elk-patch.sh','elk-report.sh','elk-report-web.py',
 'elk-oneclick-update.sh','proxysg-log-process.sh','proxysg-log-filter.conf',
 'proxysg-lib.sh','elk-tls-lib.sh','elk-color.sh','elk-stack-upgrade.sh'
];
let ADOPT_LATEST_SNAPSHOT=null;
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
  area.innerHTML='<div class="adopt-offline-steps"><strong>파일별 복사 순서</strong><span class="adopt-offline-step">① 준비</span><span class="adopt-offline-arrow">→</span><span class="adopt-offline-step">② 본문 조각 순서대로</span><span class="adopt-offline-arrow">→</span><span class="adopt-offline-step">③ 완료</span><span class="adopt-offline-steps-note">복원 후 SHA256 검사를 확인하세요.</span></div>'+files.map((f,i)=>{
    const pieces=f.b64.match(/.{1,1700}/g)||[];
    return '<details class="adoptlatestfile" style="border:1px solid #dbe4ef;border-radius:9px;padding:9px 10px;margin:6px 0;background:white"><summary style="cursor:pointer;font-size:13px;font-weight:650">'+String(i+1).padStart(2,'0')+' · '+adoptHtml(f.name)+' <small>('+Math.ceil(f.bytes/1024)+'KB · 복사 '+(pieces.length+2)+'회)</small></summary><div class="adoptlatestbtns" data-file="'+i+'" style="display:flex;gap:5px;flex-wrap:wrap;margin-top:9px"></div><small style="color:#64748b">SHA256 '+f.hash+'</small></details>';
  }).join('')+'<div class="adoptlatestfinal" style="margin:12px 0"><button class="ubtn primary" type="button" id="adoptCopyLatestInspect">전체 파일 검사 및 호환성 검사 명령 복사</button><button class="ubtn" type="button" id="adoptCopyLatestApply">관리 등록 명령 복사</button></div>';
  area.querySelectorAll('[data-file]').forEach(el=>{
   const ix=Number(el.dataset.file),f=files[ix],pieces=f.b64.match(/.{1,1700}/g)||[];
   function mk(label,text){const b=document.createElement('button');b.className='ubtn';b.type='button';b.textContent=label;b.onclick=async()=>{let ok=await copyText(text);b.textContent=ok?'복사됨 ✓':'복사 실패';setTimeout(()=>b.textContent=label,1500)};el.appendChild(b)}
   const dst='/root/elk-adopt/'+f.name,tmp='/root/elk-adopt/.'+f.name+'.b64';
   mk('① 준비',"sudo mkdir -p /root/elk-adopt && sudo sh -c ': > "+tmp+"'");
   pieces.forEach((x,j)=>mk('② 본문 '+(j+1)+'/'+pieces.length,"printf '%s' '"+x+"' | sudo tee -a "+tmp+" >/dev/null"));
   const decode="base64 -d '"+tmp+"'"+(f.gz?' | gzip -dc':'')+" > '"+dst+"'";
   const finish="sudo sh -c '"+decode+"' && echo '"+f.hash+"  "+dst+"' | sha256sum -c - && "+(/\.(sh|py)$/.test(f.name)?"sudo chmod 755 '"+dst+"' && ":'')+(/\.sh$/.test(f.name)?"sudo bash -n '"+dst+"' && ":'')+"sudo rm -f '"+tmp+"'";
   mk('③ 복원·검증',finish);
  });
  const inspect=area.querySelector('#adoptCopyLatestInspect');
  inspect.onclick=async()=>{let cmd='sudo bash -n /root/elk-adopt/elk-oneclick-adopt.sh && sudo bash /root/elk-adopt/elk-oneclick-adopt.sh --inspect';await copyText(cmd);inspect.textContent='복사됨 ✓'};
  const apply=area.querySelector('#adoptCopyLatestApply');
  apply.onclick=async()=>{let cmd='sudo bash /root/elk-adopt/elk-oneclick-adopt.sh --apply';await copyText(cmd);apply.textContent='복사됨 ✓'};
  adoptStatus('최신 GitHub 커밋 '+sha.slice(0,12)+' · '+files.length+'개 파일 확인 · 조회 시각 '+ADOPT_LATEST_SNAPSHOT.loadedAt+' (이 커밋으로 고정)');
 }catch(e){adoptStatus('최신 파일을 검증할 수 없습니다: '+(e&&e.message||e)+'. 오래된 내장본 대신 명령어 생성이 중단되었습니다.',true);}
 finally{btn.disabled=false;}
}
function wireAdoptLatestCommands(){const b=document.getElementById('adoptFetchLatest');if(b)b.onclick=adoptLatestFetch;}
