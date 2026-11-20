-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 01. 내 테이블 생성 + 적재
-- MAGIC
-- MAGIC **교육생은 이 노트북부터 시작합니다.** 공통 스키마 `kpsec.sandbox_edu` 는 미리 준비되어 있고, 원본 CSV 6개는 공유 폴더 `/Workspace/Shared/kpsec_handson/data` 에 있습니다.
-- MAGIC
-- MAGIC **`my_id` 설정 (처음 한 번)**
-- MAGIC
-- MAGIC 1. **Run all** 을 누릅니다. 첫 셀 `CREATE WIDGET` 이 입력 칸 `my_id` 를 만들고("Parameter created" 알림), ID가 비어 있으므로 **검사 셀에서 멈춥니다** (정상).
-- MAGIC 2. 노트북 **왼쪽 세로 메뉴의 `{ }` 아이콘(Parameters)** 을 눌러 패널을 열고, `my_id` 칸에 본인 ID를 입력합니다. (영문 소문자 · 숫자 · `_` 만, 예: `rian_bow`)
-- MAGIC 3. 다시 **Run all** — 공유 폴더의 CSV 파일이 있는지 확인한 뒤, CSV를 읽어 `dim_stock_<my_id>` 처럼 **본인 이름이 붙은 테이블 7개** 를 만들고, 검증 쿼리 · **앱 이벤트 보정 INSERT** 까지 실행합니다.
-- MAGIC
-- MAGIC - 테이블 이름은 `IDENTIFIER('dim_stock_' || :my_id)` 형태로 위젯 값을 붙여 만듭니다.
-- MAGIC - 사내 관례: `base_date` = STRING `yyyymmdd`, 원장성 테이블은 `eis_` 접두사, 코멘트 = `BIGDATA(DBX)_<소스>_<업무>_<한글명>`
-- MAGIC - 모든 테이블은 `CREATE OR REPLACE` 라서 **다시 실행해도 안전**합니다.

-- COMMAND ----------

CREATE WIDGET TEXT my_id DEFAULT ''

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ID가 비어 있거나 형식이 맞지 않으면 여기서 멈춥니다. 왼쪽 `{ }` 아이콘 → Parameters 패널의 `my_id` 에 ID를 넣고 다시 **Run all** 하세요.

-- COMMAND ----------

SELECT  :my_id AS my_id

-- COMMAND ----------

USE kpsec.sandbox_edu

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 공유 폴더의 CSV 파일 확인
-- MAGIC
-- MAGIC 테이블을 만들기 전에 `/Workspace/Shared/kpsec_handson/data` 에 CSV 6개가 있는지 조회합니다.
-- MAGIC 여러 사람이 같은 파일을 동시에 **읽기만** 하므로 함께 실행해도 문제없습니다.
-- MAGIC
-- MAGIC 기대값 (`rows` = 헤더 제외 행 수): `app_event_log` 79 · `dim_customer` 20 · `dim_stock` 10 · `eis_ac_account` 22 · `eis_tr_order` 22 · `stock_price_daily` 20

-- COMMAND ----------

SELECT _metadata.file_name          AS file_name,
       MAX(_metadata.file_size)     AS file_size_bytes,
       COUNT(*) - 1                 AS rows,
       MAX(_metadata.file_modification_time) AS modified_at
FROM read_files('file:/Workspace/Shared/kpsec_handson/data/*.csv', format => 'text')
GROUP BY 1
ORDER BY 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 6개가 모두 없으면 여기서 멈춥니다. 강사에게 공유 폴더 상태(Git folder Pull 여부)와 읽기 권한을 확인해 달라고 하세요.

-- COMMAND ----------

SELECT assert_true(COUNT(DISTINCT _metadata.file_name) = 6,
                   '/Workspace/Shared/kpsec_handson/data 에 CSV 6개가 없습니다. 강사에게 확인하세요') AS files_ok,
       COUNT(DISTINCT _metadata.file_name) AS csv_files
FROM read_files('file:/Workspace/Shared/kpsec_handson/data/*.csv', format => 'text')
WHERE _metadata.file_name IN ('dim_stock.csv', 'stock_price_daily.csv', 'dim_customer.csv',
                              'eis_ac_account.csv', 'eis_tr_order.csv', 'app_event_log.csv')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 종목 마스터 `dim_stock_<my_id>`

-- COMMAND ----------

CREATE OR REPLACE TABLE IDENTIFIER('dim_stock_' || :my_id) (
  stock_cd STRING COMMENT '종목코드',
  stock_nm STRING COMMENT '종목명',
  market   STRING COMMENT '시장(KOSPI/KOSDAQ)',
  sector   STRING COMMENT '업종',
  list_dt  STRING COMMENT '상장일 yyyymmdd'
) COMMENT 'BIGDATA(DBX)_EDU_종목_종목마스터'

