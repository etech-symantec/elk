ELK OneClick 웹 리포트 로그 포맷 및 주요 설정 파일 조회 기능

변경 파일:
- config-wizard.html
- _internal/core/elk-report.sh

주요 기능:
- MAIN/SSL/Cloud 로그 포맷별 필드 확인
- Elasticsearch/Logstash/Kibana 주요 구성 파일 읽기 전용 보기
- 주요 민감 정보 마스킹, 허용 경로 및 크기 제한

기존 서버는 elk-report.sh를 /usr/local/sbin/elk-report에 반영 후 sudo elk-report 실행하여 HTML 리포트를 갱신하세요.
일부 플러그인의 사용자 정의 비밀 값은 규칙으로 탐지되지 않을 수 있으므로 리포트 접근 제어를 유지하세요.
