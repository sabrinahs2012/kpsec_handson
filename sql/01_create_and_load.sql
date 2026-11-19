-- Databricks 교육용 샘플 테이블 생성 + 적재 (SQL Editor 실행용)
-- notebooks/01_load_tables.sql 과 같은 내용입니다.
--
-- [사전 준비 · 관리자] 공통 스키마 · 볼륨 생성 후 data/*.csv 6개를 볼륨에 업로드 (README 참고)
--   CREATE SCHEMA IF NOT EXISTS kpsec.sandbox_edu COMMENT '데이터브릭스 교육용 가상 데이터 (실데이터 아님)';
--   CREATE VOLUME IF NOT EXISTS kpsec.sandbox_edu.edu_raw COMMENT '교육용 CSV 원본';
--
-- [교육생] 아래부터 실행. 에디터 위쪽 파라미터 칸 my_id 에 본인 ID 입력 (영문 소문자 · 숫자 · _, 예: rian_bow)
--   → dim_stock_<my_id> 처럼 본인 이름이 붙은 테이블 7개가 만들어집니다.


-- ------------------------------------------------------------ 01. 내 테이블 생성 + 적재
SELECT assert_true(:my_id RLIKE '^[a-z][a-z0-9_]*$',
                   'my_id 위젯(파라미터)에 본인 ID를 영문 소문자 · 숫자 · _ 로 입력하세요 (예: rian_bow)') AS id_ok,
       :my_id AS my_id;
USE kpsec.sandbox_edu;

-- ------------------------------------------------------------ 종목 마스터 `dim_stock_<my_id>`
CREATE OR REPLACE TABLE IDENTIFIER('dim_stock_' || :my_id) (
  stock_cd STRING COMMENT '종목코드',
  stock_nm STRING COMMENT '종목명',
  market   STRING COMMENT '시장(KOSPI/KOSDAQ)',
  sector   STRING COMMENT '업종',
  list_dt  STRING COMMENT '상장일 yyyymmdd'
) COMMENT 'BIGDATA(DBX)_EDU_종목_종목마스터';
INSERT INTO IDENTIFIER('dim_stock_' || :my_id)
SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/dim_stock.csv',
  format => 'csv', header => true,
  schema => 'stock_cd STRING, stock_nm STRING, market STRING, sector STRING, list_dt STRING');

-- ------------------------------------------------------------ 일별 시세 `stock_price_daily_<my_id>`
CREATE OR REPLACE TABLE IDENTIFIER('stock_price_daily_' || :my_id) (
  base_date STRING COMMENT '기준일 yyyymmdd',
  stock_cd  STRING COMMENT '종목코드',
  open_px   BIGINT COMMENT '시가',
  high_px   BIGINT COMMENT '고가',
  low_px    BIGINT COMMENT '저가',
  close_px  BIGINT COMMENT '종가',
  volume    BIGINT COMMENT '거래량'
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_시세_일별시세';
INSERT INTO IDENTIFIER('stock_price_daily_' || :my_id)
SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/stock_price_daily.csv',
  format => 'csv', header => true,
  schema => 'base_date STRING, stock_cd STRING, open_px BIGINT, high_px BIGINT, low_px BIGINT, close_px BIGINT, volume BIGINT');

-- ------------------------------------------------------------ 고객 `dim_customer_<my_id>` (마스킹 컬럼 시연용)
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
) COMMENT 'BIGDATA(DBX)_EDU_고객_고객마스터';
INSERT INTO IDENTIFIER('dim_customer_' || :my_id)
SELECT * FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/dim_customer.csv',
  format => 'csv', header => true,
  schema => 'cust_no STRING, cust_nm_mask STRING, mobile_mask STRING, ci_hash STRING, age_grp STRING, sido STRING, join_channel STRING, cust_grade STRING, join_dt STRING, mkt_agree_yn STRING');

-- ------------------------------------------------------------ 계좌 원장 `eis_ac_account_<my_id>` (`eis_` = 계정계 원장)
CREATE OR REPLACE TABLE IDENTIFIER('eis_ac_account_' || :my_id) (
  acct_no      STRING COMMENT '계좌번호(가상 999-XX-XXXXXX)',
  cust_no      STRING COMMENT '고객번호',
  acct_type_cd STRING COMMENT '계좌유형코드',
  acct_type_nm STRING COMMENT '계좌유형명',
  open_dt      STRING COMMENT '개설일 yyyymmdd',
  close_dt     STRING COMMENT '해지일 yyyymmdd(미해지=빈값)',
  acct_stat    STRING COMMENT '계좌상태(정상/해지)'
) COMMENT 'BIGDATA(DBX)_EDU_계좌_계좌원장';
INSERT INTO IDENTIFIER('eis_ac_account_' || :my_id)
SELECT acct_no, cust_no, acct_type_cd, acct_type_nm, open_dt, NULLIF(close_dt, ''), acct_stat
FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/eis_ac_account.csv',
  format => 'csv', header => true,
  schema => 'acct_no STRING, cust_no STRING, acct_type_cd STRING, acct_type_nm STRING, open_dt STRING, close_dt STRING, acct_stat STRING');

-- ------------------------------------------------------------ 주문/체결 `eis_tr_order_<my_id>` (중복 · 음수수량 · 채널결측 포함)
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
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_주문_주문체결 (교육용 오염 데이터 포함)';
INSERT INTO IDENTIFIER('eis_tr_order_' || :my_id)
SELECT order_id, base_date, CAST(order_ts AS TIMESTAMP), acct_no, stock_cd, side, qty, order_px, exec_amt, NULLIF(channel, ''), order_stat
FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/eis_tr_order.csv',
  format => 'csv', header => true,
  schema => 'order_id STRING, base_date STRING, order_ts STRING, acct_no STRING, stock_cd STRING, side STRING, qty INT, order_px BIGINT, exec_amt BIGINT, channel STRING, order_stat STRING');

-- ------------------------------------------------------------ 앱 이벤트 `app_event_log_<my_id>` (JSON 반정형)
CREATE OR REPLACE TABLE IDENTIFIER('app_event_log_' || :my_id) (
  event_id   STRING    COMMENT '이벤트ID',
  base_date  STRING    COMMENT '발생일 yyyymmdd',
  event_ts   TIMESTAMP COMMENT '발생시각',
  cust_no    STRING    COMMENT '고객번호',
  event_name STRING    COMMENT '이벤트명',
  screen     STRING    COMMENT '화면',
  props_json STRING    COMMENT '속성 JSON (os, app_ver, stock_cd)'
) CLUSTER BY (base_date) COMMENT 'BIGDATA(DBX)_EDU_앱로그_앱이벤트';
INSERT INTO IDENTIFIER('app_event_log_' || :my_id)
SELECT event_id, base_date, CAST(event_ts AS TIMESTAMP), cust_no, event_name, screen, props_json
FROM read_files('/Volumes/kpsec/sandbox_edu/edu_raw/app_event_log.csv',
  format => 'csv', header => true, escape => '"',
  schema => 'event_id STRING, base_date STRING, event_ts STRING, cust_no STRING, event_name STRING, screen STRING, props_json STRING');

-- ------------------------------------------------------------ 마트 예시 `daily_trade_kpi_<my_id>` (실습 정답 겸 KPI 형태)
CREATE OR REPLACE TABLE IDENTIFIER('daily_trade_kpi_' || :my_id)
COMMENT 'BIGDATA(DBX)_EDU_마트_일별거래KPI (중복 제거 후 집계)'
AS
WITH o AS (SELECT DISTINCT * FROM IDENTIFIER('eis_tr_order_' || :my_id) WHERE qty > 0 AND order_stat = '체결')
SELECT base_date,
       COUNT(DISTINCT acct_no) AS trade_acct_cnt,
       COUNT(*)                AS exec_cnt,
       SUM(exec_amt)           AS exec_amt
FROM o GROUP BY base_date;

-- ------------------------------------------------------------ 검증 — 행수 확인
SELECT 'dim_stock' t, COUNT(*) c FROM IDENTIFIER('dim_stock_' || :my_id) UNION ALL
SELECT 'stock_price_daily', COUNT(*) FROM IDENTIFIER('stock_price_daily_' || :my_id) UNION ALL
SELECT 'dim_customer', COUNT(*) FROM IDENTIFIER('dim_customer_' || :my_id) UNION ALL
SELECT 'eis_ac_account', COUNT(*) FROM IDENTIFIER('eis_ac_account_' || :my_id) UNION ALL
SELECT 'eis_tr_order', COUNT(*) FROM IDENTIFIER('eis_tr_order_' || :my_id) UNION ALL
SELECT 'app_event_log', COUNT(*) FROM IDENTIFIER('app_event_log_' || :my_id) UNION ALL
SELECT 'daily_trade_kpi', COUNT(*) FROM IDENTIFIER('daily_trade_kpi_' || :my_id);

-- ------------------------------------------------------------ [보정] 앱 이벤트 주문 퍼널 데이터 추가 INSERT
INSERT INTO IDENTIFIER('app_event_log_' || :my_id)
SELECT v.* FROM VALUES
  ('E00000011', '20261029', TIMESTAMP '2026-10-29 10:31:01', '90000004', 'order_start', '주문', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900037"}'),
  ('E00000012', '20261029', TIMESTAMP '2026-10-29 12:53:39', '90000007', 'order_start', '주문', '{"os": "Android", "app_ver": "5.1.0", "stock_cd": "X900000"}'),
  ('E00000013', '20261030', TIMESTAMP '2026-10-30 10:41:33', '90000007', 'order_start', '주문', '{"os": "Android", "app_ver": "5.1.0", "stock_cd": "X900000"}'),
  ('E00000014', '20261030', TIMESTAMP '2026-10-30 14:07:40', '90000004', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900000"}'),
  ('E00000015', '20261030', TIMESTAMP '2026-10-30 14:10:09', '90000004', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900000"}'),
  ('E00000016', '20261030', TIMESTAMP '2026-10-30 14:09:39', '90000003', 'order_start', '주문', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900074"}'),
  ('E00000017', '20261030', TIMESTAMP '2026-10-30 14:10:40', '90000003', 'order_done', '주문완료', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900074"}'),
  ('E00000018', '20261029', TIMESTAMP '2026-10-29 11:43:59', '90000002', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.1.0", "stock_cd": "X900148"}'),
  ('E00000019', '20261030', TIMESTAMP '2026-10-30 15:09:14', '90000005', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900074"}'),
  ('E00000020', '20261030', TIMESTAMP '2026-10-30 15:09:57', '90000005', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900074"}'),
  ('E00000021', '20261030', TIMESTAMP '2026-10-30 15:09:21', '90000008', 'order_start', '주문', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900037"}'),
  ('E00000022', '20261030', TIMESTAMP '2026-10-30 10:20:31', '90000009', 'order_start', '주문', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900037"}'),
  ('E00000023', '20261030', TIMESTAMP '2026-10-30 10:38:36', '90000004', 'order_start', '주문', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000024', '20261029', TIMESTAMP '2026-10-29 12:20:12', '90000001', 'order_start', '주문', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900111"}'),
  ('E00000025', '20261030', TIMESTAMP '2026-10-30 15:22:23', '90000003', 'order_start', '주문', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000026', '20261030', TIMESTAMP '2026-10-30 15:22:31', '90000003', 'order_done', '주문완료', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000027', '20261029', TIMESTAMP '2026-10-29 12:07:07', '90000007', 'order_start', '주문', '{"os": "Android", "app_ver": "5.1.0", "stock_cd": "X900074"}'),
  ('E00000028', '20261030', TIMESTAMP '2026-10-30 13:54:51', '90000003', 'order_start', '주문', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000029', '20261030', TIMESTAMP '2026-10-30 09:01:18', '90000005', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.1.0", "stock_cd": "X900074"}'),
  ('E00000030', '20261030', TIMESTAMP '2026-10-30 09:03:16', '90000005', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.1.0", "stock_cd": "X900074"}'),
  ('E00000031', '20261030', TIMESTAMP '2026-10-30 11:02:51', '90000003', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.1.0", "stock_cd": "X900111"}'),
  ('E00000032', '20261030', TIMESTAMP '2026-10-30 13:36:05', '90000008', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900074"}'),
  ('E00000033', '20261030', TIMESTAMP '2026-10-30 13:37:43', '90000008', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900074"}'),
  ('E00000034', '20261030', TIMESTAMP '2026-10-30 13:41:42', '90000006', 'order_start', '주문', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000035', '20261030', TIMESTAMP '2026-10-30 13:44:12', '90000006', 'order_done', '주문완료', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000036', '20261030', TIMESTAMP '2026-10-30 10:38:16', '90000005', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.1.0", "stock_cd": "X900000"}'),
  ('E00000037', '20261030', TIMESTAMP '2026-10-30 10:38:49', '90000005', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.1.0", "stock_cd": "X900000"}'),
  ('E00000038', '20261030', TIMESTAMP '2026-10-30 11:02:16', '90000001', 'order_start', '주문', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000039', '20261030', TIMESTAMP '2026-10-30 11:04:36', '90000001', 'order_done', '주문완료', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000041', '20261030', TIMESTAMP '2026-10-30 23:16:51', '90000013', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900037"}'),
  ('E00000046', '20261030', TIMESTAMP '2026-10-30 23:20:16', '90000011', 'order_start', '주문', '{"os": "Android", "app_ver": "5.1.0", "stock_cd": "X900000"}'),
  ('E00000050', '20261029', TIMESTAMP '2026-10-29 09:51:05', '90000020', 'order_start', '주문', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900074"}'),
  ('E00000051', '20261030', TIMESTAMP '2026-10-30 10:04:03', '90000006', 'order_start', '주문', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900259"}'),
  ('E00000052', '20261030', TIMESTAMP '2026-10-30 10:05:43', '90000006', 'order_done', '주문완료', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900259"}'),
  ('E00000053', '20261030', TIMESTAMP '2026-10-30 14:25:20', '90000001', 'order_start', '주문', '{"os": "Android", "app_ver": "5.1.0", "stock_cd": "X900296"}'),
  ('E00000054', '20261029', TIMESTAMP '2026-10-29 13:13:44', '90000010', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900037"}'),
  ('E00000055', '20261029', TIMESTAMP '2026-10-29 12:31:42', '90000002', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900111"}'),
  ('E00000056', '20261030', TIMESTAMP '2026-10-30 13:19:14', '90000020', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900259"}'),
  ('E00000057', '20261030', TIMESTAMP '2026-10-30 11:07:19', '90000018', 'order_start', '주문', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900148"}'),
  ('E00000058', '20261029', TIMESTAMP '2026-10-29 15:05:28', '90000020', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900111"}'),
  ('E00000059', '20261029', TIMESTAMP '2026-10-29 15:07:29', '90000020', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900111"}'),
  ('E00000060', '20261029', TIMESTAMP '2026-10-29 12:37:12', '90000016', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900296"}'),
  ('E00000061', '20261029', TIMESTAMP '2026-10-29 12:38:21', '90000016', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900296"}'),
  ('E00000062', '20261030', TIMESTAMP '2026-10-30 12:57:33', '90000015', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000063', '20261030', TIMESTAMP '2026-10-30 13:00:21', '90000015', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000064', '20261029', TIMESTAMP '2026-10-29 14:18:06', '90000011', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.2.0", "stock_cd": "X900111"}'),
  ('E00000065', '20261030', TIMESTAMP '2026-10-30 11:39:26', '90000011', 'order_start', '주문', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900000"}'),
  ('E00000066', '20261029', TIMESTAMP '2026-10-29 15:02:37', '90000005', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900074"}'),
  ('E00000067', '20261029', TIMESTAMP '2026-10-29 15:05:03', '90000005', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900074"}'),
  ('E00000068', '20261029', TIMESTAMP '2026-10-29 13:45:18', '90000014', 'order_start', '주문', '{"os": "Android", "app_ver": "5.1.0", "stock_cd": "X900148"}'),
  ('E00000069', '20261029', TIMESTAMP '2026-10-29 13:47:57', '90000014', 'order_done', '주문완료', '{"os": "Android", "app_ver": "5.1.0", "stock_cd": "X900148"}'),
  ('E00000070', '20261030', TIMESTAMP '2026-10-30 14:41:01', '90000003', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000071', '20261030', TIMESTAMP '2026-10-30 14:43:34', '90000003', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000072', '20261030', TIMESTAMP '2026-10-30 13:20:24', '90000008', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.1.0", "stock_cd": "X900037"}'),
  ('E00000073', '20261030', TIMESTAMP '2026-10-30 13:20:30', '90000008', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.1.0", "stock_cd": "X900037"}'),
  ('E00000074', '20261029', TIMESTAMP '2026-10-29 10:05:07', '90000013', 'order_start', '주문', '{"os": "Android", "app_ver": "5.1.0", "stock_cd": "X900111"}'),
  ('E00000075', '20261029', TIMESTAMP '2026-10-29 11:11:08', '90000010', 'order_start', '주문', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900037"}'),
  ('E00000076', '20261029', TIMESTAMP '2026-10-29 11:13:12', '90000010', 'order_done', '주문완료', '{"os": "Android", "app_ver": "5.3.1", "stock_cd": "X900037"}'),
  ('E00000077', '20261030', TIMESTAMP '2026-10-30 12:34:05', '90000004', 'order_start', '주문', '{"os": "Android", "app_ver": "5.2.0", "stock_cd": "X900074"}'),
  ('E00000078', '20261029', TIMESTAMP '2026-10-29 14:51:29', '90000018', 'order_start', '주문', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900000"}'),
  ('E00000079', '20261029', TIMESTAMP '2026-10-29 14:53:35', '90000018', 'order_done', '주문완료', '{"os": "iOS", "app_ver": "5.3.1", "stock_cd": "X900000"}')
AS v(event_id, base_date, event_ts, cust_no, event_name, screen, props_json)
WHERE v.event_id NOT IN (SELECT event_id FROM IDENTIFIER('app_event_log_' || :my_id));
SELECT event_name, COUNT(*) AS cnt
FROM IDENTIFIER('app_event_log_' || :my_id)
GROUP BY 1 ORDER BY 2 DESC;
