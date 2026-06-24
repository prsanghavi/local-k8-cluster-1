# Build Plan — Family Equity Portfolio Sync & Analysis System

**Version:** 0.1  
**Status:** Draft  
**Owner:** Samay  
**Last updated:** June 2026  
**Companion docs:** [PRD](./PRD.md) · [HLD](./HLD.md)

---

## Guiding Principle

Each stage ends with a **concrete, testable proof** that the system works at that level before moving to the next. No stage is complete until its exit tests pass. Stages are sized to fit a single focused weekend session (2–4 hours of build time).

---

## Stage Overview

| Stage | Name | What gets built | Exit test |
|-------|------|-----------------|-----------|
| S1 | Infra Up | Postgres + Temporal running; Sharesight API connection verified | Dummy trade inserted in Postgres, synced to Sharesight via API call |
| S2 | First ETL Flow | Chase CSV ETL workflow end-to-end | Real Chase CSV parsed, trades in Postgres, synced to Sharesight |
| S3 | US ETL Complete | ML and Robinhood ETL workflows | All 3 US sources flowing; dedup verified |
| S4 | Historical Load | Pre-2Y gap filled for US sources | No "unknown cost basis" in Sharesight for US portfolios |
| S5 | Corporate Actions | CA workflow running | Monthly CA backlog cleared in ≤5 min |
| S6 | India ETL | All 3 Indian sources flowing | India holdings in Sharesight with INR/USD values |
| S7 | Full Sync ≤10 min | All 6 sources + CA in one session | Timed session ≤10 min, 3× confirmed |
| S8 | Access & Polish | Spouse access, docs, runbook | Both users can run a session independently |

---

## Stage 1 — Infra Up

**Goal:** Local infrastructure running and end-to-end API connectivity proven with synthetic data. Nothing real yet — just proving the pipes work.

**Time estimate:** 3–4 hours

### What to build

#### 1.1 — Postgres
```bash
# docker-compose.yml excerpt
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: investments
      POSTGRES_USER: samay
      POSTGRES_PASSWORD: <local-dev-password>
    ports:
      - "5432:5432"
    volumes:
      - ./pgdata:/var/lib/postgresql/data
```
- Run `docker compose up -d postgres`
- Connect via pgAdmin to verify
- Apply schema migrations (create all tables from HLD §3.4)

#### 1.2 — Temporal
```bash
# Add to docker-compose.yml
  temporal:
    image: temporalio/auto-setup:1.24
    ports:
      - "7233:7233"   # gRPC
      - "8080:8080"   # Web UI
    environment:
      - DB=postgres12
      - DB_PORT=5432
      - POSTGRES_USER=samay
      - POSTGRES_PWD=<local-dev-password>
      - POSTGRES_SEEDS=postgres
    depends_on:
      - postgres
```
- Run `docker compose up -d temporal`
- Open `http://localhost:8080` — Temporal UI should load

#### 1.3 — Python worker scaffold
```
investment-sync/
  worker/
    __init__.py
    workflows/
      __init__.py
      etl_base.py          # shared ETL workflow class
      chase_etl.py
    activities/
      __init__.py
      sharesight_client.py  # API wrapper
      postgres_client.py    # DB wrapper
    config.py               # reads .env
  .env                      # Sharesight creds, DB URL
  requirements.txt
  docker-compose.yml
```

Install dependencies:
```
temporalio
psycopg2-binary
pandas
openpyxl
python-dotenv
requests
```

#### 1.4 — Sharesight API connection test
Write a standalone script `scripts/test_sharesight.py`:
- Authenticate via OAuth (client credentials)
- `GET /portfolios` — print portfolio names and IDs
- `POST /portfolios/{id}/trades` with a dummy trade (AAPL, 1 share, $1.00, today)
- `DELETE /portfolios/{id}/trades/{id}` — clean it up

#### 1.5 — Dummy ETL workflow
Write a minimal `DummyEtlWorkflow` in Temporal:
- Activity 1: Insert 1 dummy trade row into Postgres `trades` table
- Activity 2: Call Sharesight API to sync that trade
- Activity 3: Update `etl_runs` with result

