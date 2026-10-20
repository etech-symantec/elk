# SSL 로그 @timestamp 보정

원인: ProxySG SSL `localtime` 값 `[20/Oct/2026:14:40:00 +0900]`에 맞는 Date filter 패턴이 누락되어 ingest 시각이 @timestamp로 사용됨.

변경: `proxysg-log-filter.conf`의 localtime date matcher에 `[dd/MMM/yyyy:HH:mm:ss Z]`와 `dd/MMM/yyyy:HH:mm:ss Z`, `locale => "en"`을 추가. 기존 ISO8601, YYYY-MM-dd 패턴 및 date+time 처리는 유지.

신규 설치: ZIP 전체를 배포하면 Wizard의 내장 템플릿이 수정된 상태에서 설치 파일이 생성됨.

기존 서버: `_internal/core/proxysg-log-filter.conf`를 서버에 복사한 후 `apply-proxysg-timestamp-fix.sh`를 같은 폴더에서 sudo로 실행. 이후 PQ/DLQ 충돌 방지 수정된 `elk-patch`로 SSL 로그 포맷 설정을 동일한 값으로 다시 적용해 실제 Logstash pipeline을 재생성. 필요 시 `sudo grep '^PROXYSG_SSL_LOG_FORMAT=' /etc/elk-auto/elk.env`로 전체 포맷 확인. 서비스 상태와 Kibana 신규 문서 @timestamp를 확인.

중요: 이미 Elasticsearch에 저장된 과거 문서의 @timestamp는 자동 변경되지 않음. 기존 PQ/DLQ 디렉터리나 .lock 파일 삭제 금지.
