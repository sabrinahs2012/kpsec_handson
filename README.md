# Databricks 교육용 샘플 데이터셋

사내 환경과 유사한 전부 가상의 증권 도메인 데이터. 실제 고객·계좌 정보 없음
(고객번호 9xxxxxxx, 계좌번호 999-XX-XXXXXX, 이름/전화는 처음부터 마스킹 형태, CI는 가상 해시).

> 출처: 고객사가 제공한 샘플(README / SQL 2종 / 데이터 생성기 / CSV 6종)을 로컬 파일로 복원한 것입니다.

## 사내 관례 반영

- 카탈로그 `kpsec`, 스키마 `sandbox_edu` (교육 전용, sandbox 워크스페이스)
- `base_date` = STRING `yyyymmdd`, 원장성 테이블은 `eis_` 접두사(계정계 원장)
- 테이블 코멘트 `BIGDATA(DBX)_<소스>_<업무>_<한글명>`, 큰 테이블은 `CLUSTER BY (base_date)`

## 테이블

| 테이블 | 행수 | 용도 |
|---|---|---|
| dim_stock | 10 | 종목 마스터 |
| stock_price_daily | 20 | 일별 시세, 윈도우 함수 |
| dim_customer | 20 | 마스킹 컬럼·결측(마케팅동의 2건) |
| eis_ac_account | 22 | 계좌 원장, 해지/정상 |
| eis_tr_order | 22 | 주문/체결. 일부러 오염: 중복 2건, 음수 수량 2건, 채널 결측 2건 |
| app_event_log | 79 | JSON(`props_json`) 반정형, 전환율 (order_start 42 · order_done 19) |
| daily_trade_kpi | (파생) | 마트 예시 (중복 제거 후 일별 KPI) |

종목코드는 실재 코드와 겹치지 않게 `X` 접두사. CSV 전체 합계 수 KB(1MB 미만, 테이블당 10~79행).
2배 확장분(종목 5 · 고객 10 · 계좌 11 · 주문 11 · 이벤트 40)은 별도 RNG(`SEED + 100`)로 만들어 기존 행은 그대로 유지됩니다.
기간 2026-10-29 ~ 2026-10-30 (2영업일, 해지 계좌 1건 포함). 시드 고정이라 재생성해도 동일.

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
│   ├── 00_setup_and_upload.py # 스키마/볼륨 생성 + data/*.csv → Volume 복사
│   ├── 01_load_tables.py      # 테이블 생성·적재 + 행수 검증
│   └── 02_exercises.py        # 실습 문제 9개
└── sql/
    ├── 01_create_and_load.sql # 스키마/볼륨 생성 + 테이블 적재 + 검증
    └── 02_exercises.sql       # 실습 문제 9개
```

## Databricks 노트북으로 실행 (권장)

Git folder(Repos)에 이 저장소를 연결한 뒤 `notebooks/` 의 노트북을 **번호 순서대로** 실행합니다. CSV 업로드도 노트북이 대신 합니다.

| 순서 | 노트북 | 하는 일 |
|---|---|---|
| 1 | `00_setup_and_upload` | `kpsec.sandbox_edu` 스키마·`edu_raw` 볼륨 생성, `data/*.csv` 6개를 Volume 으로 복사 |
| 2 | `01_load_tables` | 테이블 7개 생성·적재, 마지막에 행수 검증 |
| 3 | `02_exercises` | 실습 문제 9개 (품질점검 → 조인 → 윈도우 → JSON → 코호트 → 마스킹뷰 → 타임트래블) |

- 사전 조건: 카탈로그 `kpsec` 존재, 실행 계정에 `CREATE SCHEMA` / `CREATE VOLUME` 권한. SQL 웨어하우스 또는 서버리스/클러스터 어디서나 실행 가능
- `01_load_tables` 는 `CREATE OR REPLACE` 라 재실행해도 안전합니다.
- 노트북은 `sql/` 의 스크립트를 Databricks 실행에 맞게 옮긴 것입니다. 차이점: 적재를 `CREATE TABLE (컬럼 정의)` → `INSERT INTO ... SELECT` 두 단계로 분리했고, 실습 [5] 는 0 나누기 방지를 위해 `try_divide` 를 사용, 실습 [9] 의 `RESTORE` 버전은 `1` 입니다.

아래 `사용 순서` 는 노트북 없이 수동으로 실행할 때의 절차입니다.

## 사용 순서

1. (이미 생성됨) 재생성: `python3 -I scripts/generate_data.py data`
2. Databricks sandbox 에서 `sql/01_create_and_load.sql` 의 앞부분(스키마·볼륨 생성)만 먼저 실행
3. `data/*.csv` 6개를 Volume `/Volumes/kpsec/sandbox_edu/edu_raw/` 에 업로드 (UI: Catalog → 볼륨 → Upload)
4. `01_create_and_load.sql` 나머지 실행 → 마지막 검증 쿼리로 행수 확인
5. `sql/02_exercises.sql` 로 실습 (품질점검 → 조인 → 윈도우 → JSON → 코호트 → 마스킹뷰 → 타임트래블)

## 참고

- 권한은 참가자별 스키마 쓰기가 필요하면 `USE`/`SELECT`/`MODIFY` 를 교육 그룹에 부여하거나, 참가자마다 `sandbox_edu_<id>` 스키마로 CTAS 복제.
- 데이터셋 관련 요청/문의는 카카오페이증권 담당자(메일 발신자)에게 직접 전달.

## 복원 시 메모 (메일 → 파일)

메일 본문이 HTML 로 변환되면서 손실된 부분을 아래와 같이 복원했습니다.

- 들여쓰기 손실 → `generate_data.py` 의 Python 들여쓰기, SQL 정렬 재구성
- `*` 손실 → `COUNT(*)`, `data/*.csv`, 마스킹 값(`신*`, `010-****-1807`) 복원
- `#` 주석이 제목으로 변환된 부분 → Python/SQL 주석으로 복원
- 원문 SQL 1 헤더 주석의 Volume 경로 `/Volumes/kpsec/sandbox/edu_raw/` 는 코드 본문(`sandbox_edu`)과 달라 **`sandbox_edu` 로 통일**
- 검증: 복원한 `generate_data.py` 를 실행해 생성된 CSV 6종이 메일 본문 CSV 와 모두 동일함을 확인
