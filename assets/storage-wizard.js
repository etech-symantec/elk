/* Network disk configuration, shared by Quick/Advanced Step 1. */
(function(){
'use strict';
if(typeof DATA==='undefined'||typeof VM==='undefined'||typeof values==='undefined'||typeof renderMain!=='function')return;
const extra=[
['ELK_NETWORK_DRIVE_ENABLED','false','네트워크 드라이브 사용','NFS 등 사전 마운트된 별도 디스크에 인덱스와 원본 로그를 저장합니다.'],
['ELK_NETWORK_DRIVE_SIZE_TB','','네트워크 디스크 크기(TB)','용량 계획 참고값. 실제 용량과 파일시스템은 서버에서 확인합니다.'],
['ELK_DATA_MOUNT','','네트워크 드라이브 마운트 경로','예: /ELKDATA. 마운트되지 않았다면 설치를 중단합니다.'],
['ELK_ALLOW_ES_ON_NFS','false','Elasticsearch NFS 사용 허용','파일 잠금·fsync·영속성·장애 복구 테스트 후에만 허용합니다.'],
['PROXYSG_MIXED_SOURCE_DIR','','ProxySG 혼합 FTP 수신 폴더','MAIN/SSL 파일이 한 폴더에 업로드되는 경우 파일명에 따라 분리합니다.'],
['PROXYSG_MIXED_MIN_AGE_SECONDS','120','FTP 업로드 안정화 대기 시간(초)','마지막 수정 이후 일정 시간이 지난 완성된 gzip만 분류합니다.']
];
for(const [key,def,label,help] of extra){
 if(!VM[key]){const x={key,default:def,label,help,section:'2. OS 기본 설정',secret:false,select:null};DATA.vars.push(x);VM[key]=x;}
 if(!(key in values))values[key]=def;
 if(typeof INITIAL_VALUES!=='undefined'&&!(key in INITIAL_VALUES))INITIAL_VALUES[key]=def;
}
const css=document.createElement('style');
css.textContent='.elk-netbox{margin:16px 0 10px;padding:16px;border:1px solid var(--line,#566);border-radius:12px;background:rgba(120,145,155,.045);line-height:1.6}.elk-nettitle{font-size:15px;font-weight:800;margin-bottom:6px}.elk-netbox label{font-size:13px;font-weight:650}.elk-netbox input[type=checkbox]{width:17px;height:17px;vertical-align:middle;accent-color:#16a46d}.elk-netgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(215px,1fr));gap:14px;margin:12px 0}.elk-netgrid label{display:grid;gap:5px}.elk-netgrid input{padding:10px 12px;min-width:0;width:100%;box-sizing:border-box;border:1px solid #85919d;border-radius:8px;background:var(--input-bg,#fff);color:var(--text,#222)}.elk-netwarn{font-size:12px;padding:10px;border-left:3px solid #ad7b20;background:rgba(181,127,31,.07);border-radius:5px;margin-top:12px}.elk-netdesc{font-size:12px;opacity:.86;margin-bottom:8px}.elk-netpaths{font-size:12px;overflow-wrap:anywhere;margin-top:10px}.elk-netpaths code{font-size:11px}';
document.head.appendChild(css);
const oldDefaults={
 ES_PATH_DATA:'/var/lib/elasticsearch',ES_PATH_LOGS:'/var/log/elasticsearch',
 PROXYSG_MAIN_SOURCE_DIR:'/home/main',PROXYSG_SSL_SOURCE_DIR:'/home/ssl',
 PROXYSG_MAIN_BACKUP_DIR:'/home/main_backup',PROXYSG_SSL_BACKUP_DIR:'/home/ssl_backup',
 PROXYSG_MAIN_PROCESS_DIR:'/home/main_process',PROXYSG_SSL_PROCESS_DIR:'/home/ssl_process',
 SNAPSHOT_REPO_PATH:'/backup/elasticsearch',
 ELK_DATA_MOUNT:'',ELK_ALLOW_ES_ON_NFS:'false',OS_EXTEND_ROOT_LVM:'true'
};
let lastAuto={};
const enabled=()=>String(values.ELK_NETWORK_DRIVE_ENABLED)==='true';
const path=()=>String(values.ELK_DATA_MOUNT||'').trim().replace(/\/+$/,'');
const esc=s=>String(s==null?'':s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const under=(v,m)=>v===m||v.startsWith(m+'/');
function auto(k,v,force){
 v=String(v);
 if(force||!(k in lastAuto)||String(values[k]??'')===lastAuto[k]){values[k]=v;lastAuto[k]=v;}
}
function applyLayout(force){
 if(!enabled())return;
 const m=path()||'/ELKDATA';
 values.ELK_DATA_MOUNT=m;values.ELK_ALLOW_ES_ON_NFS='true';
 auto('ES_PATH_DATA',m+'/elk/elasticsearch/data',force);
 if(String(values.PROXYSG_FLOW_ENABLED)==='true'){
  for(const [k,n] of Object.entries({
   PROXYSG_MAIN_SOURCE_DIR:'main',PROXYSG_SSL_SOURCE_DIR:'ssl',
   PROXYSG_MAIN_BACKUP_DIR:'main_backup',PROXYSG_SSL_BACKUP_DIR:'ssl_backup',
   PROXYSG_MAIN_PROCESS_DIR:'main_process',PROXYSG_SSL_PROCESS_DIR:'ssl_process'
  }))auto(k,m+'/elk/logs/'+n,force);
 }
 auto('SNAPSHOT_REPO_PATH',m+'/elk/backup/elasticsearch',force);
 auto('OS_EXTEND_ROOT_LVM','false',force);
 // Keep PQ, DLQ, sincedb, installer files and application logs on the OS disk.
 if(under(String(values.LOGSTASH_PATH_DATA||''),m)) values.LOGSTASH_PATH_DATA='/var/lib/logstash';
}
function disableLayout(){
 // Also handle previously imported elk.env files (no lastAuto history).
 // Never leave a network path active after removing the mount guard.
 const m=path();
 for(const [k,v] of Object.entries(lastAuto)){
  if(String(values[k]??'')===v&&k in oldDefaults)values[k]=oldDefaults[k];
 }
 if(m&&m!=='/'){
  for(const [k,local] of Object.entries(oldDefaults)){
   if(k==='ELK_DATA_MOUNT'||k==='ELK_ALLOW_ES_ON_NFS')continue;
   if(under(String(values[k]||''),m))values[k]=local;
  }
  if(under(String(values.PROXYSG_MIXED_SOURCE_DIR||''),m))values.PROXYSG_MIXED_SOURCE_DIR='';
 }
 values.ELK_DATA_MOUNT='';values.ELK_ALLOW_ES_ON_NFS='false';lastAuto={};
}
function inject(){
 if(typeof mode==='undefined'||typeof step==='undefined'||!['simple','advanced'].includes(mode)||step!==1||(typeof query!=='undefined'&&query))return;
 const panel=document.getElementById('specpanel');
 if(!panel||document.getElementById('elkNetBox'))return;
 const on=enabled(),m=path()||'/ELKDATA',mixed=!!values.PROXYSG_MIXED_SOURCE_DIR;
 let box=document.createElement('section');box.id='elkNetBox';box.className='elk-netbox';
 box.innerHTML='<div class="elk-nettitle">네트워크 드라이브 / 데이터 디스크 분리</div>'+
 '<div class="elk-netdesc">OS 디스크는 ELK 프로그램·Logstash PQ, 네트워크 드라이브는 Elasticsearch 인덱스·ProxySG 원본/처리/백업 로그에 사용합니다.</div>'+
 '<label><input type="checkbox" id="elkNetEnable" '+(on?'checked':'')+'> 네트워크 드라이브 사용</label>'+
 '<div id="elkNetDetails" '+(on?'':'hidden')+'>'+
 '<div class="elk-netgrid">'+
 '<label>네트워크 디스크 크기 (TB)<input type="number" id="elkNetSize" min="0.1" step="0.1" placeholder="예: 100" value="'+esc(values.ELK_NETWORK_DRIVE_SIZE_TB)+'"></label>'+
 '<label>마운트 경로<input type="text" id="elkNetMount" spellcheck="false" placeholder="/ELKDATA" value="'+esc(m)+'"></label></div>'+
 '<label><input type="checkbox" id="elkNetMixed" '+(mixed?'checked':'')+'> 기존 FTP 혼합 수신 폴더 자동 분류 (MAIN/SSL)</label>'+
 '<div class="elk-netgrid" id="elkNetMixedDetails" '+(mixed?'':'hidden')+'>'+
 '<label>실제 FTP 수신 폴더<input id="elkNetMixedPath" type="text" value="'+esc(values.PROXYSG_MIXED_SOURCE_DIR||m+'/proxy_log')+'"></label>'+
 '<label>파일 안정화 시간 (초)<input id="elkNetAge" type="number" min="30" step="30" value="'+esc(values.PROXYSG_MIXED_MIN_AGE_SECONDS||'120')+'"></label></div>'+
 '<div class="elk-netwarn"><b>NFS 주의:</b> Elasticsearch는 로컬 디스크 수준의 잠금·fsync·영속성이 보장되어야 합니다. 서비스 계정 UID/GID 권한, root_squash 및 마운트 복구를 서버에서 확인하세요. Logstash PQ/DLQ는 NFS에 배치하지 않습니다.</div>'+
 '<div class="elk-netpaths">Elasticsearch: <code>'+esc(m)+'/elk/elasticsearch/data</code><div>ProxySG MAIN/SSL: <code>'+esc(m)+'/elk/logs/</code></div><div>Snapshot 저장소: <code>'+esc(m)+'/elk/backup/elasticsearch</code> (동일 NFS 장애에는 독립 백업이 아님)</div><div>FTP 계정·CWD·local_root는 기존 값을 유지합니다. 장비의 업로드 경로를 확인하세요.</div></div>'+
 '</div>';
 (panel.querySelector('.specinputs')||panel).insertAdjacentElement('afterend',box);
 const disk=document.getElementById('specDisk');
 if(disk&&disk.closest('label'))disk.closest('label').firstChild.textContent=on?'OS 디스크 (GB, PQ 크기 산정)':'데이터 디스크 (GB, 로컬 기준)';
 document.getElementById('elkNetEnable').onchange=e=>{
  if(e.target.checked){values.ELK_NETWORK_DRIVE_ENABLED='true';if(!path())values.ELK_DATA_MOUNT='/ELKDATA';applyLayout(true);}
  else{values.ELK_NETWORK_DRIVE_ENABLED='false';disableLayout();}
  renderMain();
 };
 if(!on)return;
 document.getElementById('elkNetSize').oninput=e=>values.ELK_NETWORK_DRIVE_SIZE_TB=e.target.value;
 document.getElementById('elkNetMount').onchange=e=>{
  values.ELK_DATA_MOUNT=e.target.value.trim().replace(/\/+$/,'');applyLayout(true);renderMain();
 };
 document.getElementById('elkNetMixed').onchange=e=>{
  values.PROXYSG_MIXED_SOURCE_DIR=e.target.checked?path()+'/proxy_log':'';renderMain();
 };
 document.getElementById('elkNetMixedPath').onchange=e=>{
  values.PROXYSG_MIXED_SOURCE_DIR=e.target.value.trim().replace(/\/+$/,'');renderMain();
 };
 document.getElementById('elkNetAge').oninput=e=>values.PROXYSG_MIXED_MIN_AGE_SECONDS=e.target.value;
}
const prevRender=renderMain;
renderMain=function(){prevRender.apply(this,arguments);inject()};
const prevImport=applyLegacyEnv;
applyLegacyEnv=function(o){
 const n=prevImport(o);
 if(!('ELK_NETWORK_DRIVE_ENABLED' in o)&&o.ELK_DATA_MOUNT)values.ELK_NETWORK_DRIVE_ENABLED='true';
 return n;
};
const prevErrors=validationErrors;
validationErrors=function(){
 const errors=prevErrors();
 if(!enabled())return errors;
 const m=path(),size=Number(values.ELK_NETWORK_DRIVE_SIZE_TB);
 if(!/^\/[a-zA-Z0-9_./-]+$/.test(m)||m==='/'||m.includes('/../')||m.includes('/./'))errors.push('네트워크 마운트 경로는 /ELKDATA처럼 올바른 절대경로여야 합니다.');
 if(!Number.isFinite(size)||size<=0)errors.push('네트워크 디스크 크기(TB)를 입력하세요.');
 if(m&&m!=='/'){
  if(!under(String(values.ES_PATH_DATA||''),m))errors.push('Elasticsearch 인덱스 저장 경로가 네트워크 드라이브 아래에 있어야 합니다.');
  if(under(String(values.LOGSTASH_PATH_DATA||''),m))errors.push('Logstash PQ는 네트워크 드라이브에 저장할 수 없습니다.');
 }
 if(values.ELK_ALLOW_ES_ON_NFS!=='true')errors.push('NFS 인덱스 사용을 명시적으로 허용해야 합니다.');
 const mixed=String(values.PROXYSG_MIXED_SOURCE_DIR||'');
 if(mixed&&(!mixed.startsWith('/')||!under(mixed,m)))errors.push('FTP 혼합 수신 경로는 네트워크 드라이브 아래에 있어야 합니다.');
 if(mixed&&(!/^\d+$/.test(String(values.PROXYSG_MIXED_MIN_AGE_SECONDS))||Number(values.PROXYSG_MIXED_MIN_AGE_SECONDS)<30))errors.push('FTP 안정화 대기는 최소 30초여야 합니다.');
 return errors;
};
renderMain();
})();