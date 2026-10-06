# v2.9.5

- **점검 웹 그래픽 대시보드 확장**: CPU·메모리·JVM Heap·루트 디스크·Elasticsearch 데이터 디스크를 원형 게이지로 표시하고, 전체 점검 결과와 서비스 상태는 정상/주의/이상 비율의 도넛 차트로 표시합니다. 기존 막대 그래프와 상세 표는 유지하며, 외부 차트 라이브러리 없이 CSS/JavaScript만 사용해 폐쇄망에서도 동작합니다.
- **읽기 쉬운 Wizard 빌드 이름**: 기존 8자리 16진수 빌드 번호 대신 `calm-river-blue-star`처럼 사전적 의미가 있는 쉬운 영단어 4개 조합을 파일 내용에서 결정적으로 생성합니다. 같은 파일은 항상 같은 빌드 이름을 사용하고 내용이 바뀌면 이름도 바뀝니다.
- **점검 웹 기본 포트 변경**: `elk-report-web` 기본 포트를 `8088/tcp`에서 `5602/tcp`로 변경했습니다. Kibana 기본 포트 5601 바로 다음 번호라 운영 시 구분하기 쉽습니다.
- `elk-report`가 기존 터미널 출력과 동시에 시각적 HTML 리포트(`/var/lib/elk-report/report.html`)를 생성하도록 확장했습니다.
- 새 `elk-report-web.py` / `elk-report-web.service`를 추가해 기본 `5602/tcp`에서 점검 HTML을 제공합니다. 웹 페이지에서 `elk-report`와 허용된 옵션만 실행해 최신 정보를 다시 불러올 수 있으며 임의 셸 명령은 거절합니다.
- `elk-report`에 `cfg`(OneClick 구성 일치) 섹션을 추가해 설치 패키지, vm.max_map_count, Swap/swappiness, Elasticsearch/Kibana 주요 설정, Logstash Heap·pipeline, 관리 도구, ProxySG cron, 점검 웹 서비스를 `elk.env` 기대값과 비교합니다.
- `check-elk.sh`도 관리 도구·sysctl·Swap·Logstash Heap/pipeline·ProxySG cron·점검 웹 누락/불일치를 검사합니다.
- Config Wizard 점검 출력 예시를 현재 Swap 안전망 정책과 `cfg`/HTML 출력에 맞게 갱신하고, 점검 웹 Listen/Port/HTML 경로/UFW 허용 대역 설정을 추가했습니다.
- Config Wizard / One-Click / elk-patch / elk-report / Windows 원격 배포 표기를 v2.9.5로 올렸습니다.

# v2.9.4

