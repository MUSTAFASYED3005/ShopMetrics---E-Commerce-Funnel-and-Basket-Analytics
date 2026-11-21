# ShopMetrics: E-Commerce Funnel, Attribution & Merchandising

An end-to-end analytics project that turns a month of raw e-commerce clickstream data (December 2019) into a funnel diagnostics model in PostgreSQL, a Power BI dashboard, and data-driven cross-sell bundle recommendations.

**Stack:** Python (pandas, SQLAlchemy) · PostgreSQL · Power BI

---

## Dashboard Preview

![ShopMetrics dashboard](shopmetricbi.png)

> Export the dashboard as `shopmetricbi.png` (or update the path above). A PDF export is included as `shopmetricbi.pdf`.

---

## Architecture

```
2019-Dec.csv  ──►  Python ETL  ──►  PostgreSQL  ──►  Power BI
 (raw events)      clean, sample,    star schema,     KPIs, funnel,
                   build dims,       fact tables,     attribution,
                   mine baskets      diagnostic view  cross-sell rules
```

| Stage | What it does |
|---|---|
| **1. Python** | Loads the CSV, removes rows with missing user/session/product IDs or non-positive prices, and samples 150,000 sessions (seed 42, ~630K events). Builds `dim_products`, `dim_users` and `dim_session_attribution`, loads them with `raw_events` into PostgreSQL, then mines product-pair association rules from purchase baskets into `mart_basket_rules`. |
| **2. PostgreSQL** | Builds `fct_sessions` (one row per session: funnel flags, exit stage, revenue) and `fct_user_journey` (one row per user: segment, lifetime revenue), adds keys and indexes, and exposes `vw_funnel_diagnostics` for slicing by traffic source, device and country. |
| **3. Power BI** | Dashboard with source/device/country slicers: KPI cards, conversion funnel, revenue and conversion by channel, session exit stage by device, daily revenue, and a cross-sell rules table. |

---

## KPI Definitions

| Metric | Formula | Baseline |
|---|---|---|
| Sessions | `COUNT(DISTINCT session_id)` | 150,000 |
| Conversion rate | Sessions with a purchase ÷ total sessions | 3.43% |
| Cart abandonment | Cart sessions with no purchase ÷ cart sessions | 83.16% |
| Checkout friction | Cart sessions with a `remove_from_cart` or ≥3 cart adds ÷ cart sessions | 58.63% |
| Revenue | `SUM(price)` of purchase events | $189.25K |
| AOV | Revenue ÷ converted sessions | $36.78 |

**Session exit stages** (used in the device breakdown): `1. Direct Bounce`, `2. Product View Only`, `3a. Cart Abandoned`, `3b. Cart Friction (Removed Item)`, `4. Purchased`.

**Customer segments** (`fct_user_journey`): Repeat Customer, One-Time Buyer, Cart Abandoner, Window Shopper.

---

## Key Findings

- **The cart is the main leak.** Roughly 4 in 5 cart sessions end without a purchase, and about 3 in 5 show friction (item removals or repeated adds).
- **Channel:** Organic Search and Paid Social drive the most revenue; conversion stays in a narrow band (~3.2%–3.6%) across channels.
- **Device:** The exit-stage mix is nearly identical across Mobile, Desktop and Tablet.
- **Cross-sell:** Only one product pair shows a strong association (lift > 20); the rest fall between roughly 1.7 and 6 and are better suited to widgets or post-purchase emails.

### Top Bundle Recommendations

| Anchor | Add-on | Attach % | Lift | Bundle (10% off) |
|---|---|---|---|---|
| Insight Gel Nail Polish #0496 | Insight Setting Powder #0494 | 100 | 26.71 | $1,698.00 |
| Irisk Hair Repair Oil #1279 | Irisk Skincare Serum #1278 | 100 | 5.99 | $1,273.50 |
| Freedecor Hydrating Cream #1620 | Freedecor Hair Repair Oil #1619 | 100 | 4.28 | $1,273.50 |
| Dermal Setting Powder #4305 | Dermal Hydrating Cream #4309 | 100 | 1.85 | $1,273.50 |
| Airnails Gel Nail Polish #9771 | Airnails Skincare Serum #9772 | 100 | 1.71 | $1,698.00 |

Merchandising action logic (from the notebook): lift ≥ 20 and confidence ≥ 25% → Cart Drawer 1-Click Cross-Sell; lift ≥ 10 → "Frequently Bought Together" widget; otherwise → post-purchase email upsell. Pairs need at least 3 co-purchases.

---

## Repository Structure

```
.
├── shpmtrc.ipynb           # Python ETL + basket rule mining
├── shpmtric.sql            # PostgreSQL modelling + analysis queries
├── shopmetricbi.pbix       # Power BI dashboard
├── shopmetricbi.pdf        # Dashboard PDF export
├── basket_recommendations.csv   # Generated: top 50 cross-sell rules
└── README.md
```

The raw dataset (`2019-Dec.csv`) is not included because of its size.

---

## Getting Started

### Prerequisites

- Python 3.10+ with `pandas`, `numpy`, `sqlalchemy`, `psycopg2-binary`, `jupyter`
- PostgreSQL 13+
- Power BI Desktop (Windows)
- The `2019-Dec.csv` file from the Kaggle "eCommerce events history in cosmetics shop" dataset

### Run it

1. **Create the database**
   ```sql
   CREATE DATABASE shopmetricsdb;
   ```
2. **Configure the notebook.** Set `DB_USER`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT` and `DB_NAME` in both notebook cells (use the same database name in both), and set `csv_path` to where you saved `2019-Dec.csv`. Prefer environment variables over hardcoding credentials, and never commit real passwords.
3. **Run the ETL cell** in `shpmtrc.ipynb` to load `raw_events` and the dimension tables.
4. **Run `shpmtric.sql`** in psql, pgAdmin or DBeaver to build `fct_sessions`, `fct_user_journey` and `vw_funnel_diagnostics`.
5. **Run the basket-mining cell** to create `mart_basket_rules` and `basket_recommendations.csv`.
6. **Open `shopmetricbi.pbix`**, point the data source to your PostgreSQL instance, and refresh.

---

## Data Notes and Limitations

- **Traffic source, device type and country are simulated.** They are not in the original dataset; the ETL assigns them randomly with fixed probabilities. Channel and device comparisons are therefore illustrative, not real attribution findings.
- Product names and categories are partly generated: missing brands default to "Lumina Beauty" and missing categories are filled from a list of cosmetic categories.
- The data is a 150,000-session sample of one month, so results will not generalise to other periods.

---

## License

Add your preferred license here (for example MIT).
