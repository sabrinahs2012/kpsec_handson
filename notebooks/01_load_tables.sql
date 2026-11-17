-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 01. 테이블 생성 + 적재
-- MAGIC
-- MAGIC README `사용 순서` 의 **3단계** (`sql/01_create_and_load.sql` 의 나머지 부분 + 검증 쿼리).
-- MAGIC
-- MAGIC - 사전 조건: `00_setup_and_upload` 실행 완료 (Volume 에 CSV 6개)
-- MAGIC - 사내 관례: `base_date` = STRING `yyyymmdd`, 원장성 테이블은 `eis_` 접두사, 코멘트 = `BIGDATA(DBX)_<소스>_<업무>_<한글명>`
-- MAGIC - 모든 테이블은 `CREATE OR REPLACE` 라서 **다시 실행해도 안전**합니다.
-- MAGIC
-- MAGIC > `sql/01_create_and_load.sql` 은 `CREATE TABLE (컬럼 정의) AS SELECT` 형태인데, 런타임에 따라 이 문법이 실패할 수 있어
-- MAGIC > 이 노트북은 **`CREATE TABLE (컬럼 정의)` → `INSERT INTO ... SELECT`** 두 단계로 나눠 실행합니다. (결과 동일)

-- COMMAND ----------

USE kpsec.sandbox_edu

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 종목 마스터 `dim_stock`

-- COMMAND ----------

CREATE OR REPLACE TABLE dim_stock (
  stock_cd STRING COMMENT '종목코드',
  stock_nm STRING COMMENT '종목명',
  market   STRING COMMENT '시장(KOSPI/KOSDAQ)',
  sector   STRING COMMENT '업종',
  list_dt  STRING COMMENT '상장일 yyyymmdd'
) COMMENT 'BIGDATA(DBX)_EDU_종목_종목마스터'

-- COMMAND ----------

INSERT INTO dim_stock
SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/dim_stock.csv',
  format => 'csv', header => true,
  schema => 'stock_cd STRING, stock_nm STRING, market STRING, sector STRING, list_dt STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 일별 시세 `stock_price_daily`

-- COMMAND ----------

CREATE OR REPLACE TABLE stock_price_daily (
  base_date STRING COMMENT '기준일 yyyymmdd',
  stock_cd  STRING COMMENT '종목코드',
  open_px   BIGINT COMMENT '시가',
  high_px   BIGINT COMMENT '고가',
  low_px    BIGINT COMMENT '저가',
  close_px  BIGINT COMMENT '종가',
  volume    BIGINT COMMENT '거래량'
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_시세_일별시세'

-- COMMAND ----------

INSERT INTO stock_price_daily
SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/stock_price_daily.csv',
  format => 'csv', header => true,
  schema => 'base_date STRING, stock_cd STRING, open_px BIGINT, high_px BIGINT, low_px BIGINT, close_px BIGINT, volume BIGINT')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 고객 `dim_customer` (마스킹 컬럼 시연용)

-- COMMAND ----------

