
(function(){
  'use strict';
  const STORAGE_KEY='elk-oneclick-menu-tour-seen-v1';
  const steps=[
    {target:['simpleBtn'],title:'빠른 설정',description:'처음 설치한다면 여기부터 시작하세요. 꼭 필요한 항목만 순서대로 입력해 설치 파일을 만들 수 있어요.'},
    {target:['advancedBtn'],title:'고급 설정',description:'로그 경로, 시간대, 저장 공간, 보안 등 세부 설정을 직접 바꿔야 할 때 사용해요.'},
    {target:['patchBtn'],title:'패치',description:'이미 설치한 서버에서 일부 설정만 바꾸거나 변경 사항을 반영할 때 사용해요. 적용 전 내용을 확인하세요.'},
    {target:['inspectBtn'],title:'점검',description:'서버가 잘 동작하는지 확인하는 점검 명령과 상태 확인 방법을 안내해 줘요.'},
    {target:['importBtn','importShBtn'],title:'기존 입력값 불러오기',description:'예전에 저장한 elk.env 또는 설치용 SH 파일을 가져와 입력값을 다시 채워요. 처음부터 다시 입력하지 않아도 돼요.'}
  ];
  let index=0,active=false,previousFocus=null;
  const make=(tag,id,cls)=>{const e=document.createElement(tag);if(id)e.id=id;if(cls)e.className=cls;return e};
  const shade=make('div','wz-tour-backdrop'),highlight=make('div','wz-tour-target'),tip=make('div','wz-tour-tooltip');
  tip.setAttribute('role','dialog');tip.setAttribute('aria-modal','true');tip.setAttribute('aria-label','메뉴 사용 안내');
  const replay=make('button','wz-tour-replay');replay.type='button';replay.textContent='❔ 메뉴 사용 안내';replay.setAttribute('aria-label','메뉴 사용 안내 다시 보기');
  const kicker=make('div',null,'wz-tour-kicker'),heading=make('h3'),description=make('p'),actions=make('div',null,'wz-tour-buttons');
  const skip=make('button'),back=make('button'),next=make('button',null,'wz-next');
  skip.type=back.type=next.type='button';skip.textContent='건너뛰기';back.textContent='이전';
  actions.append(skip,back,next);tip.append(kicker,heading,description,actions);
  document.body.append(shade,highlight,tip,replay);
  const seen=()=>{try{return localStorage.getItem(STORAGE_KEY)==='1'}catch(_){return false}};
  const markSeen=()=>{try{localStorage.setItem(STORAGE_KEY,'1')}catch(_){}};
  function rectFor(step){
    const elements=step.target.map(id=>document.getElementById(id)).filter(Boolean);
    if(!elements.length)return null;
    const r=elements.map(el=>el.getBoundingClientRect());
    return {left:Math.min(...r.map(a=>a.left)),top:Math.min(...r.map(a=>a.top)),right:Math.max(...r.map(a=>a.right)),bottom:Math.max(...r.map(a=>a.bottom))};
  }
  function place(){
    if(!active)return;
    const r=rectFor(steps[index]);if(!r)return;
    const pad=5,vw=window.innerWidth,vh=window.innerHeight;
    highlight.style.left=Math.max(0,r.left-pad)+'px';highlight.style.top=Math.max(0,r.top-pad)+'px';
    highlight.style.width=Math.min(vw,r.right+pad)-Math.max(0,r.left-pad)+'px';
    highlight.style.height=Math.min(vh,r.bottom+pad)-Math.max(0,r.top-pad)+'px';
    const tw=tip.offsetWidth,th=tip.offsetHeight;
    let x=Math.min(vw-tw-12,Math.max(12,r.left));
    let y=r.bottom+17;
    if(y+th>vh-12)y=r.top-th-17;
    if(y<12)y=Math.min(vh-th-12,Math.max(12,(vh-th)/2));
    tip.style.left=x+'px';tip.style.top=y+'px';
  }
  function show(){
    kicker.textContent='처음 시작하기 · '+(index+1)+' / '+steps.length;
    heading.textContent=steps[index].title;description.textContent=steps[index].description;
    back.hidden=index===0;next.textContent=index===steps.length-1?'완료':'다음 →';
    place();next.focus({preventScroll:true});
  }
  function finish(){active=false;markSeen();shade.style.display=highlight.style.display=tip.style.display='none';if(previousFocus&&previousFocus.isConnected)previousFocus.focus({preventScroll:true});}
  function start(){previousFocus=document.activeElement;index=0;active=true;shade.style.display=highlight.style.display=tip.style.display='block';show();}
  skip.onclick=finish;back.onclick=()=>{if(index>0){index--;show()}};
  next.onclick=()=>{if(index===steps.length-1)finish();else{index++;show()}};
  replay.onclick=start;
  if(window.parent!==window)replay.hidden=true;
  window.addEventListener('message',function(e){
    if(e.origin!==window.location.origin || e.source!==window.parent)return;
    if(e.data && e.data.type==='ELK_ONECLICK_MENU_TOUR_OPEN'){
      if(active)finish();
      start();
    }
  });
  document.addEventListener('keydown',e=>{if(!active)return;if(e.key==='Escape'){e.preventDefault();finish()}else if(e.key==='ArrowRight'){e.preventDefault();next.click()}else if(e.key==='ArrowLeft'){e.preventDefault();back.click()}else if(e.key==='Tab'){const buttons=[skip,...(back.hidden?[]:[back]),next];const first=buttons[0],last=buttons[buttons.length-1];if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus()}else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus()}}});
  window.addEventListener('resize',place);window.addEventListener('scroll',place,true);
  if(!seen())setTimeout(start,500);
})();
