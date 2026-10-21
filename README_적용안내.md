# ELK 업그레이드 오류 수정 및 웹 명령어 복사 전용 UI

## GitHub 교체 대상
- `_internal/core/elk-stack-upgrade.sh` : 최신 설치 스크립트, Debian epoch/릴리스와 메이저 버전 개별 검증, --plan latest 지원, 진단용 도구 버전 출력
- `assets/wizard-engine.js` : 패치 화면 D 메뉴의 CMD/.sh 다운로드 버튼 제거. 서버 명령 복사 4종 제공. 기존 C-1~C-3 메뉴 유지
- `SHA256SUMS.txt` : 위 두 파일의 체크섬 갱신, 다른 항목은 그대로 유지

## Ubuntu에서 동기화 후 실행
```bash
sudo elk-oneclick-update --check
sudo elk-oneclick-update --apply
sudo elk-stack-upgrade --check
sudo elk-stack-upgrade --plan 9.5.5
sudo elk-stack-upgrade --upgrade 9.5.5
```

- `sudo bash ~/elk-stack-upgrade.sh`는 홈 디렉터리의 이전 파일을 실행할 수 있습니다. 앞으로는 설치된 `sudo elk-stack-upgrade`를 사용하세요.
- `--plan latest`를 사용하면 APT 최신 후보를 조회하지만, 메이저 버전이 다르거나 제품별 후보가 일치하지 않으면 차단됩니다.
- `--upgrade` 실행은 서비스에 영향을 줄 수 있으며 스냅샷/백업 후 작업해야 합니다. 기본은 `UPGRADE` 사용자 확인입니다.
- Config Wizard의 '전체 ZIP'에 포함되는 원격 업그레이드 CMD는 기존 호환성을 위해 보존했고, 패치 화면에서 직접 내려받는 기능만 제거했습니다.
- 실제 Ubuntu 업그레이드 실행은 하지 않았고 모의 테스트 및 구문 검사를 수행했습니다.
