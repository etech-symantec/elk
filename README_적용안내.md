# ELK OneClick v2.9.91 업데이트 무출력 종료 수정

GitHub 저장소 etech-symantec/elk에 다음 두 파일을 **전체 교체**합니다.

- `_internal/core/elk-oneclick-update.sh`
- `assets/wizard-engine.js`

원인: 업데이트 스크립트가 config-wizard.html에서 WIZARD_BUILD를 grep으로 조회했으나, 최신 HTML에는 해당 상수가 없고 `set -Eeuo pipefail` 때문에 fallback 이전에 종료됨.

수정: assets/wizard-engine.js의 ONECLICK_PAYLOAD_BUILD를 조회하며, 네트워크/패턴 추출 실패는 경고 후 unknown으로 처리하고 GitHub blob SHA 비교를 계속함. Wizard에 포함된 Base64 업데이터도 똑같이 갱신함.

기존 CLI 옵션 및 delta-only 비교 로직은 그대로 유지됩니다.

## 이미 설치된 서버에서 복구

GitHub 커밋 후:

```bash
sudo curl -fL --retry 3 https://raw.githubusercontent.com/etech-symantec/elk/main/_internal/core/elk-oneclick-update.sh -o /tmp/elk-oneclick-update.sh
bash -n /tmp/elk-oneclick-update.sh
sudo cp -a /usr/local/sbin/elk-oneclick-update /usr/local/sbin/elk-oneclick-update.bak
sudo install -m 755 /tmp/elk-oneclick-update.sh /usr/local/sbin/elk-oneclick-update
sudo elk-oneclick-update --check
```

--check는 변경된 파일이 있으면 exit 10을 돌려줄 수 있으므로, 마지막에 `echo $?`도 확인하세요. 업그레이드 적용에는 `sudo elk-oneclick-update --apply`를 실행합니다.

테스트: `bash -n`, `node --check`, Base64 내장 업데이터 바이트 일치, mock curl API check 실행. 실제 운영 서버 배포/원격 GitHub 호출은 미실행.