- **점검 리포트(`elk-report`) 출력 가독성 개선**: 화면 폭(80~120칸)에 맞춘 섹션 구분선, 고정 라벨 칸 + 긴 설명 자동 줄바꿈(값 칸 정렬), 주의/이상 항목 라벨 색 강조, 맨 아래에 **섹션별 상태 요약**과 **조치 필요 목록**(이상 → 주의 순)을 추가했습니다. 점검 로직·종료 코드(0/1/2)·옵션은 그대로입니다. 파이프/파일 저장 시 폭은 100칸이며 `ELK_REPORT_COLS=숫자`로 바꿀 수 있습니다.
- **서버 스펙 → 권장값 자동 입력 + Swap 안전망**: 1단계 맨 위에 CPU·메모리·디스크를 적으면 Elasticsearch/Logstash Heap, Logstash workers·batch·영구 큐, swap, memory lock, 샤드/복제본이 자동으로 채워지는 패널을 추가했습니다(빠른 선택 4종, 직접 고친 값은 덮어쓰지 않음, 되돌리기). Swap 은 이제 **끄지 않는 것이 기본**(`DISABLE_SWAP=false`)이며, swap 이 없으면 swap 파일을 안전망으로 만듭니다(`SWAP_CREATE_IF_NONE`, `SWAP_SIZE_GB`(0=메모리의 절반, 2~8GB), `SWAP_FILE`; 컨테이너·공간 부족·파일시스템 미지원이면 건너뜀). `ES_BOOTSTRAP_MEMORY_LOCK=true`는 컨테이너에서 설치기가 자동으로 끕니다. `elk-report`의 Swap 항목은 swappiness·memory_lock·사용률로 판정합니다. (`wizard-defaults.js`의 `DISABLE_SWAP` 기본값을 true→false 로 바꿨습니다.)
- **TLS 인증서 20년**: `ES_CA_DAYS`/`ES_CERT_DAYS`(기본 7300일), `NGINX_TLS_DAYS`(기본 3650→7300), `ES_TLS_REISSUE`, `ES_CERT_EXTRA_SANS`를 추가했습니다. 새 공용 라이브러리 `elk-tls-lib.sh`(openssl 기반)가 Elasticsearch 자동 생성 인증서를 **같은 CA 키로** 새 유효기간으로 다시 발급해 `certs/pem/`에 저장하고 `elasticsearch.yml`이 PEM 을 쓰게 합니다. 설치기는 Elasticsearch 가 멈춘 상태에서 운영 yml 을 쓰기 직전에 수행하며, 이미 충분히 길면 건드리지 않고 실패해도 기본 인증서로 계속합니다. Wizard 2·4단계/고급 3·5A번에서 기간을 바꿀 수 있습니다.
- **패치로 인증서 연장·갱신**: `elk-patch`에 `ES_CA_DAYS`, `ES_CERT_DAYS`, `NGINX_TLS_DAYS`를 추가했습니다(값이 같아도 "지금 갱신"). Elasticsearch 는 백업 → 재발급 → PEM 설정 → 한 번 재시작 → 서버가 새 인증서를 내보내는지 일련번호 확인, 실패 시 자동 복구. Nginx 는 자체 서명 인증서 갱신 → `nginx -t` → reload. 패치 페이지에 "TLS 인증서 유효기간" 그룹을 추가했고 패치 파일·붙여넣기·"이전 버전 서버" 도구 설치 블록에 `elk-tls-lib.sh`를 포함했습니다. 이전 버전(GUIDE_*) 서버에서도 쓸 수 있습니다. `elk-report`는 인증서 점검에 PEM 파일과 실제로 서빙 중인 Elasticsearch 인증서를 추가했습니다.
- **Wizard 빌드 번호 표시 + 사이트 iframe 캐시 방지**: 수정본을 올렸는데 화면이 예전 그대로 보이는 경우(브라우저 캐시, 배포 지연)를 바로 알아볼 수 있도록 Wizard 왼쪽 아래에 `v2.9.4 · 빌드 xxxxxxxx` 를 표시합니다. 번호는 파일 내용의 sha256 앞 8자리(번호 자리를 비운 상태로 계산)이고 `tools/sync_wizard.py` 가 자동으로 넣으며 `--check` 로 검증합니다. 사이트(`script.js`)는 자동 구성 iframe 주소 뒤에 현재 시각(`?v=…`)을 붙여 열 때마다 최신 Wizard를 받도록 했습니다.
- **패치 페이지 2번(바꿀 값 수정) 입력칸 스타일**: 입력칸이 `.field` 밖에 있어 브라우저 기본 모양(안쪽으로 파인 2px 테두리, 각진 모서리, 기본 글꼴)으로 보이던 것을, 다른 페이지의 입력칸과 같은 값(1px `#cbd5e1` 테두리, 8px 둥근 모서리, 패딩 8px 9px, 높이 36px)으로 맞췄습니다. 로그 포맷 입력칸은 다른 페이지의 포맷 입력칸과 같은 모양(고정폭 12px, 9px 둥근 모서리, 최소 높이 96px, 세로 크기 조절)입니다. 값이 잘못되면 다른 페이지와 같은 빨간 입력칸으로 표시됩니다.
- **점검 표를 한 줄로**: 점검 항목마다 한 줄이고, 왼쪽 약 70%(17% + 37% + 16%)에 점검 항목·왜 확인하나·정상 기준, 오른쪽 약 30%에 **한 줄짜리 명령 입력칸 + 복사 버튼**을 둡니다. 명령이 입력칸보다 길면(실제 화면 폭으로 판단, 창 크기를 바꾸면 다시 판단) `펼치기` 버튼이 나오고, 누르면 입력칸 자리는 "아래에 펼쳐짐 ▼"로 바뀌며 **바로 아랫줄(표 전체 폭)에 전체 명령**이 줄바꿈되어 펼쳐집니다. `접기`로 되돌립니다. 복사는 접힌 상태에서도 전체 명령을 복사합니다. 입력칸에 마우스를 올리면 전체 명령이 툴팁으로 보입니다. **스냅샷 성공 여부 항목은 삭제**했습니다(행과 명령 모두).
- **2.9.4 이전에 설치한 서버에 재설치 없이 도구 추가**: 점검·패치 페이지에 "🧰 2.9.4 이전에 설치한 서버" 카드를 추가했습니다. 서버 터미널에 한 번 붙여넣으면(약 31KB) `elk-report`, `elk-patch`와 라이브러리만 설치하고, 설치된 서비스·설정·cron·로그 처리는 건드리지 않으며 재시작하지 않습니다(`/etc/elk-auto/elk.env`가 없으면 아무것도 설치하지 않음, 다시 붙여넣으면 갱신). `elk-report`는 `GUIDE_*` 이름의 elk.env와 예전 cron 파일(`elk-guide-log-process`)을 읽어 **모든 항목**을 점검합니다. `elk-patch`는 이전 버전(`GUIDE_*`) 서버를 감지하면 설정 파일의 예전 이름 그대로, 예전 cron 파일 그대로 수정하며 **실행 시간(cron) · 보존기간(ILM) · 수신/백업 폴더 · Data View 이름**만 패치합니다(`--list`의 ★). 예전 파이프라인은 47개 칼럼 목록 하나를 MAIN/SSL에 함께 써서 지금 도구로 다시 만들면 필드 이름이 달라지므로, 파이프라인을 다시 만드는 항목은 이유와 함께 **거절**하고 아무것도 바꾸지 않습니다. 이전에는 "먼저 재설치하세요"라고만 거절했습니다.
- **마지막 단계 정리 (설치 방법 3가지)**: 흩어져 있던 5개 버튼 영역(설치 패키지 다운로드, 서버에 직접 붙여넣기, 파일 저장·확인, 설치 실행 명령 복사, 검증·점검 명령 복사)을 **방법 1 자동 설치 / 방법 2 서버에 직접 붙여넣기 / 방법 3 파일 저장 + 명령 복사** 3개의 번호 카드로 묶었습니다. 맨 위에 "설치 방법 고르기" 표(상황 → 방법)를 두고 배지를 누르면 해당 카드로 이동합니다. 카드마다 `이럴 때 / 하는 일 / 준비물`을 적었고, 방법 3은 `💾 파일 저장 · 확인`, `📋 설치 실행 명령 복사`, `🔍 검증 · 점검 명령 복사` 3개 블록으로 나눠 **버튼마다 한 줄 설명**과 **실행 위치 표시(PC에서 / 서버에서)**, 검증은 설치 전·점검은 설치 후라는 안내를 붙였습니다. 명령 확인 상자는 방법 3 카드 안, 버튼 바로 아래에 열립니다. 모든 버튼 id와 동작은 그대로입니다.
- **점검 표 명령 상자 색상**: 검은 배경 대신 밝은 인디고 톤(연한 남보라 배경, 진한 남색 글자 — 대비 14:1, 왼쪽 인디고 막대, 앞의 `$` 표시)으로 바꿔 읽기 쉽게 했습니다. `$`는 화면 장식이라 복사되는 명령에는 들어가지 않고, 복사·펼치기 버튼도 같은 인디고 계열로 맞췄습니다.
- **서버에 직접 붙여넣기 (전송이 안 되는 환경)**: 마지막 단계(빠른 설정 11 / 고급 설정 26)에 새 그룹을 추가했습니다. SSH/SCP로 보낼 수 없을 때 명령을 복사해 Ubuntu 서버 터미널에 붙여넣으면 설치 스크립트(`~/elk-oneclick-install-v2.9.4.sh`)가 서버에서 만들어지고, **생성 후 바로 설치(`--local-install`) / 생성 후 검증만(`--validate`) / 스크립트만 만들기** 중 고른 동작이 이어서 실행됩니다. 설치 파일을 압축해 담아 일반 `.sh`(약 350KB)보다 작고(약 125KB), 본문은 76자 Base64 줄이라 붙여넣기가 깨지지 않으며, SHA-256 검사로 잘린 붙여넣기는 실행하지 않고 파일을 지웁니다. 파일은 700 권한으로 만들고 붙여넣는 동안 셸 기록을 끄며, SSH/sudo 배포 비밀번호는 넣지 않습니다. 내부적으로 `generateOneClick(opts)`가 `paste`(배포 비밀번호 제거)와 `gz`(압축 블록) 옵션을 받고, 옵션이 없을 때의 결과(.sh 다운로드, ZIP, .cmd)는 그대로입니다.
- **점검 표 레이아웃**: 점검 항목마다 **두 줄**로 나눴습니다. 윗줄에 점검 항목 · 왜 확인하나 · 정상 기준, 아랫줄에 점검 명령과 복사 버튼을 넣었습니다. 명령은 **최대 2줄까지만** 보이고(`…`로 잘림 표시) 더 길면 `펼치기`/`접기` 버튼이 나옵니다. 줄 수는 실제 화면 폭으로 판단해 창 크기를 바꾸면 다시 계산합니다. 복사는 접힌 상태에서도 전체 명령을 복사하고, 복사 결과 문구는 짧게(`✓ 복사됨`) 줄였습니다. "한 번에 점검"의 점검 항목 선택은 2열에서 **3열**로 늘렸고(좁은 창은 2열/1열), 표 아래 안내 문구가 표 테두리에 붙어 있던 것에 여백을 주었습니다.
- **버전 표기 정리**: Config Wizard 제목·상단 표기, 다운로드 파일 이름(`elk-oneclick-install-v2.9.4.sh`, `elk-auto-install-v2.9.4.cmd`, `elk-auto-installer-v2.9.4.zip`), 설치기 시작 로그(`ELK Auto Installer v2.9.4`)를 **2.9.4**로 올렸습니다. 지금까지 이 목록의 기능들은 코드 주석에는 v2.9.4로 적혀 있었지만 화면과 파일 이름은 v2.9.3으로 남아 있었습니다. `elk-patch --version`, `elk-report --version`으로 서버에 설치된 도구의 버전을 볼 수 있고, `tools/check_version.py`가 모든 표기가 `_internal/docs/VERSION`과 같은지 검사합니다(CI 포함, `--set X.Y.Z`로 한 번에 올림). 이전 이름으로 만든 One-Click SH(`…-v2.9.3.sh`)도 `run-remote-deploy`가 계속 찾아 씁니다.
- **점검 페이지 1·2번 합치기**: 정기점검 추천 항목 표와 항목별 점검 명령을 **하나의 표**로 합쳤습니다. "리포트 항목" 열 대신 항목마다 **점검 명령(한 줄, 복사 버튼)** 이 들어갑니다. 요청 항목(Ubuntu · Elastic/Logstash/Kibana 버전 · Uptime · 디스크[로그 파일·인덱스] · CPU · 메모리 · 마지막 로그 시각[파일·인덱스])은 모두 행으로 들어 있고, 표의 나머지 항목에도 명령을 추가했습니다(파일시스템, 인덱스 증가 추세, JVM Heap, ILM 오류·보존기간, Logstash 오류 로그, NTP, OS 업데이트·재부팅, 인증서 만료일, 처리 스크립트 오류, FTP 계정). 쓰지 않는 기능(ProxySG 로그 처리 스크립트, FTP)의 행은 "해당 없음"으로 표시됩니다. 사이드 메뉴는 2개(점검 항목과 명령 / 한 번에 점검)입니다.
- **사이트 화면 폭 통일**: 리소스 계산기·Logstash 설정 페이지도 ELK 자동 구성 페이지와 같은 폭(본문 최대 1560px)을 쓰도록 `style.css`의 `.layout` 폭을 1560px로 올리고 자동 구성 전용 `.layout.wide` 규칙과 `script.js`의 전환 코드를 없앴습니다. 자동 구성 iframe 높이 계산에서는 바깥 페이지에 남던 세로 스크롤(약 18px)을 제거했습니다.
- **이미 켜져 있는 UFW에 필요한 포트 자동 허용**: `UFW_MANAGE=false`로 설치해도 서버에 UFW가 **이미 켜져 있으면** 설치한 서비스에 필요한 포트(Kibana 또는 Nginx, Elasticsearch, 켜 둔 Logstash 입력 포트, FTP 제어·패시브 포트)를 허용 대역(CIDR)에 한해 허용 규칙으로 추가합니다. 새 설정 `UFW_ADD_RULES_IF_ACTIVE`(기본 true, 끄면 예전처럼 방화벽을 건드리지 않음). UFW를 설치·활성화·비활성화하거나 기본 정책·기존 규칙을 바꾸지 않으며, 꺼져 있거나 설치되어 있지 않으면 아무것도 하지 않습니다. 규칙 하나가 실패하거나(잘못된 대역) 대역이 비어 있어도 설치는 계속하고 경고만 남깁니다(이전에는 `ufw allow` 실패 시 설치가 중단될 수 있었습니다). UFW 상태 확인은 언어 설정과 무관하게 동작합니다(`LC_ALL=C`). 로그에는 `UFW 허용: <대역> → <서비스> <포트>/<프로토콜>`이 한 줄씩 남습니다. Wizard: 9단계·고급 19번에 스위치 추가, Kibana 직접 접속 허용 대역 카드를 9단계에 노출, 규칙이 적용될 수 있을 때 허용 대역 카드를 "관리자 확인" 항목으로 표시, 허용 대역 형식 검사(IPv4/IPv6/any)와 안내 문구 추가, UFW 관련 영문 자동 라벨을 한글로 정리.
- **점검 페이지 + `elk-report`**: 상단 메뉴에 `점검` 탭을 추가했습니다(빠른 설정 · 고급 설정 · 패치 · 점검). 주기별(매일/주 1회/월 1회) **정기점검 추천 항목**, 요청 항목(Ubuntu · Elastic/Logstash/Kibana 버전 · Uptime · 디스크[로그 파일·인덱스] · CPU · 메모리 · 마지막 로그 시각[파일·인덱스])의 **한 줄 점검 명령**(현재 설정값 기준), 그리고 모든 항목을 읽기 쉬운 색 리포트로 출력하는 새 도구 `elk-report.sh`를 제공합니다. 설치기는 `/usr/local/sbin/elk-report`를 설치하고(`sudo elk-report`), 설치하지 않은 서버에는 페이지의 "전체 붙여넣기"(gzip 약 14KB)로 실행할 수 있습니다. 읽기 전용이며 종료 코드 0/1/2(정상/주의/이상)를 돌려줍니다. 한 항목이 실패해도 리포트는 끝까지 나옵니다.
- **상단 메뉴 배치**: 제목과 페이지 탭을 왼쪽, 검색을 가운데, 나머지를 오른쪽으로 정렬했습니다. 좁은 창에서는 검색이 아래 줄 가운데로 내려갑니다.
- **Logstash 필터 수정 (인덱스 필드가 한 칸씩 밀리는 문제)**: `proxysg-log-filter.conf`의 공백 정리를 확인된 방식으로 교체했습니다. 이전 `gsub`(`"\\\"" → ""`, `"\\t" → " "`)는 Logstash 기본 설정(`config.support_escapes=false`)에서 문자 그대로 `\\`+`t` 같은 조합을 찾아 공백으로 바꿔(예: URL·경로의 `\test`) 필드를 쪼갰습니다. 이제 `"message", "\s+$", ""`(끝 공백 제거) 와 `"message", "\s+", " "`(연속 공백을 한 칸으로)를 사용합니다. 설치기·Wizard 미리보기·패치 도구가 같은 템플릿을 씁니다. **이미 설치된 서버**에는 재설치하거나 `/etc/logstash/conf.d/*.conf`의 해당 `mutate { gsub … }` 블록을 직접 같은 내용으로 바꾼 뒤 Logstash를 재시작해야 반영됩니다.
- **설치 전 디스크 자동 확장**: 루트(/)가 일반 LVM 볼륨이고 볼륨 그룹에 남는 공간이 있으면 `lvextend -l +100%FREE -r`로 모두 할당합니다(`OS_EXTEND_ROOT_LVM`, 기본 true). LVM이 아니거나 thin 볼륨이거나 남는 공간이 없으면 건너뛰고, 실패해도 설치는 계속합니다.
- **설치 화면 색상**: 중요도(오류 빨강 · 경고 노랑 · 완료 초록)와 주제(시스템 · 패키지 · Elasticsearch · Kibana · Logstash · Nginx/TLS · FTP/처리 스크립트 · 방화벽)로 글자색을 구분하고, 끝에는 초록 "✔ 설치 완료" 상자 / 빨강 "✖ 설치 실패" 상자(원인·로그·다음 조치)를 표시합니다. 새 파일 `elk-color.sh`(설치기·원클릭 파일·Windows 배포 스크립트가 공유). 색은 화면에만 입히며 로그 파일은 일반 텍스트입니다. 터미널이 아니면 자동으로 꺼지고, `--no-color`/`--color=always|never`, `NO_COLOR`, `ELK_COLOR`로 조절합니다. 설치가 중간에 멈추면(`die` 또는 예상 못 한 명령 실패) 이제 항상 실패 상자가 나옵니다. 원격 모니터의 완료 메시지는 `[OK] …` 줄 대신 상자로 바뀌었습니다.

