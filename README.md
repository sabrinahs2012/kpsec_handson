# Databricks 교육용 샘플 데이터셋

사내 환경과 유사한 전부 가상의 증권 도메인 데이터. 실제 고객·계좌 정보 없음
(고객번호 9xxxxxxx, 계좌번호 999-XX-XXXXXX, 이름/전화는 처음부터 마스킹 형태, CI는 가상 해시).

## 사내 관례 반영

- 카탈로그 `kpsec`, 스키마 `sandbox_edu` (교육 전용, sandbox 워크스페이스)
- `base_date` = STRING `yyyymmdd`, 원장성 테이블은 `eis_` 접두사(계정계 원장)
- 테이블 코멘트 `BIGDATA(DBX)_<소스>_<업무>_<한글명>`, 큰 테이블은 `CLUSTER BY (base_date)`

## 테이블

교육생마다 `<테이블>_<my_id>` 이름으로 본인 테이블을 만듭니다 (예: `dim_stock_rian_bow`).

| 테이블 | 행수 | 용도 |
|---|---|---|
| dim_stock | 10 | 종목 마스터 |
| stock_price_daily | 20 | 일별 시세, 윈도우 함수 |
| dim_customer | 20 | 마스킹 컬럼·결측(마케팅동의 2건) |
| eis_ac_account | 22 | 계좌 원장, 해지/정상 |
| eis_tr_order | 22 | 주문/체결. 일부러 오염: 중복 2건, 음수 수량 2건, 채널 결측 2건 |
| app_event_log | 79 | JSON(`props_json`) 반정형, 전환율 (order_start 42 · order_done 19). 처음 공유한 10행 CSV에는 주문 이벤트가 없어 `01` 끝의 보정 INSERT 로 채움 |
| daily_trade_kpi | (파생) | 마트 예시 (중복 제거 후 일별 KPI) |

## 디렉토리 구조

```
.
├── README.md
├── data/                      # 생성된 CSV 6종
│   ├── dim_stock.csv
│   ├── stock_price_daily.csv
│   ├── dim_customer.csv
│   ├── eis_ac_account.csv
│   ├── eis_tr_order.csv
│   └── app_event_log.csv
├── scripts/
│   └── generate_data.py       # 데이터 생성기 (표준 라이브러리만 사용)
├── notebooks/                 # Databricks 노트북 (Git folder 에서 바로 실행)
│   ├── 00_setup_and_upload.py # [사전 준비·관리자] 공통 스키마/볼륨 생성 + data/*.csv → Volume 복사
│   ├── 01_load_tables.sql     # [교육생] 본인 테이블(_<my_id>) 생성·적재 + 행수 검증 + 앱 이벤트 보정 INSERT
│   └── 02_exercises.sql       # 실습 문제 9개
└── sql/
    ├── 01_create_and_load.sql # 01 노트북과 같은 내용 (SQL Editor 용, :my_id 파라미터)
    └── 02_exercises.sql       # 실습 문제 9개
```

## 실행 방법

공통 스키마 · 볼륨은 **관리자가 미리 준비**하고, 교육생은 **테이블 생성부터** 진행합니다.

| 누가 | 노트북 | 하는 일 |
|---|---|---|
| 관리자 · 강사 (교육 전 1회) | `00_setup_and_upload` | 공통 스키마 `kpsec.sandbox_edu` · 볼륨 `edu_raw` 생성, `data/*.csv` 6개를 볼륨으로 복사, 교육생 권한 부여(GRANT 예시) |
| 교육생 | `01_load_tables` | 위젯 `my_id` 에 본인 ID 입력 → 볼륨 CSV 를 읽어 `dim_stock_<my_id>` 등 본인 테이블 7개 생성 · 검증 → 앱 이벤트 보정 INSERT |
| 교육생 | `02_exercises` | 같은 `my_id` 로 실습 문제 9개 (품질점검 → 조인 → 윈도우 → JSON → 코호트 → 마스킹뷰 → 타임트래블) |

- 테이블 이름은 `IDENTIFIER('dim_stock_' || :my_id)` 처럼 위젯 값을 붙여 만듭니다. SQL Editor 에서는 같은 `:my_id` 가 파라미터 칸으로 나타납니다 (`sql/` 스크립트).
- `my_id` 는 영문 소문자 · 숫자 · `_` 만 (예: `rian_bow`). 비어 있으면 첫 검사 셀에서 멈춥니다.
- 교육생 권한: `USE CATALOG kpsec`, `USE SCHEMA` · `CREATE TABLE` (스키마 `sandbox_edu`), `READ VOLUME` (볼륨 `edu_raw`).
- `01_load_tables` 는 `CREATE OR REPLACE` 라 재실행해도 안전하고, 보정 INSERT 는 이미 있는 `event_id` 는 건너뜁니다.
- 실습 [9] 는 본인 주문 테이블의 복사본 `eis_tr_order_tt_<my_id>` 로 시연합니다. `VERSION AS OF` · `RESTORE` · `DESCRIBE HISTORY` 는 `IDENTIFIER()` 를 받지 않아 `EXECUTE IMMEDIATE` 로 실행합니다.

### 노트북 없이 (SQL Editor) 실행할 때

1. (관리자) 스키마 · 볼륨 생성 후 `data/*.csv` 6개를 `/Volumes/kpsec/sandbox_edu/edu_raw/` 에 업로드 (UI: Catalog → 볼륨 → Upload)
2. (교육생) `sql/01_create_and_load.sql` 실행 — 파라미터 `my_id` 입력 → 검증 쿼리로 행수 확인
3. (교육생) `sql/02_exercises.sql` 로 실습

## 참고
