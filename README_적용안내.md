# ELK OneClick v2.9.81 · 패치/점검 메뉴 문자 번호 수정

기준: 이전에 제공한 ELK_OneClick_Remote_AutoUpgrade_v2.9.81.zip 내 최신 wizard-engine.js

## GitHub 교체 경로

- assets/wizard-engine.js
- SHA256SUMS.txt

## 변경 사항

패치 페이지 좌측 메뉴 표시 순서: A / B / C / C-1 / C-2 / C-3 / D
점검 페이지 좌측 메뉴: A / B
본문 각 섹션의 번호도 동일하게 수정했습니다.
메뉴 ID, 클릭 이벤트, 하위 아코디언 동작, ELK 업그레이드 CMD 생성 기능은 유지했습니다.

## 적용

ZIP 압축을 풀고 GitHub 저장소 루트에서 위 두 파일을 같은 경로에 덮어쓴 후 커밋하세요.
브라우저 캐시로 이전 값이 보이면 Ctrl+F5로 새로고침하세요.

## 테스트

node --check 문법 검사 및 메뉴 아이템 순서/번호 검증, SHA256 체크섬 검증 수행.
실제 브라우저 UI 클릭 테스트는 별도로 필요합니다.