- **패치 (설치 후 일부 값만 수정)**: 상단 메뉴에 `패치` 페이지를 추가했습니다(빠른 설정 · 고급 설정 · 패치). 기준값(불러온 sh/elk.env)과 달라진 항목을 자동 선택하고, 페이지에서 값을 바로 고칠 수 있으며, 적용은 ① 패치 파일(.sh), ② 서버에 바로 붙여넣는 **전체 명령**(gzip 압축으로 약 16KB, 임시 파일 자동 삭제), ③ **짧은 명령**(`sudo elk-patch KEY='값' …`) 중에서 고릅니다. 실행 방식은 확인 후 적용 / `--dry-run` / `--yes`. 서버 도구 `elk-patch.sh`(+ `proxysg-lib.sh`)는 변경 내용 표시 → 확인 → elk.env 백업 후 수정 → 필요한 부분만 적용(cron 시간, ILM 보존기간, Logstash 파이프라인[검사 실패 시 자동 복구], Index Template 패턴, Data View, 폴더)하며, 지원하지 않는 값이나 여러 줄 값은 거절하고 아무것도 바꾸지 않습니다. 설치기는 이제 `/usr/local/sbin/elk-patch` 와 `/usr/local/lib/elk-auto/`(도구 라이브러리, 필터 템플릿, 수정한 파이프라인)를 서버에 설치합니다. `tools/check_patch_lib.sh`가 `proxysg-lib.sh`와 설치기의 파이프라인 생성 결과가 같은지 검사하며 CI에 포함했습니다.
- **Config Wizard**: 좌측 단계 메뉴와 제작 안내 문구를 한 열로 묶어 화면에 고정했습니다. 이전에는 메뉴만 고정되어 문구가 같이 스크롤되거나(빠른 설정) 26개 메뉴를 가렸습니다(고급 설정). 이제 문구는 메뉴 바로 아래 같은 위치에 계속 보이고, 메뉴가 화면보다 길면 메뉴 카드 안에서만 스크롤되며 현재 단계가 자동으로 보입니다. (좁은 화면에서는 고정 해제) 11단계·26단계에 있던 패치 패널은 `패치` 페이지로 옮겼습니다.
- **Config Wizard**: 이전/다음 버튼으로 단계를 옮기면 화면 맨 위로 이동(사이트에 넣어 쓸 때는 바깥 페이지도 맨 위로). 비밀번호 입력칸은 마스킹하지 않고 "보기" 버튼을 없앴습니다(SSH/sudo 포함). 8단계에서 MAIN/SSL(사용 시 Cloud) 인덱스 Prefix, Data View 이름, 인덱스 보존기간을 필수(관리자 확인) 항목으로 올리고 3열로 배치, 형식·중복 검사 추가(설치기에도 같은 검사). 상단의 elk.env/기존 SH 불러오기를 "기존 입력값 불러오기" 그룹(elk.env · sh 파일)으로 묶음. 좌측 단계 목록 카드 아래에 제작 안내 문구 추가. 사이트 왼쪽 미니 버튼 순서를 리소스 계산기 → 자동 구성 → Logstash 설정으로 변경.
- **ProxySG Cloud 로그(선택) 추가**: 7단계(고급 14A)에 Cloud를 MAIN·SSL과 나란히 추가했습니다. 기본은 **사용 안 함**이며 `PROXYSG_CLOUD_ENABLED=true`일 때만 적용됩니다. 새 변수 8개: `PROXYSG_CLOUD_ENABLED`, `…_SOURCE_DIR`(/home/cloud), `…_BACKUP_DIR`, `…_PROCESS_DIR`, `…_SINCEDB`, `…_LOG_FORMAT`(기본값: 75개 필드 ELFF), `…_INDEX_PREFIX`(proxy-cloud), `…_DATA_VIEW_NAME`(cloud). 사용 시 설치기는 Cloud 폴더 생성, 처리 스크립트(`proxysg-log-process.sh`)의 Cloud 처리, Logstash file 입력(type `cloud`)·필터 분기·`proxy-cloud-날짜` 출력, Index Template 패턴 추가, Data View 생성, `check-elk.sh`/`elk-ops.sh` 점검 범위 확장을 수행하고, 사용 안 함이면 기존 결과와 동일합니다. `proxysg-log-filter.conf`는 Cloud 분기를 `# @@PROXYSG_CLOUD_BEGIN@@ ~ END@@` 표식으로 감싸 Cloud를 쓸 때만 남깁니다.
- **Config Wizard**: 7단계 제목을 "로그 처리 스크립트"로 변경하고 관련 카드 이름을 정리(예: "ProxySG MAIN/SSL 흐름 사용" → "ProxySG 로그 처리 스크립트 사용", 영문 자동 라벨 → 한글). 로그 종류별 카드를 MAIN | SSL | Cloud **3열**로 배치하고, "처리할 로그 종류" 패널에서 Cloud를 켜고 끄며, 꺼져 있으면 Cloud 카드·도표 열·요약을 회색 "비활성"으로 표시합니다. 11단계 로그 처리 흐름 도표와 요약에도 Cloud 열이 추가되었습니다.
- **Config Wizard 버그 수정**: 파일 카드의 중괄호 검사가 정상 설정(기본 필터 템플릿 포함)에도 "개수가 맞지 않습니다"라고 경고하던 문제를 수정했습니다. 원인은 주석 제거가 문자열·정규식 안의 `#`까지 지워 닫는 중괄호가 사라지던 것과, 정규식 리터럴(`/^\{/`)·작은따옴표 문자열을 해석하지 못하던 것입니다. 이제 Logstash 문법(주석, 큰/작은따옴표 문자열, `=~`/`!~` 정규식)을 읽어 괄호를 세고, 실제로 짝이 맞지 않을 때만 몇 번째 줄인지 알려 줍니다.
- **wizard-defaults.js**: 관리자가 수정한 파일(예: `LOGSTASH_PIPELINE_FILE`을 `/etc/logstash/conf.d/logstash.conf`로 지정)을 기준 파일로 채택. `tools/gen_defaults.py`는 이제 기존 파일을 그대로 두고 새 항목만 추가하며(전체 재생성은 `--rewrite`), `--file`로 다른 경로의 파일도 대상으로 지정할 수 있다.
- **Config Wizard**: 마지막 단계를 좌우 2개 섹션(1 : 2)으로 재배치 — 왼쪽 "구성 요약 및 검증 결과"(요약 카드 1열 + 그 아래 필수 조건 검증·권장 확인)와, 같은 위계의 오른쪽 **"로그 처리 흐름 도표"**(① FTP 업로드 위치 → ② 스크립트 처리(수신·백업·처리 폴더, cron, 처리 순서) → ③ Logstash 처리(파이프라인, 입력, 필터 필드 수, 출력) → ④ 생성되는 인덱스·Data View·Template·ILM). 설정값 기준으로 표시되며 설정을 바꾸면 도표도 함께 바뀌고, 흐름을 쓰지 않을 때는 일반 프로필 요약을 보여 준다.
- **Config Wizard**: 단계 제목 아래의 "각 입력 카드를 클릭하면…" 안내 줄 삭제. 입력 카드·파일 카드의 테두리를 진하게 하고 카드 영역에 옅은 배경과 그림자를 넣어 구분을 명확히 함(마우스를 올리거나 펼친 카드는 파란 테두리, 오류는 빨강·필수는 주황 유지). 11단계의 "자동 실행 파일(.cmd) 다운로드" 버튼을 크고 눈에 띄는 주 버튼으로 바꾸고 ZIP은 보조 버튼으로 구분.
- **이름 정리 (호환 유지)**: 기존 설치 절차 문서에서 가져온 이름을 ProxySG 기준으로 바꿨습니다. 예전 이름으로 만든 설치 파일·`elk.env`·서버도 그대로 이어서 쓸 수 있습니다.

  | 구분 | 이전 이름 | 새 이름 |
  |---|---|---|
  | 환경변수 | `GUIDE_*` | `PROXYSG_*` (`GUIDE_PROXY_FLOW_ENABLED` → `PROXYSG_FLOW_ENABLED`, `GUIDE_PROXY_CSV_FILTER_ENABLED` → `PROXYSG_CSV_FILTER_ENABLED`) |
  | Logstash 프로필 값 | `proxysg_guide` | `proxysg` |
  | 파일 처리 스크립트 | `guide-log-process.sh` → `/usr/local/sbin/elk-guide-log-process` | `proxysg-log-process.sh` → `/usr/local/sbin/elk-proxysg-log-process` |
  | 스케줄 / 로그 | `/etc/cron.d/elk-guide-log-process`, `/var/log/elk-guide-log-process.log` | `/etc/cron.d/elk-proxysg-log-process`, `/var/log/elk-proxysg-log-process.log` |
  | Logstash 필터 템플릿 | `proxysg-guide-filter.conf` | `proxysg-log-filter.conf` |
  | 운영 명령 | `elk-ops guide` | `elk-ops proxysg` |
  | 문서/예제 | `PPT_GUIDE_MAPPING.md`, `elk-guide-9.5.2.env` | `INSTALL_STEP_MAPPING.md`, `elk-proxysg.env.example` |

  호환 처리: 설치기는 예전 환경변수 이름과 프로필 값을 새 이름으로 이어받고(새 이름이 있으면 그 값이 우선), 이전 이름으로 등록된 cron 파일과 스크립트가 남아 있으면 정리해 같은 처리가 두 번 실행되지 않게 합니다. Wizard의 "기존 SH/env 불러오기"와 `wizard-defaults.js`도 예전 이름을 새 이름으로 읽습니다. 예전 설치 파일 안에 들어 있던 스크립트·필터는 수정한 것으로 취급하지 않습니다. 설명 문구의 "입력 가이드"는 "입력 방법"으로 바꿨습니다.
