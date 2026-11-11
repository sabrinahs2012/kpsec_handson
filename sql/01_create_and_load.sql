-- Databricks 교육용 샘플 테이블 생성 + 적재
-- 사전 준비: data/*.csv 를 Volume 에 업로드 (README 참고)
--   /Volumes/kpsec/sandbox_edu/edu_raw/   (또는 아래 경로를 :volume_path 로 교체)
-- 실행 위치: sandbox 워크스페이스, 교육 참가자 쓰기 가능한 스키마
-- 사내 관례: base_date = STRING yyyymmdd, 코멘트 = BIGDATA(DBX)_<소스>_<업무>_<한글명>

CREATE SCHEMA IF NOT EXISTS kpsec.sandbox_edu COMMENT '데이터브릭스 교육용 가상 데이터 (실데이터 아님)';
USE kpsec.sandbox_edu;
CREATE VOLUME IF NOT EXISTS edu_raw COMMENT '교육용 CSV 원본';

-- ---------------------------------------------------------------- 종목 마스터
CREATE OR REPLACE TABLE dim_stock (
  stock_cd STRING COMMENT '종목코드',
  stock_nm STRING COMMENT '종목명',
  market   STRING COMMENT '시장(KOSPI/KOSDAQ)',
  sector   STRING COMMENT '업종',
  list_dt  STRING COMMENT '상장일 yyyymmdd'
) COMMENT 'BIGDATA(DBX)_EDU_종목_종목마스터'
AS SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/dim_stock.csv',
  format => 'csv', header => true, schema => 'stock_cd STRING, stock_nm STRING, market STRING, sector STRING, list_dt STRING');

-- ---------------------------------------------------------------- 일별 시세
CREATE OR REPLACE TABLE stock_price_daily (
  base_date STRING COMMENT '기준일 yyyymmdd',
  stock_cd  STRING COMMENT '종목코드',
  open_px BIGINT COMMENT '시가', high_px BIGINT COMMENT '고가', low_px BIGINT COMMENT '저가',
  close_px BIGINT COMMENT '종가', volume BIGINT COMMENT '거래량'
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_시세_일별시세'
AS SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/stock_price_daily.csv',
  format => 'csv', header => true,
  schema => 'base_date STRING, stock_cd STRING, open_px BIGINT, high_px BIGINT, low_px BIGINT, close_px BIGINT, volume BIGINT');

-- ---------------------------------------------------------------- 고객 (마스킹 컬럼 시연용)
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
AS SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/dim_customer.csv',
  format => 'csv', header => true,
  schema => 'cust_no STRING, cust_nm_mask STRING, mobile_mask STRING, ci_hash STRING, age_grp STRING, sido STRING, join_channel STRING, cust_grade STRING, join_dt STRING, mkt_agree_yn STRING');

-- ---------------------------------------------------------------- 계좌 원장 (eis_ 접두사 = 계정계 원장)
CREATE OR REPLACE TABLE eis_ac_account (
  acct_no      STRING COMMENT '계좌번호(가상 999-XX-XXXXXX)',
  cust_no      STRING COMMENT '고객번호',
  acct_type_cd STRING COMMENT '계좌유형코드',
  acct_type_nm STRING COMMENT '계좌유형명',
  open_dt      STRING COMMENT '개설일 yyyymmdd',
  close_dt     STRING COMMENT '해지일 yyyymmdd(미해지=빈값)',
  acct_stat    STRING COMMENT '계좌상태(정상/해지)'
) COMMENT 'BIGDATA(DBX)_EDU_계좌_계좌원장'
AS SELECT acct_no, cust_no, acct_type_cd, acct_type_nm, open_dt, NULLIF(close_dt, ''), acct_stat
FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/eis_ac_account.csv',
  format => 'csv', header => true,
  schema => 'acct_no STRING, cust_no STRING, acct_type_cd STRING, acct_type_nm STRING, open_dt STRING, close_dt STRING, acct_stat STRING');

-- ---------------------------------------------------------------- 주문/체결 (중복·음수수량·채널결측 포함)
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
AS SELECT order_id, base_date, CAST(order_ts AS TIMESTAMP), acct_no, stock_cd, side, qty, order_px, exec_amt, NULLIF(channel, ''), order_stat
FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/eis_tr_order.csv',
  format => 'csv', header => true,
  schema => 'order_id STRING, base_date STRING, order_ts STRING, acct_no STRING, stock_cd STRING, side STRING, qty INT, order_px BIGINT, exec_amt BIGINT, channel STRING, order_stat STRING');

-- ---------------------------------------------------------------- 앱 이벤트 (JSON 반정형)
CREATE OR REPLACE TABLE app_event_log (
  event_id   STRING    COMMENT '이벤트ID',
  base_date  STRING    COMMENT '발생일 yyyymmdd',
  event_ts   TIMESTAMP COMMENT '발생시각',
  cust_no    STRING    COMMENT '고객번호',
  event_name STRING    COMMENT '이벤트명',
  screen     STRING    COMMENT '화면',
  props_json STRING    COMMENT '속성 JSON (os, app_ver, stock_cd)'
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_앱로그_앱이벤트'
AS SELECT event_id, base_date, CAST(event_ts AS TIMESTAMP), cust_no, event_name, screen, props_json
FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/app_event_log.csv',
  format => 'csv', header => true,
  schema => 'event_id STRING, base_date STRING, event_ts STRING, cust_no STRING, event_name STRING, screen STRING, props_json STRING');

-- ---------------------------------------------------------------- 마트 예시 (실습 정답 겸 KPI 형태)
CREATE OR REPLACE TABLE daily_trade_kpi
COMMENT 'BIGDATA(DBX)_EDU_마트_일별거래KPI (중복 제거 후 집계)'
AS
WITH o AS (SELECT DISTINCT * FROM eis_tr_order WHERE qty > 0 AND order_stat = '체결')
SELECT base_date,
       COUNT(DISTINCT acct_no) AS trade_acct_cnt,
       COUNT(*)                AS exec_cnt,
       SUM(exec_amt)           AS exec_amt
FROM o GROUP BY base_date;

-- 검증
SELECT 'dim_stock' t, COUNT(*) c FROM dim_stock UNION ALL
SELECT 'stock_price_daily', COUNT(*) FROM stock_price_daily UNION ALL
SELECT 'dim_customer', COUNT(*) FROM dim_customer UNION ALL
SELECT 'eis_ac_account', COUNT(*) FROM eis_ac_account UNION ALL
SELECT 'eis_tr_order', COUNT(*) FROM eis_tr_order UNION ALL
SELECT 'app_event_log', COUNT(*) FROM app_event_log UNION ALL
SELECT 'daily_trade_kpi', COUNT(*) FROM daily_trade_kpi;
