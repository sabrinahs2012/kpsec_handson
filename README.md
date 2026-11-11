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
| dim_stock | 5 | 종목 마스터 |
| stock_price_daily | 10 | 일별 시세, 윈도우 함수 |
| dim_customer | 10 | 마스킹 컬럼·결측(마케팅동의 1건) |
| eis_ac_account | 11 | 계좌 원장, 해지/정상 |
| eis_tr_order | 11 | 주문/체결. 일부러 오염: 중복 1건, 음수 수량 1건, 채널 결측 1건 |
| app_event_log | 10 | JSON(`props_json`) 반정형, 전환율 |
| daily_trade_kpi | (파생) | 마트 예시 (중복 제거 후 일별 KPI) |

종목코드는 실재 코드와 겹치지 않게 `X` 접두사. CSV 전체 합계 수 KB(1MB 미만, 테이블당 5~11행).
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
└── sql/
    ├── 01_create_and_load.sql # 스키마/볼륨 생성 + 테이블 적재 + 검증
    └── 02_exercises.sql       # 실습 문제 9개
```

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
