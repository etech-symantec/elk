// ─────────────────────────────────────────────────────────────
// 1. 공통 템플릿 (type 개수 제한 없음)
// ─────────────────────────────────────────────────────────────
const TEMPLATE = `input {
PLACEHOLDER_INPUT
}
filter {
PLACEHOLDER_FILTER
}
output {
PLACEHOLDER_OUTPUT
}`;

// input 블록
function tplInput(o){
  const lines = [`path => "${o.path}"`, `mode => "${o.mode}"`];
  if(o.mode === 'read'){
    lines.push(`file_completed_action => "${o.action}"`);
    if(o.action !== 'delete') lines.push(`file_completed_log_path => "${o.logPath}"`);
  } else {
    lines.push(`start_position => "${o.start}"`);
  }
  lines.push(`sincedb_path => "${o.since}"`, `type => "${o.type}"`,
             `discover_interval => ${o.discover}`, `max_open_files => ${o.maxOpen}`);
  return `file {\n    ` + lines.join('\n    ') + `\n  }`;
}

// filter 블록 (type별 if [type] == "X")
function tplFilter(type, grokArray, convertBlock, tz){
  // cloud / edge 구분 없이, type 이름에 따라 date 포맷 힌트만 변경
  const isCloudLike = type.toLowerCase().includes('cloud');

  const dateAdd = isCloudLike
    ? `add_field => { "date" => "%{year}-%{month}-%{day}" }
      add_field => { "date-time" => "%{date} %{time}" }`
    : `add_field => { "date" => "%{day}/%{month}/%{year}" }
      add_field => { "date-time" => "%{day}/%{month}/%{year}:%{time_zone}" }`;

  const dateMatch = isCloudLike
    ? `match => ["date-time", "yyyy-MM-dd HH:mm:ss"]`
    : `match => ["date-time", "dd/MMM/yyyy:HH:mm:ss Z"]`;

  return `if [type] == "${type}" {
    if [message] =~ /^\\#.*/ {
      drop {}
    }
    grok {
      match => { "message" => ${grokArray} }
    }
    mutate {
      add_field => { "log_type" => "${type}" }
      ${dateAdd}
      remove_field => ["@timestamp", "message", "host", "path", "auth", "extra1", "tags", "@version", "_id", "_index", "_score", "_type", "year", "month", "day"]
    }${convertBlock}
    date {
      ${dateMatch}
      target => "@timestamp_log"
      timezone => "${tz}"
    }
  }`;
}

// ELFF 토큰 → 필드명 (date/time은 log_date/log_time)
function elffToField(t){
  let f = t.toLowerCase().replace(/[^a-z0-9]+/g,'_').replace(/^_+|_+$/g,'');
  if(f === 'date') f = 'log_date';
  if(f === 'time') f = 'log_time';
  return f;
}

// filter 블록: ELFF 그대로 (csv 필터)
function tplFilterCsv(type, tokens, tz){
  const cols = tokens.map(elffToField);
  const has = f => cols.includes(f);
  const hasTs = has('log_date') && has('log_time');
  const conv = ['time_taken','sc_bytes','cs_bytes'].filter(has).map(f => `      "${f}" => "integer"`);
  const rm = (hasTs ? ['log_date','log_time','full_timestamp'] : [])
             .concat(['message','host','path','event','@version','log']).map(f => `"${f}"`).join(', ');
  const tsBlock = hasTs
    ? `mutate {
      add_field => { "full_timestamp" => "%{log_date} %{log_time}" }
    }
    date {
      match => ["full_timestamp", "yyyy-MM-dd HH:mm:ss"]
      timezone => "${tz}"
      target => "@timestamp"
    }`
    : `# date/time 컬럼이 없어 @timestamp 변환은 생략됩니다`;
  return `if [type] == "${type}" {
    if [message] =~ /^\\s*#/ or [message] == "" {
      drop {}
    }
    mutate {
      gsub => [
        "message", "\\s+$", "",
        "message", "\\s+", " "
      ]
    }
    csv {
      separator => " "
      quote_char => '"'
      autogenerate_column_names => false
      columns => [
${cols.map(c => `        "${c}"`).join(',\n')}
      ]
    }
    ${tsBlock}
    mutate {${conv.length ? `\n      convert => {\n${conv.join('\n')}\n      }` : ''}
      remove_field => [${rm}]
    }
  }`;
}

// output 블록
function tplOutput(type, o){
  const l = [`hosts => [${o.hosts}]`];
  if(o.ssl) l.push(`ssl_enabled => true`, `ssl_verification_mode => "${o.sslVerify}"`);
  if(o.user){ l.push(`user => "${o.user}"`, `password => "${o.pass}"`); }
  l.push(`index => "${o.index}"`);
  if(o.ilm !== 'auto') l.push(`ilm_enabled => ${o.ilm}`);
  l.push(`manage_template => ${o.manageTemplate}`);
  return `if [type] == "${type}" {
    elasticsearch {
      ` + l.join('\n      ') + `
    }
  }`;
}

// ─────────────────────────────────────────────────────────────
// 2. Type 카드 추가/삭제 (상단 패널용)
// ─────────────────────────────────────────────────────────────
let typeSeq = 0;

// 공통 input 설정 (원하면 HTML에 입력창 추가해서 읽어오면 됨)
const DEFAULT_PATH_PREFIX  = "/home/";
const DEFAULT_SINCE_PREFIX = "/var/lib/logstash/";
const DEFAULT_MAX_OPEN     = 1000;
const DEFAULT_HOSTS        = ["https://localhost:9200"];

