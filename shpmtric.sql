


-- 1. Indexing raw_events for fast aggregation
CREATE INDEX idx_raw_events_session ON raw_events(session_id);
CREATE INDEX idx_raw_events_user ON raw_events(user_id);
CREATE INDEX idx_raw_events_type ON raw_events(event_type);

-- 2. Building session-level fact table (fct_sessions)
CREATE TABLE fct_sessions AS
WITH session_events AS (
    SELECT
        session_id,
        MIN(user_id) AS user_id,
        MIN(event_time) AS session_start,
        MAX(event_time) AS session_end,
        EXTRACT(EPOCH FROM (MAX(event_time) - MIN(event_time)))::INT AS duration_sec,
        COUNT(*) AS total_events,
        COUNT(CASE WHEN event_type = 'view' THEN 1 END) AS view_events,
        COUNT(CASE WHEN event_type = 'cart' THEN 1 END) AS cart_add_events,
        COUNT(CASE WHEN event_type = 'remove_from_cart' THEN 1 END) AS cart_remove_events,
        COUNT(CASE WHEN event_type = 'purchase' THEN 1 END) AS purchase_events,
        MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS raw_view,
        MAX(CASE WHEN event_type IN ('cart', 'remove_from_cart') THEN 1 ELSE 0 END) AS raw_cart,
        MAX(CASE WHEN event_type = 'remove_from_cart' THEN 1 ELSE 0 END) AS has_remove,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase,
        COALESCE(SUM(CASE WHEN event_type = 'purchase' THEN price ELSE 0 END), 0)::NUMERIC(12,2) AS session_revenue
    FROM raw_events
    GROUP BY session_id
),
normalized_flags AS (
    SELECT
        se.*,
        GREATEST(se.raw_cart, se.has_purchase) AS has_cart,
        GREATEST(se.raw_view, se.raw_cart, se.has_purchase) AS has_view
    FROM session_events se
)
SELECT
    nf.session_id,
    nf.user_id,
    nf.session_start,
    nf.session_end,
    nf.duration_sec,
    attr.traffic_source,
    attr.device_type,
    attr.country,
    nf.total_events,
    nf.view_events,
    nf.cart_add_events,
    nf.cart_remove_events,
    nf.purchase_events,
    nf.has_view,
    nf.has_cart,
    nf.has_purchase,
    CASE WHEN nf.has_cart = 1 AND nf.has_purchase = 0 THEN 1 ELSE 0 END AS is_cart_abandoned,
    CASE WHEN nf.has_cart = 1 AND (nf.has_remove = 1 OR nf.cart_add_events >= 3) THEN 1 ELSE 0 END AS has_checkout_friction,
    CASE
        WHEN nf.has_purchase = 1 THEN '4. Purchased'
        WHEN nf.has_cart = 1 AND nf.has_remove = 1 THEN '3b. Cart Friction (Removed Item)'
        WHEN nf.has_cart = 1 THEN '3a. Cart Abandoned'
        WHEN nf.has_view = 1 THEN '2. Product View Only'
        ELSE '1. Direct Bounce'
    END AS exit_stage,
    nf.session_revenue
FROM normalized_flags nf
LEFT JOIN dim_session_attribution attr
    ON nf.session_id = attr.session_id;

-- 3. Building user-level journey fact table (fct_user_journey)
CREATE TABLE fct_user_journey AS
SELECT
    user_id,
    MIN(session_start) AS first_session_at,
    MAX(session_start) AS last_session_at,
    COUNT(session_id) AS total_sessions,
    SUM(has_view) AS total_view_sessions,
    SUM(has_cart) AS total_cart_sessions,
    SUM(has_purchase) AS total_orders,
    SUM(session_revenue)::NUMERIC(12,2) AS lifetime_revenue,
    CASE WHEN SUM(has_purchase) > 1 THEN 1 ELSE 0 END AS is_repeat_buyer,
    CASE
        WHEN SUM(has_purchase) >= 2 THEN 'Repeat Customer'
        WHEN SUM(has_purchase) = 1 THEN 'One-Time Buyer'
        WHEN SUM(has_cart) >= 1 THEN 'Cart Abandoner'
        ELSE 'Window Shopper'
    END AS customer_segment
FROM fct_sessions
GROUP BY user_id;

-- 4. Adding Primary & Foreign Keys (Star Schema constraints)
ALTER TABLE dim_products ADD PRIMARY KEY (product_id);
ALTER TABLE dim_users ADD PRIMARY KEY (user_id);
ALTER TABLE dim_session_attribution ADD PRIMARY KEY (session_id);
ALTER TABLE fct_sessions ADD PRIMARY KEY (session_id);
ALTER TABLE fct_user_journey ADD PRIMARY KEY (user_id);

ALTER TABLE fct_sessions
    ADD CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES dim_users(user_id),
    ADD CONSTRAINT fk_sessions_attr FOREIGN KEY (session_id) REFERENCES dim_session_attribution(session_id);

CREATE INDEX idx_fct_sessions_user ON fct_sessions(user_id);
CREATE INDEX idx_fct_sessions_start ON fct_sessions(session_start);

