# Databricks notebook source
# MAGIC %md
# MAGIC # 01. 테이블 생성 + 적재
# MAGIC
# MAGIC README `사용 순서` 의 **4단계** (`sql/01_create_and_load.sql` 의 나머지 부분 + 검증 쿼리).
# MAGIC
# MAGIC - 사전 조건: `00_setup_and_upload` 실행 완료 (Volume 에 CSV 6개)
# MAGIC - 사내 관례: `base_date` = STRING `yyyymmdd`, 원장성 테이블은 `eis_` 접두사, 코멘트 = `BIGDATA(DBX)_<소스>_<업무>_<한글명>`
# MAGIC - 모든 테이블은 `CREATE OR REPLACE` 라서 **다시 실행해도 안전**합니다.
# MAGIC
# MAGIC > `sql/01_create_and_load.sql` 은 `CREATE TABLE (컬럼 정의) AS SELECT` 형태인데, 런타임에 따라 이 문법이 실패할 수 있어
# MAGIC > 이 노트북은 **`CREATE TABLE (컬럼 정의)` → `INSERT INTO ... SELECT`** 두 단계로 나눠 실행합니다. (결과 동일)

# COMMAND ----------

# MAGIC %sql
# MAGIC USE kpsec.sandbox_edu

# COMMAND ----------

