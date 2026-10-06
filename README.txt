ELK v2.9.5 웹 리포트 UI + 프로세스 종료 이력 업데이트

변경 사항
- 메모리/디스크 구성 파이: 항상 전체 자원 100% 기준, 중앙에는 실제 전체 용량 표시
- 세부 구성: 사용 용량 내림차순 정렬 + 퍼센트 막대 표시
- CPU: 메모리/디스크 카드와 같은 원형 크기·카드 높이·하단 구분선
- 전체 점검/서비스 상태: 접힌 상태에서도 이상 항목을 도넛 옆에 상시 표시, 클릭 시 전체 목록 펼침
- 최근 7일 systemd/kernel journal에서 ELK/Nginx/FTP 프로세스 비정상 종료와 OOM 종료를 찾아 날짜·시간·원인 표시
- Configuration Wizard: 모든 버튼에 눌림(press) 효과 추가

기존 서버 적용
  unzip ELK_v2.9.5_Report_UI_ProcessExit_Update.zip
  cd elk_report_ui_process_update
  sudo bash apply-report-update.sh

Config Wizard
- 로컬/웹에 보관한 기존 config-wizard.html을 이 ZIP의 config-wizard.html로 교체하면 버튼 효과와 최신 내장 elk-report가 반영됩니다.
