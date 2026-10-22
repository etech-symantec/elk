# ELK Stack Upgrade 터미널 UI 재스타일링

교체 경로: `_internal/core/elk-stack-upgrade.sh`

원본의 `--check`, `--plan VERSION`, `--upgrade VERSION`, `latest`, `--yes`, `--refresh`, 동일 메이저 제한 로직을 유지하고 출력 표시만 재구성했습니다.

- 섹션 번호 / 구분선 / 헤더 / 상태별 색상
- INFO(파랑), OK(초록), WARN(노랑), ERROR(빨강)
- 일반 로그/리다이렉션 출력에는 ANSI 컬러 코드 자동 생략
- 강제 컬러: `sudo env ELK_UPGRADE_COLOR=always elk-stack-upgrade --check`
- 컬러 생략: `sudo env ELK_UPGRADE_COLOR=never elk-stack-upgrade --check`

**주의**: 이번 수정은 출력 UI 변경만입니다. 현재 원본이 패키지 업그레이드 이후 서비스 재시작과 API/실행 버전까지 보장하지 않는 점은 그대로입니다. 운영 업그레이드 전 기존 안전 재시작 기능이 포함된 스크립트와 병합하는 것이 좋습니다. 원격 설치 전 `bash -n`으로 검사하세요.