function addType(){
  const host = document.getElementById('type-list');
  const id = `type-${++typeSeq}`;
  const div = document.createElement('div');
  div.className = 'idx type-card collapsed';
  div.dataset.id = id;

    
    div.innerHTML = `
      <div class="type-card-header">
          <div onclick="toggleTypeBody('${id}')" style="flex:1; cursor:pointer;">
            <h4 style="display: flex; align-items: center; justify-content: space-between;">
              <span class="type-chip" id="${id}-chip">
                  <span class="type-index">Type <span id="${id}-num"></span></span>
                  ·
                  <span class="type-name" id="${id}-title">( - )</span>
                </span>


              <span class="small muted">접기/펼치기 ▾　</span>
            </h4>
          </div>
          
          <button class="btn ghost"
                  style="padding:4px 6px; font-size:6.6px;"
                  onclick="removeType('${id}')"
                  title="삭제">
              ✕
          </button>
        </div>

      
      <div class="type-card-body">
        <div class="grid5">
          <div>
            <label>type 이름</label>
            <input type="text"
                   id="${id}-name"
                   placeholder="예: cloud, edge, proxy01 ..."
                   oninput="updateTypeTitle('${id}', this.value)" />
          </div>
          <div>
            <label>start_position</label>
            <select id="${id}-start">
              <option value="" selected>공통값 사용</option>
              <option value="beginning">beginning</option>
              <option value="end">end</option>
            </select>
          </div>
          <div>
            <label>path suffix</label>
            <input type="text" id="${id}-path" value="*.log.gz" />
          </div>
          <div>
            <label>sincedb suffix</label>
            <input type="text" id="${id}-since" value="sincedb-main" />
          </div>
          <div>
            <label>discover_interval</label>
            <input type="number" id="${id}-discover" value="" placeholder="공통값" min="1" />
          </div>
        </div>
    
        <div class="grid3">
          <div>
            <label>파싱 방식</label>
            <select id="${id}-mode" onchange="syncParseView('${id}')">
              <option value="" selected>공통값 사용</option>
              <option value="grok">Grok 패턴 생성</option>
              <option value="csv">ELFF 그대로 (csv 필터)</option>
            </select>
          </div>
          <div>
            <label>시간대 (date timezone)</label>
            <input type="text" id="${id}-tz" value="" list="tz-list" placeholder="공통값 사용 (예: UTC, Asia/Seoul)" />
          </div>
          <div></div>
        </div>

        <label>ELFF 포맷 입력</label>
        <textarea id="${id}-elff" placeholder="date time time-taken c-ip ..." oninput="autoElffToGrok('${id}')"></textarea>
        <div class="grok-container" id="${id}-grok-container" style="display:none;">
        <label>생성된 Grok 패턴</label>
        <textarea id="${id}-grok-view" readonly></textarea>
        
        <button class="grok-toggle-btn" type="button" onclick="toggleGrokTable('${id}')">
          패턴 상세 보기 <span id="${id}-grok-toggle">▾</span>
        </button>

        <div class="table" id="${id}-table" style="display:none">
        
          <table>
            <thead>
              <tr>
                <th>순서</th>
                <th>ELFF 토큰</th>
                <th>적용 Grok 표현식</th>
              </tr>
            </thead>

            <tbody id="${id}-rows"></tbody>
          </table>
        </div>
        </div>
        <div class="grok-container" id="${id}-csv-container" style="display:none;">
          <label>csv 필터 columns (ELFF 순서 그대로)</label>
          <textarea id="${id}-csv-view" readonly></textarea>
        </div>
        <input type="hidden" id="${id}-grok" />

        <div class="grid3">
          <div>
            <label>Output user</label>
            <input type="text" id="${id}-es-user" value="elastic" />
          </div>
          <div>
            <label>Output password</label>
            <input type="password" id="${id}-es-pass" value="" placeholder="비우면 \${ES_PASSWORD} 참조" autocomplete="new-password" />
          </div>
          <div>
            <label>Output index</label>
            <input type="text" id="${id}-es-index" value="" placeholder="이름만 (날짜 제외), 비우면 type 이름" />
          </div>
        </div>
      </div>
    `;
  host.appendChild(div);
  renumberTypes();
}
function renumberTypes(){
  const cards = [...document.querySelectorAll('#type-list .type-card')];
  cards.forEach((card, idx)=>{
    const id = card.dataset.id;
    const span = document.getElementById(id + '-num');
    if(span) span.textContent = idx + 1;
  });
}




function removeType(id){
  const el = document.querySelector(`.type-card[data-id="${id}"]`);
  if(el) el.remove();
  renumberTypes();
}

    
    