# MAGIC %md
# MAGIC ## 종목 마스터 `dim_stock`

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE dim_stock (
# MAGIC   stock_cd STRING COMMENT '종목코드',
# MAGIC   stock_nm STRING COMMENT '종목명',
# MAGIC   market   STRING COMMENT '시장(KOSPI/KOSDAQ)',
# MAGIC   sector   STRING COMMENT '업종',
# MAGIC   list_dt  STRING COMMENT '상장일 yyyymmdd'
# MAGIC ) COMMENT 'BIGDATA(DBX)_EDU_종목_종목마스터'

# COMMAND ----------

# MAGIC %sql
# MAGIC INSERT INTO dim_stock
# MAGIC SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/dim_stock.csv',
# MAGIC   format => 'csv', header => true,
# MAGIC   schema => 'stock_cd STRING, stock_nm STRING, market STRING, sector STRING, list_dt STRING')

# COMMAND ----------

# MAGIC %md
# MAGIC ## 일별 시세 `stock_price_daily`

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE stock_price_daily (
# MAGIC   base_date STRING COMMENT '기준일 yyyymmdd',
# MAGIC   stock_cd  STRING COMMENT '종목코드',
# MAGIC   open_px   BIGINT COMMENT '시가',
# MAGIC   high_px   BIGINT COMMENT '고가',
# MAGIC   low_px    BIGINT COMMENT '저가',
# MAGIC   close_px  BIGINT COMMENT '종가',
# MAGIC   volume    BIGINT COMMENT '거래량'
# MAGIC ) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_시세_일별시세'

# COMMAND ----------

# MAGIC %sql
# MAGIC INSERT INTO stock_price_daily
# MAGIC SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/stock_price_daily.csv',
# MAGIC   format => 'csv', header => true,
# MAGIC   schema => 'base_date STRING, stock_cd STRING, open_px BIGINT, high_px BIGINT, low_px BIGINT, close_px BIGINT, volume BIGINT')

# COMMAND ----------

# MAGIC %md
# MAGIC ## 고객 `dim_customer` (마스킹 컬럼 시연용)

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE dim_customer (
# MAGIC   cust_no      STRING COMMENT '고객번호(가상 9xxxxxxx)',
# MAGIC   cust_nm_mask STRING COMMENT '고객명(마스킹)',
# MAGIC   mobile_mask  STRING COMMENT '휴대폰(마스킹)',
# MAGIC   ci_hash      STRING COMMENT 'CI 해시(가상)',
# MAGIC   age_grp      STRING COMMENT '연령대',
# MAGIC   sido         STRING COMMENT '거주지역',
# MAGIC   join_channel STRING COMMENT '가입채널',
# MAGIC   cust_grade   STRING COMMENT '고객등급',
# MAGIC   join_dt      STRING COMMENT '가입일 yyyymmdd',
# MAGIC   mkt_agree_yn STRING COMMENT '마케팅동의여부(결측 포함)'
# MAGIC ) COMMENT 'BIGDATA(DBX)_EDU_고객_고객마스터'

# COMMAND ----------

# MAGIC %sql
# MAGIC INSERT INTO dim_customer
# MAGIC SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/dim_customer.csv',
# MAGIC   format => 'csv', header => true,
# MAGIC   schema => 'cust_no STRING, cust_nm_mask STRING, mobile_mask STRING, ci_hash STRING, age_grp STRING, sido STRING, join_channel STRING, cust_grade STRING, join_dt STRING, mkt_agree_yn STRING')

# COMMAND ----------

# MAGIC %md
# MAGIC ## 계좌 원장 `eis_ac_account` (`eis_` = 계정계 원장)

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE eis_ac_account (
# MAGIC   acct_no      STRING COMMENT '계좌번호(가상 999-XX-XXXXXX)',
# MAGIC   cust_no      STRING COMMENT '고객번호',
# MAGIC   acct_type_cd STRING COMMENT '계좌유형코드',
# MAGIC   acct_type_nm STRING COMMENT '계좌유형명',
# MAGIC   open_dt      STRING COMMENT '개설일 yyyymmdd',
# MAGIC   close_dt     STRING COMMENT '해지일 yyyymmdd(미해지=빈값)',
# MAGIC   acct_stat    STRING COMMENT '계좌상태(정상/해지)'
# MAGIC ) COMMENT 'BIGDATA(DBX)_EDU_계좌_계좌원장'

# COMMAND ----------

# MAGIC %sql
# MAGIC INSERT INTO eis_ac_account
# MAGIC SELECT acct_no, cust_no, acct_type_cd, acct_type_nm, open_dt, NULLIF(close_dt, ''), acct_stat
# MAGIC FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/eis_ac_account.csv',
# MAGIC   format => 'csv', header => true,
# MAGIC   schema => 'acct_no STRING, cust_no STRING, acct_type_cd STRING, acct_type_nm STRING, open_dt STRING, close_dt STRING, acct_stat STRING')

# COMMAND ----------

# MAGIC %md
# MAGIC ## 주문/체결 `eis_tr_order` (중복 · 음수수량 · 채널결측 포함)

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE eis_tr_order (
# MAGIC   order_id   STRING    COMMENT '주문번호',
# MAGIC   base_date  STRING    COMMENT '주문일 yyyymmdd',
# MAGIC   order_ts   TIMESTAMP COMMENT '주문시각',
# MAGIC   acct_no    STRING    COMMENT '계좌번호',
# MAGIC   stock_cd   STRING    COMMENT '종목코드',
# MAGIC   side       STRING    COMMENT '매수/매도',
# MAGIC   qty        INT       COMMENT '수량',
# MAGIC   order_px   BIGINT    COMMENT '주문가',
# MAGIC   exec_amt   BIGINT    COMMENT '체결금액',
# MAGIC   channel    STRING    COMMENT '주문채널(결측 포함)',
# MAGIC   order_stat STRING    COMMENT '체결/미체결/취소'
# MAGIC ) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_주문_주문체결 (교육용 오염 데이터 포함)'

# COMMAND ----------

# MAGIC %sql
# MAGIC INSERT INTO eis_tr_order
# MAGIC SELECT order_id, base_date, CAST(order_ts AS TIMESTAMP), acct_no, stock_cd, side, qty, order_px, exec_amt, NULLIF(channel, ''), order_stat
# MAGIC FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/eis_tr_order.csv',
# MAGIC   format => 'csv', header => true,
# MAGIC   schema => 'order_id STRING, base_date STRING, order_ts STRING, acct_no STRING, stock_cd STRING, side STRING, qty INT, order_px BIGINT, exec_amt BIGINT, channel STRING, order_stat STRING')

# COMMAND ----------

# MAGIC %md
# MAGIC ## 앱 이벤트 `app_event_log` (JSON 반정형)

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE app_event_log (
# MAGIC   event_id   STRING    COMMENT '이벤트ID',
# MAGIC   base_date  STRING    COMMENT '발생일 yyyymmdd',
# MAGIC   event_ts   TIMESTAMP COMMENT '발생시각',
# MAGIC   cust_no    STRING    COMMENT '고객번호',
# MAGIC   event_name STRING    COMMENT '이벤트명',
# MAGIC   screen     STRING    COMMENT '화면',
# MAGIC   props_json STRING    COMMENT '속성 JSON (os, app_ver, stock_cd)'
# MAGIC ) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_앱로그_앱이벤트'

# COMMAND ----------

# MAGIC %sql
# MAGIC INSERT INTO app_event_log
# MAGIC SELECT event_id, base_date, CAST(event_ts AS TIMESTAMP), cust_no, event_name, screen, props_json
# MAGIC FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/app_event_log.csv',
# MAGIC   format => 'csv', header => true, escape => '"',
# MAGIC   schema => 'event_id STRING, base_date STRING, event_ts STRING, cust_no STRING, event_name STRING, screen STRING, props_json STRING')

# COMMAND ----------

# MAGIC %md
# MAGIC ## 마트 예시 `daily_trade_kpi` (실습 정답 겸 KPI 형태)
# MAGIC
# MAGIC 중복 제거 + 음수 수량 제외 + 체결건만 집계합니다.

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TABLE daily_trade_kpi
# MAGIC COMMENT 'BIGDATA(DBX)_EDU_마트_일별거래KPI (중복 제거 후 집계)'
# MAGIC AS
# MAGIC WITH o AS (SELECT DISTINCT * FROM eis_tr_order WHERE qty > 0 AND order_stat = '체결')
# MAGIC SELECT base_date,
# MAGIC        COUNT(DISTINCT acct_no) AS trade_acct_cnt,
# MAGIC        COUNT(*)                AS exec_cnt,
# MAGIC        SUM(exec_amt)           AS exec_amt
# MAGIC FROM o GROUP BY base_date

# COMMAND ----------

# MAGIC %md
# MAGIC ## 검증 — 행수 확인
# MAGIC
# MAGIC 기대값: `dim_stock` 5 · `stock_price_daily` 10 · `dim_customer` 10 · `eis_ac_account` 11 · `eis_tr_order` 11 · `app_event_log` 10 · `daily_trade_kpi` 2(영업일 수)

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT 'dim_stock' t, COUNT(*) c FROM dim_stock UNION ALL
# MAGIC SELECT 'stock_price_daily', COUNT(*) FROM stock_price_daily UNION ALL
# MAGIC SELECT 'dim_customer', COUNT(*) FROM dim_customer UNION ALL
# MAGIC SELECT 'eis_ac_account', COUNT(*) FROM eis_ac_account UNION ALL
# MAGIC SELECT 'eis_tr_order', COUNT(*) FROM eis_tr_order UNION ALL
# MAGIC SELECT 'app_event_log', COUNT(*) FROM app_event_log UNION ALL
# MAGIC SELECT 'daily_trade_kpi', COUNT(*) FROM daily_trade_kpi

# COMMAND ----------

# MAGIC %md
# MAGIC 다음: `02_exercises` 노트북으로 실습하세요.
