/* =====================================================================
 *  ELK Config Wizard - 기본값 파일 (관리자용)
 *
 *  이 파일에서 Config Wizard를 처음 열었을 때 입력칸에 채워지는 "초기값"을 정합니다.
 *  고친 뒤 저장(커밋)하고 Wizard를 새로고침하면 바로 반영됩니다. (별도 빌드/명령 필요 없음)
 *
 *  편집 방법
 *   - 값은 따옴표 안의 글자만 고칩니다.        예)  LOGSTASH_PIPELINE_FILE: "/etc/logstash/conf.d/20-proxy.conf",
 *   - true / false 항목은 따옴표 없이 true 또는 false 로 씁니다.
 *   - 줄 끝의 쉼표(,)와 따옴표("")는 지우지 마세요. 값 안에 " 나 \ 가 필요하면 \" , \\ 로 씁니다.
 *   - 줄 끝의 // 뒤는 설명(주석)이라 지워도 됩니다. 항목을 지우면 Wizard 내장 기본값이 쓰입니다.
 *   - 각 묶음 제목의 "고급 설정 N단계"는 Wizard 왼쪽 메뉴(고급 설정)의 번호입니다.
 *
 *  제한 사항
 *   - 비밀번호·암호화 키 항목은 여기서 지정할 수 없습니다. (저장소에 그대로 노출되기 때문)
 *   - 잘못된 항목 이름, true/false가 아닌 값, 선택 목록에 없는 값은 무시되고
 *     Wizard 화면 위쪽에 경고가 표시됩니다.
 *   - 이 값은 Wizard가 채워 주는 초기값입니다. 설치기(install-elk.sh)의 ": ${KEY:=값}" 줄은
 *     elk.env에 값이 없을 때만 쓰는 예비값이며 이 파일과 별개입니다.
 * ===================================================================== */

