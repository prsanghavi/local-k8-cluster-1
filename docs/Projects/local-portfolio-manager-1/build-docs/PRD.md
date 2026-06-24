# PRD — Family Equity Portfolio Sync & Analysis System

**Version:** 1.0  
**Status:** Locked  
**Owner:** Samay and Priyanka
**Last updated:** June 2026  
**Companion docs:** [HLD](./HLD.md) · [Build Plan](./BUILD-PLAN.md)

---

## 1. Problem Statement

Managing family equity investments across six brokerages — Merrill Lynch (ML), JP Morgan Chase, Robinhood (US), and three Indian fund managers — spanning **seven ingestion points** (one brokerage holds two separate accounts/portfolios) currently consumes 4–5 hours of manual data ingestion work before any analysis can begin. Given a time budget of only a few hours every other weekend or once a month, the entire session is consumed by data preparation, leaving zero time for performance analysis, strategy development, or trade execution.

The core pain is a **data ingestion bottleneck**, not an analytical shortfall. Once data is current and trustworthy, the analysis and decision-making work can happen naturally.

---

## 2. Current State & Pain Points

### 2.1 Platform in use
Sharesight (subscribed ~2 months ago) is the chosen analysis layer. The US portfolio setup is partially underway. Sharesight has been confirmed as the target platform — its v3 REST API supports trade creation/update, portfolio management, and performance reporting. Corporate action suggestions can be applied individually via the v2 payout endpoint; bulk approval will be handled through a Temporal workflow.

### 2.2 Specific pain points

| # | Problem | Root Cause | Impact |
|---|---------|------------|--------|
| P1 | Chase and ML don't natively integrate with Sharesight | No broker API/direct feed available | Manual CSV/PDF upload every session |
| P2 | CSV/PDF imports capped at last 2 years of trade history | Broker export limitation | All pre-2024 holdings require manual entry |
| P3 | Dividends, splits, and corporate actions appear as unconfirmed Sharesight suggestions | Sharesight cannot auto-apply without confirmed cost basis | Manual acceptance per event per stock |
| P4 | 300–400 positions across 7 ingestion points (~60% unique ≈ 180–240 unique stocks) | Scale amplifies P3 | Hours of clicking per session |
| P5 | Portfolio structure is rigid in Sharesight — reorganising requires full re-entry | Sharesight's portfolio is the import unit | Structural decisions cannot be changed cheaply |
| P6 | India portfolios not yet onboarded | Format and currency conversion layer not yet established | Significant blind spot in family net worth |

### 2.3 Time budget reality

| Activity | Current | Target |
|----------|---------|--------|
| Data ingestion & reconciliation | 4–5 hours | ≤10 minutes active human time |
| Analysis, strategy & execution | 0 hours remaining | Remainder of session |

---

## 3. Goals

### Primary goal
Reduce active data ingestion time from 4–5 hours to ≤10 minutes per session, so that analysis and execution become the default use of available time.

### Secondary goals
- Full consolidated portfolio visibility across all 7 ingestion points in USD-equivalent terms
- Accurate alpha measurement vs. S&P 500 (US) and Nifty 50 dollar-adjusted (India) at 1M / 3M / 6M / 1Y / all-time horizons
- Portfolio restructuring by broker, geography, or strategy tag without re-import cost
- Canonical data store in local Postgres that is the source of truth — Sharesight is the analysis/reporting layer only
- Both Samay and Priyanka can fully operate the system: ingestion (Temporal UI), the Postgres DB (pgAdmin read/write), and analysis (Sharesight shared login or multi-user) — so either can run a session
- Resilience: data survives a 2–3 month gap between sessions without re-ingestion

---

## 4. Non-Goals (Explicit Out of Scope)

- Automated trade execution
- Tax optimisation or reporting (potential future phase)
- Real-time price alerts or push notifications
- Options, futures, derivatives, or crypto tracking
- Building a custom analytics frontend — Sharesight is the analysis layer
- Replacing Sharesight with a self-hosted tool (Ghostfolio etc.) unless Sharesight API proves insufficient

---

## 5. Users

| User | Access level | Interface |
|------|-------------|-----------|
| Samay | Full — ingestion, review, analysis, execution | Temporal UI, pgAdmin (read/write), Sharesight |
| Priyanka | Full — ingestion, review, analysis, execution | Temporal UI, pgAdmin (read/write), Sharesight |

---

## 6. Data Sources

| # | Source | Country | Asset type | Export format | Sharesight status |
|---|--------|---------|------------|---------------|-------------------|
| 1 | Merrill Lynch | US | Direct equity | Trade confirmation PDFs → Sharesight email parser | Partially imported; pre-2Y gap |
| 2 | JP Morgan Chase | US | Direct equity | CSV export from portal | Partially imported; pre-2Y gap |
| 3 | Robinhood | US | Direct equity | CSV export | Not yet started |
| 4 | India PMS — Samatva (Ashwin) — Rashmi | IN | PMS (direct equity) | Excel/CSV | Not started |
| 5 | India PMS — Samatva (Ashwin) — Jalaja | IN | PMS (direct equity) | Excel/CSV | Not started |
| 6 | India — Optimus (Varun) — Rashmi | IN | ETF + Mutual Funds | Excel/CSV | Not started |
| 7 | India — Kalki (Abhinav) — Jalaja | IN | ETF + Mutual Funds | Excel/CSV | Not started |

