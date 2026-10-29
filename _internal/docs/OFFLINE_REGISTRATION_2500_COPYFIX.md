# ELK OneClick Wizard — 오프라인 등록 명령 UI 개선

수정 파일: `assets/wizard-engine.js` (ZIP 전체 교체 파일)

- 1,800자 안내를 명령 전체 길이 2,500자로 변경. Base64 청크는 `printf | sudo tee` 등 명령어 오버헤드를 뺀 길이로 계산합니다.
- 파일 11개별 용도 설명과 접이식 요약, 가로 그리드 명령 버튼.
- 복사 성공 시 60초 동안 녹색 강조(같은 버튼 재복사 시 타이머 갱신).
- `/root/elk-adopt`에 `sudo tee`로 쓰고, `sudo sha256sum -c`로 검증합니다. 복원 후 `sudo install -m 755` (conf는 644)로 배치하여 일반 사용자 접근권한 문제 해결.
- 가능한 브라우저에서는 gzip 압축 후 base64로 생성하여 조각 개수를 줄입니다.
- 파일 다운로드 HTTP 오류 시 파일별 오류 메시지를 표시하고 해당 항목의 명령은 만들지 않습니다.

## 적용
1. GitHub 저장소의 `assets/wizard-engine.js`를 ZIP 내 파일로 교체 후 커밋합니다.
2. 웹페이지를 강력 새로고침(Ctrl+Shift+R)합니다.
3. 패치 → 기존 ELK 서버 OneClick 관리 등록 → OFFLINE REGISTRATION → GitHub 최신 파일 불러오기 실행.
4. 각 파일을 펼쳐서 `준비 → 전송 1/N ... → 복원·검증·권한` 순서대로 붙여넣습니다.

주의: 모든 명령은 인터넷에 연결된 브라우저에서 생성되며 Ubuntu 서버에는 GitHub 연결이 필요 없습니다. 클립보드가 HTTPS 컨텍스트에서 지원되어야 자동 복사가 됩니다. 실제 서버 통합 테스트는 수행되지 않았습니다.
