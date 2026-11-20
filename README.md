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
| app_event_log | 79 | JSON(`props_json`) 반정형, 전환율 (order_start 42 · order_done 19). |
| daily_trade_kpi | (파생) | 마트 예시 (중복 제거 후 일별 KPI) |

## 디렉토리 구조

```
.
├── README.md
├── data/                      # 공유 폴더 data/ 에 올리는 실습 파일 (CSV 6종 + 대시보드 템플릿)
│   ├── dim_stock.csv
│   ├── stock_price_daily.csv
│   ├── dim_customer.csv
│   ├── eis_ac_account.csv
│   ├── eis_tr_order.csv
│   ├── app_event_log.csv
│   └── edu_trade_kpi.lvdash.json # 대시보드 템플릿 (테이블 이름에 <my_id> 자리 표시, 위젯 6개)
├── scripts/
│   └── generate_data.py       # 데이터 생성기 (표준 라이브러리만 사용)
└── notebooks/                 # 공유 폴더 notebooks/ 에 올리고, 교육생은 내 홈으로 Clone 해서 실행
    ├── 01_load_tables.sql     # [교육생] 본인 테이블(_<my_id>) 생성·적재 + 행수 검증
    └── 02_exercises.sql       # 실습 문제 8개
```

## 실행 방법

공통 스키마 `kpsec.sandbox_edu` 와 공유 폴더는 **관리자가 미리 준비**하고, 교육생은 **노트북 Clone → 테이블 생성** 순서로 진행합니다.

공유 폴더 **`/Workspace/Shared/kpsec_handson`** 에는 관리자가 이 저장소의 `data/` 와 `notebooks/` 를 그대로 올려 둡니다 (Workspace → Shared → Create → Folder 후 Import).

```
/Workspace/Shared/kpsec_handson/
├── data/        # CSV 6개 — 노트북이 이 경로를 직접 읽음
└── notebooks/   # 01 · 02 원본 — 교육생은 Clone 해서 사용
```

**교육생 준비 — 노트북을 내 홈으로 Clone**

1. Workspace → Shared → `kpsec_handson` 에서 `notebooks` 폴더를 오른쪽 클릭(또는 ⋮) → **Clone**
2. New name: `kpsec_notebooks`, **Clone to: Browse → Users → 내 계정(홈)** (기본값이 Shared 라서 꼭 바꿔야 함), Include outputs 체크 해제
3. **Clone** → 내 홈(`/Workspace/Users/<본인 계정>/kpsec_notebooks`)의 `01_load_tables` 부터 실행

Shared 의 원본 노트북은 직접 실행 · 수정하지 않습니다. 원본 CSV 는 `/Workspace/Shared/kpsec_handson/data` 에서 읽으며, 여러 교육생이 같은 파일을 동시에 읽기만 하고 쓰기는 각자 `_<my_id>` 테이블에만 하므로 서로 충돌하지 않습니다.

| 누가 | 노트북 | 하는 일 |
|---|---|---|
| 관리자 · 강사 (교육 전 1회) | — | 공통 스키마 `kpsec.sandbox_edu` 준비, 공유 폴더 `/Workspace/Shared/kpsec_handson` 에 `data/` · `notebooks/` 업로드, 교육생 권한 부여 |
| 교육생 | `01_load_tables` (내 홈에 Clone 한 것) | 첫 셀 `CREATE WIDGET` 실행 → 왼쪽 `{ }` 아이콘(Parameters) 패널 `my_id` 에 본인 ID 입력 → Run all → 공유 폴더의 CSV 6개 확인 → CSV 를 읽어 `dim_stock_<my_id>` 등 본인 테이블 7개 생성 · 검증 |
| 교육생 | `02_exercises` (내 홈에 Clone 한 것) | 같은 `my_id` 로 실습 문제 8개 (품질점검 → 조인 → 윈도우 → JSON → 코호트 → 마스킹뷰) |

- 테이블 이름은 `IDENTIFIER('dim_stock_' || :my_id)` 처럼 위젯 값을 붙여 만듭니다. `CREATE WIDGET` 셀이 실행돼야 입력 칸이 생기고, 칸은 노트북 왼쪽 `{ }` 아이콘의 **Parameters 패널**에 있습니다.
- `my_id` 는 영문 소문자 · 숫자 · `_` 만 (예: `rian_bow`). `01_load_tables` 에는 ID 검사 셀이 없으므로, 비운 채 Run all 하면 `dim_stock_` 처럼 이름 끝이 빈 테이블이 만들어집니다. ID를 먼저 입력하세요. (`02_exercises` 는 ID가 비어 있으면 첫 검사 셀에서 멈춥니다.)
- 교육생 권한: `USE CATALOG kpsec`, `USE SCHEMA` · `CREATE TABLE` (스키마 `sandbox_edu`), 공유 폴더 `/Workspace/Shared/kpsec_handson` 읽기(Can Read 이상).
- 노트북은 `read_files('file:/Workspace/Shared/kpsec_handson/data/<파일>.csv', …)` 로 읽습니다. 강의 중에는 공유 폴더의 파일을 바꾸거나 다시 올리지 마세요 (읽는 도중 파일이 바뀌면 그 순간 실행한 사람만 오류가 날 수 있음).
- `01_load_tables` 는 `CREATE OR REPLACE` 라 재실행해도 안전합니다.

### 대시보드 템플릿 가져오기 (JSON Import)

1. 저장소 `data/edu_trade_kpi.lvdash.json` 을 내려받아 (GitHub → 파일 열기 → Download raw file) 텍스트 편집기에서 `<my_id>` 를 본인 ID로 모두 바꿉니다 (9곳).
2. Dashboards → **Create dashboard ▾ → Import dashboard from file** 로 파일을 올립니다. 대시보드 이름은 파일 이름을 따릅니다.
3. 위젯 6개(채널별 · 일별 · 계좌유형별 체결금액, 종목별 최근 종가, 월별 신규 계좌, 주문 데이터 품질)가 본인 테이블로 그려집니다.

내보내기는 대시보드 ⋮ → File actions → **Export** (`.lvdash.json`), 기존 대시보드를 파일로 덮어쓰려면 같은 메뉴의 **Replace** 를 씁니다.

## 참고