**Note:** Samatva's two PMS accounts (Rashmi and Jalaja) are separate ingestion points (separate exports), bringing the total to 7 ingestion points across 6 brokerages.

**Historical gap (US):** All pre-2024 US holdings will be reconstructed as a one-time exercise using bank UI / tax statements. Data entry goes directly into Postgres via a structured template; Sharesight is loaded from Postgres.

---

## 7. Key Requirements

### R1 — Canonical Postgres store
All trade, holding, and corporate action data is stored in a local Postgres database. Sharesight is populated from Postgres, not directly from broker exports. This decouples broker format changes from the analysis layer and makes portfolio restructuring free.

**Acceptance:** Any Sharesight portfolio can be fully reconstructed from Postgres without re-touching broker exports.

---

### R2 — Historical holdings reconstruction (one-time)
Pre-2024 ML and Chase holdings are entered into Postgres once, with correct cost basis, acquisition date, and broker tag. Robinhood and India holdings are entered at initial onboarding.

**Acceptance:** All current holdings across all 6 sources have a cost basis and acquisition date in Postgres. Sharesight shows no "unknown cost basis" warnings for any holding.

---

### R3 — Repeatable sync in ≤10 minutes (ongoing)
Each session's full ingestion step — all 7 ingestion points — completes in ≤10 minutes of active human time. This means: drop/upload export files, trigger Temporal workflows from UI, review summary, done.

**Acceptance:** Timed across 3 consecutive monthly sessions; active human time ≤10 min each.

---

### R4 — Corporate action workflow
Sharesight corporate action suggestions (dividends, splits, bonus issues) are retrieved via API, staged in Postgres, and applied to Sharesight one-by-one via the v2 payout endpoint through a Temporal workflow. The workflow is UI-triggerable and shows progress.

**Acceptance:** Corporate action backlog for a normal month (≤20 events across 300 positions) is cleared in ≤5 minutes of human review time.

---

### R5 — India portfolio onboarding
All three Indian fund managers are represented in Postgres and Sharesight. INR cost basis is stored natively; USD-equivalent values use trade-date FX for cost basis and current spot for market value.

**Acceptance:** India holdings visible in Sharesight with benchmark comparison vs. Nifty 50 or BSE Sensex.

---

### R6 — Flexible portfolio grouping
Sharesight portfolio structure can be reorganised (by broker, geography, strategy) by updating Postgres tags and re-syncing — not by re-entering trades.

**Acceptance:** Regrouping all positions from broker-based to strategy-based grouping takes under 30 minutes including sync, with no manual trade re-entry.

---

### R7 — Benchmark comparison
1M / 3M / 6M / 1Y performance is visible vs. S&P 500 (US) and a dollar-adjusted India index (India).

**Acceptance:** Sharesight displays benchmark-relative returns for each portfolio group at the above horizons.

---

## 8. Architecture Decision (Locked)

```
Broker exports (CSV/PDF/Excel)
        ↓
  ETL scripts (Python, per source)
        ↓
  Local Postgres  ←── manual entry (historical gap)
  (source of truth)
        ↓
  Temporal workflows (Python worker)
        ↓
  Sharesight API (v3 trades, v2 payouts)
        ↓
  Sharesight UI  ←── analysis, benchmark comparison
```

Temporal is confirmed as the orchestration layer (Samay has prior Temporal experience). It provides workflow orchestration, UI-triggered execution, visibility into each ETL run, retry handling, and audit log. Seven ETL workflows (one per ingestion point) plus one corporate action workflow run independently and can be triggered from the Temporal UI without touching the command line.

---

## 9. Success Definition

> On a Saturday morning, in ≤10 minutes of active effort, Samay drops 7 export files, clicks "Run All" in the Temporal UI, watches the workflows complete, and spends the rest of the session on analysis and trades — not data plumbing.

### Milestones

| ID | Milestone | Done when |
|----|-----------|-----------|
| M1 | Infra up | Postgres + Temporal running locally; dummy trade inserted and synced to Sharesight via API |
| M2 | US historical complete | All ML + Chase + Robinhood holdings in Postgres with cost basis; Sharesight loaded |
| M3 | US ETL automated | All 3 US ETL workflows running end-to-end; sync time ≤5 min |
| M4 | Corporate action workflow live | Monthly corporate action backlog cleared in ≤5 min |
| M5 | India onboarded | All 3 Indian sources in Postgres and Sharesight with INR/USD values |
| M6 | Full sync ≤10 min | All 7 ingestion points + corporate actions in ≤10 min, confirmed over 3 sessions |
| M7 | Analysis live | 1/3/6M vs benchmarks visible; spouse access confirmed |

---

## 10. Open Questions

| # | Question | Owner | Status |
|---|----------|-------|--------|
| OQ1 | Exact column formats from 3 Indian fund manager Excel/CSV exports | Samay — request sample statements | Open |
| OQ2 | Sharesight plan — confirm API access is enabled and portfolio limit (should be 10) | Samay | Open |
| OQ3 | Sharesight multi-user — confirm spouse can be added as viewer on current plan | Samay | Open |
| OQ4 | India PMS Samatva export: does it include trade-date FX rate or just INR amounts? | Samay — check with Samatva (Ashwin) | Open |
| OQ5 | Do India PMS Samatva's two accounts (Rashmi, Jalaja) share one parameterized ETL workflow (run per-account) or two separate workflows? | HLD decision | Open — defer to HLD |