- **run-remote-deploy**: sudo 비밀번호 자동 입력 시 stdin 앞에 UTF-8 BOM이 붙어 sudo 인증이 실패하던 문제 수정(BOM 없는 입력 인코딩 + 원격 측 BOM/CR 제거). sudo 검증 실패 시 `[DIAG]` 자동 진단(비밀번호 값은 출력하지 않음) 추가.
- **install-elk**: `logstash-keystore create`가 stdin이 없는 systemd 실행에서 확인 질문 때문에 중단되던 문제 수정, keystore 실패 시 실제 오류 메시지 출력.
- **install-elk**: Elasticsearch 9.x에서 본문이 있는 Kibana service token 요청이 거부되던 문제 수정.
- **install-elk**: 서비스 기동 대기 중 curl 연결 오류 출력 제거, 15초마다 대기 진행 로그 출력.
- **install-elk**: `ELASTIC_USERNAME` 검증 추가, Kibana 로그인 사용 여부(`KIBANA_LOGIN_ENABLED`)와 세션 유휴 만료(`KIBANA_SESSION_IDLE_TIMEOUT`) 옵션 추가.
- **run-remote-deploy.cmd**: 완료/오류 결과를 노란 글씨로 표시하고 창이 닫히지 않도록 `pause` 추가(`ELK_NO_PAUSE=1`이면 생략). 경로에 괄호가 있어도 동작하도록 구조 정리.
- **Config Wizard**: 초기값(기본값)을 별도 파일 `wizard-defaults.js`로 분리 — 관리자가 이 파일만 고치면 반영(빌드 불필요). 잘못된 항목은 무시하고 화면 위에 경고, 파일이 없거나 문법 오류여도 내장 기본값으로 동작, 비밀번호·키 항목은 지정 불가. `tools/gen_defaults.py`(생성/점검)와 CI 점검 추가.
- **Config Wizard**: 모든 입력 카드에 `기본값: …`(기본값에서 바꾼 경우 `● 기본값에서 변경됨`)을 표시하고, 모호했던 체크박스를 `사용 | 사용 안 함` 선택 버튼(기본 옵션에 `기본` 표시)으로 교체. Nginx 사용 시 Kibana server.host 경고를 제거하고 설치기가 자동으로 127.0.0.1로 제한한다는 안내로 변경.
- **Config Wizard / install-elk**: ProxySG MAIN/SSL 로그 포맷(ELFF `#Fields` 순서)을 7단계 필수 항목으로 입력(`PROXYSG_MAIN_LOG_FORMAT`, `PROXYSG_SSL_LOG_FORMAT`). 설치기가 로그 종류(edge-http / edge-https)마다 별도의 csv `columns`를 이 포맷으로 생성해 Logstash 필터에 반영한다. 필드 이름 규칙은 소문자와 `_`(예: `cs(Referer)`→`cs_referer`, `date`→`log_date`, `time`→`log_time`)이며 화면에서 미리 볼 수 있다. `proxysg-log-filter.conf`는 `@@PROXYSG_MAIN_COLUMNS@@` / `@@PROXYSG_SSL_COLUMNS@@` 줄을 가진 템플릿으로 변경. 설치 전 검증 추가(포맷 비어 있음/허용 문자, `LOGSTASH_PIPELINE_FILE`은 `/etc/logstash/conf.d/` 바로 아래 `.conf`).
- **Config Wizard**: 빠른 설정 3단계(Kibana)·5단계(Logstash)에 설정 파일 저장 위치 패널과 경로 입력칸(`KIBANA_EXTRA_CONFIG_FILE`, `LOGSTASH_PIPELINE_FILE`, `LOGSTASH_EXTRA_CONFIG_FILE`) 추가. 7단계에 파일 처리 cron 파일 경로(`/etc/cron.d/elk-proxysg-log-process`)와 `crontab -l`에 나오지 않는 이유, `* * * * *` 테스트 후 실제 시간으로 바꾸는 방법 안내. 검색 결과 카드에 빠른/고급 설정 단계 위치 표시(클릭 시 이동).
- **Config Wizard / install-elk**: 빠른 설정 7단계(고급 설정 14A)에 "사용되는 스크립트 · Logstash 설정" 패널 추가 — `proxysg-log-process.sh`, `proxysg-log-filter.conf`, Logstash 파이프라인(설치기가 만드는 내용의 미리보기)을 화면에서 보고 수정하면 생성되는 설치 파일·ZIP에 그대로 반영. 수정한 파이프라인은 `custom-pipeline.conf`로 내장되어 자동 생성 대신 설치되고, 수정한 스크립트는 설치 전 `bash -n`으로 검사. 수정 내용은 "기본값으로 되돌리기"/"설정값으로 다시 생성"으로 복구, 기존 SH 불러오기 시 함께 복원.
- **Config Wizard**: 단계 설명을 제목 아래 줄에서 제목 옆의 짧은 주석형 문구("…하는 기능")로 이동. 기존의 자세한 역할 설명은 문구에 마우스를 올리면 표시. 카드 펼치기 안내는 작은 줄로 유지.
- **Config Wizard**: (이전) 각 단계 제목 아래 설명을 "이 단계의 기능이 무슨 역할을 하는지" 설명으로 교체(빠른 설정 11단계, 고급 설정 26단계 전부). 카드 펼치기 안내는 별도 작은 줄로 분리.
- **Config Wizard**: 자동 실행 파일(`elk-auto-install-v2.9.4.cmd`) 다운로드 추가 — 더블클릭하면 임시 폴더에 자동으로 풀고 run-remote-deploy.cmd까지 실행, 끝나면 임시 폴더 삭제(`ELK_KEEP_TEMP=1`이면 유지).
- **Config Wizard**: 자동 전송 및 설치(10단계) / 검증 및 완료(11단계) 분리, 잘못된 값이 있으면 단계 이동 차단 및 빨간 표시, 좌측 메뉴 `필수` 태그, 초기 사용자 Role 드롭다운, 명령어 복사 버튼 수정(기존 `copy()` 미정의 오류) 및 명령어 펼침, 고급 설정 단계 제목 정리, 전체 패키지 ZIP 다운로드.

