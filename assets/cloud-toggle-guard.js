/* Keep dependent Cloud API switches consistent with disabled Cloud ingestion. */
(()=>{
 'use strict';
 const root=document.getElementById('main');if(!root)return;
 const keys=['PROXYSG_CLOUD_API_ENABLED','PROXYSG_CLOUD_API_INSECURE'];
 const switches=new Map();
 let busy=false,queued=false;
 function field(key){
   const candidates=[...root.querySelectorAll('*')].filter(el=>el.children.length===0&&(el.textContent||'').trim()===key);
   for(const leaf of candidates){
     for(let node=leaf.parentElement;node&&node!==root;node=node.parentElement){
       const buttons=[...node.querySelectorAll('button')].filter(b=>['사용','사용 안 함'].includes(b.textContent.trim()));
       if(buttons.length===2&&buttons.some(b=>b.textContent.trim()==='사용')&&buttons.some(b=>b.textContent.trim()==='사용 안 함'))return {node,buttons};
       if(buttons.length>2)break;
     }
   }
   return null;
 }
 function isOn(group){
   const on=group?.buttons.find(b=>b.textContent.trim()==='사용');
   const off=group?.buttons.find(b=>b.textContent.trim()==='사용 안 함');
   if(!on||!off)return false;
   const selected=b=>b.getAttribute('aria-pressed')==='true'||b.classList.contains('on')||b.classList.contains('active')||b.classList.contains('selected');
   return selected(on)&&!selected(off);
 }
 function disabledByParent(group){
   if(!group)return false;
   let el=group.node;
   for(let j=0;j<3&&el&&el!==root;j++,el=el.parentElement){
     if(el.matches('[disabled],[aria-disabled="true"],.disabled,.is-disabled'))return true;
   }
   return false;
 }
 function run(){
   if(busy)return;
   busy=true;
   observer.disconnect();
   try{
     const cloud=field('PROXYSG_CLOUD_ENABLED');
     const cloudOff=cloud? !isOn(cloud):null;
     if(cloudOff===null)return;
     for(const key of keys){
       const group=field(key);if(!group)continue;
       const off=group.buttons.find(b=>b.textContent.trim()==='사용 안 함');
       const shouldLock=cloudOff||disabledByParent(group);
       if(shouldLock){
         // Trigger the Wizard's own handler so exported elk.env reflects false.
         if(!switches.has(group.node)&&off){switches.set(group.node,true);if(!off.disabled)off.click();}
       }else switches.delete(group.node);
       for(const button of group.buttons){
         button.disabled=!!shouldLock;
         button.setAttribute('aria-disabled',String(!!shouldLock));
         button.style.cursor=shouldLock?'not-allowed':'';
       }
     }
   }catch(e){console.error('[Cloud toggles]',e)}
   finally{busy=false;observer.observe(root,{childList:true,subtree:true});}
 }
 function schedule(){if(queued)return;queued=true;setTimeout(()=>{queued=false;run()},0)}
 const observer=new MutationObserver(schedule);
 root.addEventListener('click',e=>{
   const b=e.target.closest('button');
   if(!b)return;
   const cloud=field('PROXYSG_CLOUD_ENABLED');
   if(cloud?.node.contains(b))schedule();
 },true);
 run();
})();
