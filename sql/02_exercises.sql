-- 교육 실습 문제 (난이도 순, SQL Editor 실행용). notebooks/02_exercises.sql 과 같은 내용입니다.
-- 에디터 왼쪽 { } 아이콘(Parameters) 패널의 my_id 에 01 과 같은 본인 ID 를 입력하세요.


-- ------------------------------------------------------------ 02. 실습 문제
SELECT assert_true(:my_id RLIKE '^[a-z][a-z0-9_]*$',
                   '왼쪽 { } 아이콘 → Parameters 패널 my_id 에 01_load_tables 와 같은 ID를 입력하세요 (예: rian_bow)') AS id_ok,
       :my_id AS my_id;
USE kpsec.sandbox_edu;

-- ------------------------------------------------------------ [1] 기본 조회: 종목별 최근 종가 상위 10
SELECT s.stock_nm, p.base_date, p.close_px
FROM IDENTIFIER('stock_price_daily_' || :my_id) p
JOIN IDENTIFIER('dim_stock_' || :my_id) s USING (stock_cd)
WHERE p.base_date = (SELECT MAX(base_date) FROM IDENTIFIER('stock_price_daily_' || :my_id))
ORDER BY p.close_px DESC LIMIT 10;

-- ------------------------------------------------------------ [2] 데이터 품질: 주문 테이블 중복 / 음수 수량 / 채널 결측 건수
SELECT COUNT(*) total,
       COUNT(*) - COUNT(DISTINCT order_id) AS dup_rows,
       SUM(CASE WHEN qty <= 0 THEN 1 END) AS bad_qty,
       SUM(CASE WHEN channel IS NULL THEN 1 END) AS null_channel
FROM IDENTIFIER('eis_tr_order_' || :my_id);

-- ------------------------------------------------------------ [3] 조인+집계: 계좌유형별 월별 체결금액 (해지 계좌 제외)
SELECT a.acct_type_nm, SUBSTR(o.base_date, 1, 6) AS ym, SUM(o.exec_amt) AS amt
FROM (SELECT DISTINCT * FROM IDENTIFIER('eis_tr_order_' || :my_id)
      WHERE qty > 0 AND order_stat = '체결') o
JOIN IDENTIFIER('eis_ac_account_' || :my_id) a USING (acct_no)
WHERE a.acct_stat = '정상'
GROUP BY 1, 2 ORDER BY 2, 1;

-- ------------------------------------------------------------ [4] 윈도우 함수: 종목별 5일 이동평균 종가와 전일 대비 등락률
SELECT stock_cd, base_date, close_px,
       AVG(close_px) OVER (PARTITION BY stock_cd ORDER BY base_date ROWS 4 PRECEDING) AS ma5,
       close_px / LAG(close_px) OVER (PARTITION BY stock_cd ORDER BY base_date) - 1 AS chg_rate
FROM IDENTIFIER('stock_price_daily_' || :my_id)
ORDER BY stock_cd, base_date LIMIT 50;

-- ------------------------------------------------------------ [5] 반정형 JSON: 앱 이벤트에서 OS별 주문 전환율 (order_start → order_done)
SELECT props_json:os::string AS os,
       COUNT_IF(event_name = 'order_start') AS starts,
       COUNT_IF(event_name = 'order_done')  AS dones,
       ROUND(try_divide(COUNT_IF(event_name = 'order_done'), COUNT_IF(event_name = 'order_start')), 3) AS conv
FROM IDENTIFIER('app_event_log_' || :my_id) GROUP BY 1;

-- ------------------------------------------------------------ [6] 신규 계좌 월간 추이 (사내 KPI 형태): 개설월별 신규 계좌
SELECT SUBSTR(open_dt, 1, 6) AS ym, COUNT(*) AS new_accts
FROM IDENTIFIER('eis_ac_account_' || :my_id) GROUP BY 1 ORDER BY 1;

-- ------------------------------------------------------------ [7] 코호트: 가입연도별 고객의 첫 주문까지 걸린 일수(중앙값)
WITH first_ord AS (
  SELECT a.cust_no, MIN(o.base_date) AS first_dt
  FROM IDENTIFIER('eis_tr_order_' || :my_id) o
  JOIN IDENTIFIER('eis_ac_account_' || :my_id) a USING (acct_no) GROUP BY 1)
SELECT SUBSTR(c.join_dt, 1, 4) AS join_yr,
       PERCENTILE(DATEDIFF(TO_DATE(f.first_dt, 'yyyyMMdd'), TO_DATE(c.join_dt, 'yyyyMMdd')), 0.5) AS median_days
FROM IDENTIFIER('dim_customer_' || :my_id) c JOIN first_ord f USING (cust_no) GROUP BY 1 ORDER BY 1;

-- ------------------------------------------------------------ [8] 거버넌스 실습: 마스킹 뷰 + 권한
CREATE OR REPLACE VIEW IDENTIFIER('v_customer_safe_' || :my_id) AS
SELECT cust_no, age_grp, sido, join_channel, cust_grade, join_dt,
       CASE WHEN is_account_group_member('dbx_edu_unmask') THEN cust_nm_mask ELSE '' END AS cust_nm_mask
FROM IDENTIFIER('dim_customer_' || :my_id);
SELECT * FROM IDENTIFIER('v_customer_safe_' || :my_id);
-- GRANT SELECT ON VIEW IDENTIFIER('v_customer_safe_' || :my_id) TO `account users`;

-- ------------------------------------------------------------ [9] Delta 기능: 타임트래블 / 복구 / 최적화 (잘못 지운 뒤 복구 시연)
DECLARE OR REPLACE VARIABLE tt STRING;
SET VAR tt = 'kpsec.sandbox_edu.eis_tr_order_tt_' || :my_id;
SELECT tt;
-- ① 복사본 만들기 (버전 0)
DROP TABLE IF EXISTS IDENTIFIER(tt);
CREATE TABLE IDENTIFIER(tt) AS SELECT * FROM IDENTIFIER('eis_tr_order_' || :my_id);
-- ② 실수로 미체결 건 삭제 (버전 1)
DELETE FROM IDENTIFIER(tt) WHERE order_stat = '미체결';
-- ③ 지우기 전(버전 0)과 지금 비교 → v0 22건 · 미체결 3 / now 19건 · 미체결 0
EXECUTE IMMEDIATE
  'SELECT "v0" AS ver, COUNT(*) AS total, COUNT_IF(order_stat = "미체결") AS unfilled FROM ' || tt || ' VERSION AS OF 0
   UNION ALL
   SELECT "now", COUNT(*), COUNT_IF(order_stat = "미체결") FROM ' || tt;
-- ④ 버전 0으로 복구
EXECUTE IMMEDIATE 'RESTORE TABLE ' || tt || ' TO VERSION AS OF 0';
-- ⑤ 변경 이력: CREATE TABLE AS SELECT → DELETE → (자동 OPTIMIZE) → RESTORE
EXECUTE IMMEDIATE 'DESCRIBE HISTORY ' || tt;
-- ⑥ 작은 파일 합치기
OPTIMIZE IDENTIFIER(tt);
