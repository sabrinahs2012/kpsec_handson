#!/usr/bin/env python3
"""Databricks 교육용 가상 데이터셋 생성기 (표준 라이브러리만 사용, 시드 고정).

모든 값은 가상이다. 실제 고객/계좌 정보가 아니며 식별자는 의도적으로 실재 형식과 다르게 만든다.
  고객번호: 9로 시작하는 8자리 (실제 앱 유저 ID 대역과 구분)
  계좌번호: 999-XX-XXXXXX (실제 020-XX-XXXXXX 아님)
  이름/전화: 처음부터 마스킹 형태만 생성
교육용 '지저분한 데이터'(NULL, 중복, 이상값)를 일부러 소량 섞는다.

사용: python3 -I generate_data.py <출력디렉토리>
"""
import csv
import hashlib
import json
import random
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

SEED = 20261109
random.seed(SEED)
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else "../data")
OUT.mkdir(parents=True, exist_ok=True)

N_CUST = 10
N_STOCK = 5
START, END = date(2026, 10, 29), date(2026, 10, 30)  # 소량 샘플: 2영업일


def ymd(d):
    return d.strftime("%Y%m%d")  # 사내 관례: base_date = STRING yyyymmdd


def write(name, header, rows):
    with open(OUT / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(f"{name}.csv {len(rows):,} rows")


bdays = [START + timedelta(days=i) for i in range((END - START).days + 1)]
bdays = [d for d in bdays if d.weekday() < 5]

# ---------------------------------------------------------------- dim_stock
SECTORS = ["반도체", "2차전지", "바이오", "금융", "자동차", "인터넷", "화학", "조선", "게임", "유통"]
stocks = []
for i in range(N_STOCK):
    cd = f"X{900000 + i * 37:06d}"  # 실재 종목코드(6자리 숫자)와 겹치지 않도록 X 접두사
    mkt = random.choices(["KOSPI", "KOSDAQ"], [0.6, 0.4])[0]
    stocks.append({
        "stock_cd": cd,
        "stock_nm": f"샘플종목{i + 1:03d}",
        "market": mkt,
        "sector": random.choice(SECTORS),
        "base_px": random.choice([3000, 8000, 15000, 32000, 58000, 91000, 180000, 420000]),
        "list_dt": ymd(date(2005, 1, 1) + timedelta(days=random.randint(0, 6000))),
    })
write("dim_stock", ["stock_cd", "stock_nm", "market", "sector", "list_dt"],
      [[s["stock_cd"], s["stock_nm"], s["market"], s["sector"], s["list_dt"]] for s in stocks])

# ------------------------------------------------------ stock_price_daily
prices = {}  # (stock_cd, ymd) -> close
rows = []
for s in stocks:
    px = s["base_px"]
    for d in bdays:
        chg = random.gauss(0.0004, 0.02)
        o = px
        c = max(100, round(px * (1 + chg), -1))
        h = max(o, c) * (1 + abs(random.gauss(0, 0.007)))
        l = min(o, c) * (1 - abs(random.gauss(0, 0.007)))
        vol = int(abs(random.gauss(300000, 150000))) + 1000
        rows.append([ymd(d), s["stock_cd"], int(o), int(round(h, -1)), int(round(l, -1)), int(c), vol])
        prices[(s["stock_cd"], ymd(d))] = int(c)
        px = c
write("stock_price_daily", ["base_date", "stock_cd", "open_px", "high_px", "low_px", "close_px", "volume"], rows)

# ------------------------------------------------------------ dim_customer
SURN = "김이박최정강조윤장임한오서신권황안송류전홍"
CHANNELS = ["MTS", "HTS", "제휴앱", "오프라인"]
GRADES = ["일반", "우수", "VIP"]
custs = []
rows = []
for i in range(N_CUST):
    cno = f"{90000001 + i}"
    join = date(2018, 1, 1) + timedelta(days=int(random.random() ** 0.6 * 3200))
    age = random.choices(["20대", "30대", "40대", "50대", "60대+"], [0.25, 0.32, 0.22, 0.14, 0.07])[0]
    sido = random.choices(["서울", "경기", "부산", "대구", "인천", "기타"], [0.28, 0.27, 0.07, 0.05, 0.06, 0.27])[0]
    ci = hashlib.sha256(f"edu-{cno}".encode()).hexdigest()[:32]
    c = {"cust_no": cno, "join_dt": ymd(join), "age_grp": age}
    custs.append(c)
    rows.append([
        cno,
        random.choice(SURN) + "*",
        f"010-****-{random.randint(0, 9999):04d}",
        ci,
        age,
        sido,
        random.choices(CHANNELS, [0.55, 0.15, 0.2, 0.1])[0],
        random.choices(GRADES, [0.85, 0.12, 0.03])[0],
        ymd(join),
        random.choice(["Y", "N"]) if i != 7 else "",  # 마케팅 동의 결측 1건
    ])
write("dim_customer",
      ["cust_no", "cust_nm_mask", "mobile_mask", "ci_hash", "age_grp", "sido", "join_channel", "cust_grade", "join_dt", "mkt_agree_yn"],
      rows)

# ------------------------------------------------------------- eis_ac_account
ACCT_TYPES = [("01", "종합매매"), ("02", "ISA"), ("03", "연금저축"), ("04", "미성년"), ("05", "해외주식")]
accts = []
rows = []
seq = 100000
for c in custs:
    for _ in range(random.choices([1, 2], [0.9, 0.1])[0]):
        seq += random.randint(1, 9)
        tp = random.choices(ACCT_TYPES, [0.6, 0.12, 0.12, 0.04, 0.12])[0]
        jd = datetime.strptime(c["join_dt"], "%Y%m%d").date()
        open_d = jd + timedelta(days=random.randint(0, 400))
        if open_d > END:
            open_d = END - timedelta(days=random.randint(0, 30))
        closed = c['cust_no'] == '90000004' and open_d < date(2026, 10, 28)
        close_d = date(2026, 10, 28) if closed else None  # 해지 계좌 1건 시연
        if close_d and close_d > END:
            close_d = None
            closed = False
        acct_no = f"999-{random.randint(10, 99)}-{seq:06d}"
        accts.append({"acct_no": acct_no, "cust_no": c["cust_no"], "open": open_d, "close": close_d})
        rows.append([acct_no, c["cust_no"], tp[0], tp[1], ymd(open_d),
                     ymd(close_d) if close_d else "", "해지" if closed else "정상"])
write("eis_ac_account", ["acct_no", "cust_no", "acct_type_cd", "acct_type_nm", "open_dt", "close_dt", "acct_stat"], rows)

# --------------------------------------------------------------- eis_tr_order
weights = [1 / (i + 1) ** 0.8 for i in range(N_STOCK)]  # 소수 종목 쏠림
active_by_day_cache = {}
rows = []
oid = 0
N_ORD = 10
day_w = [1.0 + 1.5 * (d.month in (1, 3)) for d in bdays]
while len(rows) < N_ORD:
    d = random.choices(bdays, day_w)[0]
    a = random.choice(accts)
    if a["open"] > d or (a["close"] and a["close"] < d):
        continue
    s = random.choices(stocks, weights)[0]
    close = prices[(s["stock_cd"], ymd(d))]
    qty = random.choice([1, 2, 3, 5, 10, 20, 50, 100, 300])
    px = max(100, int(round(close * (1 + random.gauss(0, 0.004)), -1)))
    oid += 1
    status = random.choices(["체결", "미체결", "취소"], [0.9, 0.04, 0.06])[0]
    ts = datetime(d.year, d.month, d.day, 9, 0) + timedelta(seconds=random.randint(0, 6 * 3600 + 1800))
    rows.append([
        f"O{ymd(d)}{oid:07d}", ymd(d), ts.strftime("%Y-%m-%d %H:%M:%S"), a["acct_no"], s["stock_cd"],
        random.choices(["매수", "매도"], [0.55, 0.45])[0], qty, px, qty * px if status == "체결" else 0,
        random.choices(["MTS", "HTS", "ARS", "API"], [0.72, 0.2, 0.01, 0.07])[0] if random.random() > 0.005 else "",
        status,
    ])
# 교육용 오염: 중복 행 1%, 이상 수량(음수) 몇 건
rows.append(list(rows[0]))  # 중복 1건
rows[1][6] = -abs(int(rows[1][6]))  # 음수 수량 1건
rows[2][9] = ""  # 채널 결측 1건
random.shuffle(rows)
write("eis_tr_order",
      ["order_id", "base_date", "order_ts", "acct_no", "stock_cd", "side", "qty", "order_px", "exec_amt", "channel", "order_stat"],
      rows)

# ------------------------------------------------------------- app_event_log
EVENTS = [("app_open", "홈"), ("view_stock", "종목상세"), ("search", "검색"), ("order_start", "주문"),
          ("order_done", "주문완료"), ("view_asset", "내자산"), ("open_account_start", "계좌개설"),
          ("open_account_done", "계좌개설완료")]
rows = []
for _ in range(10):
    d = random.choice(bdays)
    c = random.choice(custs)
    ev, scr = random.choices(EVENTS, [30, 28, 14, 10, 6, 8, 3, 1])[0]
    ts = datetime(d.year, d.month, d.day, random.randint(7, 23), random.randint(0, 59), random.randint(0, 59))
    props = {"os": random.choices(["iOS", "Android"], [0.45, 0.55])[0], "app_ver": random.choice(["5.1.0", "5.2.0", "5.3.1"])}
    if ev in ("view_stock", "order_start", "order_done"):
        props["stock_cd"] = random.choices(stocks, weights)[0]["stock_cd"]
    rows.append([f"E{len(rows) + 1:08d}", ymd(d), ts.strftime("%Y-%m-%d %H:%M:%S"), c["cust_no"], ev, scr,
                 json.dumps(props, ensure_ascii=False)])
write("app_event_log", ["event_id", "base_date", "event_ts", "cust_no", "event_name", "screen", "props_json"], rows)