### Exit tests — Stage 1

| # | Test | Pass condition |
|---|------|---------------|
| T1.1 | Postgres connection | pgAdmin connects; all tables created with correct schema |
| T1.2 | Temporal UI loads | `http://localhost:8080` shows Temporal UI with no errors |
| T1.3 | Worker registers | Start Python worker; Temporal UI shows worker registered on task queue `investment-sync` |
| T1.4 | Sharesight auth | `test_sharesight.py` prints list of Sharesight portfolio names without error |
| T1.5 | Dummy workflow runs | Trigger `DummyEtlWorkflow` from Temporal UI; workflow shows `Completed` status |
| T1.6 | Postgres record exists | After T1.5, `SELECT * FROM trades` returns the dummy trade row |
| T1.7 | Sharesight trade visible | After T1.5, dummy trade appears in correct Sharesight portfolio |
| T1.8 | Idempotency | Run T1.5 again with same dummy data; `SELECT COUNT(*) FROM trades` still returns 1 (dedup worked) |
| T1.9 | Cleanup | Delete dummy trade from Sharesight; verify Postgres `sharesight_trade_id` is nulled or record flagged |

**Stage 1 is done when all 9 tests pass.**

---

## Stage 2 — First ETL Flow (Chase)

**Goal:** Chase CSV goes in, real trades come out in Postgres and Sharesight. This is the full ETL pipeline with real data for one source.

**Time estimate:** 3–5 hours

### What to build