// ─────────────────────────────────────────────────────────────
// ELFF → Grok 기본 매핑 / 타입 추정
// ─────────────────────────────────────────────────────────────
const MAP = {
  'date': '%{YEAR:year}-%{MONTHNUM:month}-%{MONTHDAY:day}',
  'time': '%{TIME:time}',
  'time-taken': '%{NUMBER:time_taken:int}',
  'c-ip': '%{IP:c_ip}',
  'cs-username': '%{NOTSPACE:cs_username}',
  'cs-auth-group': '%{NOTSPACE:cs_auth_group}',
  's-supplier-name': '%{NOTSPACE:s_supplier_name}',
  's-supplier-ip': '(%{IP:s_supplier_ip}|-)',
  's-supplier-country': '%{QUOTEDSTRING:s_supplier_country}',
  's-supplier-failures': '%{NOTSPACE:s_supplier_failures}',
  'x-exception-id': '%{NOTSPACE:x_exception_id}',
  'sc-filter-result': '%{NOTSPACE:sc_filter_result}',
  'cs-categories': '%{QUOTEDSTRING:cs_categories}',
  'sc-status': '%{NOTSPACE:sc_status}',
  's-action': '%{NOTSPACE:s_action}',
  'cs-method': '%{WORD:cs_method}',
  'rs(Content-Type)': '%{NOTSPACE:rs_Content_Type}',
  'cs-uri-scheme': '%{NOTSPACE:cs_uri_scheme}',
  'cs-host': '%{NOTSPACE:cs_host}',
  'cs-uri-port': '%{NUMBER:cs_uri_port}',
  'cs-uri-extension': '%{NOTSPACE:cs_uri_extension}',
  'cs(User-Agent)': '(%{QUOTEDSTRING:cs_User_Agent}|-)',
  's-ip': '%{IP:s_ip}',
  'sc-bytes': '%{NUMBER:sc_bytes:int}',
  'cs-bytes': '%{NUMBER:cs_bytes:int}',
  'x-virus-id': '%{NOTSPACE:x_virus_id}',
  'cs-threat-source': '%{NOTSPACE:cs_threat_source}',
  'cs-threat-id': '%{NOTSPACE:cs_threat_id}',
  'rs-threat-source': '%{NOTSPACE:rs_threat_source}',
  'rs-threat-id': '%{NOTSPACE:rs_threat_id}',
  'x-rs-certificate-observed-errors': '%{NOTSPACE:x_rs_certificate_observed_errors}',
  'x-cs-ocsp-error': '%{NOTSPACE:x_cs_ocsp_error}',
  'x-rs-ocsp-error': '%{NOTSPACE:x_rs_ocsp_error}',
  'x-rs-connection-negotiated-cipher-strength': '%{NOTSPACE:x_rs_connection_negotiated_cipher_strength}',
  'x-rs-certificate-hostname': '%{NOTSPACE:x_rs_certificate_hostname}',
  'x-rs-certificate-hostname-category': '"%{DATA:x_rs_certificate_hostname_category}"',
  'cs-threat-risk': '%{NOTSPACE:cs_threat_risk}',
  'x-rs-certificate-hostname-threat-risk': '%{NOTSPACE:x_rs_certificate_hostname_threat_risk}',
  'x-bluecoat-access-security-policy-action': '%{NOTSPACE:x_bluecoat_access_security_policy_action}',
  'x-bluecoat-access-security-policy-reason': '%{NOTSPACE:x_bluecoat_access_security_policy_reason}',
  'cs-auth-groups': '%{NOTSPACE:cs_auth_groups}',
  'cs-icap-error-details': '%{NOTSPACE:cs_icap_error_details}',
  'cs-icap-status': '%{NOTSPACE:cs_icap_status}',
  'cs-referer': '%{NOTSPACE:cs_Referer}',
  'cs-uri-path': '%{NOTSPACE:cs_uri_path}',
  'cs-uri-query': '%{NOTSPACE:cs_uri_query}',
  'cs-user-agent': '(%{QUOTEDSTRING:cs_User_Agent}|-)',
  'cs-userdn': '%{NOTSPACE:cs_userdn}',
  'cs-x-requested-with': '%{NOTSPACE:cs_X_Requested_With}',
  'r-supplier-country': '%{QUOTEDSTRING:r_supplier_country}',
  'rs-content-type': '%{NOTSPACE:rs_Content_Type}',
  'rs-icap-error-details': '%{NOTSPACE:rs_icap_error_details}',
  'rs-icap-status': '%{NOTSPACE:rs_icap_status}',
  's-source-ip': '(%{IP:s_supplier_ip}|-)',
  's-supplier-ip': '%{IP:s_supplier_ip}',
  'x-action-result': '%{NOTSPACE:x_action_result}',
  'x-bluecoat-access-type': '%{NOTSPACE:x_bluecoat_access_type}',
  'x-bluecoat-application-name': '\"%{DATA:x_bluecoat_application_name}\"',
  'x-bluecoat-application-operation': '\"%{DATA:x_bluecoat_application_operation}\"',
  'x-bluecoat-location-id': '%{NOTSPACE:x_bluecoat_location_id}',
  'x-bluecoat-location-name': '%{QUOTEDSTRING:x_bluecoat_location_name}',  
  'x-bluecoat-placeholder': '%{NOTSPACE:x_bluecoat_placeholder}',
  'x-bluecoat-reference-id': '%{NOTSPACE:x_bluecoat_reference_id}',
  'x-bluecoat-request-tenant-id': '%{NOTSPACE:x_bluecoat_request_tenant_id}',
  'x-bluecoat-transaction-uuid': '(?<x_bluecoat_transaction_uuid>[0-9a-fA-F]{16}-[0-9a-fA-F]{16}-[0-9a-fA-F]{16})',
  'x-client-agent-ip': '%{IP:x_client_agent_ip}',
  'x-client-agent-sw': '(?<x_client_agent_sw>\d+\.\d+\.\d+\.\d+)',
  'x-client-agent-type': '%{NOTSPACE:x_client_agent_type}',
  'x-client-device-id': '(?<x_client_device_id>[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12})',
  'x-client-device-name': '%{NOTSPACE:x_client_device_name}',
  'x-client-device-type': '%{NOTSPACE:x_client_device_type}',
  'x-client-os': '%{QUOTEDSTRING:x_client_os}',
  'x-client-security-posture-details': '%{NOTSPACE:x_client_security_posture_details}',
  'x-client-security-posture-risk-score': '%{NOTSPACE:x_client_security_posture_risk_score}',
  'x-cloud-rs': '%{NOTSPACE:x_cloud_rs}',
  'x-cs-certificate-subject': '%{NOTSPACE:x_cs_certificate_subject}',
  'x-cs-client-ip-country': '%{QUOTEDSTRING:x_cs_client_ip_country}',
  'x-cs-connection-negotiated-cipher': '%{NOTSPACE:x_cs_connection_negotiated_cipher}',
  'x-cs-connection-negotiated-cipher-size': '%{NUMBER:x_cs_connection_negotiated_cipher_size}',
  'x-cs-connection-negotiated-ssl-version': '%{NOTSPACE:x_cs_connection_negotiated_ssl_version}',
  'x-cs-public-ip': '%{IP:x_cs_public_ip}',
  'x-data-leak-detected': '%{NOTSPACE:x_data_leak_detected}',
  'x-data-types': '%{NOTSPACE:x_data_types}',
  'x-icap-reqmod-header(X-ICAP-Metadata)': '%{NOTSPACE:x_icap_reqmod_header_X_ICAP_Metadata}',
  'x-icap-respmod-header(X-ICAP-Metadata)': '%{NOTSPACE:x_icap_respmod_header_X_ICAP_Metadata}',
  'x-random-ipv6': '(%{IPV6:x_random_ipv6}|-)',
  'x-rs-certificate-hostname-categories': '%{NOTSPACE:x_rs_certificate_hostname_categories}',
  'x-rs-certificate-validate-status': '%{NOTSPACE:x_rs_certificate_validate_status}',
  'x-rs-connection-negotiated-cipher': '%{NOTSPACE:x_rs_connection_negotiated_cipher}',
  'x-rs-connection-negotiated-cipher-size': '%{NUMBER:x_rs_connection_negotiated_cipher_size}',
  'x-rs-connection-negotiated-ssl-version': '%{NOTSPACE:x_rs_connection_negotiated_ssl_version}',
  'x-sc-connection-issuer-keyring': '%{NOTSPACE:x_sc_connection_issuer_keyring}',
  'x-sc-connection-issuer-keyring-alias': '%{NOTSPACE:x_sc_connection_issuer_keyring_alias}',
  'x-virus-id': '%{NOTSPACE:x_virus_id}'

};


// ─────────────────────────────────────────────────────────────
// ELK 리소스(CPU/MEM/Disk) 산정기
// 참고: ODIN-I BASIC-V20 / V50 / V100 / V200 사이즈 가이드
// ─────────────────────────────────────────────────────────────
const SIZING_GUIDE = [
  { label:'ODIN-I BASIC-V20',  days90:16,  days120:12, days365:4,  cpu:12, mem:72,  diskTB:2  },
  { label:'ODIN-I BASIC-V50',  days90:41,  days120:31, days365:10, cpu:12, mem:72,  diskTB:5  },
  { label:'ODIN-I BASIC-V100', days90:84,  days120:63, days365:20, cpu:16, mem:84,  diskTB:10 },
  { label:'ODIN-I BASIC-V200', days90:125, days120:94, days365:30, cpu:24, mem:118, diskTB:15 },
];

// 각 모델이 실제로 DB(ES)에 보유하게 되는 데이터량(GB)을
// 90/120/365일 시나리오 평균으로 역산 → 보간용 앵커 포인트
const SIZING_ANCHORS = SIZING_GUIDE.map(g=>{
  const dataGB = ((g.days90*90) + (g.days120*120) + (g.days365*365)) / 3;
  return { label:g.label, dataGB, cpu:g.cpu, mem:g.mem, diskGB:g.diskTB*1024 };
});

