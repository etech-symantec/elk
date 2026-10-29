/* OneClick online adopt workflow — progressively enhance existing copy cards without changing commands. */
(function(){
 'use strict';
 const names=['다운로드 명령 복사','명령 복사','전체 도구 다운로드 명령 복사','등록 명령 복사'];
 const steps=[
  {n:'01',title:'관리 도구 준비',help:'등록 스크립트와 필요한 관리 도구를 내려받습니다.',kind:'준비',status:'필수'},
  {n:'02',title:'기존 환경 검사',help:'ELK 설치·서비스 상태를 읽기 전용으로 검사합니다.',kind:'검사',status:'필수'},
  {n:'03',title:'OneClick 관리 등록',help:'검사 후 기존 ELK를 OneClick 관리 대상으로 등록합니다.',kind:'등록',status:'최초 1회'}
 ];
 function buttonFor(name,root){return [...root.querySelectorAll('button')].find(b=>b.textContent.trim()===name);}
 function smallestCard(b,needle){
  let el=b?.parentElement;
  while(el && el!==document.body){
   const t=(el.innerText||'').trim();
   if(t.includes(needle) && el.querySelectorAll('button').length===1 && t.length<1200)return el;
   el=el.parentElement;
  }
  return null;
 }
 function enhance(){
  if(document.getElementById('adoptOnlineFlow'))return;
  const root=document.getElementById('main');if(!root)return;
  const buttons=names.map(n=>buttonFor(n,root));if(buttons.some(b=>!b))return;
  const needles=['0. 등록 도구','1. 호환성 검사','2. 전체 관리 도구','3. 관리 대상'];
  const cards=buttons.map((b,i)=>smallestCard(b,needles[i]));
  if(cards.some(c=>!c) || new Set(cards).size!==4)return;
  const top=cards[0].parentElement;
  if(!top || !cards.every(c=>c.parentElement===top))return;
  const flow=document.createElement('section');flow.id='adoptOnlineFlow';flow.className='adopt-flow';
  const title=document.createElement('div');title.className='adopt-flow-head';
  title.innerHTML='<div><div class="adopt-flow-tag">ONECLICK · ONLINE REGISTRATION</div><h3>기존 ELK 서버를 OneClick으로 등록하기</h3><p>인터넷 연결 서버 기준입니다. 아래 명령을 순서대로 복사해 Ubuntu 터미널에서 실행하세요.</p></div><span class="adopt-flow-pill">최초 등록 시 1회</span>';
  flow.appendChild(title);
  const three=document.createElement('div');three.className='adopt-flow-grid';
  steps.forEach((s,i)=>{
   const block=document.createElement('article');block.className='adopt-flow-step';
   const heading=document.createElement('header');heading.className='adopt-flow-stephead';
   const badge=document.createElement('span');badge.className='adopt-flow-number';badge.textContent=s.n;
   const h=document.createElement('div');const bold=document.createElement('strong');bold.textContent=s.title;
   const p=document.createElement('p');p.textContent=s.help;h.append(bold,p);
   const flag=document.createElement('span');flag.className='adopt-flow-flag';flag.textContent=s.status;
   heading.append(badge,h,flag);block.appendChild(heading);
   const inner=document.createElement('div');inner.className='adopt-flow-commands';
   if(i===0){inner.append(cards[0],cards[2]);}else if(i===1){inner.append(cards[1]);}else{inner.append(cards[3]);}
   block.appendChild(inner);three.appendChild(block);
  });
  flow.appendChild(three);
  const note=document.createElement('p');note.className='adopt-flow-note';note.textContent='이미 OneClick이 등록된 서버라면 신규 등록을 반복하지 말고 아래 OFFLINE REGISTRATION의 ‘기존 서버 · 웹 복구’ 절차를 사용하세요. 인터넷이 차단된 서버는 아래 오프라인 방식으로 진행합니다.';
  flow.appendChild(note);top.prepend(flow);
 }

 /* Choose one environment; never show both registration procedures simultaneously. */
 let selectedEnvironment=null;
 function getOnlineCards(root){
  const buttons=names.map(n=>buttonFor(n,root));
  return buttons.map((b,i)=>b?smallestCard(b,['0. 등록 도구','1. 호환성 검사','2. 전체 관리 도구','3. 관리 대상'][i]):null).filter(Boolean);
 }
 function setupEnvironmentSelector(){
  const root=document.getElementById('main'),offline=document.getElementById('adoptOfflineCopy');
  if(!root||!offline||!offline.isConnected)return;
  const onlineFlow=document.getElementById('adoptOnlineFlow');
  const cards=getOnlineCards(root);
  const first=onlineFlow||cards[0]||offline;
  let chooser=document.getElementById('adoptEnvironmentChooser');
  if(!chooser){
   chooser=document.createElement('div');chooser.id='adoptEnvironmentChooser';
   chooser.innerHTML='<div class="adopt-environment-heading"><strong>서버 인터넷 환경 선택</strong><span>서버의 인터넷 연결 여부를 선택하면 필요한 절차만 표시됩니다.</span></div><div class="adopt-environment-options"><button type="button" data-env="online"><strong>🌐 인터넷 환경</strong><small>서버에서 GitHub에 접속 가능 · 직접 다운로드 후 등록</small></button><button type="button" data-env="offline"><strong>🔒 인터넷 차단 환경</strong><small>인터넷 가능한 PC에서 명령 생성 · 서버에 복사해 등록</small></button></div>';
   chooser.addEventListener('click',event=>{const b=event.target.closest('button[data-env]');if(!b)return;selectedEnvironment=b.dataset.env;updateEnvironment();});
  }
  // Locate the title itself; never require subtitles to be in the same element.
  const titleText='기존 ELK를 그대로 유지하고 관리 도구만 추가';
  const anchor=[...root.querySelectorAll('*')].find(e=>e.children.length===0 && (e.textContent||'').includes(titleText));
  let header=null;
  if(anchor){
   for(let el=anchor;el&&el!==root;el=el.parentElement){
    const rect=el.getBoundingClientRect();
    if(rect.width>=280&&rect.height>=35&&rect.height<=125&&!el.contains(offline)&&!el.contains(onlineFlow)){
     header=el;break;
    }
   }
  }
  if(header&&header.parentElement){
   // Position as an accordion-header sibling, not as a nested interactive button.
   const parent=header.parentElement,hr=header.getBoundingClientRect(),pr=parent.getBoundingClientRect();
   if(chooser.parentElement!==parent)parent.appendChild(chooser);
   chooser.classList.add('adopt-environment-inline','adopt-environment-anchored');
   parent.classList.add('adopt-environment-anchor-parent');
   chooser.style.top=(hr.top-pr.top+hr.height/2)+'px';
   chooser.style.right=Math.max(10,pr.right-hr.right+12)+'px';
   header.classList.add('adopt-environment-target-header');
  }else if(first&&first.parentElement){
   if(chooser.parentElement!==first.parentElement)first.parentElement.insertBefore(chooser,first);
   chooser.classList.remove('adopt-environment-inline','adopt-environment-anchored');
   chooser.style.top='';chooser.style.right='';
  }
  function updateEnvironment(){
   chooser.querySelectorAll('button[data-env]').forEach(b=>{const chosen=selectedEnvironment===b.dataset.env;b.classList.toggle('selected',chosen);b.setAttribute('aria-pressed',String(chosen));});
   if(onlineFlow)onlineFlow.hidden=selectedEnvironment!=='online';
   cards.forEach(card=>{if(!onlineFlow||!onlineFlow.contains(card))card.hidden=selectedEnvironment!=='online';});
   offline.hidden=selectedEnvironment!=='offline';
   let hint=document.getElementById('adoptEnvironmentHint');
   if(!hint){hint=document.createElement('p');hint.id='adoptEnvironmentHint';hint.textContent='위 두 환경 중 하나를 선택해 등록 절차를 시작하세요.';chooser.appendChild(hint);}
   hint.hidden=selectedEnvironment!==null;
  }
  updateEnvironment();
 }


 /* The old four-item strip repeats internal adoption phases and confuses users.
    Keep the actionable environment chooser and three guided steps instead. */
 function hideLegacyAdoptSummary(){
  const root=document.getElementById('main');if(!root)return;
  const labels=['읽기 전용 검사','기존 설정 백업','관리 환경 생성','필요한 기능만 패치'];
  const nodes=[...root.querySelectorAll('div,section,ol,ul')];
  for(const el of nodes){
   if(el.id==='adoptOnlineFlow'||el.id==='adoptEnvironmentChooser'||el.closest('#adoptOnlineFlow,#adoptEnvironmentChooser'))continue;
   if(el.dataset.adoptLegacyHidden==='1')continue;
   const t=(el.innerText||'').trim();
   if(t.length<30||t.length>420||!labels.every(s=>t.includes(s)))continue;
   const childMatches=[...el.children].filter(ch=>labels.some(s=>(ch.innerText||'').includes(s)));
   if(childMatches.length<3||el.querySelector('button,input,select,textarea'))continue;
   el.dataset.adoptLegacyHidden='1';
   el.hidden=true;el.style.display='none';
   break;
  }
 }
 let pending=false;
 const observer=new MutationObserver(()=>{if(pending)return;pending=true;queueMicrotask(()=>{pending=false;enhance();setupEnvironmentSelector();hideLegacyAdoptSummary()});});
 observer.observe(document.documentElement,{childList:true,subtree:true});
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>{enhance();setupEnvironmentSelector();hideLegacyAdoptSummary()});else{enhance();setupEnvironmentSelector();hideLegacyAdoptSummary();}
})();
