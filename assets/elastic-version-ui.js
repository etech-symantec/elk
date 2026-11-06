/* Keep the Elastic Stack version field aligned with the latest stable 9.x default.
 * The Wizard's built-in schema may still have ELASTIC_VERSION='' and a 9.5.2
 * placeholder; wizard-defaults.js alone does not update that rendered metadata.
 */
(function(){
'use strict';
if(typeof VM==='undefined'||!VM.ELASTIC_VERSION||typeof values==='undefined'||typeof renderMain!=='function')return;
const KEY='ELASTIC_VERSION';
let latest='9.5.6'; // offline fallback; read fresh canonical default below
let autoValue='';
let updated=false;
const valid=/^9\.\d{1,3}\.\d{1,3}$/;
function tuple(v){return v.split('.').map(Number);}
function newer(a,b){const x=tuple(a),y=tuple(b);return x[0]>y[0]||(x[0]===y[0]&&(x[1]>y[1]||(x[1]===y[1]&&x[2]>y[2])));}
function ensureDefaults(){
  const meta=VM[KEY];
  if(meta&&(!meta.default||valid.test(String(meta.default))))meta.default=latest;
  if(typeof INITIAL_VALUES!=='undefined'&&INITIAL_VALUES&&(!INITIAL_VALUES[KEY]||INITIAL_VALUES[KEY]===autoValue)){
    INITIAL_VALUES[KEY]=latest;
  }
  const actual=String(values[KEY]??'').trim();
  if(!actual||(autoValue&&actual===autoValue)){
    values[KEY]=latest;
    autoValue=latest;
  }
}
function markCard(){
  const card=document.querySelector('.field[data-card="ELASTIC_VERSION"]');
  if(!card)return;
  const input=card.querySelector('input');
  if(input&&(!input.placeholder||input.placeholder==='9.5.2'))input.placeholder=latest;
  // The value must be real, not a gray placeholder: it must be included in elk.env.
  if(input&&!String(input.value||'').trim()&&String(values[KEY]||'')===latest)input.value=latest;
  // Keep the heading clean: the version is shown below the input only.
  card.querySelectorAll('.elk-latest-version-note').forEach(el=>el.remove());
  // Update only this field's default hint (not other configuration cards).
  const walker=document.createTreeWalker(card,NodeFilter.SHOW_TEXT);
  let node;
  while((node=walker.nextNode())){
    if(!node.nodeValue||!node.nodeValue.includes('기본값:'))continue;
    node.nodeValue=node.nodeValue.replace(
      /기본값:\s*(?:비어 있음|9\.\d{1,3}\.\d{1,3})?/g,
      '최신 버전: '+latest
    );
  }
}
const before=renderMain;
renderMain=function(){
  ensureDefaults();
  const out=before.apply(this,arguments);
  markCard();
  return out;
};
ensureDefaults();
renderMain();

// A fresh read also works when the Wizard runs without loading wizard-defaults.js
// as an executable script. Parsing a version string only; never eval remote data.
if(typeof fetch==='function'){
  fetch('wizard-defaults.js?t='+Date.now(),{cache:'no-store'})
    .then(r=>{if(!r.ok)throw Error('HTTP '+r.status);return r.text();})
    .then(t=>{
      const m=t.match(/^\s*ELASTIC_VERSION\s*:\s*["'](9\.\d{1,3}\.\d{1,3})["']/m);
      if(!m||!valid.test(m[1]))return;
      if(newer(m[1],latest)){
        latest=m[1];
        ensureDefaults();
        renderMain();
      }else if(!updated){
        updated=true;markCard();
      }
    })
    .catch(()=>{/* keep offline fallback; user-entered values remain intact */});
}
})();