#### 2.1 — Chase CSV parser
- Analyse Chase CSV format (columns, date format, action types)
- Write `parsers/chase.py` → `parse_chase_csv(filepath) -> List[RawTrade]`
- Handle: BUY, SELL, DIVIDEND (log dividends separately, don't push to trades table)
- Handle date parsing edge cases

#### 2.2 — Normalisation layer
- Write `normalise.py` → `normalise_trade(raw: RawTrade) -> Trade`
- Map Chase action codes to `BUY`/`SELL`
- Generate deterministic `trade_key`
- Set `source = "chase"`, `currency = "USD"`, `fx_rate = NULL`

#### 2.3 — Chase ETL Workflow
Full workflow with all 7 activities from HLD §3.2:
- `detect_new_files` — scan `drops/chase/` for new CSVs
- `parse_file` — call `parse_chase_csv`
- `normalise_trades` — call `normalise_trade` per row
- `deduplicate` — query Postgres for existing `trade_key`
- `upsert_postgres` — insert new trades; update `etl_runs`
- `sync_to_sharesight` — push to Sharesight portfolio (Chase portfolio)
- `mark_files_processed` — move file to `drops/chase/processed/`

#### 2.4 — Error handling
- Invalid rows (missing ticker, unparseable date) → log to `etl_runs.error_detail`; skip row; don't fail workflow
- Sharesight API error → retry 5× with backoff; if all fail, mark trade with `synced_at = NULL` for retry next run

### Exit tests — Stage 2

| # | Test | Pass condition |
|---|------|---------------|
| T2.1 | Parser unit test | `parse_chase_csv` on sample Chase CSV returns correct `RawTrade` list with expected trade count |
| T2.2 | Normalisation | All trades have valid `trade_key`, `trade_type` is `BUY` or `SELL`, `currency = USD` |
| T2.3 | Dedup | Import same CSV twice; trade count in Postgres does not increase on second run |
| T2.4 | Workflow trigger | Drop Chase CSV in `drops/chase/`; trigger `ChaseEtlWorkflow` from Temporal UI; status = `Completed` |
| T2.5 | Postgres records | `SELECT COUNT(*) FROM trades WHERE source = 'chase'` matches expected trade count from CSV |
| T2.6 | Sharesight sync | All inserted trades have non-null `sharesight_trade_id`; trades visible in Chase portfolio in Sharesight UI |
| T2.7 | File moved | After workflow, CSV is in `drops/chase/processed/YYYY-MM-DD/` not in `drops/chase/` |
| T2.8 | etl_runs log | `SELECT * FROM etl_runs WHERE source = 'chase'` shows correct counts for inserted/skipped/failed |
| T2.9 | Bad row handling | CSV with 1 intentionally malformed row → workflow completes; 1 row logged as error; rest imported cleanly |
| T2.10 | Sharesight portfolio match | Trades appear in the correct Chase portfolio in Sharesight (not a different portfolio) |

**Stage 2 is done when all 10 tests pass.**

---

## Stage 3 — US ETL Complete (ML + Robinhood)

**Goal:** All three US sources have working ETL workflows. Deduplication works across sources (same stock bought on different brokers doesn't conflict).

**Time estimate:** 3–5 hours (reuses Stage 2 framework heavily)

### What to build

#### 3.1 — Merrill Lynch parser
- Investigate whether ML CSV is obtainable from ML portal (preferred over PDF)
- If CSV: write `parsers/merrill.py` similar to Chase
- If PDF only: use `pdfplumber` to extract trade table; map columns
- Flag: ML may include different account types (individual, joint, IRA) — tag accordingly in `account_id`

#### 3.2 — Robinhood parser
- Robinhood CSV is well-documented; write `parsers/robinhood.py`
- Handle: Robinhood includes dividends, fractional shares, and DRIP in same file
- Separate DRIP dividends → `corporate_actions` staging, not `trades`

#### 3.3 — ML ETL Workflow + Robinhood ETL Workflow
- Clone Chase workflow structure; swap parser and source tag
- Each gets its own Temporal workflow name: `MerrillEtlWorkflow`, `RobinhoodEtlWorkflow`

#### 3.4 — Cross-source dedup validation
- A stock like AAPL can be held across Chase and ML — these are different trades, not duplicates
- Confirm `trade_key` includes `source` field so they don't collide
- Write a test: same ticker, same date, different source → both inserted, no dedup false positive

### Exit tests — Stage 3

| # | Test | Pass condition |
|---|------|---------------|
| T3.1 | ML workflow runs | Drop ML export; trigger `MerrillEtlWorkflow`; status = Completed |
| T3.2 | ML trades in Postgres | `SELECT COUNT(*) FROM trades WHERE source = 'merrill_lynch'` > 0 |
| T3.3 | ML Sharesight sync | ML trades visible in ML portfolio in Sharesight |
| T3.4 | Robinhood workflow runs | Same check for Robinhood |
| T3.5 | Robinhood fractional shares | Fractional share trades (qty < 1) imported correctly; no rounding errors |
| T3.6 | Cross-source dedup | AAPL in Chase and AAPL in ML both present in Postgres as separate rows; no false dedup |
| T3.7 | Three portfolios in Sharesight | Chase, ML, and Robinhood portfolios all have trades; no cross-portfolio bleed |
| T3.8 | Combined run time | Trigger all 3 ETL workflows simultaneously from Temporal UI; all complete in <5 min wall clock |

**Stage 3 is done when all 8 tests pass.**

---

## Stage 4 — Historical Load (Pre-2Y Gap)

**Goal:** All pre-2024 US holdings entered into Postgres. Sharesight shows complete cost basis history with no gaps. This is the most time-consuming stage but is one-time work.

**Time estimate:** One-time manual effort of 3–6 hours spread over 1–2 weekends, plus 1 hour of tooling

### What to build

#### 4.1 — Manual entry template
Create `tools/historical_entry_template.csv`:
```
source,account_id,ticker,trade_date,trade_type,quantity,price_local,currency,notes
merrill_lynch,ML-XXXX,AAPL,2019-03-15,BUY,10,185.72,USD,from 2019 tax statement
```
- Document: where to find the data (bank UI "Closed Positions", annual tax statements, 1099-B)
- Write a `scripts/import_historical.py` that bulk-loads this CSV into Postgres, then triggers Sharesight sync

#### 4.2 — Sharesight "opening balance" trades
For very old holdings where only current position is known (not individual purchase lots):
- Enter as a synthetic `BUY` on earliest known date with average cost basis
- Tag as `"historical_estimate": true` in `tags` JSONB column
- Document that these are estimates for cost basis; actual P&L may differ

#### 4.3 — CA backlog (historical)
After historical trades are loaded, there will be a large backlog of historical corporate action suggestions in Sharesight. Run the Corporate Action workflow (Stage 5) in bulk to clear these before doing ongoing sessions. Stage 5 can be built in parallel with this stage.

### Exit tests — Stage 4

| # | Test | Pass condition |
|---|------|---------------|
| T4.1 | Template import | `import_historical.py` on a sample 10-row template CSV inserts correctly into Postgres |
| T4.2 | No cost basis warnings | Sharesight shows 0 "cost basis unknown" warnings across all US portfolios after sync |
| T4.3 | Oldest holding visible | The earliest known holding for each US portfolio has a trade date in Sharesight; no position shows as "opened unknown" |
| T4.4 | 1Y return calculable | Sharesight can compute 1Y return for at least 3 US positions without "insufficient data" error |
| T4.5 | Duplicate check | Re-running ETL workflows after historical load doesn't insert duplicates (historical entries have correct `trade_key`) |

**Stage 4 is done when all 5 tests pass.**

---

## Stage 5 — Corporate Action Workflow

**Goal:** Sharesight CA suggestions are fetched, staged in Postgres, reviewed, and applied via API. Monthly backlog cleared in ≤5 min.

**Time estimate:** 3–4 hours

### What to build

#### 5.1 — CA suggestion fetch activity
- Call Sharesight API to list pending suggestions per portfolio
- Map response to `corporate_actions` table rows
- Upsert (skip already-known suggestions)

#### 5.2 — Human review step
- After staging, the Temporal workflow sends a signal/waits
- Phase 1: print staged CAs to console / query via pgAdmin; user runs `scripts/approve_all_pending.py` to set `status = approved`
- Phase 2 (optional): simple Flask/FastAPI local page listing pending CAs with approve/reject buttons

#### 5.3 — Apply approved CAs
- For each `status = approved` row: POST to Sharesight v2 `/payouts` endpoint
- Include `sleep(0.5)` between calls to respect rate limits
- Update `status = applied` + `applied_at`
- If API fails: retry 3×; if still failing: mark `status = failed`; continue with others

#### 5.4 — CorporateActionWorkflow
- Temporal workflow combining all the above
- Triggerable from Temporal UI; shows progress in workflow history

### Exit tests — Stage 5

| # | Test | Pass condition |
|---|------|---------------|
| T5.1 | Suggestions fetched | After triggering workflow, `SELECT COUNT(*) FROM corporate_actions WHERE status = 'pending'` > 0 |
| T5.2 | No duplicates | Run CA workflow twice; pending count does not double |
| T5.3 | Approve and apply | Approve all pending via script; trigger apply step; all rows move to `status = applied` |
| T5.4 | Sharesight updated | Applied dividends appear as cash/income entries in Sharesight UI |
| T5.5 | Time budget | Full CA cycle (fetch + approve + apply) for ≤20 events completes in ≤5 min active human time |
| T5.6 | Failure resilience | Simulate 1 API failure during apply step; workflow retries and continues; failed row marked `status = failed`; others succeed |

**Stage 5 is done when all 6 tests pass.**

---

## Stage 6 — India ETL (All 3 Fund Managers)

**Goal:** All three Indian sources flow into Postgres and Sharesight with correct INR cost basis and USD-equivalent values.

**Time estimate:** 4–6 hours (format analysis adds uncertainty)

### Pre-work before building
- Obtain sample Excel/CSV from all 3 Indian fund managers
- Map columns: identify trade date, scrip/ticker, quantity, price, buy/sell indicator
- Confirm whether FM2/FM3 mutual fund exports use NAV or market price
- Confirm NSE ticker symbol format used (e.g. `RELIANCE` vs `RELIANCE.NS`)

### What to build

#### 6.1 — FX rate lookup activity
- `activities/fx.py` → `get_inr_usd_rate(date: date) -> float`
- Use `api.frankfurter.app/YYYY-MM-DD?from=INR&to=USD` (free, no key required)
- Cache in Postgres: `fx_rates(date DATE, inr_usd NUMERIC)` to avoid redundant calls
- Fallback: if date is a weekend/holiday, use previous business day's rate

#### 6.2 — India parsers (×3)
- `parsers/india_fm1.py` — PMS Excel; likely multi-sheet or dated tabs
- `parsers/india_fm2.py` — ETF/MF Excel; handle NAV-based pricing for MF rows
- `parsers/india_fm3.py` — ETF/MF Excel
- Each outputs `RawTrade` with `currency = "INR"`

#### 6.3 — India normalisation
- Call FX activity to populate `price_usd` and `fx_rate`
- Map NSE ticker to format Sharesight expects (verify via Sharesight instrument search)
- Set `instrument_type = "mutual_fund"` in `tags` for MF rows

#### 6.4 — Three India ETL Workflows
- `IndiaFM1EtlWorkflow`, `IndiaFM2EtlWorkflow`, `IndiaFM3EtlWorkflow`
- Each maps to a separate Sharesight portfolio (India-FM1, India-FM2, India-FM3)

### Exit tests — Stage 6

| # | Test | Pass condition |
|---|------|---------------|
| T6.1 | FX lookup | `get_inr_usd_rate("2023-01-15")` returns a plausible rate (0.011–0.014 range); cached in `fx_rates` table |
| T6.2 | FM1 parser | `parse_india_fm1` on sample Excel returns `RawTrade` list with correct ticker, date, qty, price |
| T6.3 | FM2/FM3 parsers | Same check; MF rows have `instrument_type = mutual_fund` in tags |
| T6.4 | USD equivalent | All India trades have non-null `price_usd` and `fx_rate` |
| T6.5 | India workflows run | All 3 India workflows trigger from Temporal UI; all Complete |
| T6.6 | India in Sharesight | India trades visible in India portfolio(s); currency shows as INR; Sharesight displays USD equivalent |
| T6.7 | Benchmark visible | Sharesight shows Nifty 50 or BSE Sensex comparison for at least one India portfolio |
| T6.8 | NSE tickers resolve | Sharesight recognises all NSE tickers (no "security not found" errors); resolve any mismatches manually |

**Stage 6 is done when all 8 tests pass.**

---

## Stage 7 — Full Sync ≤10 Min

**Goal:** The complete monthly session — all 6 sources + corporate actions — runs in ≤10 minutes of active human time. Confirmed over 3 separate sessions.

**Time estimate:** 1–2 hours of optimisation + 3 monthly session confirmations

### What to build

#### 7.1 — Parallel workflow trigger
- Shell script or Python script: `scripts/run_all.py`
- Triggers all 6 ETL workflows simultaneously via Temporal SDK
- Waits for completion; prints summary

#### 7.2 — Session summary report
After all workflows complete, generate a session summary:
```
Session summary — 2026-08-03
==============================
Chase:           42 trades synced, 0 errors
Merrill Lynch:   18 trades synced, 0 errors
Robinhood:       7 trades synced, 0 errors
India FM1:       12 trades synced, 0 errors
India FM2:       5 trades synced, 0 errors
India FM3:       3 trades synced, 0 errors
Corporate actions: 8 applied, 0 failed
Total active time: 8m 42s
```

#### 7.3 — Timing instrumentation
- Record wall-clock time from first workflow trigger to last CA applied
- Record active human time (time spent not waiting for automation)
- Log both to `etl_runs` for each session

### Exit tests — Stage 7

| # | Test | Pass condition |
|---|------|---------------|
| T7.1 | All 6 sources in one trigger | `run_all.py` completes with all 6 ETL workflows in Completed state |
| T7.2 | Session 1 timing | Active human time ≤10 min; recorded in `etl_runs` |
| T7.3 | Session 2 timing | Same; ≤10 min |
| T7.4 | Session 3 timing | Same; ≤10 min |
| T7.5 | No stale data | After session, Sharesight holdings match current broker portal balances (spot-check 5 positions) |
| T7.6 | Summary output | Session summary printed with per-source counts and total time |

**Stage 7 is done when all 6 tests pass across 3 real sessions (not the same day).**

---

## Stage 8 — Access, Docs & Runbook

**Goal:** The system is operable by both Samay and spouse. Documented well enough to pick up after a 3-month gap without re-learning.

**Time estimate:** 2–3 hours

### What to build

#### 8.1 — Sharesight spouse access
- Add spouse as viewer in Sharesight (confirm plan allows this)
- Verify spouse can see all portfolios and benchmarks

#### 8.2 — pgAdmin spouse access
- Add a read-only Postgres user: `CREATE USER spouse WITH PASSWORD '...'`
- Grant `SELECT` on all tables
- Share pgAdmin connection config

#### 8.3 — Session runbook (1 page)
Create `RUNBOOK.md`:
```
Monthly sync session — step by step

1. Download exports (5 min)
   - Chase: [URL] → Accounts → Download → CSV
   - ML: [URL] → Statements → Trade confirmations → CSV
   - Robinhood: [URL] → Account → History → Export
   - India FM1/FM2/FM3: [URL or email instructions]

2. Drop files
   - Drag to ~/investment-sync/drops/{source}/

3. Run sync
   - Option A: open http://localhost:8080 (Temporal UI) → click each workflow
   - Option B: run `python scripts/run_all.py` in terminal

4. Review corporate actions
   - Check Temporal UI for CorporateActionWorkflow status
   - Run `python scripts/approve_all_pending.py` when ready

5. Open Sharesight
   - https://portfolio.sharesight.com
   - Check session summary for any errors
```

#### 8.4 — Recovery docs
- What to do if Temporal is down: `docker compose up -d`
- What to do if Postgres is down: same
- What to do if a workflow fails: Temporal UI → workflow → retry from failed activity
- What to do if Sharesight API key expires: re-generate at [Sharesight developer settings URL]

### Exit tests — Stage 8

| # | Test | Pass condition |
|---|------|---------------|
| T8.1 | Spouse Sharesight access | Spouse logs into Sharesight; can see all portfolios and benchmark charts |
| T8.2 | Spouse pgAdmin access | Spouse connects via pgAdmin with read-only credentials; can query `trades` table |
| T8.3 | Cold start | Simulate 3-month gap: stop all Docker containers, restart, run session — system works without relearning |
| T8.4 | Runbook completeness | Another person (spouse) can complete a full sync session using only the runbook; no help needed |

**Stage 8 is done when all 4 tests pass. System is complete.**

---

## Summary Timeline (Rough)

| Stage | Estimated effort | When |
|-------|-----------------|------|
| S1 — Infra Up | Weekend 1 (3–4h) | Session 1 |
| S2 — Chase ETL | Weekend 1–2 (3–5h) | Session 1–2 |
| S3 — ML + Robinhood ETL | Weekend 2 (3–5h) | Session 2 |
| S4 — Historical Load | Weekend 2–3 (3–6h manual) | Session 2–3 |
| S5 — Corporate Actions | Weekend 3 (3–4h) | Session 3 |
| S6 — India ETL | Weekend 4 (4–6h) | Session 4 |
| S7 — Full Sync ≤10 min | Ongoing (confirmed over 3 sessions) | Sessions 5–7 |
| S8 — Access & Docs | Weekend 5 (2–3h) | Session 5 |

**Total build time:** ~5–6 focused weekend sessions over 2–3 months  
**Ongoing maintenance:** ≤10 min/session once fully operational

---

## Dependencies Between Stages

```
S1 (Infra)
  └─► S2 (Chase ETL)
        └─► S3 (ML + Robinhood)
              ├─► S4 (Historical load) ──┐
              └─► S5 (Corp actions) ─────┤
                                         ▼
                                    S6 (India ETL)
                                         │
                                         ▼
                                    S7 (Full sync timing)
                                         │
                                         ▼
                                    S8 (Access & docs)
```

S4 and S5 can be built in parallel after S3. S6 can start as soon as India fund manager sample exports are obtained — it's independent of S4/S5 from a code perspective.
