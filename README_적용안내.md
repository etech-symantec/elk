# ELK OneClick Stack Upgrade v2.9.81.5

## 교체 경로
GitHub 저장소의 `_internal/core/elk-stack-upgrade.sh` 파일을 ZIP 안의 동일 경로 파일로 **전체 교체**하세요.

서버에서 업데이트: `sudo elk-oneclick-update --apply`

### 지금 설치 9.5.4 / 실행 9.5.2 불일치 복구
`sudo elk-stack-upgrade --reconcile`

- 설치된 Elasticsearch 버전과 실제 JVM의 버전 표시를 비교합니다.
- 다르면 Elasticsearch 서비스의 정상적인 `systemctl restart --no-block`을 요청하며, 최대 180초 동안 실제 프로세스 버전이 맞는지 확인합니다.
- 사용자의 `RESTART` 입력이 필요합니다. 무인 실행은 `--reconcile --yes`를 사용합니다.
- 이 작업은 패키지를 재설치하지 않고 Elasticsearch 서비스만 재시작합니다.
- Elasticsearch 재시작으로 검색/색인에 일시적 영향이 있으므로 유지보수 시간에 실행하세요.

### 다음 버전 업그레이드
`sudo elk-stack-upgrade --plan 9.5.5`
`sudo elk-stack-upgrade --upgrade 9.5.5`

- Elasticsearch를 패키지 교체 후 실제 JVM 버전과 비교하고, 실행 버전 불일치 시 재시작합니다.
- Kibana Keystore 자동 접근 권한 복구 및 Logstash 제한시간 종료 보호 유지.
- 터미널에서는 컬러 출력, 비TTY에서는 ANSI 색상 제거.

### 검증
`sudo systemctl status elasticsearch --no-pager`
`curl -k -sS -o /dev/null -w '%{http_code}\n' https://127.0.0.1:9200/` (보안 활성화 환경에서는 401도 정상 연결 응답)
`sudo elk-stack-upgrade --check`

주의: 실제 실행 버전은 `/proc` 내 Elasticsearch Java 실행 인자의 버전별 jar 이름을 기반으로 확인합니다. JVM 실행 인자 형식이 변경된 배포판에서는 버전 탐지가 실패할 수 있으며 그 경우 자동 완료 처리하지 않습니다.
