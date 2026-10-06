ELK v2.9.5 웹 리포트 자원 구성 통합 업데이트

변경 사항
- 메모리: 전체 RAM을 기준으로 JVM Heap 실제 사용 / 기타 사용 / 사용 가능 메모리를 하나의 구성 도넛으로 표시
- JVM Heap 최대 한도는 참고값으로 별도 표시
- 디스크: 관련 파일시스템을 mount 기준으로 중복 제거 후 ES 데이터 / Logstash 작업 데이터 / 로그·백업 / 기타 사용 / 여유 공간으로 표시
- CPU 원형 게이지 유지
- 전체 점검 상태 / 서비스 상태 클릭 펼치기 유지
- 기존 상세 점검 표 유지

적용
  unzip ELK_v2.9.5_Resource_Composition_Update.zip
  cd elk_resource_composition_update
  sudo bash apply-report-update.sh