# v2.9.3

- Windows PowerShell 5.1 parser error in `_internal/tools/run-remote-deploy.ps1` fixed.
  - Removed fragile nested Bash quote function.
  - Remote root commands are Base64 encoded before SSH execution.
- Top-level `run-remote-deploy.cmd` is stored as ASCII/CRLF-compatible text so `@echo off` works reliably in cmd.exe.
- Config Wizard: added **기존 SH 불러오기**.
  - Reads embedded `elk.env` from prior `elk-oneclick-install*.sh`.
  - Restores Ubuntu host/user/port/remote path and SSH/sudo auto-login settings when present.
  - Supports both historical `__ELK_ELK_ENV_B64__` and current heredoc marker names.
- Imported older SH files can be edited and re-saved as the current v2.9.3 format.

# v2.9.0

- systemd detached install에서 `/dev/tty` ENXIO로 중단되는 진행률 출력 버그 수정
- 실제 제어 TTY가 있는 경우에만 fd 9를 확보하고, 비대화형 실행은 stdout 로그 방식으로 진행률 출력
- 패키지 버전 해석 실패 시 정의되지 않은 `err` 호출을 명시적 오류 출력으로 수정

# v2.8.8

- Fixed stale one-click payload selection: Windows launcher now prefers the versioned `elk-oneclick-install-v2.8.8.sh` file.
- Added one-click payload markers so the launcher rejects an older generated SH instead of silently deploying it.
- Hardened Elastic APT version resolution with `apt-cache madison` + `awk`; Logstash `9.5.2` now resolves to Debian package `1:9.5.2-1`.
- Installer logs both the requested upstream version and the exact APT package version before installing.
- Wizard downloads a versioned one-click filename to prevent collisions with older `elk-oneclick-install.sh` files.