window.ELK_DEFAULTS = {
  values: {

    // ───── 고급 설정 1단계 · 설치 제어 ─────
    INSTALL_ELASTICSEARCH: true,                              // Install Elasticsearch  [true | false]
    INSTALL_KIBANA: true,                                     // Install Kibana  [true | false]
    INSTALL_LOGSTASH: true,                                   // Install Logstash  [true | false]
    ELASTIC_MAJOR: "9.x",                                     // Elastic 저장소 버전  [9.x]
    ELASTIC_VERSION: "",                                      // 정확한 Elastic 버전
    APT_REPOSITORY_URL: "https://artifacts.elastic.co/packages",  // Elastic APT 저장소
    APT_GPG_KEY_URL: "https://artifacts.elastic.co/GPG-KEY-elasticsearch",  // Elastic GPG Key URL
    APT_PROXY: "",                                            // Apt Proxy
    HTTP_PROXY: "",                                           // Http Proxy
    HTTPS_PROXY: "",                                          // Https Proxy
    NO_PROXY: "127.0.0.1,localhost",                          // No Proxy

    // ───── 고급 설정 2단계 · OS 기본 설정 ─────
    SET_HOSTNAME: false,                                      // Set Hostname  [true | false]
    SYSTEM_HOSTNAME: "elk01",                                 // System Hostname
    TIMEZONE: "Asia/Seoul",                                   // Timezone
    ENABLE_NTP: true,                                         // Enable Ntp  [true | false]
    DISABLE_SWAP: true,                                       // Disable Swap  [true | false]
    VM_MAX_MAP_COUNT: "1048576",                              // Vm Max Map Count
    SYSTEM_SWAPPINESS: "1",                                   // System Swappiness
    INSTALL_LOG: "/var/log/elk-auto-install.log",             // Install Log
    STATE_DIR: "/root/.elk-auto-installer",                   // State Dir
    SECRETS_FILE: "/root/.elk-auto-installer/secrets.env",    // Secrets File
    BACKUP_DIR: "/root/.elk-auto-installer/backups",          // Backup Dir

    // ───── 고급 설정 3단계 · Elasticsearch 기본 ─────
    ES_CLUSTER_NAME: "elk-cluster",                           // Es Cluster Name
    ES_NODE_NAME: "elk01",                                    // Es Node Name
    ES_NETWORK_HOST: "0.0.0.0",                               // Elasticsearch Listen 주소
    ES_HTTP_PORT: "9200",                                     // Elasticsearch HTTPS 포트
    ES_TRANSPORT_PORT: "9300",                                // Es Transport Port
    ES_ACTION_DESTRUCTIVE_REQUIRES_NAME: false,               // Wildcard 파괴 작업 허용  [true | false]
    ES_PATH_DATA: "/var/lib/elasticsearch",                   // Elasticsearch 데이터 저장 경로
    ES_PATH_LOGS: "/var/log/elasticsearch",                   // Elasticsearch 서비스 로그 경로
    ES_DISCOVERY_MODE: "single-node",                         // Es Discovery Mode  [single-node | multi-node]
    ES_DISCOVERY_SEED_HOSTS: "",                              // Es Discovery Seed Hosts
    ES_CLUSTER_INITIAL_MASTER_NODES: "",                      // Es Cluster Initial Master Nodes
    ES_SECURITY_ENABLED: true,                                // Es Security Enabled  [true | false]
    ES_ENROLLMENT_ENABLED: true,                              // Es Enrollment Enabled  [true | false]
    ES_HTTP_TLS_ENABLED: true,                                // Es Http Tls Enabled  [true | false]
    ES_TRANSPORT_TLS_ENABLED: true,                           // Es Transport Tls Enabled  [true | false]
    ELASTIC_USERNAME: "elastic",                              // Elasticsearch 관리자 ID
    ES_HEAP_MODE: "auto",                                     // Elasticsearch Heap 방식  [auto | fixed]
    ES_HEAP_MIN: "16g",                                       // Elasticsearch Xms
    ES_HEAP_MAX: "16g",                                       // Elasticsearch Xmx
    ES_BOOTSTRAP_MEMORY_LOCK: false,                          // Es Bootstrap Memory Lock  [true | false]
    ES_LIMIT_NOFILE: "65535",                                 // Es Limit Nofile
    ES_LIMIT_NPROC: "4096",                                   // Es Limit Nproc
    ES_EXTRA_CONFIG_FILE: "",                                 // Es Extra Config File

    // ───── 고급 설정 4단계 · Elasticsearch 디스크 보호 설정 ─────
    ES_DISK_WATERMARK_LOW: "85%",                             // Es Disk Watermark Low
    ES_DISK_WATERMARK_HIGH: "90%",                            // Es Disk Watermark High
    ES_DISK_WATERMARK_FLOOD_STAGE: "95%",                     // Es Disk Watermark Flood Stage
    ES_CLUSTER_INFO_UPDATE_INTERVAL: "30s",                   // Es Cluster Info Update Interval

    // ───── 고급 설정 5단계 · Kibana ─────
    KIBANA_SERVER_NAME: "elk-kibana",                         // Kibana Server Name
    KIBANA_SERVER_HOST: "0.0.0.0",                            // Kibana Listen 주소
    KIBANA_SERVER_PORT: "5601",                               // Kibana 포트
    KIBANA_LOGIN_ENABLED: true,                               // Kibana 로그인 사용  [true | false]
    KIBANA_SESSION_IDLE_TIMEOUT: "",                          // 로그인 세션 유휴 만료
    KIBANA_PUBLIC_BASE_URL: "",                               // Kibana Public Base Url
    KIBANA_ES_HOST: "",                                       // Kibana Es Host
    KIBANA_ES_SSL_VERIFICATION_MODE: "full",                  // Kibana Es Ssl Verification Mode  [full | certificate | none]
    KIBANA_SERVICE_TOKEN_NAME: "elk-auto-kibana",             // Kibana Service Token Name
    KIBANA_LOG_LEVEL: "info",                                 // Kibana Log Level
    KIBANA_CREATE_DATA_VIEW: true,                            // Kibana Create Data View  [true | false]
    KIBANA_DATA_VIEW_NAME: "ELK Logs",                        // Kibana Data View Name
    KIBANA_DATA_VIEW_TIME_FIELD: "@timestamp",                // Kibana Data View Time Field
    KIBANA_DATA_VIEW_ALLOW_NO_INDEX: true,                    // Kibana Data View Allow No Index  [true | false]
    KIBANA_CREATE_INITIAL_USER: false,                        // 초기 사용자 자동 생성  [true | false]
    KIBANA_INITIAL_USER_NAME: "",                             // 초기 사용자 ID
    KIBANA_INITIAL_USER_ROLES: "viewer",                      // 초기 사용자 Role  [viewer | editor | kibana_admin | superuser]
    KIBANA_EXTRA_CONFIG_FILE: "",                             // Kibana 추가 설정 파일 경로

    // ───── 고급 설정 6단계 · Nginx HTTPS (선택) ─────
    INSTALL_NGINX: false,                                     // Nginx HTTPS 사용  [true | false]
    NGINX_SERVER_NAME: "_",                                   // Nginx Server Name
    NGINX_HTTP_PORT: "80",                                    // Nginx HTTP 포트
    NGINX_HTTPS_PORT: "443",                                  // Nginx HTTPS 포트
    NGINX_REDIRECT_HTTP_TO_HTTPS: true,                       // HTTP → HTTPS Redirect  [true | false]
    NGINX_DISABLE_DEFAULT_SITE: true,                         // Nginx Disable Default Site  [true | false]
    NGINX_PROXY_HOST: "127.0.0.1",                            // Nginx Proxy Host
    NGINX_PROXY_PORT: "",                                     // Nginx Proxy Port
    NGINX_CLIENT_MAX_BODY_SIZE: "100m",                       // Nginx Client Max Body Size
    NGINX_TLS_MODE: "selfsigned",                             // Nginx 인증서 방식  [selfsigned | existing]
    NGINX_TLS_CERT_FILE: "/etc/ssl/certs/kibana-selfsigned.crt",  // Nginx Tls Cert File
    NGINX_TLS_KEY_FILE: "/etc/ssl/private/kibana-selfsigned.key",  // Nginx Tls Key File
    NGINX_TLS_CN: "",                                         // 인증서 CN / SAN
    NGINX_TLS_DAYS: "3650",                                   // Self-Signed 유효기간
    NGINX_TLS_PROTOCOLS: "TLSv1.2 TLSv1.3",                   // Nginx Tls Protocols
    NGINX_TLS_CIPHERS: "HIGH:!aNULL:!MD5",                    // Nginx Tls Ciphers

    // ───── 고급 설정 7단계 · Logstash 기본 ─────
    LOGSTASH_NODE_NAME: "elk-logstash",                       // Logstash Node Name
    LOGSTASH_PATH_DATA: "/var/lib/logstash",                  // Logstash Path Data
    LOGSTASH_PATH_LOGS: "/var/log/logstash",                  // Logstash Path Logs
    LOGSTASH_PIPELINE_ID: "main",                             // Logstash Pipeline Id
    LOGSTASH_PIPELINE_FILE: "/etc/logstash/conf.d/logstash.conf",  // Logstash 파이프라인 설정 파일(.conf) 경로
    LOGSTASH_PROFILE: "proxysg",                        // Logstash Pipeline 프로필  [generic | proxysg]
    LOGSTASH_HEAP_MIN: "2g",                                  // Logstash Xms
    LOGSTASH_HEAP_MAX: "2g",                                  // Logstash Xmx
    LOGSTASH_PIPELINE_WORKERS: "0",                           // Logstash Pipeline Workers
    LOGSTASH_PIPELINE_BATCH_SIZE: "125",                      // Logstash Pipeline Batch Size
    LOGSTASH_PIPELINE_BATCH_DELAY: "50",                      // Logstash Pipeline Batch Delay
    LOGSTASH_CONFIG_RELOAD_AUTOMATIC: true,                   // Logstash Config Reload Automatic  [true | false]
    LOGSTASH_CONFIG_RELOAD_INTERVAL: "3s",                    // Logstash Config Reload Interval
    LOGSTASH_QUEUE_TYPE: "persisted",                         // Logstash Queue Type
    LOGSTASH_QUEUE_MAX_BYTES: "4gb",                          // Logstash Queue Max Bytes
    LOGSTASH_QUEUE_PAGE_CAPACITY: "64mb",                     // Logstash Queue Page Capacity
    LOGSTASH_QUEUE_DRAIN: false,                              // Logstash Queue Drain  [true | false]
    LOGSTASH_DEAD_LETTER_QUEUE: true,                         // Logstash Dead Letter Queue  [true | false]
    LOGSTASH_DLQ_MAX_BYTES: "1gb",                            // Logstash Dlq Max Bytes
    LOGSTASH_API_ENABLED: true,                               // Logstash Api Enabled  [true | false]
    LOGSTASH_API_HOST: "127.0.0.1",                           // Logstash Api Host
    LOGSTASH_API_PORT: "9600",                                // Logstash Api Port
    LOGSTASH_ES_USERNAME: "logstash_internal",                // Logstash Elasticsearch 계정
    LOGSTASH_ES_ROLE: "logstash_writer",                      // Logstash Es Role
    LOGSTASH_ES_HOST: "",                                     // Logstash Es Host
    LOGSTASH_EXTRA_CONFIG_FILE: "",                           // Logstash 추가 설정 파일 경로 (logstash.yml)

    // ───── 고급 설정 8단계 · Logstash Input - TCP ─────
    LS_TCP_ENABLED: false,                                    // Ls Tcp Enabled  [true | false]
    LS_TCP_HOST: "0.0.0.0",                                   // Ls Tcp Host
    LS_TCP_PORT: "5514",                                      // Ls Tcp Port
    LS_TCP_CODEC: "plain",                                    // Ls Tcp Codec  [plain | json | json_lines]

    // ───── 고급 설정 9단계 · Logstash Input - UDP ─────
    LS_UDP_ENABLED: false,                                    // Ls Udp Enabled  [true | false]
    LS_UDP_HOST: "0.0.0.0",                                   // Ls Udp Host
    LS_UDP_PORT: "5514",                                      // Ls Udp Port
    LS_UDP_CODEC: "plain",                                    // Ls Udp Codec  [plain | json | json_lines]

    // ───── 고급 설정 10단계 · Logstash Input - Syslog ─────
    LS_SYSLOG_ENABLED: false,                                 // Ls Syslog Enabled  [true | false]
    LS_SYSLOG_HOST: "0.0.0.0",                                // Ls Syslog Host
    LS_SYSLOG_PORT: "5515",                                   // Ls Syslog Port

    // ───── 고급 설정 11단계 · Logstash Input - Beats ─────
    LS_BEATS_ENABLED: false,                                  // Ls Beats Enabled  [true | false]
    LS_BEATS_HOST: "0.0.0.0",                                 // Ls Beats Host
    LS_BEATS_PORT: "5044",                                    // Ls Beats Port

    // ───── 고급 설정 12단계 · Logstash Input - HTTP ─────
    LS_HTTP_ENABLED: false,                                   // Ls Http Enabled  [true | false]
    LS_HTTP_HOST: "0.0.0.0",                                  // Ls Http Host
    LS_HTTP_PORT: "8080",                                     // Ls Http Port
    LS_HTTP_CODEC: "json",                                    // Ls Http Codec  [plain | json | json_lines]

    // ───── 고급 설정 13단계 · Logstash Input - File ─────
    LS_FILE_ENABLED: false,                                   // Ls File Enabled  [true | false]
    LS_FILE_PATHS: "/data/logs/*.log",                        // Ls File Paths
    LS_FILE_EXCLUDE: "*.gz,*.zip,*.xz,*.zst",                 // Ls File Exclude
    LS_FILE_MODE: "tail",                                     // Ls File Mode  [tail | read]
    LS_FILE_START_POSITION: "beginning",                      // Ls File Start Position  [beginning | end]
    LS_FILE_SINCEDB_PATH: "/var/lib/logstash/.sincedb-main",  // Ls File Sincedb Path
    LS_FILE_CODEC: "plain",                                   // Ls File Codec
    LS_FILE_IGNORE_OLDER: "",                                 // Ls File Ignore Older
    LS_FILE_CLOSE_OLDER: "5m",                                // Ls File Close Older
    LS_FILE_COMPLETED_ACTION: "log",                          // Ls File Completed Action  [delete | log | log_and_delete]
    LS_FILE_COMPLETED_LOG_PATH: "/var/log/logstash/completed-files.log",  // Ls File Completed Log Path

    // ───── 고급 설정 14단계 · Logstash Filter ─────
    LS_PARSE_JSON_MESSAGE: false,                             // Ls Parse Json Message  [true | false]
    LS_JSON_SOURCE_FIELD: "message",                          // Ls Json Source Field
    LS_JSON_TARGET_FIELD: "",                                 // Ls Json Target Field
    LS_DATE_SOURCE_FIELD: "",                                 // Ls Date Source Field
    LS_DATE_MATCH: "",                                        // Ls Date Match
    LS_DATE_TARGET_FIELD: "@timestamp",                       // Ls Date Target Field
    LS_DATE_TIMEZONE: "Asia/Seoul",                           // Ls Date Timezone
    LS_DROP_EMPTY_MESSAGE: false,                             // Ls Drop Empty Message  [true | false]
    LS_CUSTOM_FILTER_FILE: "",                                // Ls Custom Filter File
    LS_STDOUT_DEBUG: false,                                   // Ls Stdout Debug  [true | false]

    // ───── 고급 설정 15단계 · FTP 서버 (vsftpd) ─────
    INSTALL_FTP_SERVER: true,                                 // Install Ftp Server  [true | false]
    FTP_PACKAGE: "vsftpd",                                    // Ftp Package
    FTP_LISTEN_ADDRESS: "0.0.0.0",                            // Ftp Listen Address
    FTP_LISTEN_PORT: "21",                                    // Ftp Listen Port
    FTP_USER: "elkftp",                                       // FTP 계정
    FTP_GROUP: "elkftp",                                      // Ftp Group
    FTP_USER_SHELL: "/usr/sbin/nologin",                      // Ftp User Shell
    FTP_ROOT_DIR: "/home/elkftp",                             // FTP 루트 경로
    FTP_UPLOAD_DIR: "/home/main",                             // FTP 기본 업로드 경로
    FTP_ROOT_MODE: "0755",                                    // Ftp Root Mode
    FTP_UPLOAD_MODE: "2770",                                  // Ftp Upload Mode
    FTP_LOCAL_UMASK: "0007",                                  // Ftp Local Umask
    FTP_CHROOT_LOCAL_USER: false,                             // FTP Chroot  [true | false]
    FTP_ALLOW_WRITEABLE_CHROOT: false,                        // Ftp Allow Writeable Chroot  [true | false]
    FTP_ALLOW_ANONYMOUS: false,                               // Ftp Allow Anonymous  [true | false]
    FTP_DOWNLOAD_ENABLE: true,                                // Ftp Download Enable  [true | false]
    FTP_BANNER: "ELK Log Upload FTP",                         // Ftp Banner
    FTP_ACTIVE_ENABLE: true,                                  // Active FTP 허용  [true | false]
    FTP_CONNECT_FROM_PORT_20: true,                           // FTP 데이터 Port 20 사용  [true | false]
    FTP_PASV_ENABLE: false,                                   // Passive FTP 사용  [true | false]
    FTP_PASV_MIN_PORT: "40000",                               // Ftp Pasv Min Port
    FTP_PASV_MAX_PORT: "40100",                               // Ftp Pasv Max Port
    FTP_PASV_ADDRESS: "",                                     // Ftp Pasv Address
    FTP_MAX_CLIENTS: "20",                                    // Ftp Max Clients
    FTP_MAX_PER_IP: "5",                                      // Ftp Max Per Ip
    FTP_IDLE_SESSION_TIMEOUT: "600",                          // Ftp Idle Session Timeout
    FTP_DATA_CONNECTION_TIMEOUT: "120",                       // Ftp Data Connection Timeout
    FTP_LOG_FILE: "/var/log/vsftpd.log",                      // Ftp Log File
    FTP_TLS_ENABLED: false,                                   // FTP TLS(FTPS)  [true | false]
    FTP_TLS_FORCE: true,                                      // Ftp Tls Force  [true | false]
    FTP_TLS_CERT_FILE: "/etc/ssl/certs/elk-vsftpd.crt",       // Ftp Tls Cert File
    FTP_TLS_KEY_FILE: "/etc/ssl/private/elk-vsftpd.key",      // Ftp Tls Key File
    FTP_TLS_CN: "",                                           // Ftp Tls Cn
    FTP_TLS_DAYS: "3650",                                     // Ftp Tls Days
    FTP_TLS_REQUIRE_REUSE: false,                             // Ftp Tls Require Reuse  [true | false]
    FTP_INTEGRATE_FILE_INGEST: false,                         // Ftp Integrate File Ingest  [true | false]

    // ───── 고급 설정 16단계 · ProxySG MAIN/SSL 파일 흐름 ─────
    PROXYSG_FLOW_ENABLED: true,                           // ProxySG MAIN/SSL 흐름 사용  [true | false]
    PROXYSG_MAIN_SOURCE_DIR: "/home/main",                      // MAIN FTP 수신 폴더
    PROXYSG_SSL_SOURCE_DIR: "/home/ssl",                        // SSL FTP 수신 폴더
    PROXYSG_MAIN_BACKUP_DIR: "/home/main_backup",               // MAIN 원본 백업 폴더
    PROXYSG_SSL_BACKUP_DIR: "/home/ssl_backup",                 // SSL 원본 백업 폴더
    PROXYSG_MAIN_PROCESS_DIR: "/home/main_process",             // MAIN Logstash 처리 폴더
    PROXYSG_SSL_PROCESS_DIR: "/home/ssl_process",               // SSL Logstash 처리 폴더
    PROXYSG_FILE_GLOB: "*.log.gz",                              // ProxySG File Glob
    PROXYSG_DIR_MODE: "0775",                                   // ProxySG Dir Mode
    PROXYSG_PROCESS_SCRIPT: "/usr/local/sbin/elk-proxysg-log-process",  // ProxySG Process Script
    PROXYSG_PROCESS_LOG: "/var/log/elk-proxysg-log-process.log",  // ProxySG Process Log
    PROXYSG_PROCESS_CRON: "0 3 * * *",                          // 파일 처리 실행 시간
    PROXYSG_MAIN_SINCEDB: "/var/lib/logstash/sincedb-main",     // ProxySG Main Sincedb
    PROXYSG_SSL_SINCEDB: "/var/lib/logstash/sincedb-ssl",       // ProxySG Ssl Sincedb
    PROXYSG_LOGSTASH_DISCOVER_INTERVAL: "5",                    // ProxySG Logstash Discover Interval
    PROXYSG_LOGSTASH_MAX_OPEN_FILES: "1000",                    // ProxySG Logstash Max Open Files
    PROXYSG_CSV_FILTER_ENABLED: true,                     // ProxySG CSV 파싱  [true | false]
    PROXYSG_MAIN_LOG_FORMAT: "date time time-taken c-ip cs-username cs-auth-group s-supplier-name s-supplier-ip s-supplier-country s-supplier-failures x-exception-id sc-filter-result cs-categories cs(Referer)  sc-status s-action cs-method rs(Content-Type) cs-uri-scheme cs-host cs-uri-port cs-uri-path cs-uri-query cs-uri-extension cs(User-Agent) s-ip sc-bytes cs-bytes x-virus-id cs-threat-source cs-threat-id rs-threat-source rs-threat-id x-bluecoat-application-name x-bluecoat-application-operation x-bluecoat-application-groups cs-threat-risk x-bluecoat-access-security-policy-action x-bluecoat-access-security-policy-reason x-bluecoat-transaction-uuid x-icap-reqmod-header(X-ICAP-Metadata) x-icap-respmod-header(X-ICAP-Metadata)",  // MAIN 로그 포맷 (ELFF 필드 순서)
    PROXYSG_SSL_LOG_FORMAT: "date time time-taken c-ip cs-username cs-auth-group s-supplier-name s-supplier-ip s-supplier-country s-supplier-failures x-exception-id sc-filter-result cs-categories sc-status s-action cs-method rs(Content-Type) cs-uri-scheme cs-host cs-uri-port cs-uri-extension cs(User-Agent) s-ip sc-bytes cs-bytes x-virus-id cs-threat-source cs-threat-id rs-threat-source rs-threat-id x-rs-certificate-observed-errors x-cs-ocsp-error x-rs-ocsp-error x-rs-connection-negotiated-cipher-strength x-rs-certificate-hostname x-rs-certificate-hostname-category cs-threat-risk x-rs-certificate-hostname-threat-risk x-bluecoat-access-security-policy-action x-bluecoat-access-security-policy-reason",  // SSL 로그 포맷 (ELFF 필드 순서)
    PROXYSG_MAIN_INDEX_PREFIX: "proxy-main",                    // MAIN 인덱스 Prefix
    PROXYSG_SSL_INDEX_PREFIX: "proxy-ssl",                      // SSL 인덱스 Prefix
    PROXYSG_MAIN_DATA_VIEW_NAME: "main",                        // MAIN Data View 이름
    PROXYSG_SSL_DATA_VIEW_NAME: "ssl",                          // SSL Data View 이름
    PROXYSG_ILM_POLICY_NAME: "proxy-retention-policy",          // ILM Policy 이름
    PROXYSG_INDEX_TEMPLATE_NAME: "proxy-index-template",        // Index Template 이름

    // ───── 고급 설정 17단계 · 파일 로그 자동 수집 관리자 ─────
    FILE_INGEST_MANAGER_ENABLED: false,                       // File Ingest Manager Enabled  [true | false]
    FILE_INGEST_SOURCE_DIRS: "/log/incoming",                 // 일반 파일수집 Source 경로
    FILE_INGEST_STAGING_DIR: "/var/lib/elk-file-ingest/staging",  // File Ingest Staging Dir
    FILE_INGEST_STATE_DIR: "/var/lib/elk-file-ingest/state",  // File Ingest State Dir
    FILE_INGEST_BACKUP_DIR: "/backup/logs",                   // 일반 파일수집 Backup 경로
    FILE_INGEST_DUPLICATE_DIR: "/backup/logs/duplicates",     // File Ingest Duplicate Dir
    FILE_INGEST_QUARANTINE_DIR: "/backup/logs/quarantine",    // File Ingest Quarantine Dir
    FILE_INGEST_COMPLETED_LOG: "/var/log/logstash/completed-files.log",  // File Ingest Completed Log
    FILE_INGEST_LOG: "/var/log/elk-file-ingest.log",          // File Ingest Log
    FILE_INGEST_LOCK_FILE: "/run/lock/elk-file-ingest.lock",  // File Ingest Lock File
    FILE_INGEST_EXTENSIONS: "log,txt,json,csv,gz,xz,zst,bz2",  // File Ingest Extensions
    FILE_INGEST_RECURSIVE: true,                              // File Ingest Recursive  [true | false]
    FILE_INGEST_MIN_AGE_SECONDS: "60",                        // File Ingest Min Age Seconds
    FILE_INGEST_MAX_FILES_PER_RUN: "20",                      // File Ingest Max Files Per Run

    // ───── 고급 설정 18단계 · 파일 수집 - 처리 옵션 ─────
    FILE_INGEST_MAX_SOURCE_FILE_BYTES: "0",                   // File Ingest Max Source File Bytes
    FILE_INGEST_MIN_STAGING_FREE_GB: "20",                    // File Ingest Min Staging Free Gb
    FILE_INGEST_DEDUPE_MODE: "content_sha256",                // File Ingest Dedupe Mode  [content_sha256 | metadata | none]
    FILE_INGEST_DUPLICATE_ACTION: "archive",                  // File Ingest Duplicate Action  [archive | delete | leave]
    FILE_INGEST_PLAIN_BACKUP_COMPRESSION: "zstd",             // File Ingest Plain Backup Compression  [zstd | gzip | xz | none]
    FILE_INGEST_COMPRESSION_LEVEL: "3",                       // File Ingest Compression Level
    FILE_INGEST_PRESERVE_RELATIVE_PATH: true,                 // File Ingest Preserve Relative Path  [true | false]
    FILE_INGEST_DELETE_STAGING_AFTER_COMPLETE: true,          // File Ingest Delete Staging After Complete  [true | false]

    // ───── 고급 설정 19단계 · 파일 수집 - 보관 · 스캔 옵션 ─────
    FILE_INGEST_BACKUP_RETENTION_DAYS: "0",                   // File Ingest Backup Retention Days
    FILE_INGEST_DUPLICATE_RETENTION_DAYS: "0",                // File Ingest Duplicate Retention Days
    FILE_INGEST_QUARANTINE_RETENTION_DAYS: "0",               // File Ingest Quarantine Retention Days
    FILE_INGEST_SCAN_INTERVAL: "1min",                        // File Ingest Scan Interval
    FILE_INGEST_TIMER_RANDOM_DELAY: "10s",                    // File Ingest Timer Random Delay
    FILE_INGEST_SOURCE_OWNER: "root",                         // File Ingest Source Owner
    FILE_INGEST_SOURCE_GROUP: "logstash",                     // File Ingest Source Group
    FILE_INGEST_SOURCE_MODE: "0775",                          // File Ingest Source Mode

    // ───── 고급 설정 20단계 · 상태 모니터링 ─────
    HEALTH_MONITOR_ENABLED: true,                             // 상태 모니터링 사용  [true | false]
    HEALTH_MONITOR_INTERVAL: "5min",                          // Health Monitor Interval
    HEALTH_MONITOR_RANDOM_DELAY: "20s",                       // Health Monitor Random Delay
    HEALTH_MONITOR_LOG: "/var/log/elk-health-monitor.log",    // Health Monitor Log
    HEALTH_DISK_WARN_PERCENT: "85",                           // Health Disk Warn Percent
    HEALTH_DISK_CRIT_PERCENT: "92",                           // Health Disk Crit Percent
    HEALTH_AUTO_PAUSE_FILE_INGEST_ON_CRITICAL: false,         // Health Auto Pause File Ingest On Critical  [true | false]

    // ───── 고급 설정 21단계 · 인덱스 / ILM ─────
    INDEX_PREFIX: "network-log",                              // Index Prefix
    INDEX_MODE: "daily",                                      // Index Mode  [daily | rollover | plain]
    INDEX_DATE_PATTERN: "YYYY.MM.dd",                         // Index Date Pattern
    INDEX_TEMPLATE_NAME: "proxy-index-template",              // Index Template Name
    INDEX_TEMPLATE_PATTERNS: "proxy-main-*,proxy-ssl-*",      // Index Template Patterns
    INDEX_TEMPLATE_PRIORITY: "200",                           // Index Template Priority
    INDEX_NUMBER_OF_SHARDS: "1",                              // Primary Shard 수
    INDEX_NUMBER_OF_REPLICAS: "0",                            // Replica 수
    INDEX_REFRESH_INTERVAL: "5s",                             // Index Refresh Interval
    INDEX_TOTAL_FIELDS_LIMIT: "2000",                         // Index Total Fields Limit
    INDEX_MAPPING_FILE: "",                                   // Index Mapping File
    ILM_POLICY_NAME: "proxy-retention-policy",                // Ilm Policy Name
    ILM_DELETE_ENABLED: true,                                 // Ilm Delete Enabled  [true | false]
    ILM_DELETE_MIN_AGE: "90d",                                // 인덱스 보존기간
    ILM_APPLY_TO_EXISTING: true,                              // 기존 인덱스에도 ILM 적용  [true | false]
    ILM_EXISTING_INDEX_PATTERNS: "proxy-main-*,proxy-ssl-*",  // Ilm Existing Index Patterns
    ILM_WARM_ENABLED: false,                                  // Ilm Warm Enabled  [true | false]
    ILM_WARM_MIN_AGE: "7d",                                   // Ilm Warm Min Age
    ILM_WARM_READONLY: true,                                  // Ilm Warm Readonly  [true | false]
    ILM_WARM_FORCE_MERGE: false,                              // Ilm Warm Force Merge  [true | false]
    ILM_WARM_FORCE_MERGE_SEGMENTS: "1",                       // Ilm Warm Force Merge Segments
    ILM_ROLLOVER_ALIAS: "network-log",                        // Ilm Rollover Alias
    ILM_ROLLOVER_PATTERN: "000001",                           // Ilm Rollover Pattern
    ILM_ROLLOVER_MAX_AGE: "1d",                               // Ilm Rollover Max Age
    ILM_ROLLOVER_MAX_PRIMARY_SHARD_SIZE: "50gb",              // Ilm Rollover Max Primary Shard Size
    ILM_ROLLOVER_MAX_DOCS: "",                                // Ilm Rollover Max Docs

    // ───── 고급 설정 22단계 · Snapshot / SLM (선택) ─────
    SNAPSHOT_REPO_ENABLED: false,                             // Snapshot Repo Enabled  [true | false]
    SNAPSHOT_REPO_NAME: "local-backup",                       // Snapshot Repo Name
    SNAPSHOT_REPO_PATH: "/backup/elasticsearch",              // Snapshot 저장 경로
    SNAPSHOT_COMPRESS: true,                                  // Snapshot Compress  [true | false]
    SNAPSHOT_READONLY: false,                                 // Snapshot Readonly  [true | false]
    SLM_POLICY_ENABLED: false,                                // Slm Policy Enabled  [true | false]
    SLM_POLICY_NAME: "daily-snapshot",                        // Slm Policy Name
    SLM_SCHEDULE: "0 30 1 * * ?",                             // Slm Schedule
    SLM_SNAPSHOT_NAME: "<elk-snap-{now/d}>",                  // Slm Snapshot Name
    SLM_INDICES: "network-log-*",                             // Slm Indices
    SLM_IGNORE_UNAVAILABLE: true,                             // Slm Ignore Unavailable  [true | false]
    SLM_INCLUDE_GLOBAL_STATE: false,                          // Slm Include Global State  [true | false]
    SLM_RETENTION_EXPIRE_AFTER: "30d",                        // Slm Retention Expire After
    SLM_RETENTION_MIN_COUNT: "3",                             // Slm Retention Min Count
    SLM_RETENTION_MAX_COUNT: "50",                            // Slm Retention Max Count

    // ───── 고급 설정 23단계 · UFW 방화벽 (선택) ─────
    UFW_MANAGE: false,                                        // UFW 자동 관리  [true | false]
    UFW_ENABLE_IF_INACTIVE: false,                            // Ufw Enable If Inactive  [true | false]
    UFW_KIBANA_ALLOWED_CIDRS: "192.168.0.0/16,10.0.0.0/8",    // Ufw Kibana Allowed Cidrs
    UFW_NGINX_ALLOWED_CIDRS: "192.168.0.0/16,10.0.0.0/8",     // Kibana/Nginx 접속 허용 대역
    UFW_ELASTICSEARCH_ALLOWED_CIDRS: "127.0.0.1/32",          // Ufw Elasticsearch Allowed Cidrs
    UFW_LOGSTASH_ALLOWED_CIDRS: "192.168.0.0/16,10.0.0.0/8",  // Ufw Logstash Allowed Cidrs
    UFW_FTP_ALLOWED_CIDRS: "192.168.0.0/16,10.0.0.0/8",       // FTP 접속 허용 대역

    // ───── 고급 설정 24단계 · 서비스 / 설치 후 검증 ─────
    ENABLE_SERVICES_ON_BOOT: true,                            // 부팅 시 자동 시작  [true | false]
    START_SERVICES_AFTER_INSTALL: true,                       // 설치 후 즉시 시작  [true | false]
    WAIT_TIMEOUT_SECONDS: "180",                              // 설치 후 서비스 대기 시간(초)
    CREATE_TEST_EVENT: false,                                 // 설치 후 테스트 이벤트 생성  [true | false]
    TEST_EVENT_MESSAGE: "ELK auto installer test event",      // Test Event Message
    POST_INSTALL_SCRIPT: "",                                  // Post Install Script

    // ───── 기타 (설치 진행 표시 · APT 재시도) ─────
    INSTALL_PROGRESS_ENABLED: true,                           // 설치 전체 진행률 표시  [true | false]
    INSTALL_PROGRESS_BAR_WIDTH: "30",                         // 진행률 막대 길이
    APT_PROGRESS_ENABLED: true,                               // APT 다운로드/설치 상세 진행률  [true | false]
    APT_RETRIES: "10",                                        // APT 다운로드 재시도 횟수
    APT_CONNECT_TIMEOUT: "30",                                // APT 연결 타임아웃(초)


    // ───── 새로 추가된 항목 (tools/gen_defaults.py) ─────
    PROXYSG_CLOUD_ENABLED: false,                             // Cloud 로그 처리 사용  [true | false]
    PROXYSG_CLOUD_SOURCE_DIR: "/home/cloud",                  // Cloud FTP 수신 폴더
    PROXYSG_CLOUD_BACKUP_DIR: "/home/cloud_backup",           // Cloud 원본 백업 폴더
    PROXYSG_CLOUD_PROCESS_DIR: "/home/cloud_process",         // Cloud Logstash 처리 폴더
    PROXYSG_CLOUD_SINCEDB: "/var/lib/logstash/sincedb-cloud",  // Cloud sincedb 파일
    PROXYSG_CLOUD_LOG_FORMAT: "c-ip c-ip-version c-port cs-auth-groups cs-bytes cs-categories cs-host cs-icap-error-details cs-icap-service cs-icap-status cs-method cs-referer cs-threat-risk cs-uri-extension cs-uri-path cs-uri-port cs-uri-query cs-uri-scheme cs-user-agent cs-user-domain cs-userdn cs-x-requested-with date r-ip r-ip-version r-supplier-country rs-content-type rs-icap-error-details rs-icap-service rs-icap-status s-action s-ip s-source-ip s-supplier-country s-supplier-failures s-supplier-ip sc-bytes sc-filter-result sc-status time time-taken x-action-result x-bluecoat-access-type x-bluecoat-application-name x-bluecoat-application-operation x-bluecoat-location-id x-bluecoat-location-name x-bluecoat-placeholder x-bluecoat-reference-id x-bluecoat-reference-ids x-bluecoat-request-tenant-id x-bluecoat-transaction-uuid x-client-agent-ip x-client-agent-sw x-client-agent-type x-client-device-id x-client-device-name x-client-device-type x-client-os x-client-security-posture-details x-client-security-posture-risk-score x-cloud-rs x-cs-certificate-subject x-cs-client-ip-country x-cs-connection-negotiated-cipher x-cs-connection-negotiated-cipher-size x-cs-connection-negotiated-ssl-version x-cs-ocsp-error x-cs-public-ip x-data-leak-detected x-data-types x-exception-id x-file-details x-icap-reqmod-header(X-ICAP-Metadata) x-icap-respmod-header(X-ICAP-Metadata) x-random-ipv6 x-request-origin x-rs-certificate-hostname x-rs-certificate-hostname-categories x-rs-certificate-hostname-threat-risk x-rs-certificate-observed-errors x-rs-certificate-validate-status x-rs-connection-negotiated-cipher x-rs-connection-negotiated-cipher-size x-rs-connection-negotiated-ssl-version x-rs-ocsp-error x-sc-connection-issuer-keyring x-sc-connection-issuer-keyring-alias x-symc-inspected x-symc-page-views x-symc-upload-source x-virus-id",  // Cloud 로그 포맷 (ELFF 필드 순서)
    PROXYSG_CLOUD_INDEX_PREFIX: "proxy-cloud",                // Cloud 인덱스 Prefix
    PROXYSG_CLOUD_DATA_VIEW_NAME: "cloud",                    // Cloud Data View 이름

    // (비밀번호·암호화 키 항목은 이 파일에서 지정할 수 없습니다: ELASTIC_PASSWORD, KIBANA_SECURITY_ENCRYPTION_KEY, KIBANA_REPORTING_ENCRYPTION_KEY, KIBANA_SAVED_OBJECTS_ENCRYPTION_KEY, KIBANA_INITIAL_USER_PASSWORD, LOGSTASH_ES_PASSWORD, FTP_PASSWORD)
  },

  // Ubuntu 자동 전송/설치 대상의 초기값 (고급 설정 21단계 / 빠른 설정 10단계). 비밀번호는 지정할 수 없습니다.
  deploy: {
    host: "172.16.70.208",                                    // Ubuntu 서버 IP / 호스트
    user: "etech",                                            // SSH 로그인 계정
    port: "22",                                               // SSH 포트
    remoteDir: "/home/etech",                                 // 원격 전송 폴더
    autoInstall: true,                                        // 전송 후 자동 설치 [true | false]
    removeAfter: true,                                        // 성공 후 원격 설치파일 삭제 [true | false]
    sudoSame: true,                                           // sudo 비밀번호 = SSH 비밀번호 [true | false]
  }
};