function szInterp(dataGB, key){
  const A = SIZING_ANCHORS;
  if(dataGB <= A[0].dataGB) return A[0][key];
  for(let i=0; i<A.length-1; i++){
    if(dataGB >= A[i].dataGB && dataGB <= A[i+1].dataGB){
      const t = (dataGB - A[i].dataGB) / (A[i+1].dataGB - A[i].dataGB);
      return A[i][key] + t * (A[i+1][key] - A[i][key]);
    }
  }
  const a = A[A.length-2], b = A[A.length-1];
  const slope = (b[key] - a[key]) / (b.dataGB - a.dataGB);
  return b[key] + slope * (dataGB - b.dataGB);
}

function szNearestTier(dataGB){
  let best = SIZING_ANCHORS[0], bestDiff = Infinity;
  SIZING_ANCHORS.forEach(a=>{
    const diff = Math.abs(a.dataGB - dataGB);
    if(diff < bestDiff){ bestDiff = diff; best = a; }
  });
  return best.label;
}

function szFmt(n, digits=1){
  return Number(n).toLocaleString('ko-KR', { maximumFractionDigits: digits, minimumFractionDigits:0 });
}

function renderSizingGuideTable(){
  const tbody = document.getElementById('sz-guide-rows');
  if(!tbody) return;
  tbody.innerHTML = SIZING_GUIDE.map(g => `
    <tr>
      <td>${g.label}</td>
      <td>${g.days90}GB/일</td>
      <td>${g.days120}GB/일</td>
      <td>${g.days365}GB/일</td>
      <td>${g.cpu}코어</td>
      <td>${g.mem}GB</td>
      <td>${g.diskTB}TB</td>
    </tr>
  `).join('');
}

function toggleSzPanel(panelId, btnId){
  const panel = document.getElementById(panelId);
  const btn = document.getElementById(btnId);
  if(!panel) return;
  const isHidden = (panel.style.display === 'none' || panel.style.display === '');
  panel.style.display = isHidden ? 'block' : 'none';
  if(btn){
    btn.classList.toggle('active', isHidden);
    const arrow = btn.querySelector('.sz-toggle-arrow');
    if(arrow) arrow.textContent = isHidden ? '▴' : '▾';
  }
}

function calcResourceSizing(){
  const dailyMB       = parseFloat(document.getElementById('sz-daily-mb').value);
  const dbDays        = parseFloat(document.getElementById('sz-db-days').value);
  const archiveDays   = parseFloat(document.getElementById('sz-archive-days').value) || 0;
  const overhead      = parseFloat(document.getElementById('sz-overhead').value) || 1.38;
  const replica       = parseFloat(document.getElementById('sz-replica').value) || 0;
  const gzRatioPct    = parseFloat(document.getElementById('sz-gzratio').value);
  const archiveMethod = document.getElementById('sz-archive-method').value;
  const marginPct     = parseFloat(document.getElementById('sz-margin').value);

  if(!dailyMB || dailyMB <= 0 || !dbDays || dbDays <= 0){
    alert('일일 로그 크기(MB)와 DB 보관 기간(일)을 올바르게 입력하세요.');
    return;
  }

  const gzRatio = (isNaN(gzRatioPct) ? 10 : gzRatioPct) / 100;   // gz 크기 / 원본 크기
  const margin  = (isNaN(marginPct) ? 20 : marginPct) / 100;

  const dailyGzGB     = dailyMB / 1024;                              // 입력값: gz 압축 상태의 일일 로그량
  const rawDailyGB    = dailyGzGB / gzRatio;                         // ES 색인 대상, 원본(비압축) 로그량으로 환산
  const indexedDataGB = rawDailyGB * dbDays;                         // ES에 실제 적재되는 원본 데이터 총량
  const dbDiskGB      = indexedDataGB * overhead * (1 + replica);    // 색인 오버헤드 + 레플리카 반영

  const archiveFactor  = (archiveMethod === 'zstxz') ? 0.7 : 1.0;    // zst/xz는 gz 대비 30% 감소
  const archiveDailyGB = dailyGzGB * archiveFactor;
  const archiveDiskGB  = archiveDailyGB * archiveDays;               // 압축 아카이브 보관 용량

  const rawTotalGB  = dbDiskGB + archiveDiskGB;
  const totalDiskGB = rawTotalGB / (1 - margin);                     // 디스크 여유율 반영

  const cpuRaw = szInterp(indexedDataGB, 'cpu');
  const memRaw = szInterp(indexedDataGB, 'mem');
  const cpu = Math.max(4, Math.ceil(cpuRaw/2)*2);
  const mem = Math.max(8, Math.ceil(memRaw/4)*4);
  const nearest = szNearestTier(indexedDataGB);

  const archiveMethodLabel = (archiveMethod === 'zstxz') ? 'zst/xz (gz 대비 30%↓)' : 'gz (그대로)';

  const box = document.getElementById('sz-result');
  box.style.display = 'block';
  box.innerHTML = `
    <div class="divider"></div>
    <h4 style="margin-top:0;">📊 산정 결과 <span class="chip">근접 참고 사양: ${nearest}</span></h4>
    <div class="grid4">
      <div class="stat">
        <div class="small muted">일일 로그 (gz 압축)</div>
        <div class="val">${szFmt(dailyGzGB,2)} GB/일</div>
      </div>
      <div class="stat">
        <div class="small muted">권장 CPU</div>
        <div class="val">${cpu} vCPU</div>
      </div>
      <div class="stat">
        <div class="small muted">권장 메모리</div>
        <div class="val">${mem} GB</div>
      </div>
      <div class="stat">
        <div class="small muted">필요 디스크 (여유율 포함)</div>
        <div class="val">${szFmt(totalDiskGB/1024,2)} TB</div>
      </div>
    </div>

    <div class="table" style="margin-top:12px;">
      <table>
        <thead>
          <tr><th>항목</th><th>계산 값</th><th>비고</th></tr>
        </thead>
        <tbody>
          <tr><td>원본(비압축) 환산 로그량</td><td>${szFmt(rawDailyGB,2)} GB/일</td><td>gz ${szFmt(dailyGzGB,2)}GB ÷ 압축률 ${(gzRatio*100).toFixed(0)}%</td></tr>
          <tr><td>DB(ES) 보관 데이터량</td><td>${szFmt(indexedDataGB)} GB</td><td>원본 ${szFmt(rawDailyGB,2)}GB × ${dbDays}일</td></tr>
          <tr><td>DB 디스크 소요</td><td>${szFmt(dbDiskGB)} GB</td><td>오버헤드 ${overhead}배 × (1 + 레플리카 ${replica}개)</td></tr>
          <tr><td>압축 아카이브 보관</td><td>${szFmt(archiveDiskGB)} GB</td><td>${archiveDays}일 × ${archiveMethodLabel}</td></tr>
          <tr><td>디스크 합계 (여유율 반영 전)</td><td>${szFmt(rawTotalGB)} GB</td><td>DB 디스크 + 아카이브</td></tr>
          <tr><td><b>최종 필요 디스크</b></td><td><b>${szFmt(totalDiskGB)} GB (${szFmt(totalDiskGB/1024,2)} TB)</b></td><td>여유율 ${isNaN(marginPct)?20:marginPct}% 반영</td></tr>
        </tbody>
      </table>
    </div>
    <div class="small muted" style="margin-top:8px;">
      ※ ODIN-I BASIC 사이즈 가이드(V20/V50/V100/V200)를 기반으로 한 추정치입니다. 실제 인덱싱/검색 부하, 필드 수, 매핑 구조, 노드 구성에 따라 달라질 수 있습니다.
    </div>
  `;
}

