# ZSTD 디스크 절약 우선 설정

- ZSTD 백업 기본 압축 레벨: 10 → 19 (일반 ZSTD 최고 레벨)
- 압축 흐름: gzip -dc | zstd -19 -T2 (평문 중간 파일 없음)
- ZSTD 스레드 기본값: 2 유지
- 기존 GZ 방식은 변경하지 않음
- 원본과 백업 검증·성공 후 원본 삭제 로직 유지
- 주의: 레벨 19는 CPU, 압축 시간 및 RAM 사용량이 크게 증가할 수 있음. 여유 공간과 메모리, 야간 처리 완료 시각 확인 필요

GitHub 배포 시 config-wizard.html과 _internal/core/proxysg-log-process.sh를 갱신하고, 기존 서버는 도구만 교체해도 elk.env에 PROXYSG_ZSTD_LEVEL이 명시된 경우 그 설정값이 우선 적용됨.
