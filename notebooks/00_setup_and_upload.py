# Databricks notebook source
# MAGIC %md
# MAGIC # 00. 사전 준비 (관리자 · 강사용) — 공통 스키마 · 볼륨 + 실습 파일 업로드
# MAGIC
# MAGIC > **교육생은 이 노트북을 실행하지 않습니다.** 교육 전에 관리자(고객사) 또는 강사가 한 번만 실행합니다.
# MAGIC > 교육생은 `01_load_tables` 부터 시작해, 이 볼륨의 CSV로 **본인 이름이 붙은 테이블** (`dim_stock_<my_id>` …)을 만듭니다.
# MAGIC
# MAGIC 1. 공통 스키마 `kpsec.sandbox_edu` / 볼륨 `edu_raw` 생성
# MAGIC 2. Git folder 의 `data/` 파일 7개(CSV 6개 + 대시보드 템플릿 `edu_trade_kpi.lvdash.json`)를 Volume `/Volumes/kpsec/sandbox_edu/edu_raw/` 로 복사
# MAGIC 3. (권한) 교육생 그룹에 스키마 사용 · 테이블 생성 · 볼륨 읽기 권한 부여 — 아래 GRANT 예시 참고
# MAGIC
# MAGIC **실행 순서**: (사전 준비) `00_setup_and_upload` → (교육생) `01_load_tables` → `02_exercises`
# MAGIC
# MAGIC > 사전 조건: 카탈로그 `kpsec` 가 있고, 실행 계정에 `CREATE SCHEMA` / `CREATE VOLUME` 권한이 있어야 합니다. (sandbox 워크스페이스)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. 스키마 · 볼륨 생성

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE SCHEMA IF NOT EXISTS kpsec.sandbox_edu COMMENT '데이터브릭스 교육용 가상 데이터 (실데이터 아님)'

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE VOLUME IF NOT EXISTS kpsec.sandbox_edu.edu_raw COMMENT '교육용 CSV 원본'

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. 실습 파일을 Volume 으로 복사
# MAGIC
# MAGIC 이 노트북이 있는 Git folder 기준으로 `../data/` 의 CSV 6개와 대시보드 템플릿 JSON 을 찾아 Volume 에 복사합니다. (UI 에서 직접 Upload 하는 것과 동일한 결과)
# MAGIC 교육생은 볼륨에서 JSON 을 내려받아 대시보드 Import 실습에 씁니다.
# MAGIC
# MAGIC 이미 같은 이름의 파일이 있으면 **덮어씁니다.**

# COMMAND ----------

import glob
import os
import shutil

VOLUME_DIR = "/Volumes/kpsec/sandbox_edu/edu_raw"
EXPECTED = [
    "dim_stock.csv",
    "stock_price_daily.csv",
    "dim_customer.csv",
    "eis_ac_account.csv",
    "eis_tr_order.csv",
    "app_event_log.csv",
    "edu_trade_kpi.lvdash.json",  # 대시보드 템플릿 (Import 실습용)
]

# 노트북 위치(.../notebooks) 기준 상위의 data/ 폴더
data_dir = os.path.abspath(os.path.join(os.getcwd(), "..", "data"))
print("data dir :", data_dir)

found = sorted(os.path.basename(p) for p in glob.glob(os.path.join(data_dir, "*")))
missing = [f for f in EXPECTED if f not in found]
if missing:
    raise FileNotFoundError(
        f"{data_dir} 에서 파일을 찾지 못했습니다: {missing}\n"
        "Git folder 에서 Pull 했는지, 노트북이 notebooks/ 폴더 안에서 실행 중인지 확인하세요. "
        "(아니면 data_dir 값을 직접 지정)"
    )

for name in EXPECTED:
    shutil.copyfile(os.path.join(data_dir, name), f"{VOLUME_DIR}/{name}")
    print("copied:", name)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. 업로드 확인
# MAGIC
# MAGIC CSV 6개와 `edu_trade_kpi.lvdash.json` 이 보여야 합니다.

# COMMAND ----------

display(dbutils.fs.ls("/Volumes/kpsec/sandbox_edu/edu_raw/"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. (선택) 교육생 권한 부여 예시
# MAGIC
# MAGIC 교육생 그룹 이름(예: `dbx_edu_users`)에 맞게 바꿔서 SQL 셀에서 실행하세요. 관리자 · 스키마 소유자만 실행할 수 있습니다.
# MAGIC
# MAGIC ```sql
# MAGIC GRANT USE CATALOG ON CATALOG kpsec TO `dbx_edu_users`;
# MAGIC GRANT USE SCHEMA, CREATE TABLE ON SCHEMA kpsec.sandbox_edu TO `dbx_edu_users`;
# MAGIC GRANT READ VOLUME ON VOLUME kpsec.sandbox_edu.edu_raw TO `dbx_edu_users`;
# MAGIC ```

# COMMAND ----------

# MAGIC %md
# MAGIC 사전 준비 끝. 교육생은 `01_load_tables` 노트북부터 실행합니다.