# v2.8.7

- Fixed exact-version APT resolution for packages whose Debian version contains an epoch/revision (for example Logstash `1:9.5.2-1` vs upstream `9.5.2`).
- Re-runs now compare installed package upstream versions before deciding to skip.
- Remote console log is pre-created with mode 0600 before the detached systemd job starts.

# v2.8.6

- Windows launcher no longer calls `--remote-start` or `--remote-monitor` inside the one-click SH.
- `run-remote-deploy.cmd` now invokes Ubuntu `systemd-run` directly and only requires the SH to support `--local-install`.
- This prevents CMD/SH version mismatches such as v2.8.5 launcher + older v2.8 generated SH.
- Detached job uses `TimeoutStartSec=infinity` so large Elasticsearch/Kibana/Logstash downloads are not killed by systemd's normal startup timeout.
- Console output is stored in `/var/log/elk-oneclick-console.log`; `--status` reconnects to the same detached job.

# v2.8.6

- 원격 설치를 SSH 세션과 분리된 `systemd-run` 작업으로 실행하도록 변경
- SSH 모니터링 연결이 끊겨도 Ubuntu 서버의 실제 설치는 계속 진행
- `run-remote-deploy.cmd --status`로 실행 중 설치에 다시 연결 가능
- 원격 콘솔 로그 `/var/log/elk-oneclick-console.log` 추가
- APT 다운로드 재시도(`APT_RETRIES`, 기본 10회) 및 연결 타임아웃(`APT_CONNECT_TIMEOUT`, 기본 30초) 추가
- 비대화형(systemd) 실행에서도 다운로드/설치 진행률이 로그에 줄 단위로 표시되도록 개선
- Elasticsearch/Kibana/Logstash 등 APT 패키지 다운로드·설치 진행률 표시 유지

