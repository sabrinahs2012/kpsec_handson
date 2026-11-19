-- Databricks notebook source
-- MAGIC %md
-- MAGIC # 02. 실습 문제
-- MAGIC
-- MAGIC 품질점검 → 조인 → 윈도우 → JSON → 코호트 → 마스킹뷰 → 타임트래블 순서로 난이도가 올라갑니다.
-- MAGIC
-- MAGIC - 사전 조건: `01_load_tables` 실행 완료 (본인 테이블 7개)
-- MAGIC - 왼쪽 `{ }` 아이콘(Parameters) 패널의 **`my_id`** 에 `01_load_tables` 와 **같은 ID** 를 입력하세요. (칸이 없으면 Run all 한 번 → 검사 셀에서 멈춘 뒤 입력) 모든 쿼리가 `IDENTIFIER('<테이블>_' || :my_id)` 로 본인 테이블을 읽습니다.
-- MAGIC - 각 문제의 쿼리는 **힌트/정답** 입니다. 교육 시에는 쿼리를 가리고 풀어보게 하세요.

-- COMMAND ----------

CREATE WIDGET TEXT my_id DEFAULT ''

-- COMMAND ----------

SELECT assert_true(:my_id RLIKE '^[a-z][a-z0-9_]*$',
                   '왼쪽 { } 아이콘 → Parameters 패널 my_id 에 01_load_tables 와 같은 ID를 입력하세요 (예: rian_bow)') AS id_ok,
       :my_id AS my_id

-- COMMAND ----------

USE kpsec.sandbox_edu

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [1] 기본 조회: 종목별 최근 종가 상위 10

-- COMMAND ----------

SELECT s.stock_nm, p.base_date, p.close_px
FROM IDENTIFIER('stock_price_daily_' || :my_id) p
JOIN IDENTIFIER('dim_stock_' || :my_id) s USING (stock_cd)
WHERE p.base_date = (SELECT MAX(base_date) FROM IDENTIFIER('stock_price_daily_' || :my_id))
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
FROM IDENTIFIER('eis_tr_order_' || :my_id)

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [3] 조인+집계: 계좌유형별 월별 체결금액 (해지 계좌 제외)

-- COMMAND ----------

SELECT a.acct_type_nm, SUBSTR(o.base_date, 1, 6) AS ym, SUM(o.exec_amt) AS amt
FROM (SELECT DISTINCT * FROM IDENTIFIER('eis_tr_order_' || :my_id)
      WHERE qty > 0 AND order_stat = '체결') o
JOIN IDENTIFIER('eis_ac_account_' || :my_id) a USING (acct_no)
WHERE a.acct_stat = '정상'
GROUP BY 1, 2 ORDER BY 2, 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [4] 윈도우 함수: 종목별 5일 이동평균 종가와 전일 대비 등락률

-- COMMAND ----------

SELECT stock_cd, base_date, close_px,
       AVG(close_px) OVER (PARTITION BY stock_cd ORDER BY base_date ROWS 4 PRECEDING) AS ma5,
       close_px / LAG(close_px) OVER (PARTITION BY stock_cd ORDER BY base_date) - 1 AS chg_rate
FROM IDENTIFIER('stock_price_daily_' || :my_id)
ORDER BY stock_cd, base_date LIMIT 50

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [5] 반정형 JSON: 앱 이벤트에서 OS별 주문 전환율 (order_start → order_done)
-- MAGIC
-- MAGIC 기대값: Android `starts` 23 · `dones` 7 · `conv` 0.304 / iOS `starts` 19 · `dones` 12 · `conv` 0.632
-- MAGIC
-- MAGIC `starts` 가 0 이면(`01_load_tables` 의 보정 INSERT 를 건너뛴 경우) `try_divide` 가 오류 대신 NULL 을 돌려줍니다.

-- COMMAND ----------

SELECT props_json:os::string AS os,
       COUNT_IF(event_name = 'order_start') AS starts,
       COUNT_IF(event_name = 'order_done')  AS dones,
       ROUND(try_divide(COUNT_IF(event_name = 'order_done'), COUNT_IF(event_name = 'order_start')), 3) AS conv
FROM IDENTIFIER('app_event_log_' || :my_id) GROUP BY 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [6] 신규 계좌 월간 추이 (사내 KPI 형태): 개설월별 신규 계좌

-- COMMAND ----------

SELECT SUBSTR(open_dt, 1, 6) AS ym, COUNT(*) AS new_accts
FROM IDENTIFIER('eis_ac_account_' || :my_id) GROUP BY 1 ORDER BY 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [7] 코호트: 가입연도별 고객의 첫 주문까지 걸린 일수(중앙값)

-- COMMAND ----------

WITH first_ord AS (
  SELECT a.cust_no, MIN(o.base_date) AS first_dt
  FROM IDENTIFIER('eis_tr_order_' || :my_id) o
  JOIN IDENTIFIER('eis_ac_account_' || :my_id) a USING (acct_no) GROUP BY 1)