-- 5. Creating diagnostic funnel view
CREATE OR REPLACE VIEW vw_funnel_diagnostics AS
SELECT
    traffic_source,
    device_type,
    country,
    COUNT(*) AS total_sessions,
    SUM(has_view) AS view_sessions,
    SUM(has_cart) AS cart_sessions,
    SUM(has_purchase) AS converted_sessions,
    ROUND(100.0 * SUM(has_purchase) / NULLIF(COUNT(*), 0), 2) AS conversion_rate_pct,
    ROUND(100.0 * SUM(is_cart_abandoned) / NULLIF(SUM(has_cart), 0), 2) AS cart_abandonment_pct,
    ROUND(100.0 * SUM(has_checkout_friction) / NULLIF(SUM(has_cart), 0), 2) AS checkout_friction_pct,
    SUM(session_revenue) AS total_revenue,
    ROUND(SUM(session_revenue) / NULLIF(SUM(has_purchase), 0), 2) AS aov
FROM fct_sessions
GROUP BY traffic_source, device_type, country;

-- 6. Verifying row counts
SELECT 
    (SELECT COUNT(*) FROM dim_users) AS total_users,
    (SELECT COUNT(*) FROM fct_sessions) AS total_sessions,
    (SELECT COUNT(*) FROM fct_user_journey) AS user_journeys,
    (SELECT COUNT(*) FROM vw_funnel_diagnostics) AS diagnostic_segments;



-- DATA ANALYSIS --

--Executive Summary KPIs
SELECT 
    COUNT(*) AS total_sessions,
    SUM(has_view) AS product_view_sessions,
    SUM(has_cart) AS cart_add_sessions,
    SUM(has_purchase) AS converted_sessions,
    ROUND(SUM(has_purchase)::NUMERIC / COUNT(*) * 100, 2) AS conversion_rate_pct,
    ROUND(SUM(is_cart_abandoned)::NUMERIC / NULLIF(SUM(has_cart), 0) * 100, 2) AS cart_abandonment_pct,
    ROUND(SUM(has_checkout_friction)::NUMERIC / NULLIF(SUM(has_cart), 0) * 100, 2) AS checkout_friction_pct,
    ROUND(SUM(session_revenue)::NUMERIC, 2) AS total_revenue,
    ROUND((SUM(session_revenue) / NULLIF(SUM(has_purchase), 0))::NUMERIC, 2) AS aov
FROM fct_sessions;



--Campaign-to-Sales Attribution by Traffic Source
SELECT 
    traffic_source,
    COUNT(*) AS sessions,
    SUM(has_purchase) AS orders,
    ROUND(SUM(has_purchase)::NUMERIC / COUNT(*) * 100, 2) AS conversion_rate_pct,
    ROUND(SUM(is_cart_abandoned)::NUMERIC / NULLIF(SUM(has_cart), 0) * 100, 2) AS cart_abandonment_pct,
    ROUND(SUM(session_revenue)::NUMERIC, 2) AS revenue,
    ROUND((SUM(session_revenue) / NULLIF(SUM(has_purchase), 0))::NUMERIC, 2) AS aov
FROM fct_sessions
GROUP BY traffic_source
ORDER BY revenue DESC;



--Device Friction & Drop-Off Diagnostics
SELECT 
    device_type,
    COUNT(*) AS sessions,
    SUM(has_cart) AS cart_adds,
    SUM(has_purchase) AS orders,
    ROUND(SUM(has_purchase)::NUMERIC / COUNT(*) * 100, 2) AS conversion_rate_pct,
    ROUND(SUM(is_cart_abandoned)::NUMERIC / NULLIF(SUM(has_cart), 0) * 100, 2) AS cart_abandonment_pct,
    ROUND(SUM(has_checkout_friction)::NUMERIC / NULLIF(SUM(has_cart), 0) * 100, 2) AS friction_rate_pct
FROM fct_sessions
GROUP BY device_type
ORDER BY sessions DESC;



--Geographic Conversion & Revenue Breakdown
SELECT 
    country,
    COUNT(*) AS sessions,
    SUM(has_purchase) AS orders,
    ROUND(SUM(has_purchase)::NUMERIC / COUNT(*) * 100, 2) AS conversion_rate_pct,
    ROUND(SUM(is_cart_abandoned)::NUMERIC / NULLIF(SUM(has_cart), 0) * 100, 2) AS cart_abandonment_pct,
    ROUND(SUM(session_revenue)::NUMERIC, 2) AS revenue
FROM fct_sessions
GROUP BY country
ORDER BY revenue DESC;



--Daily Conversion & Revenue Trend
SELECT 
    DATE(session_start) AS session_date,
    COUNT(*) AS sessions,
    SUM(has_purchase) AS orders,
    ROUND(SUM(has_purchase)::NUMERIC / COUNT(*) * 100, 2) AS conversion_rate_pct,
    ROUND(SUM(session_revenue)::NUMERIC, 2) AS daily_revenue
FROM fct_sessions
GROUP BY DATE(session_start)
ORDER BY session_date;
