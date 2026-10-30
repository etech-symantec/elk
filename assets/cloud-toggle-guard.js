/* Cloud API controls: synchronize Wizard state and lock switches when Cloud is off. */
(()=>{
 'use strict';
 const root=document.getElementById('main');if(!root)return;
 const dependent=['PROXYSG_CLOUD_API_ENABLED','PROXYSG_CLOUD_API_INSECURE'];
 let updating=false,pending=false;
 function card(key){
   // Variable names may be nested in labels: do not require a leaf's exact text.
   const nodes=[...root.querySelectorAll('small,span,label,div')].filter(el=>{
     const t=(el.textContent||'').trim();
     return t===key && ![...el.children].some(c=>(c.textContent||'').trim()===key);
   });
   for(const leaf of nodes){
     for(let el=leaf.parentElement;el&&el!==root;el=el.parentElement){
       const text=(el.textContent||'');
       const buttons=[...el.querySelectorAll('button')].filter(b=>/^(사용|사용 안 함)\s*(기본)?$/.test(b.textContent.trim()));
       if(buttons.length===2 && text.length<1400 && !dependent.some(k=>k!==key&&text.includes(k)))return {el,buttons};
       if(buttons.length>2)break;
     }
   }
   return null;
 }
 function choice(group,word){
   return group?.buttons.find(b=>b.textContent.trim().startsWith(word)&&
       (word!=='사용'||!b.textContent.trim().startsWith('사용 안 함')));
 }
 function active(group){
   const on=choice(group,'사용'),off=choice(group,'사용 안 함');
   if(!on||!off)return false;
   const chosen=b=>b.classList.contains('active')||b.classList.contains('selected')||b.classList.contains('on')||b.getAttribute('aria-pressed')==='true';
   if(chosen(off))return false;
   if(chosen(on))return true;
   // Fail-safe: if no selection can be inferred, don't activate Cloud API.
   return false;
 }
 function sync(){
   if(updating)return;updating=true;
   observer.disconnect();
   try{
     const cloud=card('PROXYSG_CLOUD_ENABLED');
     if(!cloud)return;
     const locked=!active(cloud);
     for(const key of dependent){
       const g=card(key);if(!g)continue;
       const off=choice(g,'사용 안 함');
       // Click the genuine Wizard toggle, not merely its visual representation.
       if(locked&&off&&!off.disabled&&active(g))off.click();
       g.el.classList.toggle('cloud-dependent-locked',locked);
       g.buttons.forEach(b=>{b.disabled=locked;b.setAttribute('aria-disabled',String(locked));});
     }
   }catch(e){console.error('[Cloud switch guard]',e)}
   finally{observer.observe(root,{childList:true,subtree:true});updating=false}
 }
 function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;sync()},35)}
 const observer=new MutationObserver(schedule);
 root.addEventListener('click',e=>{
   const b=e.target.closest('button');if(!b)return;
   const source=card('PROXYSG_CLOUD_ENABLED');
   if(source?.el.contains(b))schedule();
 },true);
 sync();
})();