CREATE OR REPLACE TABLE dim_customer (
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

INSERT INTO dim_customer
SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/dim_customer.csv',
  format => 'csv', header => true,
  schema => 'cust_no STRING, cust_nm_mask STRING, mobile_mask STRING, ci_hash STRING, age_grp STRING, sido STRING, join_channel STRING, cust_grade STRING, join_dt STRING, mkt_agree_yn STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 계좌 원장 `eis_ac_account` (`eis_` = 계정계 원장)

-- COMMAND ----------

CREATE OR REPLACE TABLE eis_ac_account (
  acct_no      STRING COMMENT '계좌번호(가상 999-XX-XXXXXX)',
  cust_no      STRING COMMENT '고객번호',
  acct_type_cd STRING COMMENT '계좌유형코드',
  acct_type_nm STRING COMMENT '계좌유형명',
  open_dt      STRING COMMENT '개설일 yyyymmdd',
  close_dt     STRING COMMENT '해지일 yyyymmdd(미해지=빈값)',
  acct_stat    STRING COMMENT '계좌상태(정상/해지)'
) COMMENT 'BIGDATA(DBX)_EDU_계좌_계좌원장'

-- COMMAND ----------

INSERT INTO eis_ac_account
SELECT acct_no, cust_no, acct_type_cd, acct_type_nm, open_dt, NULLIF(close_dt, ''), acct_stat
FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/eis_ac_account.csv',
  format => 'csv', header => true,
  schema => 'acct_no STRING, cust_no STRING, acct_type_cd STRING, acct_type_nm STRING, open_dt STRING, close_dt STRING, acct_stat STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 주문/체결 `eis_tr_order` (중복 · 음수수량 · 채널결측 포함)

-- COMMAND ----------

CREATE OR REPLACE TABLE eis_tr_order (
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

INSERT INTO eis_tr_order
SELECT order_id, base_date, CAST(order_ts AS TIMESTAMP), acct_no, stock_cd, side, qty, order_px, exec_amt, NULLIF(channel, ''), order_stat
FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/eis_tr_order.csv',
  format => 'csv', header => true,
  schema => 'order_id STRING, base_date STRING, order_ts STRING, acct_no STRING, stock_cd STRING, side STRING, qty INT, order_px BIGINT, exec_amt BIGINT, channel STRING, order_stat STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 앱 이벤트 `app_event_log` (JSON 반정형)

-- COMMAND ----------

CREATE OR REPLACE TABLE app_event_log (
  event_id   STRING    COMMENT '이벤트ID',
  base_date  STRING    COMMENT '발생일 yyyymmdd',
  event_ts   TIMESTAMP COMMENT '발생시각',
  cust_no    STRING    COMMENT '고객번호',
  event_name STRING    COMMENT '이벤트명',
  screen     STRING    COMMENT '화면',
  props_json STRING    COMMENT '속성 JSON (os, app_ver, stock_cd)'
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_앱로그_앱이벤트'

-- COMMAND ----------

INSERT INTO app_event_log
SELECT event_id, base_date, CAST(event_ts AS TIMESTAMP), cust_no, event_name, screen, props_json
FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/app_event_log.csv',
  format => 'csv', header => true, escape => '"',
  schema => 'event_id STRING, base_date STRING, event_ts STRING, cust_no STRING, event_name STRING, screen STRING, props_json STRING')

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 마트 예시 `daily_trade_kpi` (실습 정답 겸 KPI 형태)
-- MAGIC
-- MAGIC 중복 제거 + 음수 수량 제외 + 체결건만 집계합니다.

-- COMMAND ----------

CREATE OR REPLACE TABLE daily_trade_kpi
COMMENT 'BIGDATA(DBX)_EDU_마트_일별거래KPI (중복 제거 후 집계)'
AS
WITH o AS (SELECT DISTINCT * FROM eis_tr_order WHERE qty > 0 AND order_stat = '체결')
SELECT base_date,
       COUNT(DISTINCT acct_no) AS trade_acct_cnt,
       COUNT(*)                AS exec_cnt,
       SUM(exec_amt)           AS exec_amt
FROM o GROUP BY base_date

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## 검증 — 행수 확인
-- MAGIC
-- MAGIC 기대값: `dim_stock` 10 · `stock_price_daily` 20 · `dim_customer` 20 · `eis_ac_account` 22 · `eis_tr_order` 22 · `app_event_log` 79 · `daily_trade_kpi` 2(영업일 수)

-- COMMAND ----------

SELECT 'dim_stock' t, COUNT(*) c FROM dim_stock UNION ALL
SELECT 'stock_price_daily', COUNT(*) FROM stock_price_daily UNION ALL
SELECT 'dim_customer', COUNT(*) FROM dim_customer UNION ALL
SELECT 'eis_ac_account', COUNT(*) FROM eis_ac_account UNION ALL
SELECT 'eis_tr_order', COUNT(*) FROM eis_tr_order UNION ALL
SELECT 'app_event_log', COUNT(*) FROM app_event_log UNION ALL
SELECT 'daily_trade_kpi', COUNT(*) FROM daily_trade_kpi

-- COMMAND ----------

-- MAGIC %md
-- MAGIC 다음: `02_exercises` 노트북으로 실습하세요.
