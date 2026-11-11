# Databricks notebook source
# MAGIC %md
# MAGIC # 00. 환경 준비 + CSV 업로드
# MAGIC
# MAGIC README `사용 순서` 의 **2~3단계**를 수행합니다.
# MAGIC
# MAGIC 1. 스키마 `kpsec.sandbox_edu` / 볼륨 `edu_raw` 생성
# MAGIC 2. Git folder 의 `data/*.csv` 6개를 Volume `/Volumes/kpsec/sandbox_edu/edu_raw/` 로 복사
# MAGIC
# MAGIC **실행 순서**: `00_setup_and_upload` → `01_load_tables` → `02_exercises`
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
# MAGIC ## 2. CSV 를 Volume 으로 복사
# MAGIC
# MAGIC 이 노트북이 있는 Git folder 기준으로 `../data/*.csv` 를 찾아 Volume 에 복사합니다. (UI 에서 직접 Upload 하는 것과 동일한 결과)
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
]

# 노트북 위치(.../notebooks) 기준 상위의 data/ 폴더
data_dir = os.path.abspath(os.path.join(os.getcwd(), "..", "data"))
print("data dir :", data_dir)

found = sorted(os.path.basename(p) for p in glob.glob(os.path.join(data_dir, "*.csv")))
missing = [f for f in EXPECTED if f not in found]
if missing:
    raise FileNotFoundError(
        f"{data_dir} 에서 CSV 를 찾지 못했습니다: {missing}\n"
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
# MAGIC CSV 6개가 보여야 합니다.

# COMMAND ----------

display(dbutils.fs.ls("/Volumes/kpsec/sandbox_edu/edu_raw/"))

# COMMAND ----------

# MAGIC %md
# MAGIC 다음: `01_load_tables` 노트북을 실행하세요.
