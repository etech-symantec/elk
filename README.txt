ELK v2.9.5 웹 리포트 실제 사용률 파이 수정

변경사항
- 메모리/디스크 파이는 전체 용량 100% 기준
- 실제 사용률까지만 세부 사용 항목 색상으로 누적 표시
- 남은 메모리/디스크는 회색 영역으로 표시
- 세부 사용 항목은 사용량 내림차순 + 퍼센트 막대
- 전체 점검 상태/서비스 상태 카드 높이를 더 긴 카드에 맞춤
- 기존 프로세스 종료 이력 및 Config Wizard 버튼 눌림 효과 유지

기존 서버 적용
  unzip ELK_v2.9.5_Actual_Usage_Pie_Update.zip
  cd elk_actual_usage_pie_update
  sudo bash apply-report-update.sh