# v2.8.3
- Windows OpenSSH 원격 실행 명령 단순화
- `rc=$?; if ...` 복합 원격 shell 구문 제거
- 설치 성공 시 one-click installer가 자기 자신을 삭제하도록 변경
- SCP/SSH host-key 검증 무시 설정 유지

## v2.8.2
- Windows remote deploy now ignores SSH host-key verification for both SCP and SSH.
- Uses StrictHostKeyChecking=no and NUL known-hosts files, so stale/changed host keys do not block automation.

# v2.7.0

- Configuration Wizard에서 `elk.env`와 모든 설치/보조 스크립트를 포함한 `elk-oneclick-install.sh` 단일 파일 생성
- Ubuntu 서버에는 단일 `.sh` 파일만 업로드하여 설치 가능
- 실행 시 `--validate → 설치 → 전체 상태 점검` 자동 연속 수행
- `--validate`, `--check` 실행 모드 추가
- 설치 후 `/usr/local/sbin/elk-check` 배치
- 전체 상태 점검에 서비스/API/Cluster Health/ILM/Index Template/Nginx/FTP/Timer 검사와 PASS/WARN/FAIL 집계 추가
- 상태점검 로그 `/var/log/elk-post-install-check.log` 저장

# v2.5.0
- 전역 관리자 필수 입력 영역 제거, 각 설치 단계 상단으로 관리자 확인 항목 이동
- 단계별 필수/조건부 항목을 자동 판별하여 주황색 영역에 우선 표시
- Elasticsearch 데이터 경로, Logstash 전용 계정, FTP 루트/업로드 경로 등 사이트별 확인값을 단계별 필수 확인 대상으로 보강
- 필수 항목은 아래 일반 설정 영역에서 중복 표시하지 않도록 정리
- 모든 입력 카드의 상세 설명을 기본 접힘 상태로 변경
- 카드 빈 영역 클릭 또는 Enter/Space로 기능/필요 이유/입력 방법 펼침·접힘 지원
- 조건 기능(Kibana 사용자, Nginx 인증서, FTP, UFW 등) On/Off 시 현재 단계 필수 항목이 즉시 재계산되도록 개선

