# ELK OneClick Wizard — 3개 페이지 / 공통 리소스 분리

- `config-wizard.html`: 빠른 설정 및 고급 설정 (상단 탭으로 전환, URL #advanced)
- `patch.html`: 기존 서버 패치
- `inspect.html`: 서버 점검
- `assets/wizard.css`: 공통 스타일
- `assets/wizard-engine.js`: 공통 Wizard 엔진 + 기존 내장 배포 리소스
- `assets/adopt.js`: 기존 서버 등록 기능
- `assets/menu-tour.js`: 메뉴 안내
- `_internal/core/`: 기존 리포트 / 패치 도구 유지

기존 repo의 `config-wizard.html` 대신 새 HTML 3개와 `assets/` 폴더를 **같은 레벨에 업로드**하세요. 웹 서버 또는 GitHub Pages에서 `config-wizard.html`, `patch.html`, `inspect.html`로 접근하면 됩니다.

상단 메뉴를 클릭하면 페이지 주소는 이동하지만 브라우저 문서를 다시 로드하지 않으므로 **입력 중인 값이 보존**됩니다. 브라우저에서 직접 다른 페이지 주소를 열거나 새로고침하면 기존 단일 파일과 마찬가지로 미저장 값이 초기화됩니다. HTML만 따로 배포하면 안 되고 assets 폴더가 반드시 필요합니다.

주의: 내장 설치/점검/패치 기능을 안전하게 유지하기 위해 공통 엔진을 별도 파일로 분리하였으며 모듈 별 실행 코드 자체를 완전히 분리하지는 않았습니다. 웹 리포트의 설정 파일 조회 시 민감정보 노출을 주의하세요.