function buildConf(){
    
    // 공통 prefix 유효성 검사
    function markInvalid(id, condition){
        const el = document.getElementById(id);
        if(!el) return;
        if(condition){
            el.style.border = "2px solid #ef4444";   // 빨간색 강조
        }else{
            el.style.border = "";                    // 원상복구
        }
    }
    
    const cp = document.getElementById('common-path-prefix').value.trim();
    const cs = document.getElementById('common-since-prefix').value.trim();
    
    markInvalid('common-path-prefix',  cp === "");
    markInvalid('common-since-prefix', cs === "");
    
    if(cp === "" || cs === ""){
        alert("공통 prefix는 비워둘 수 없습니다.");
        return;
    }

    
  const typeCards = [...document.querySelectorAll('#type-list .type-card')];
  if(typeCards.length === 0){
    alert('최소 1개의 Type을 추가하세요.');
    return;
  }

  // csv 모드는 ELFF 입력 필수
  let csvMissing = false;
  typeCards.forEach(card => {
    const id = card.dataset.id;
    const bad = document.getElementById(id+'-name').value.trim() &&
                effParseMode(id) === 'csv' &&
                !document.getElementById(id+'-elff').value.trim();
    markInvalid(id+'-elff', bad);
    if(bad) csvMissing = true;
  });
  if(csvMissing){
    alert('ELFF 그대로(csv) 방식은 ELFF 포맷 입력이 필요합니다.');
    return;
  }
  
  // 🔥 공통 박스 변수 읽어오기
  let DEFAULT_PATH_PREFIX  = document.getElementById('common-path-prefix').value.trim();
    let DEFAULT_SINCE_PREFIX = document.getElementById('common-since-prefix').value.trim();
    
    // 공통 prefix 자동 / 추가
    if(DEFAULT_PATH_PREFIX && !DEFAULT_PATH_PREFIX.endsWith('/')) {
        DEFAULT_PATH_PREFIX += '/';
    }
    if(DEFAULT_SINCE_PREFIX && !DEFAULT_SINCE_PREFIX.endsWith('/')) {
        DEFAULT_SINCE_PREFIX += '/';
    }

  const DEFAULT_MAX_OPEN     = parseInt(document.getElementById('common-max-open').value.trim() || "1000", 10);


  // 공통 input/output 값
  const maxOpen = DEFAULT_MAX_OPEN;
  const commonDisc   = document.getElementById('common-discover').value.trim() || '5';
  const commonMode   = document.getElementById('common-mode').value;
  const commonStart  = document.getElementById('common-start').value;
  const commonTz     = getCommonTz();
  const commonAction = document.getElementById('common-completed-action').value;
  const commonLogPath = escapeQuotes(document.getElementById('common-completed-log').value.trim());
  const hostList = document.getElementById('common-output-hosts').value
                     .split(',').map(h => h.trim()).filter(Boolean);
  const hosts = hostList.map(h => '"' + escapeQuotes(h) + '"').join(', ');
  const useSsl = hostList.some(h => /^https:/i.test(h));
  const sslVerify = document.getElementById('common-ssl-verify').value;
  const indexMode = document.getElementById('common-index-mode').value;
  const dateFmt   = document.getElementById('common-index-datefmt').value.trim() || 'yyyy.MM.dd';
  const ilm       = document.getElementById('common-ilm').value;
  const manageTemplate = document.getElementById('common-manage-template').value;

  const mkGrokArray = (parts) => {
    if(!parts || parts.length === 0) return '["%{GREEDYDATA:message}"]';
    // 한 type당 1줄 패턴으로 합치는 방식
    return '["' + escapeQuotes(parts.join(' ')) + '"]';
  };

  const mkConvert = (typesMap) => {
    const conv = [];
    Object.entries(typesMap || {}).forEach(([token, type]) => {
      const fieldName = guessFieldName(token);
      if(!fieldName) return;
      if(type === 'int' || type === 'float' || type === 'boolean'){
        conv.push(`"${fieldName}" => "${type}"`);
      }
    });
    if(conv.length === 0) return '';
    return `\n    mutate {\n      convert => { ${conv.join(' ')} }\n    }`;
  };

  let inputs = [], filters = [], outputs = [];

  typeCards.forEach(card => {
    const id   = card.dataset.id;
    const type = document.getElementById(id+'-name').value.trim();
    const start = document.getElementById(id+'-start').value || commonStart;
    const pathS = document.getElementById(id+'-path').value.trim();
    const sinceS = document.getElementById(id+'-since').value.trim();
    const disc  = document.getElementById(id+'-discover').value.trim() || commonDisc;

    if(!type) return;

    // input
    const fullPath  = DEFAULT_PATH_PREFIX  + pathS;
    const fullSince = DEFAULT_SINCE_PREFIX + sinceS;
    inputs.push(tplInput({
      path: escapeQuotes(fullPath), mode: commonMode, action: commonAction, logPath: commonLogPath,
      start, since: escapeQuotes(fullSince), type: escapeQuotes(type), discover: disc, maxOpen
    }));

    // grok/convert
    let data = {parts:[], types:{}};
    try{
      data = JSON.parse(document.getElementById(id+'-grok').value || '{}');
    }catch(e){}
    const grokArray    = mkGrokArray(data.parts);
    const convertBlock = mkConvert(data.types);

    const parseMode = effParseMode(id);
    const tz = escapeQuotes(document.getElementById(id+'-tz').value.trim() || commonTz);
    if(parseMode === 'csv'){
      const tokens = document.getElementById(id+'-elff').value.trim().split(/\s+/);
      filters.push(tplFilterCsv(escapeQuotes(type), tokens, tz));
    } else {
      filters.push(tplFilter(type, grokArray, convertBlock, tz));
    }

    // output (index = type)
    const esUser  = document.getElementById(id+'-es-user').value.trim();
    const esPass  = document.getElementById(id+'-es-pass').value;
    let esIndex = document.getElementById(id+'-es-index').value.trim() || type.toLowerCase();
    if(indexMode === 'daily') esIndex += '-%{+' + dateFmt + '}';
    outputs.push(tplOutput(escapeQuotes(type), {
      hosts, ssl: useSsl, sslVerify, ilm, manageTemplate,
      user: escapeQuotes(esUser),
      pass: esPass ? escapeQuotes(esPass) : '${ES_PASSWORD}',
      index: escapeQuotes(esIndex)
    }));
  });

  if(inputs.length === 0){
    alert('Type 이름을 하나 이상 입력하세요.');
    return;
  }

  const conf = TEMPLATE
    .replace('PLACEHOLDER_INPUT',  inputs.join('\n'))
    .replace('PLACEHOLDER_FILTER', filters.join('\nelse {\n  }  # dummy\n') ) // else 사이에 구분용
    .replace('PLACEHOLDER_OUTPUT', outputs.join('\n  else {\n  }  # dummy\n'));

  document.getElementById('preview').innerHTML = highlightLogstash(conf);

}


