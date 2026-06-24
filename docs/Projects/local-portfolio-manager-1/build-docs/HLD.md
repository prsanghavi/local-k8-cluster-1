# HLD — Family Equity Portfolio Sync & Analysis System

**Version:** 0.1  
**Status:** Draft  
**Owner:** Samay  
**Last updated:** June 2026  
**Companion docs:** [PRD](./PRD.md) · [Build Plan](./BUILD-PLAN.md)

---

## 1. Overview

This system solves a data ingestion bottleneck: six broker/fund data sources need to be consolidated into a single analysis platform (Sharesight) within a ≤10 minute active time budget per session.

The architecture uses **local Postgres as the canonical source of truth** and **Sharesight as a read/analysis layer only**. No broker data goes directly to Sharesight — it always flows through Postgres first. This decouples broker export format changes from the analysis layer and makes portfolio restructuring a database operation, not a manual re-entry exercise.

**Temporal** orchestrates all data flows as observable, UI-triggerable workflows. The Temporal worker is Python. Six ETL workflows (one per broker) and one corporate action workflow can each be triggered independently from the Temporal UI without touching a terminal.

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                             │
│                                                                 │
│  [ML PDF]  [Chase CSV]  [Robinhood CSV]  [IN-FM1 Excel]        │
│                                  [IN-FM2 Excel]  [IN-FM3 Excel] │
└────────────────────────┬────────────────────────────────────────┘
                         │  manual file drop to watched folder
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    TEMPORAL (local / Docker)                     │
│                                                                 │
│   ETL Workflow × 6          Corporate Action Workflow           │
│   ┌─────────────────┐       ┌──────────────────────────┐       │
│   │ 1. Parse file   │       │ 1. Fetch suggestions API │       │
│   │ 2. Normalise    │       │ 2. Stage in Postgres     │       │
│   │ 3. Deduplicate  │       │ 3. Human review step     │       │
│   │ 4. Upsert PG    │       │ 4. Apply via v2 payout   │       │
│   │ 5. Sync to SS   │       │    endpoint (one-by-one) │       │
│   └─────────────────┘       └──────────────────────────┘       │
│                                                                 │
│   Python Worker  ◄──── Temporal Server (Docker)                │
└──────────────┬──────────────────────────┬───────────────────────┘
               │                          │
               ▼                          ▼
┌──────────────────────┐    ┌─────────────────────────────────────┐
│   LOCAL POSTGRES     │    │         SHARESIGHT API              │
│                      │    │                                     │
│  trades              │    │  POST /portfolios/{id}/trades       │
│  holdings            │    │  PUT  /portfolios/{id}/trades/{id}  │
│  corporate_actions   │    │  POST /payouts (v2, per event)      │
│  sync_log            │    │  GET  /portfolios/{id}/performance  │
│  etl_runs            │    │                                     │
└──────────────────────┘    └─────────────────────────────────────┘
                                          │
                                          ▼
                             ┌────────────────────────┐
                             │    SHARESIGHT UI        │
                             │                         │
                             │  Benchmark comparison   │
                             │  1M/3M/6M/1Y returns   │
                             │  Portfolio grouping     │
                             │  (Samay + spouse view)  │
                             └────────────────────────┘
```

---

## 3. Component Breakdown

### 3.1 File Drop Zone
A local directory (e.g. `~/investment-sync/drops/`) with subdirectories per source:
```
drops/
  merrill-lynch/
  chase/
  robinhood/
  india-fm1/
  india-fm2/
  india-fm3/
