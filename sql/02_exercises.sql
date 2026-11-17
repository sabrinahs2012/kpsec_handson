-- 교육 실습 문제 (난이도 순). 각 문제 아래 힌트/정답 쿼리 포함.
USE kpsec.sandbox_edu;

-- [1] 기본 조회: 종목별 최근 종가 상위 10
SELECT s.stock_nm, p.base_date, p.close_px
FROM stock_price_daily p JOIN dim_stock s USING (stock_cd)
WHERE p.base_date = (SELECT MAX(base_date) FROM stock_price_daily)
ORDER BY p.close_px DESC LIMIT 10;

-- [2] 데이터 품질: 주문 테이블 중복 / 음수 수량 / 채널 결측 건수
SELECT COUNT(*) total,
       COUNT(*) - COUNT(DISTINCT order_id) AS dup_rows,
       SUM(CASE WHEN qty <= 0 THEN 1 END) AS bad_qty,
       SUM(CASE WHEN channel IS NULL THEN 1 END) AS null_channel
FROM eis_tr_order;

-- [3] 조인+집계: 계좌유형별 월별 체결금액 (해지 계좌 제외)
SELECT a.acct_type_nm, SUBSTR(o.base_date, 1, 6) AS ym, SUM(o.exec_amt) AS amt
FROM (SELECT DISTINCT * FROM eis_tr_order WHERE qty > 0 AND order_stat = '체결') o
JOIN eis_ac_account a USING (acct_no)
WHERE a.acct_stat = '정상'
GROUP BY 1, 2 ORDER BY 2, 1;

-- [4] 윈도우 함수: 종목별 5일 이동평균 종가와 전일 대비 등락률
SELECT stock_cd, base_date, close_px,
       AVG(close_px) OVER (PARTITION BY stock_cd ORDER BY base_date ROWS 4 PRECEDING) AS ma5,
       close_px / LAG(close_px) OVER (PARTITION BY stock_cd ORDER BY base_date) - 1 AS chg_rate
FROM stock_price_daily
ORDER BY stock_cd, base_date LIMIT 50;

-- [5] 반정형 JSON: 앱 이벤트에서 OS별 주문 전환율 (order_start -> order_done)
SELECT props_json:os::string AS os,
       COUNT_IF(event_name = 'order_start') AS starts,
       COUNT_IF(event_name = 'order_done')  AS dones,
       ROUND(COUNT_IF(event_name = 'order_done') / COUNT_IF(event_name = 'order_start'), 3) AS conv
FROM app_event_log GROUP BY 1;

-- [6] 신규 계좌 월간 추이 (사내 KPI 형태): 개설월별 신규/해지/순증
SELECT SUBSTR(open_dt, 1, 6) AS ym, COUNT(*) AS new_accts
FROM eis_ac_account GROUP BY 1 ORDER BY 1;

-- [7] 코호트: 가입월별 고객의 첫 주문까지 걸린 일수 분포
WITH first_ord AS (
  SELECT a.cust_no, MIN(o.base_date) AS first_dt
  FROM eis_tr_order o JOIN eis_ac_account a USING (acct_no) GROUP BY 1)
SELECT SUBSTR(c.join_dt, 1, 4) AS join_yr,
       PERCENTILE(DATEDIFF(TO_DATE(f.first_dt, 'yyyyMMdd'), TO_DATE(c.join_dt, 'yyyyMMdd')), 0.5) AS median_days
FROM dim_customer c JOIN first_ord f USING (cust_no) GROUP BY 1 ORDER BY 1;

-- [8] 거버넌스 실습: 마스킹 뷰 + 권한 (교육 시연용, 권한 문장은 소유자만 실행)
CREATE OR REPLACE VIEW v_customer_safe AS
SELECT cust_no, age_grp, sido, join_channel, cust_grade, join_dt,
       CASE WHEN is_account_group_member('dbx_edu_unmask') THEN cust_nm_mask ELSE '' END AS cust_nm_mask
FROM dim_customer;
-- GRANT SELECT ON VIEW v_customer_safe TO `account users`;

-- [9] Delta 기능: 타임트래블 / 최적화 (잘못 지운 뒤 복구 시연)
-- DELETE FROM eis_tr_order WHERE order_stat = '미체결';
-- DESCRIBE HISTORY eis_tr_order;
-- RESTORE TABLE eis_tr_order TO VERSION AS OF 0;
OPTIMIZE eis_tr_order;