function defaultType(token){
  const m = { 'time-taken':'int','cs-uri-port':'int','sc-bytes':'int','cs-bytes':'int' };
  if(m[token]) return m[token];
  if(token.endsWith('-ip')) return 'ip';
  return 'string';
}


// 공통: ELFF → Grok 변환 및 테이블 렌더링
function elffToGrok(id){
  const raw = document.getElementById(id+'-elff').value.trim();
  if(!raw){ alert('ELFF 포맷을 입력하세요.'); return; }
  const tokens = raw.split(/\s+/);
  renderGrokTable(id, tokens, null);
}

function renderGrokTable(id, tokens, existing){
  const rows = document.getElementById(id+'-rows');
  if(!rows) return;
  rows.innerHTML='';

  let parts = [];
  let types = existing?.types || {};

  tokens.forEach((t, i)=>{

    // 추천값
    const recommended = MAP[t] || `%{NOTSPACE:${t.replace(/[^a-zA-Z0-9_]/g,'_')}}`;

    // 적용값
    const applied = existing?.parts?.[i] || recommended;
    parts.push(applied);

    // MAP에 존재하는지 확인
    const isMapped = MAP.hasOwnProperty(t);
    const isSame = (applied.trim() === recommended.trim());
    const bg = (isMapped && isSame) ? "background:#e6ffed;" : "";

    // 🔥 미등록 라벨 생성
    const warnLabel = !isMapped
      ? `<span class="unmapped-label">미등록</span>`
      : "";

    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="small muted">${i + 1}</td>

      <!-- 🔥 토큰 표시 + 미등록 라벨 -->
      <td class="mono">${t} ${warnLabel}</td>

      <td>
        <input type="text"
               value="${applied.replace(/"/g, '&quot;')}"
               style="width:100%; ${bg}"
               oninput="onGrokCell('${id}', ${i}, this.value)" />
      </td>
    `;

    rows.appendChild(tr);
  });

  document.getElementById(id+'-grok').value =
    JSON.stringify({parts, types:collectTypes(id)});
}




function onGrokCell(id, idx, value){
  const hidden = document.getElementById(id+'-grok');
  if(!hidden) return;

  let data={parts:[],types:{}};
  try{ data = JSON.parse(hidden.value||'{}'); }catch(e){}

  if(!data.parts) data.parts=[];
  data.parts[idx] = value;
  saveGrokState(id, data);

  // textarea 반영
  document.getElementById(id+'-grok-view').value = data.parts.join(' ');

  // 테이블에서 token 읽기
  const token = document.getElementById(id+'-rows')
                .children[idx]
                .children[1]
                .textContent;

  // 추천값 (MAP 기반)
  const recommended = MAP[token] || `%{NOTSPACE:${token.replace(/[^a-zA-Z0-9_]/g,'_')}}`;

  // 🔥 MAP에 등록된 토큰인지 체크
  const isMapped = MAP.hasOwnProperty(token);

  // input element 찾기
  const inputEl = document.getElementById(id+'-rows')
                .children[idx]
                .children[2]
                .querySelector('input');

  if(inputEl){
    // 🔥 MAP에 존재하고 + 추천값과 정확히 일치해야 초록색
    if (isMapped && value.trim() === recommended.trim()) {
      inputEl.style.background = "#e6ffed";
    } else {
      inputEl.style.background = "";
    }
  }
}


function onTypeCell(id, token, type){
  const hidden = document.getElementById(id+'-grok');
  if(!hidden) return;
  let data={parts:[],types:{}};
  try{ data = JSON.parse(hidden.value||'{}'); }catch(e){}
  if(!data.types) data.types={};
  data.types[token]=type;
  saveGrokState(id, data);
}
function collectTypes(id){
  const tbody = document.getElementById(id+'-rows');
  const types={};
  if(!tbody) return types;
  [...tbody.querySelectorAll('tr')].forEach(tr=>{
    const token = tr.children[1].textContent;
    const sel = tr.querySelector('select');
    if(!sel) return;
    types[token]=sel.value;
  });
  return types;
}
function saveGrokState(id, data){
  const hidden = document.getElementById(id+'-grok');
  if(hidden) hidden.value = JSON.stringify(data);
}

function escapeQuotes(s){
  return s.replace(/\\/g,'\\\\').replace(/"/g,'\\"');
}

function guessFieldName(token){
  if(MAP[token]){
    const m = MAP[token].match(/%\{[^:]+:([^}]+)\}/);
    if(m) return m[1];
  }
  return token.replace(/[^a-zA-Z0-9_]/g,'_');
}

function toggleTypeBody(id){
  const card = document.querySelector(`.type-card[data-id="${id}"]`);
  if(!card) return;
  card.classList.toggle('collapsed');
}


function openMappingModal(){
  const m = document.getElementById('mapping-modal');
  if(!m) return;

  const body = document.getElementById('mapping-body');
  body.innerHTML = "";  // 기존 내용 삭제

  // MAP 객체의 모든 key/value를 테이블로 출력
  Object.entries(MAP).forEach(([token, pattern]) => {
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td><code>${token}</code></td>
      <td><code>${pattern}</code></td>
    `;
    body.appendChild(tr);
  });

  m.style.display = 'flex';
}


function closeMappingModal(e){
  const m = document.getElementById('mapping-modal');
  if(m) m.style.display = 'none';
}