SELECT SUBSTR(c.join_dt, 1, 4) AS join_yr,
       PERCENTILE(DATEDIFF(TO_DATE(f.first_dt, 'yyyyMMdd'), TO_DATE(c.join_dt, 'yyyyMMdd')), 0.5) AS median_days
FROM IDENTIFIER('dim_customer_' || :my_id) c JOIN first_ord f USING (cust_no) GROUP BY 1 ORDER BY 1

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [8] 거버넌스 실습: 마스킹 뷰 + 권한
-- MAGIC
-- MAGIC 그룹 `dbx_edu_unmask` 멤버에게만 고객명 마스킹 값이 보이고, 그 외에는 빈 문자열입니다.
-- MAGIC 뷰 이름은 `v_customer_safe_<my_id>` 입니다.
-- MAGIC
-- MAGIC 아래 `GRANT` 는 **소유자만 실행** 가능하므로 시연용으로 주석 처리되어 있습니다.

-- COMMAND ----------

CREATE OR REPLACE VIEW IDENTIFIER('v_customer_safe_' || :my_id) AS
SELECT cust_no, age_grp, sido, join_channel, cust_grade, join_dt,
       CASE WHEN is_account_group_member('dbx_edu_unmask') THEN cust_nm_mask ELSE '' END AS cust_nm_mask
FROM IDENTIFIER('dim_customer_' || :my_id)

-- COMMAND ----------

SELECT * FROM IDENTIFIER('v_customer_safe_' || :my_id)

-- COMMAND ----------

-- GRANT SELECT ON VIEW IDENTIFIER('v_customer_safe_' || :my_id) TO `account users`

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## [9] Delta 기능: 타임트래블 / 복구 / 최적화 (잘못 지운 뒤 복구 시연)
-- MAGIC
-- MAGIC 본인 주문 테이블의 **복사본** `eis_tr_order_tt_<my_id>` 에서 시연합니다.
-- MAGIC 순서: ① 복사본 만들기(버전 0) → ② 미체결 건 삭제(버전 1) → ③ 이전 버전과 비교 → ④ 버전 0으로 복구 → ⑤ 이력 확인 → ⑥ OPTIMIZE
-- MAGIC
-- MAGIC 기대값: 미체결 3건 삭제 → 22건이 19건으로 줄고, 복구하면 다시 22건.
-- MAGIC 복사본을 지웠다가 새로 만들기 때문에, 여러 번 실행해도 버전 번호는 항상 0부터 시작합니다.
-- MAGIC
-- MAGIC > `VERSION AS OF` · `RESTORE` · `DESCRIBE HISTORY` 는 `IDENTIFIER(...)` 를 받지 않습니다.
-- MAGIC > 그래서 테이블 이름을 변수 `tt` 에 담고, 이 세 문장은 `EXECUTE IMMEDIATE` 로 문자열을 만들어 실행합니다.
-- MAGIC >
-- MAGIC > 서버리스에서는 DELETE 직후 Databricks가 작은 파일을 **자동으로 OPTIMIZE(auto compaction)** 해서 이력에 버전이 하나 더 생길 수 있습니다.
-- MAGIC > 그 순간과 겹쳐 `ConcurrentWriteException` 이 나면 **그 셀만 다시 실행**하면 됩니다. 복구 대상은 그래도 버전 0 입니다.

-- COMMAND ----------

DECLARE OR REPLACE VARIABLE tt STRING;
SET VAR tt = 'kpsec.sandbox_edu.eis_tr_order_tt_' || :my_id;
SELECT tt

-- COMMAND ----------

-- ① 복사본 만들기 (버전 0)
DROP TABLE IF EXISTS IDENTIFIER(tt);
CREATE TABLE IDENTIFIER(tt) AS SELECT * FROM IDENTIFIER('eis_tr_order_' || :my_id)

-- COMMAND ----------

-- ② 실수로 미체결 건 삭제 (버전 1)
DELETE FROM IDENTIFIER(tt) WHERE order_stat = '미체결'

-- COMMAND ----------

-- ③ 지우기 전(버전 0)과 지금 비교 → v0 22건 · 미체결 3 / now 19건 · 미체결 0
EXECUTE IMMEDIATE
  'SELECT "v0" AS ver, COUNT(*) AS total, COUNT_IF(order_stat = "미체결") AS unfilled FROM ' || tt || ' VERSION AS OF 0
   UNION ALL
   SELECT "now", COUNT(*), COUNT_IF(order_stat = "미체결") FROM ' || tt

-- COMMAND ----------

-- ④ 버전 0으로 복구
EXECUTE IMMEDIATE 'RESTORE TABLE ' || tt || ' TO VERSION AS OF 0'

-- COMMAND ----------

-- ⑤ 변경 이력: CREATE TABLE AS SELECT → DELETE → (자동 OPTIMIZE) → RESTORE
EXECUTE IMMEDIATE 'DESCRIBE HISTORY ' || tt

-- COMMAND ----------

-- ⑥ 작은 파일 합치기
OPTIMIZE IDENTIFIER(tt)