# v2.4.0
- Wizard 상단 중복 흐름표 제거
- 관리자 필수 확인/입력 영역 추가(계정, 비밀번호, 로그 경로, 조건부 인증서/방화벽/백업 경로)
- 상단/단계 중복 필드 실시간 동기화
- 주요 입력항목 설명을 기능/필요 이유/입력 방법 형식으로 상세화
- 고급 변수의 단순 설명을 섹션별 운영 목적과 입력 기준이 포함된 설명으로 보강

# Changelog

## v2.3.0

- ELK 9.5.2 설치 절차 전체를 GUI `빠른 설정` 10단계로 반영
- GUI에 `빠른 설정` / `고급 설정` 모드 추가
- 환경변수 303개 전체 검색/편집 및 기존 `elk.env` Import/Export 지원
- 빠른 설정 초기값(프리셋) 추가
- ILM 기본 보존기간을 60일에서 90일로 변경
- Elasticsearch `action.destructive_requires_name` 변수화
- Nginx 설치, Self-Signed 인증서, 80→443 Redirect, Kibana Reverse Proxy 자동화
- Kibana 초기 사용자 자동 생성 옵션 추가
- ProxySG MAIN/SSL Logstash `read` mode 프로필 추가
- `/home/main`, `/home/ssl`, backup/process 디렉터리 구조 자동 생성
- `log_process.sh` 흐름을 강화한 `proxysg-log-process.sh` 추가
- 매일 03:00 등 configurable cron 자동 등록
- vsftpd Active FTP / Port 20 옵션 추가, 기존 Passive/FTPS 고급 구성 유지
- `proxy-main-*`, `proxy-ssl-*` 복수 index pattern template 지원
- 기존 인덱스에도 ILM lifecycle 설정을 적용하는 옵션 추가
- main/ssl Kibana Data View 자동 생성
- `elk-ops nginx`, `elk-ops proxysg` 운영 명령 추가

## v2.2.0

- vsftpd FTP 자동 설치/계정/Passive/FTPS/UFW 연동

## v2.1.0

- GUI Configuration Wizard 추가

## v2.0.0

- Managed File Ingest, 90일 ILM, Health Monitor, Snapshot/SLM 추가

## v2.7
- 단일 설치 `.sh`에 원격 배포 모드 추가.
- PC의 Git Bash/WSL/Linux shell에서 일반 권한으로 실행하면 자체 파일을 `scp`로 Ubuntu에 전송하고 `ssh`로 원격 설치를 시작.
- `--deploy`, `--deploy-only`, `--local-install` 모드 추가.
- Wizard 마지막 단계에 Ubuntu 서버 IP/호스트, SSH 계정/포트, 원격 전송 폴더, 전송 후 자동 설치, 성공 후 원격 설치파일 삭제 설정 추가.
- 원격 설치 완료 후 기존 v2.6과 동일하게 전체 상태 점검 자동 수행.
- 설치 성공 시 민감정보가 포함될 수 있는 사용자 홈의 원클릭 `.sh` 파일을 기본 자동 삭제. 실패 시 재실행/분석을 위해 보존.

## v2.8.1
- Fixed Windows `run-remote-deploy.cmd` parsing failures on native cmd.exe.
- Converted launcher to Windows CRLF line endings.
- Removed nested FINDSTR command parsing and delayed expansion.
- Uses direct `for /f usebackq` parsing of DEPLOY_* values from the generated SH.
- Launcher content is ASCII-only for maximum Windows cmd.exe compatibility.

## v2.9.3
- Elasticsearch 운영 설정 재시작 직후 elastic 인증을 단발성 검사하지 않고 재시도합니다.
- 인증이 계속 실패하면 elastic 비밀번호를 재동기화한 뒤 Wizard의 목표 비밀번호를 다시 적용합니다.
- Config Wizard 원격 배포 단계에 SSH 로그인 비밀번호와 sudo 비밀번호 입력을 추가했습니다.
- Windows 원격 배포는 SSH_ASKPASS + sudo -S를 사용해 저장된 비밀번호를 자동 입력할 수 있습니다.
- SSH/sudo 배포 비밀번호는 서버 업로드 직전 설치 파일에서 제거합니다.
- SH/ENV 저장 버튼은 최초 1회 폴더 권한 선택 후 Config Wizard 작업 폴더에 직접 저장합니다.
- ZIP 최상위는 config-wizard.html, run-remote-deploy.cmd만 유지하고 나머지 구성요소는 _internal 아래에 둡니다.
