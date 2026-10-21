ELK v2.9.89 updater 긴급 수정

수정 원인: 서버 업데이터가 config-wizard.html에서 WIZARD_BUILD를 grep하여 set -e/pipefail로 무음 종료.
또한 Wizard 화면 빌드와 OneClick 설치 빌드는 별개의 값입니다.

GitHub 적용 대상:
  _internal/core/elk-oneclick-update.sh
  assets/wizard-engine.js

config-wizard.html은 참고를 위해 동봉하였으며 원본과 동일합니다(교체 불필요).

기존 서버 긴급 복구:
  먼저 GitHub에 수정된 파일을 커밋한 뒤, 업데이터를 직접 교체하거나 설치 도구로 동기화합니다.
  해당 업데이터가 현재 고장 상태이므로 수정본을 SSH/SCP로 복사하여
  sudo install -m 755 elk-oneclick-update.sh /usr/local/sbin/elk-oneclick-update
  sudo elk-oneclick-update --check
  sudo elk-oneclick-update --apply

--apply는 패키지 재설치/서비스 재시작 없이 변경 런타임 도구만 동기화합니다.
--full은 재설치/재구성이 개입하므로 별도 계획을 세운 뒤 실행하세요.