function autoElffToGrok(id){
  const raw = document.getElementById(id+'-elff').value.trim();
  // 🔥 ELFF 입력칸이 비었으면 grok 영역 숨김
  const box = document.getElementById(id+"-grok-container");
  syncParseView(id);
  if (raw === "") { return; }

  // 🔥 입력이 생기면 grok 영역 표시

  
  if(!raw){
    document.getElementById(id+'-grok-view').value = "";
    document.getElementById(id+'-table').style.display = "none";
    return;
  }

  const tokens = raw.split(/\s+/);

  // 🔥 MAP 기반 권장값으로 패턴 생성
  const parts = tokens.map(t =>
    MAP[t] || `%{NOTSPACE:${t.replace(/[^a-zA-Z0-9_]/g,'_')}}`
  );

  // Grok 패턴 textarea 반영
  document.getElementById(id+'-grok-view').value = parts.join(' ');

  // type 카드 숨은 값 저장
  const data = { parts, types:{} };
  document.getElementById(id+'-grok').value = JSON.stringify(data);

  // 🔥 MAP 기반 권장 패턴 테이블도 즉시 생성
  renderGrokTable(id, tokens, data);

  // csv(ELFF 그대로) 컬럼 미리보기
  document.getElementById(id+'-csv-view').value = tokens.map(elffToField).join(' ');
}

// 파싱 방식에 따라 Grok/csv 영역 표시 전환
function syncParseView(id){
  const raw  = document.getElementById(id+'-elff').value.trim();
  const mode = effParseMode(id);
  const g = document.getElementById(id+'-grok-container');
  const c = document.getElementById(id+'-csv-container');
  if(g) g.style.display = (raw && mode === 'grok') ? 'block' : 'none';
  if(c) c.style.display = (raw && mode === 'csv')  ? 'block' : 'none';
  if(raw && mode === 'csv'){
    document.getElementById(id+'-csv-view').value = raw.split(/\s+/).map(elffToField).join(' ');
  }
}

// 유효 파싱 방식 (Type 값 → 없으면 공통값)
function effParseMode(id){
  return document.getElementById(id+'-mode').value ||
         document.getElementById('common-parse-mode').value;
}

// 공통 시간대 값 (직접 입력 지원)
function getCommonTz(){
  const sel = document.getElementById('common-tz').value;
  if(sel === '__custom__'){
    return document.getElementById('common-tz-custom').value.trim() || 'UTC';
  }
  return sel;
}
function onCommonTzChange(){
  const custom = document.getElementById('common-tz').value === '__custom__';
  document.getElementById('common-tz-custom').style.display = custom ? 'block' : 'none';
}

// 공통 파싱 방식 변경 → 모든 Type 카드 표시 갱신
function onCommonFilterChange(){
  document.querySelectorAll('#type-list .type-card').forEach(c => syncParseView(c.dataset.id));
}

// 인덱스 방식에 따라 날짜 포맷 입력 활성/비활성
function onCommonIndexModeChange(){
  document.getElementById('common-index-datefmt').disabled =
    document.getElementById('common-index-mode').value !== 'daily';
}

// 공통 input: mode / file_completed_action 연동
function onCommonInputChange(){
  const mode = document.getElementById('common-mode').value;
  const act  = document.getElementById('common-completed-action');
  const logp = document.getElementById('common-completed-log');
  act.disabled  = (mode !== 'read');
  logp.disabled = (mode !== 'read' || act.value === 'delete');
}

function toggleGrokTable(id){
  const tbl = document.getElementById(id+'-table');
  const icon = document.getElementById(id+'-grok-toggle');
  if(!tbl || !icon) return;

  const isCollapsed = tbl.style.display === "none" || tbl.style.display === "";

  if(isCollapsed){
    tbl.style.display = "block";
    icon.textContent = "▴";   // 펼쳐졌을 때 아이콘
  } else {
    tbl.style.display = "none";
    icon.textContent = "▾";   // 접혔을 때 아이콘
  }
}
function copyPreview() {
  const txt = document.getElementById("preview").textContent;
  if (!txt.trim()) {
    alert("복사할 내용이 없습니다.");
    return;
  }

  navigator.clipboard.writeText(txt)
    .then(() => alert("logstash.conf 내용이 복사되었습니다!"))
    .catch(() => alert("복사 중 오류가 발생했습니다."));
}

function highlightLogstash(conf) {
  // 원본 텍스트를 먼저 HTML 이스케이프
  let html = escapeHTML(conf);

  // 1) 문자열
  html = html.replace(/"([^"]*)"/g,
    match => `<span class="c-string">${match}</span>`
  );
  // 2) 숫자
  html = html.replace(/\b\d+\b/g,
    match => `<span class="c-number">${match}</span>`
  );
  // 3) 키워드
  html = html.replace(
    /\b(path|type|mode|file_completed_action|file_completed_log_path|sincedb_path|start_position|discover_interval|max_open_files|hosts|ssl_enabled|ssl_verification_mode|user|password|index|separator|quote_char|columns|timezone|target|ilm_enabled|manage_template)\b/g,
    match => `<span class="c-key">${match}</span>`
  );
  // 4) 블록명
  html = html.replace(/\b(input|filter|output)\b/g,
    match => `<span class="c-block">${match}</span>`
  );
  // 5) Grok 패턴: %{TYPE:FIELD[:EXTRA]}
  html = html.replace(
    /%\{([A-Za-z0-9_]+):([A-Za-z0-9_]+)(?::([A-Za-z0-9_]+))?\}/g,
    (match, gtype, gvar, gextra) => {
      return `<span class="c-grok">%{` +
             `<span class="c-gtype">${gtype}</span>:` +
             `<span class="c-gvar">${gvar}</span>` +
             (gextra ? `:<span class="c-gextra">${gextra}</span>` : "") +
             `}</span>`;
    }
  );

  return html;
}

function escapeHTML(str){
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}
function updateTypeTitle(id, value){
  const span = document.getElementById(id + '-title');
  const chip = document.getElementById(id + '-chip');

  if(!span || !chip) return;

  const trimmed = value.trim();
  span.textContent = trimmed ? trimmed : '( - )';
  
  if(trimmed){
    chip.classList.add("name-active");
  } else {
    chip.classList.remove("name-active");
  }
}



// 초기 상태: type 1개 샘플 + 라이브러리 로드
addType();
renderSizingGuideTable();
onCommonInputChange();
onCommonIndexModeChange();


