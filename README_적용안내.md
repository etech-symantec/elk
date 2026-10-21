# ELK 업그레이드 진단·오류 메시지 개선 (v2.9.81.2)

## 포함된 전체 교체 파일
- `_internal/core/elk-stack-upgrade.sh`
- `SHA256SUMS.txt`

GitHub 저장소의 같은 경로로 교체하고 커밋하세요. `sudo elk-oneclick-update --apply`로 동기화한 후 `sudo elk-stack-upgrade --plan 9.5.5`로 먼저 점검하세요. GitHub 동기화에 실패했다면 서버의 실제 실행 파일이 예전 버전일 수 있으니 `sudo grep TOOL_VERSION /usr/local/sbin/elk-stack-upgrade`로 확인하세요.

## 변경 내용
- 패키지 검색 시작/패키지별 선택 버전/조회 완료 로그 표시
- `apt-cache madison` 오류가 `set -e`에 묻혀 무출력 종료하는 경우 원인 표시
- 목표 버전이 APT 저장소에 없는 경우 조회 가능한 일부 버전과 안내 표시
- 예기치 않은 셸 오류의 라인과 종료 코드 표시
- 기존 메이저 버전/epoch 판별, 다운그레이드 차단, 백업, UPGRADE 확인/--yes, Ubuntu OS 비변경 유지

## 실제 운영 순서
1. `sudo elk-oneclick-update --apply`
2. `sudo elk-stack-upgrade --plan 9.5.5`
3. `sudo elk-stack-upgrade --upgrade 9.5.5` (스냅샷과 점검 시간 확보 후)

스크린샷의 명령은 종료 프롬프트가 보이지 않아, 조회 중 지연인지 오류 종료인지 구분되지 않습니다. 실제 서버에서 `apt-cache madison elasticsearch` 등의 실행 결과를 확인해야 원인을 확정할 수 있습니다.