-- COMMAND ----------

INSERT INTO IDENTIFIER('dim_stock_' || :my_id)
SELECT * FROM read_files('file:/Workspace/Shared/kpsec_handson/data/dim_stock.csv',
  format => 'csv', header => true,
  schema => 'stock_cd STRING, stock_nm STRING, market STRING, sector STRING, list_dt STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 일별 시세 `stock_price_daily_<my_id>`

-- COMMAND ----------

CREATE OR REPLACE TABLE IDENTIFIER('stock_price_daily_' || :my_id) (
  base_date STRING COMMENT '기준일 yyyymmdd',
  stock_cd  STRING COMMENT '종목코드',
  open_px   BIGINT COMMENT '시가',
  high_px   BIGINT COMMENT '고가',
  low_px    BIGINT COMMENT '저가',
  close_px  BIGINT COMMENT '종가',
  volume    BIGINT COMMENT '거래량'
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_시세_일별시세'

-- COMMAND ----------

INSERT INTO IDENTIFIER('stock_price_daily_' || :my_id)
SELECT * FROM read_files('file:/Workspace/Shared/kpsec_handson/data/stock_price_daily.csv',
  format => 'csv', header => true,
  schema => 'base_date STRING, stock_cd STRING, open_px BIGINT, high_px BIGINT, low_px BIGINT, close_px BIGINT, volume BIGINT')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 고객 `dim_customer_<my_id>` (마스킹 컬럼 시연용)

-- COMMAND ----------

CREATE OR REPLACE TABLE IDENTIFIER('dim_customer_' || :my_id) (
  cust_no      STRING COMMENT '고객번호(가상 9xxxxxxx)',
  cust_nm_mask STRING COMMENT '고객명(마스킹)',
  mobile_mask  STRING COMMENT '휴대폰(마스킹)',
  ci_hash      STRING COMMENT 'CI 해시(가상)',
  age_grp      STRING COMMENT '연령대',
  sido         STRING COMMENT '거주지역',
  join_channel STRING COMMENT '가입채널',
  cust_grade   STRING COMMENT '고객등급',
  join_dt      STRING COMMENT '가입일 yyyymmdd',
  mkt_agree_yn STRING COMMENT '마케팅동의여부(결측 포함)'
) COMMENT 'BIGDATA(DBX)_EDU_고객_고객마스터'

-- COMMAND ----------

INSERT INTO IDENTIFIER('dim_customer_' || :my_id)
SELECT * FROM read_files('file:/Workspace/Shared/kpsec_handson/data/dim_customer.csv',
  format => 'csv', header => true,
  schema => 'cust_no STRING, cust_nm_mask STRING, mobile_mask STRING, ci_hash STRING, age_grp STRING, sido STRING, join_channel STRING, cust_grade STRING, join_dt STRING, mkt_agree_yn STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 계좌 원장 `eis_ac_account_<my_id>` (`eis_` = 계정계 원장)

-- COMMAND ----------

CREATE OR REPLACE TABLE IDENTIFIER('eis_ac_account_' || :my_id) (
  acct_no      STRING COMMENT '계좌번호(가상 999-XX-XXXXXX)',
  cust_no      STRING COMMENT '고객번호',
  acct_type_cd STRING COMMENT '계좌유형코드',
  acct_type_nm STRING COMMENT '계좌유형명',
  open_dt      STRING COMMENT '개설일 yyyymmdd',
  close_dt     STRING COMMENT '해지일 yyyymmdd(미해지=빈값)',
  acct_stat    STRING COMMENT '계좌상태(정상/해지)'
) COMMENT 'BIGDATA(DBX)_EDU_계좌_계좌원장'

-- COMMAND ----------

INSERT INTO IDENTIFIER('eis_ac_account_' || :my_id)
SELECT acct_no, cust_no, acct_type_cd, acct_type_nm, open_dt, NULLIF(close_dt, ''), acct_stat
FROM read_files('file:/Workspace/Shared/kpsec_handson/data/eis_ac_account.csv',
  format => 'csv', header => true,
  schema => 'acct_no STRING, cust_no STRING, acct_type_cd STRING, acct_type_nm STRING, open_dt STRING, close_dt STRING, acct_stat STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 주문/체결 `eis_tr_order_<my_id>` (중복 · 음수수량 · 채널결측 포함)

-- COMMAND ----------

CREATE OR REPLACE TABLE IDENTIFIER('eis_tr_order_' || :my_id) (
  order_id   STRING    COMMENT '주문번호',
  base_date  STRING    COMMENT '주문일 yyyymmdd',
  order_ts   TIMESTAMP COMMENT '주문시각',
  acct_no    STRING    COMMENT '계좌번호',
  stock_cd   STRING    COMMENT '종목코드',
  side       STRING    COMMENT '매수/매도',
  qty        INT       COMMENT '수량',
  order_px   BIGINT    COMMENT '주문가',
  exec_amt   BIGINT    COMMENT '체결금액',
  channel    STRING    COMMENT '주문채널(결측 포함)',
  order_stat STRING    COMMENT '체결/미체결/취소'
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_주문_주문체결 (교육용 오염 데이터 포함)'

-- COMMAND ----------

INSERT INTO IDENTIFIER('eis_tr_order_' || :my_id)
SELECT order_id, base_date, CAST(order_ts AS TIMESTAMP), acct_no, stock_cd, side, qty, order_px, exec_amt, NULLIF(channel, ''), order_stat
FROM read_files('file:/Workspace/Shared/kpsec_handson/data/eis_tr_order.csv',
  format => 'csv', header => true,
  schema => 'order_id STRING, base_date STRING, order_ts STRING, acct_no STRING, stock_cd STRING, side STRING, qty INT, order_px BIGINT, exec_amt BIGINT, channel STRING, order_stat STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 앱 이벤트 `app_event_log_<my_id>` (JSON 반정형)

-- COMMAND ----------

CREATE OR REPLACE TABLE IDENTIFIER('app_event_log_' || :my_id) (
  event_id   STRING    COMMENT '이벤트ID',
  base_date  STRING    COMMENT '발생일 yyyymmdd',
  event_ts   TIMESTAMP COMMENT '발생시각',
  cust_no    STRING    COMMENT '고객번호',
  event_name STRING    COMMENT '이벤트명',
  screen     STRING    COMMENT '화면',
  props_json STRING    COMMENT '속성 JSON (os, app_ver, stock_cd)'
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_앱로그_앱이벤트'

-- COMMAND ----------

INSERT INTO IDENTIFIER('app_event_log_' || :my_id)
SELECT event_id, base_date, CAST(event_ts AS TIMESTAMP), cust_no, event_name, screen, props_json
FROM read_files('file:/Workspace/Shared/kpsec_handson/data/app_event_log.csv',
  format => 'csv', header => true, escape => '"',
  schema => 'event_id STRING, base_date STRING, event_ts STRING, cust_no STRING, event_name STRING, screen STRING, props_json STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 마트 예시 `daily_trade_kpi_<my_id>` (실습 정답 겸 KPI 형태)
-- MAGIC
-- MAGIC 중복 제거 + 음수 수량 제외 + 체결건만 집계합니다.

-- COMMAND ----------

CREATE OR REPLACE TABLE IDENTIFIER('daily_trade_kpi_' || :my_id)
COMMENT 'BIGDATA(DBX)_EDU_마트_일별거래KPI (중복 제거 후 집계)'
AS
WITH o AS (SELECT DISTINCT * FROM IDENTIFIER('eis_tr_order_' || :my_id) WHERE qty > 0 AND order_stat = '체결')
SELECT base_date,
       COUNT(DISTINCT acct_no) AS trade_acct_cnt,
       COUNT(*)                AS exec_cnt,
       SUM(exec_amt)           AS exec_amt
FROM o GROUP BY base_date

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 검증 — 행수 확인
-- MAGIC
-- MAGIC 기대값: `dim_stock` 10 · `stock_price_daily` 20 · `dim_customer` 20 · `eis_ac_account` 22 · `eis_tr_order` 22 · `daily_trade_kpi` 2(영업일 수)
-- MAGIC · `app_event_log` 79 (처음 공유한 CSV라면 10 → 아래 보정 INSERT 후 71)

-- COMMAND ----------

SELECT 'dim_stock' t, COUNT(*) c FROM IDENTIFIER('dim_stock_' || :my_id) UNION ALL
SELECT 'stock_price_daily', COUNT(*) FROM IDENTIFIER('stock_price_daily_' || :my_id) UNION ALL
SELECT 'dim_customer', COUNT(*) FROM IDENTIFIER('dim_customer_' || :my_id) UNION ALL
SELECT 'eis_ac_account', COUNT(*) FROM IDENTIFIER('eis_ac_account_' || :my_id) UNION ALL
SELECT 'eis_tr_order', COUNT(*) FROM IDENTIFIER('eis_tr_order_' || :my_id) UNION ALL
SELECT 'app_event_log', COUNT(*) FROM IDENTIFIER('app_event_log_' || :my_id) UNION ALL
SELECT 'daily_trade_kpi', COUNT(*) FROM IDENTIFIER('daily_trade_kpi_' || :my_id)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 다음: `02_exercises` 노트북으로 실습하세요. (같은 `my_id` 를 입력)