// ─────────────────────────────────────────────
// 기본 Type ELFF 템플릿
// ─────────────────────────────────────────────
const DEFAULT_ELFF = {
  "Edge-Main": `
localtime time-taken c-ip sc-status s-action sc-bytes cs-bytes r-ip cs-method cs-uri-scheme cs-host cs-uri-port cs-uri-path cs-uri-query cs-username cs-auth-group s-hierarchy s-supplier-name rs(Content-Type) cs(User-Agent) sc-filter-result cs-categories x-virus-id s-ip cs(Referer)
  `.trim(),

  "Edge-SSL": `
date time time-taken c-ip cs-username cs-auth-group s-supplier-name s-supplier-ip s-supplier-country s-supplier-failures x-exception-id sc-filter-result cs-categories sc-status s-action cs-method rs(Content-Type) cs-uri-scheme cs-host cs-uri-port cs-uri-extension cs(User-Agent) s-ip sc-bytes cs-bytes x-virus-id cs-threat-source cs-threat-id rs-threat-source rs-threat-id x-rs-certificate-observed-errors x-cs-ocsp-error x-rs-ocsp-error x-rs-connection-negotiated-cipher-strength x-rs-certificate-hostname x-rs-certificate-hostname-category cs-threat-risk x-rs-certificate-hostname-threat-risk x-bluecoat-access-security-policy-action x-bluecoat-access-security-policy-reason
  `.trim(),

  "Cloud": `
c-ip c-ip-version c-port cs-auth-groups cs-bytes cs-categories cs-host cs-icap-error-details cs-icap-service cs-icap-status cs-method cs-referer cs-threat-risk cs-uri-extension cs-uri-path cs-uri-port cs-uri-query cs-uri-scheme cs-user-agent cs-user-domain cs-userdn cs-x-requested-with date r-ip r-ip-version r-supplier-country rs-content-type rs-icap-error-details rs-icap-service rs-icap-status s-action s-ip s-source-ip s-supplier-country s-supplier-failures s-supplier-ip sc-bytes sc-filter-result sc-status time time-taken x-action-result x-bluecoat-access-type x-bluecoat-application-name x-bluecoat-application-operation x-bluecoat-location-id x-bluecoat-location-name x-bluecoat-placeholder x-bluecoat-reference-id x-bluecoat-reference-ids x-bluecoat-request-tenant-id x-bluecoat-transaction-uuid x-client-agent-ip x-client-agent-sw x-client-agent-type x-client-device-id x-client-device-name x-client-device-type x-client-os x-client-security-posture-details x-client-security-posture-risk-score x-cloud-rs x-cs-certificate-subject x-cs-client-ip-country x-cs-connection-negotiated-cipher x-cs-connection-negotiated-cipher-size x-cs-connection-negotiated-ssl-version x-cs-ocsp-error x-cs-public-ip x-data-leak-detected x-data-types x-exception-id x-file-details x-icap-reqmod-header(X-ICAP-Metadata) x-icap-respmod-header(X-ICAP-Metadata) x-random-ipv6 x-request-origin x-rs-certificate-hostname x-rs-certificate-hostname-categories x-rs-certificate-hostname-threat-risk x-rs-certificate-observed-errors x-rs-certificate-validate-status x-rs-connection-negotiated-cipher x-rs-connection-negotiated-cipher-size x-rs-connection-negotiated-ssl-version x-rs-ocsp-error x-sc-connection-issuer-keyring x-sc-connection-issuer-keyring-alias x-symc-inspected x-symc-page-views x-symc-upload-source x-virus-id
  `.trim()
};


// ─────────────────────────────────────────────
// 기본 Type 자동 추가 함수
// ─────────────────────────────────────────────
const DEFAULT_TYPE_OPTS = {
  "Edge-Main": { path:"main_process/*.log.gz", since:"sincedb-main",  index:"edge-http"  },
  "Edge-SSL":  { path:"ssl_process/*.log.gz",  since:"sincedb-ssl",   index:"edge-https" },
  "Cloud":     { path:"*.log.gz",              since:"sincedb-cloud", index:"" }
};

function addDefaultType(typeName) {
  addType();  // 새로운 type 카드 1개 생성

  const id = `type-${typeSeq}`;  

  // type 이름 자동 입력
  document.getElementById(`${id}-name`).value = typeName;
  updateTypeTitle(id, typeName);

  // path / sincedb / index 기본값
  const o = DEFAULT_TYPE_OPTS[typeName];
  if(o){
    document.getElementById(`${id}-path`).value = o.path;
    document.getElementById(`${id}-since`).value = o.since;
    document.getElementById(`${id}-es-index`).value = o.index;
  }

  // ELFF 자동 입력
  document.getElementById(`${id}-elff`).value = DEFAULT_ELFF[typeName];

  // 자동 GROK 변환 실행
  autoElffToGrok(id);

  // 카드 펼치기
  const card = document.querySelector(`.type-card[data-id="${id}"]`);
  if(card) card.classList.remove('collapsed');
}




// ─────────────────────────────────────────────
// 화면 전환 (첫 화면 / 리소스 계산기 / Logstash 설정 / ELK 자동 구성)
// ─────────────────────────────────────────────
function showView(v){
  document.getElementById('view-home').style.display = (v === 'home') ? 'flex' : 'none';
  document.getElementById('view-calc').style.display = (v === 'calc') ? 'block' : 'none';
  document.getElementById('view-conf').style.display = (v === 'conf') ? 'flex'  : 'none';
  document.getElementById('view-wizard').style.display = (v === 'wizard') ? 'block' : 'none';
  document.getElementById('side-nav').style.display = (v === 'home') ? 'none' : 'flex';
  document.getElementById('nav-calc').classList.toggle('active', v === 'calc');
  document.getElementById('nav-conf').classList.toggle('active', v === 'conf');
  document.getElementById('nav-wizard').classList.toggle('active', v === 'wizard');
  if(v === 'wizard') openWizardFrame();
  window.scrollTo({top:0});
}

// ELK 자동 구성(config-wizard.html): 처음 열 때 iframe에 불러오고, 화면 높이에 맞춥니다.
function openWizardFrame(){
  const f = document.getElementById('wizard-frame');
  if(f && !f.getAttribute('src')) f.setAttribute('src', f.dataset.src);
  fitWizardFrame();
}
function fitWizardFrame(){
  const f = document.getElementById('wizard-frame');
  if(!f || f.offsetParent === null) return;          // 숨겨져 있으면 계산하지 않음
  const top = f.getBoundingClientRect().top + window.scrollY;
  f.style.height = Math.max(520, window.innerHeight - top - 16) + 'px';
  // 바깥 페이지에 남는 세로 스크롤(여백만큼)을 없애 스크롤 영역이 iframe 안쪽 하나만 되도록 합니다.
  const over = document.documentElement.scrollHeight - window.innerHeight;
  if(over > 0){ const h = parseFloat(f.style.height) - over; if(h >= 520) f.style.height = h + 'px'; }
}
window.addEventListener('resize', fitWizardFrame);

showView('home');
// 주소 끝에 #wizard / #calc / #conf 를 붙이면 해당 기능을 바로 엽니다. (예: .../elk/#wizard)
(function(){
  const h = location.hash.replace('#','');
  if(['calc','conf','wizard'].includes(h)) showView(h);
})();
