-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 02. 실습 문제
-- MAGIC
-- MAGIC README `사용 순서` 의 **4단계** (`sql/02_exercises.sql`).
-- MAGIC 품질점검 → 조인 → 윈도우 → JSON → 코호트 → 마스킹뷰 → 타임트래블 순서로 난이도가 올라갑니다.
-- MAGIC
-- MAGIC - 사전 조건: `01_load_tables` 실행 완료
-- MAGIC - 각 문제의 쿼리는 **힌트/정답** 입니다. 교육 시에는 쿼리를 가리고 풀어보게 하세요.

-- COMMAND ----------

USE kpsec.sandbox_edu

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [1] 기본 조회: 종목별 최근 종가 상위 10

-- COMMAND ----------

SELECT s.stock_nm, p.base_date, p.close_px
FROM stock_price_daily p JOIN dim_stock s USING (stock_cd)
WHERE p.base_date = (SELECT MAX(base_date) FROM stock_price_daily)
ORDER BY p.close_px DESC LIMIT 10

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [2] 데이터 품질: 주문 테이블 중복 / 음수 수량 / 채널 결측 건수
-- MAGIC
-- MAGIC 기대값: `total` 22, `dup_rows` 2, `bad_qty` 2, `null_channel` 2

-- COMMAND ----------

SELECT COUNT(*) total,
       COUNT(*) - COUNT(DISTINCT order_id) AS dup_rows,
       SUM(CASE WHEN qty <= 0 THEN 1 END) AS bad_qty,
       SUM(CASE WHEN channel IS NULL THEN 1 END) AS null_channel
FROM eis_tr_order

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [3] 조인+집계: 계좌유형별 월별 체결금액 (해지 계좌 제외)

-- COMMAND ----------

SELECT a.acct_type_nm, SUBSTR(o.base_date, 1, 6) AS ym, SUM(o.exec_amt) AS amt
FROM (SELECT DISTINCT * FROM eis_tr_order WHERE qty > 0 AND order_stat = '체결') o
JOIN eis_ac_account a USING (acct_no)
WHERE a.acct_stat = '정상'
GROUP BY 1, 2 ORDER BY 2, 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [4] 윈도우 함수: 종목별 5일 이동평균 종가와 전일 대비 등락률

-- COMMAND ----------

SELECT stock_cd, base_date, close_px,
       AVG(close_px) OVER (PARTITION BY stock_cd ORDER BY base_date ROWS 4 PRECEDING) AS ma5,
       close_px / LAG(close_px) OVER (PARTITION BY stock_cd ORDER BY base_date) - 1 AS chg_rate
FROM stock_price_daily
ORDER BY stock_cd, base_date LIMIT 50

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [5] 반정형 JSON: 앱 이벤트에서 OS별 주문 전환율 (order_start → order_done)
-- MAGIC
-- MAGIC 기대값: Android `starts` 23 · `dones` 7 · `conv` 0.304 / iOS `starts` 19 · `dones` 12 · `conv` 0.632

-- COMMAND ----------

SELECT props_json:os::string AS os,
       COUNT_IF(event_name = 'order_start') AS starts,
       COUNT_IF(event_name = 'order_done')  AS dones,
       ROUND(try_divide(COUNT_IF(event_name = 'order_done'), COUNT_IF(event_name = 'order_start')), 3) AS conv
FROM app_event_log GROUP BY 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [6] 신규 계좌 월간 추이 (사내 KPI 형태): 개설월별 신규 계좌

-- COMMAND ----------

SELECT SUBSTR(open_dt, 1, 6) AS ym, COUNT(*) AS new_accts
FROM eis_ac_account GROUP BY 1 ORDER BY 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [7] 코호트: 가입연도별 고객의 첫 주문까지 걸린 일수(중앙값)

-- COMMAND ----------

WITH first_ord AS (
  SELECT a.cust_no, MIN(o.base_date) AS first_dt
  FROM eis_tr_order o JOIN eis_ac_account a USING (acct_no) GROUP BY 1)
SELECT SUBSTR(c.join_dt, 1, 4) AS join_yr,
       PERCENTILE(DATEDIFF(TO_DATE(f.first_dt, 'yyyyMMdd'), TO_DATE(c.join_dt, 'yyyyMMdd')), 0.5) AS median_days
FROM dim_customer c JOIN first_ord f USING (cust_no) GROUP BY 1 ORDER BY 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [8] 거버넌스 실습: 마스킹 뷰 + 권한
-- MAGIC
-- MAGIC 그룹 `dbx_edu_unmask` 멤버에게만 고객명 마스킹 값이 보이고, 그 외에는 빈 문자열입니다.
-- MAGIC 아래 `GRANT` 는 **소유자만 실행** 가능하므로 시연용으로 주석 처리되어 있습니다.

-- COMMAND ----------

CREATE OR REPLACE VIEW v_customer_safe AS
SELECT cust_no, age_grp, sido, join_channel, cust_grade, join_dt,
       CASE WHEN is_account_group_member('dbx_edu_unmask') THEN cust_nm_mask ELSE '' END AS cust_nm_mask
FROM dim_customer

-- COMMAND ----------

SELECT * FROM v_customer_safe

-- COMMAND ----------

-- GRANT SELECT ON VIEW v_customer_safe TO `account users`

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [9] Delta 기능: 타임트래블 / 최적화 (잘못 지운 뒤 복구 시연)
-- MAGIC
-- MAGIC 시연 순서: ① 취소 건 삭제 → ② 이력 확인 → ③ 이전 버전으로 복구.
-- MAGIC 데이터가 바뀌므로 **기본은 주석 처리**되어 있습니다. 시연할 때만 `--` 를 지우고 한 셀씩 실행하세요.
-- MAGIC
-- MAGIC `01_load_tables` 는 `CREATE`(버전 0, 빈 테이블) → `INSERT`(버전 1, 데이터 적재) 순서라서
-- MAGIC **복구 대상은 버전 1** 입니다. (버전 0 으로 복구하면 빈 테이블이 됩니다.)
-- MAGIC 마지막 셀의 `OPTIMIZE` 를 먼저 실행했거나 노트북을 여러 번 실행했다면 버전 번호가 더 늘어나 있을 수 있으니,
-- MAGIC `DESCRIBE HISTORY` 결과에서 **삭제 직전 버전** 을 확인해 번호를 맞추세요.

-- COMMAND ----------

-- DELETE FROM eis_tr_order WHERE order_stat = '취소'

-- COMMAND ----------

-- DESCRIBE HISTORY eis_tr_order

-- COMMAND ----------

-- RESTORE TABLE eis_tr_order TO VERSION AS OF 1

-- COMMAND ----------

OPTIMIZE eis_tr_order