```
User places export files here before triggering workflows. No automation of the download step — the broker portals don't allow it and the 10-minute budget accounts for manual download + drop.

---

### 3.2 ETL Workflows (one per source, Python)

Each ETL workflow is a Temporal workflow with the following activity sequence:

| Step | Activity | Description |
|------|----------|-------------|
| 1 | `detect_new_files` | Scans drop folder for files newer than last successful run timestamp |
| 2 | `parse_file` | Source-specific parser; outputs normalised `RawTrade` records |
| 3 | `normalise_trades` | Maps to canonical `Trade` schema; resolves ticker symbols; applies FX for India |
| 4 | `deduplicate` | Checks Postgres for existing trade IDs; skips exact duplicates; flags conflicts |
| 5 | `upsert_postgres` | Inserts/updates `trades` table; updates `etl_runs` log |
| 6 | `sync_to_sharesight` | Calls Sharesight v3 API to create/update trades; records `sharesight_trade_id` |
| 7 | `mark_files_processed` | Moves processed files to `drops/{source}/processed/YYYY-MM-DD/` |

**Retry policy:** Steps 1–5 retry up to 3× with exponential backoff. Step 6 (Sharesight API) retries up to 5× with 2s/4s/8s backoff. Step 7 only runs after step 6 succeeds.

**Idempotency:** Each trade has a deterministic `trade_key` = `sha256(source + account_id + ticker + trade_date + quantity + price)`. Duplicate runs are safe.

---

### 3.3 Corporate Action Workflow (Python)

The corporate action problem is that Sharesight surfaces suggestions (dividends, splits, bonus issues) that must be confirmed before they are applied. The API supports applying them individually via the v2 payout endpoint — not in bulk. This workflow handles the backlog systematically.

| Step | Activity | Description |
|------|----------|-------------|
| 1 | `fetch_ca_suggestions` | GET Sharesight `/portfolios/{id}/trade_confirmations` or equivalent suggestion endpoint for each portfolio |
| 2 | `stage_suggestions` | Upsert into `corporate_actions` table with status = `pending` |
| 3 | `human_review_signal` | Temporal signal/pause — workflow surfaces staged suggestions in a simple review UI or CLI; user approves/rejects batch |
| 4 | `apply_approved` | For each approved CA: POST to Sharesight v2 `/payouts` endpoint sequentially; update status to `applied` |
| 5 | `log_results` | Write summary to `sync_log`; surface counts in Temporal UI |

**Human review step:** In phase 1 this is a simple pgAdmin query + manual approval flag. In phase 2 this could be a lightweight local web page. The Temporal workflow waits on a signal (human triggers "approve all pending" or selects individually).

---

### 3.4 Postgres Schema

#### `trades`
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | Internal ID |
| `trade_key` | TEXT UNIQUE | Deterministic dedup key |
| `source` | TEXT | `merrill_lynch`, `chase`, `robinhood`, `india_fm1`, `india_fm2`, `india_fm3` |
| `account_id` | TEXT | Broker account identifier |
| `ticker` | TEXT | Normalised ticker (US: NYSE/NASDAQ symbol; India: NSE symbol) |
| `trade_date` | DATE | Settlement or trade date |
| `trade_type` | TEXT | `BUY`, `SELL` |
| `quantity` | NUMERIC | Shares / units |
| `price_local` | NUMERIC | Price in local currency |
| `currency` | TEXT | `USD`, `INR` |
| `price_usd` | NUMERIC | USD equivalent at trade date (FX applied at ingest) |
| `fx_rate` | NUMERIC | INR/USD rate used (NULL for USD trades) |
| `broker_trade_id` | TEXT | Original ID from broker export (if present) |
| `sharesight_trade_id` | TEXT | ID returned by Sharesight after sync (NULL until synced) |
| `sharesight_portfolio_id` | TEXT | Which Sharesight portfolio this was synced to |
| `tags` | JSONB | `{"broker": "chase", "geography": "US", "strategy": "growth"}` |
| `synced_at` | TIMESTAMPTZ | Last successful Sharesight sync |
| `created_at` | TIMESTAMPTZ | |
| `updated_at` | TIMESTAMPTZ | |

#### `corporate_actions`
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `sharesight_suggestion_id` | TEXT UNIQUE | ID from Sharesight suggestion API |
| `ticker` | TEXT | |
| `ca_type` | TEXT | `dividend`, `split`, `bonus`, `rights` |
| `ex_date` | DATE | |
| `amount_local` | NUMERIC | Dividend per share or split ratio |
| `currency` | TEXT | |
| `status` | TEXT | `pending`, `approved`, `applied`, `rejected` |
| `sharesight_portfolio_id` | TEXT | |
| `applied_at` | TIMESTAMPTZ | |
| `created_at` | TIMESTAMPTZ | |

#### `etl_runs`
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `source` | TEXT | Which ETL source |
| `workflow_id` | TEXT | Temporal workflow ID |
| `run_id` | TEXT | Temporal run ID |
| `status` | TEXT | `running`, `succeeded`, `failed` |
| `files_processed` | INT | |
| `trades_inserted` | INT | |
| `trades_skipped` | INT | |
| `trades_failed` | INT | |
| `sharesight_synced` | INT | |
| `started_at` | TIMESTAMPTZ | |
| `completed_at` | TIMESTAMPTZ | |
| `error_detail` | TEXT | Last error if failed |

#### `sync_log`
| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `entity_type` | TEXT | `trade`, `corporate_action` |
| `entity_id` | UUID | FK to `trades` or `corporate_actions` |
| `direction` | TEXT | `to_sharesight` |
| `status` | TEXT | `success`, `failed` |
| `sharesight_response` | JSONB | Raw API response |
| `attempted_at` | TIMESTAMPTZ | |

---

### 3.5 Source-Specific ETL Parsers

| Source | Format | Key parsing challenges |
|--------|--------|----------------------|
| Merrill Lynch | PDF (forwarded to Sharesight) OR direct CSV if available from ML portal | PDF parsing brittle; prefer CSV from ML online portal if obtainable. Columns: Date, Symbol, Action, Quantity, Price, Amount |
| JP Morgan Chase | CSV | Date format varies; need to distinguish taxable vs. IRA accounts |
| Robinhood | CSV | Clean format; includes dividends in same file — separate at parse time |
| India FM1 (PMS) | Excel | Multi-sheet likely; trade date + INR price; ticker is NSE symbol |
| India FM2 (ETF/MF) | Excel/CSV | May include NAV-based pricing rather than market price for MFs |
| India FM3 (ETF/MF) | Excel/CSV | Same as FM2; confirm if units vs. shares language differs |

**India FX handling:** At parse time, fetch INR/USD rate for `trade_date` from a free FX API (e.g. `api.frankfurter.app` or `exchangerate.host`). Store both `price_local` (INR) and `price_usd`. Sharesight is loaded with INR prices and currency = INR; it handles its own FX for display.

---

### 3.6 Temporal Setup

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Temporal server | Docker Compose (local) | Simple to run; no cloud dependency; persistent with volume mount |
| Worker language | Python | Matches Samay's ETL scripting preference; rich CSV/Excel parsing ecosystem |
| Worker registration | Single worker process, all workflows + activities registered | Low complexity for personal use; split if latency becomes an issue |
| Temporal UI | Bundled web UI (port 8080) | Workflow trigger, status, retry — all from browser |
| Persistence | SQLite (Temporal dev mode) → Postgres (same instance, separate DB) for production | Start simple; migrate when needed |

**Workflow triggering:** In phase 1, workflows are triggered via the Temporal UI "Start Workflow" button with a JSON input specifying the source. In phase 2, a simple shell script or local web page can trigger all 6 with one click.

---

### 3.7 Sharesight API Integration

| Operation | Endpoint | Notes |
|-----------|----------|-------|
| List portfolios | `GET /portfolios` | Run at startup to cache portfolio IDs |
| Create trade | `POST /portfolios/{id}/trades` | Primary sync operation |
| Update trade | `PUT /portfolios/{id}/trades/{trade_id}` | Used when a trade is amended in source |
| Delete trade | `DELETE /portfolios/{id}/trades/{trade_id}` | Used for erroneous trades |
| Fetch CA suggestions | `GET /portfolios/{id}/trade_confirmations` | Pull pending suggestions |
| Apply CA (dividend etc.) | `POST /payouts` (v2 endpoint) | Applied one-by-one per suggestion |
| Performance report | `GET /portfolios/{id}/performance` | For verification; primary analysis done in Sharesight UI |

**Auth:** OAuth 2.0 client credentials. Store `client_id` and `client_secret` in a local `.env` file (never committed to git). Token refresh handled by the Sharesight Python SDK or a thin wrapper.

**Rate limits:** Sharesight imposes rate limits (exact numbers subject to plan — verify). The Sharesight sync activity includes a configurable `sleep_between_calls` parameter (default: 0.5s) to stay within limits.

---

## 4. Data Flow — Ongoing Sync Session

```
Saturday morning session (target: ≤10 min active time)

T+0:00  Download exports from 6 broker portals (manual, ~5 min)
T+5:00  Drop files into ~/investment-sync/drops/{source}/
T+5:30  Open Temporal UI → trigger 6 ETL workflows (30 sec)
T+6:00  Temporal runs ETL workflows in parallel (automated, ~3-5 min)
T+6:00  Trigger Corporate Action workflow (30 sec)
T+6:30  Review CA suggestions in Temporal UI / pgAdmin, approve (2-3 min)
T+9:30  Workflows complete; Sharesight updated
T+10:00 ✓ Open Sharesight for analysis
```

---

## 5. Data Flow — One-Time Historical Load

```
One-time exercise (estimated: 3-4 focused hours over 1-2 weekends)

1. Export all available broker history (max 2Y CSV/PDF)
2. Drop into ETL pipeline → auto-ingested via ETL workflow
3. For pre-2Y gap: log into bank UI / retrieve tax statements
4. Enter missing trades into Postgres directly via pgAdmin
   (using trade_entry_template.csv → bulk import)
5. Run Sharesight sync workflow for all sources
6. Trigger Corporate Action workflow to clear historical backlog
7. Verify in Sharesight: no "unknown cost basis" warnings
```

---

## 6. Design Decisions

| Decision | Resolution | Rationale |
|----------|------------|-----------|
| Postgres as source of truth vs. Sharesight as source of truth | Postgres | Broker format changes, portfolio restructuring, and historical edits are all cheaper against a local DB. Sharesight is a sync target, not the record of record. |
| Temporal vs. cron scripts | Temporal | Visibility, retry handling, human-in-the-loop steps (CA review), and UI-triggerable execution are all requirements. Cron scripts have none of these. |
| Python for worker | Python | Best ecosystem for CSV/Excel/PDF parsing (pandas, openpyxl, pdfplumber). Temporal Python SDK is mature. |
| Single worker vs. per-source workers | Single worker, all workflows | Personal use scale; simpler to run and maintain. Can split later. |
| Corporate actions: bulk accept vs. one-by-one via workflow | One-by-one via Temporal workflow | Sharesight v2 payout endpoint is per-event. Temporal workflow makes this observable and resumable. |
| FX rates: real-time vs. trade-date | Trade-date FX for cost basis; current spot surfaced by Sharesight | Correct accounting practice; Sharesight handles display-time conversion natively. |
| India MF pricing: NAV vs. market price | Store NAV as price for MFs; flag as `instrument_type = mutual_fund` | MFs don't have market prices; Sharesight supports fund NAV tracking. |
| Historical gap: automated reconstruction vs. manual entry | Manual entry into Postgres once, never again | Tax statements have the data; automation not worth the complexity for a one-time exercise. |

---

## 7. Open Questions / To Verify

| # | Question | Impact |
|---|----------|--------|
| HQ1 | Exact Sharesight endpoint for fetching CA suggestions — is it `trade_confirmations` or another path? | Corporate action workflow design |
| HQ2 | Sharesight rate limit (calls/min or calls/day) on current plan | Determines `sleep_between_calls` tuning |
| HQ3 | Can Temporal dev server use Postgres for persistence, or does it need separate setup? | Infra setup complexity |
| HQ4 | Indian PMS (FM1) Excel format — is it one sheet per month or cumulative? | ETL parser complexity |
| HQ5 | Robinhood CSV: does it include fractional shares and DRIP dividends? | Parser edge cases |
