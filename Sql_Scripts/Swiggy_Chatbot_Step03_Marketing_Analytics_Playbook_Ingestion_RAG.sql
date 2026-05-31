-- =============================================================================
-- SWIGGY MARKETING PLAYBOOK — RAG CHUNKING PIPELINE
-- Database : SWIGGY_MASTER
-- Schema   : DEV
-- Purpose  : Store semantically meaningful, hierarchy-aware chunks from the
--            Swiggy Marketing Campaign Playbook for Cortex Search / RAG use.
-- Author   : Swiggy Marketing Analytics & Ops
-- Version  : 1.0  |  FY 2025
-- =============================================================================

USE DATABASE SWIGGY_MASTER;
USE SCHEMA DEV;
USE ROLE "Dev Role";


-- =============================================================================
-- STEP 1 — DDL : PLAYBOOK CHUNKS TABLE
-- =============================================================================
-- Design principles:
--   • Every chunk carries its full structural address (chapter → section →
--     subsection) so the LLM always has provenance context.
--   • chunk_text stores the *enriched* content — breadcrumb prefix + body —
--     so that even an isolated chunk is self-explanatory to the retriever.
--   • chunk_text_raw stores the body-only text for display / citation purposes.
--   • embedding stores the dense vector produced by Cortex EMBED_TEXT_768.
--   • Separate metadata columns (chunk_type, campaign_id_ref, signal_category)
--     allow structured pre-filtering before vector search.
-- =============================================================================

CREATE OR REPLACE TABLE SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_CHUNKS (

    -- ── Identity ──────────────────────────────────────────────────────────────
    chunk_id                INTEGER AUTOINCREMENT PRIMARY KEY,
    source_document         VARCHAR(200)   NOT NULL  DEFAULT 'Swiggy Marketing Campaign Playbook v2.0',

    -- ── Structural Hierarchy ──────────────────────────────────────────────────
    chapter_number          INTEGER        NOT NULL,   -- 1 – 10
    chapter_title           VARCHAR(200)   NOT NULL,
    section_number          VARCHAR(20),               -- e.g. '3.1', '5.2'
    section_title           VARCHAR(300),
    subsection_title        VARCHAR(300),              -- heading-3 level; NULL if N/A
    chunk_sequence          INTEGER        NOT NULL,   -- ordering within a section
    full_path               VARCHAR(600)   NOT NULL,   -- breadcrumb: "Ch3 > 3.1 > Cat A"

    -- ── Content ───────────────────────────────────────────────────────────────
    chunk_type              VARCHAR(50)    NOT NULL,
    -- Allowed: OVERVIEW | BULLET_LIST | NUMBERED_LIST | TABLE_DATA |
    --          SQL_SNIPPET | CAMPAIGN_BRIEF | DECISION_LOGIC | COMPLIANCE |
    --          GLOSSARY | CHECKLIST | SCENARIO

    chunk_text_raw          VARCHAR(8000)  NOT NULL,   -- clean body text (no prefix)
    chunk_text              VARCHAR(8000)  NOT NULL,   -- breadcrumb + body (fed to embedder)

    -- ── Metadata for Pre-Filtering ────────────────────────────────────────────
    campaign_id_ref         VARCHAR(50),               -- PUSH_101 | POPUP_202 | etc. | NULL
    signal_category         VARCHAR(10),               -- A | B | C | D | NULL
    coupon_id_ref           VARCHAR(50),               -- WELCOME50 | SAVE80 | etc. | NULL
    channel_ref             VARCHAR(50),               -- PUSH | EMAIL | INAPP_POPUP | PAID_MEDIA | NULL
    priority_level          VARCHAR(20),               -- URGENT | HIGH | MEDIUM | LOW | NULL

    -- ── Vector Embedding ─────────────────────────────────────────────────────
    -- Snowflake Cortex EMBED_TEXT_768 produces a 768-dimension FLOAT vector.
    embedding               VECTOR(FLOAT, 768),

    -- ── Audit ─────────────────────────────────────────────────────────────────
    created_at              TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP(),
    updated_at              TIMESTAMP_NTZ  DEFAULT CURRENT_TIMESTAMP()

);



-- =============================================================================
-- STEP 2 — INSERT CHUNKS
-- Chunking strategy:
--   • Each H2 section becomes one or more chunks depending on content volume.
--   • H3 subsections always become independent chunks.
--   • Tables, decision trees, and SQL snippets are separate chunks to preserve
--     their tabular / code semantics.
--   • chunk_text = '[BREADCRUMB]\n\n' || chunk_text_raw  (enrichment prefix)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 1 — Introduction & Purpose
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_CHUNKS
    (chapter_number, chapter_title, section_number, section_title,
     subsection_title, chunk_sequence, full_path, chunk_type,
     chunk_text_raw, chunk_text, campaign_id_ref, signal_category,
     coupon_id_ref, channel_ref, priority_level)
VALUES
-- 1-A: Chapter 1 overview
(1, '1. Introduction & Purpose', NULL, NULL, NULL, 1,
 'Chapter 1: Introduction & Purpose',
 'OVERVIEW',
 'This Marketing Campaign Playbook is the definitive internal reference guide for Swiggy marketing managers, growth analysts, and campaign strategists. It codifies the decision logic for selecting, configuring, and launching the right campaign at the right time — driven by real-time and historical data signals from the Swiggy platform. The playbook is used alongside the Swiggy Cortex AI assistant, which allows natural-language querying of both structured transactional data and this playbook document. When the AI detects a specific business signal — such as declining order frequency in a city or low coupon adoption in a segment — it will recommend the appropriate campaign from this playbook.',
 '[Chapter 1: Introduction & Purpose]\n\nThis Marketing Campaign Playbook is the definitive internal reference guide for Swiggy marketing managers, growth analysts, and campaign strategists. It codifies the decision logic for selecting, configuring, and launching the right campaign at the right time — driven by real-time and historical data signals from the Swiggy platform. The playbook is used alongside the Swiggy Cortex AI assistant, which allows natural-language querying of both structured transactional data and this playbook document. When the AI detects a specific business signal — such as declining order frequency in a city or low coupon adoption in a segment — it will recommend the appropriate campaign from this playbook.',
 NULL, NULL, NULL, NULL, NULL),

-- 1-B: Who this document is for
(1, '1. Introduction & Purpose', '1.1', '1.1 Who This Document Is For', NULL, 2,
 'Chapter 1 > 1.1 Who This Document Is For',
 'OVERVIEW',
 'This document is intended for the following roles at Swiggy: (1) Growth Marketing Managers — responsible for campaign planning and execution. (2) CRM Analysts — monitoring customer lifecycle and churn signals. (3) City Business Managers — tracking GMV and engagement metrics. (4) Data Analysts — building dashboards and alerting pipelines. (5) Campaign Operations Teams — managing channel execution on Push, Email, and Paid Media.',
 '[Chapter 1 > 1.1 Who This Document Is For]\n\nThis document is intended for the following roles at Swiggy: (1) Growth Marketing Managers — responsible for campaign planning and execution. (2) CRM Analysts — monitoring customer lifecycle and churn signals. (3) City Business Managers — tracking GMV and engagement metrics. (4) Data Analysts — building dashboards and alerting pipelines. (5) Campaign Operations Teams — managing channel execution on Push, Email, and Paid Media.',
 NULL, NULL, NULL, NULL, NULL),

-- 1-C: How to use this playbook
(1, '1. Introduction & Purpose', '1.2', '1.2 How to Use This Playbook', NULL, 3,
 'Chapter 1 > 1.2 How to Use This Playbook',
 'NUMBERED_LIST',
 'This playbook is a signal-to-action reference. For each identifiable business condition (a signal), there is a recommended campaign, channel, coupon, and success metric. Steps to use the playbook: (1) Identify the relevant signal from the Signal Library (Chapter 3). (2) Cross-reference the signal with the Campaign Selection Matrix (Chapter 4). (3) Retrieve the full campaign brief from the Campaign Catalogue (Chapter 5). (4) Validate channel and coupon strategy using guidance in Chapters 6 and 7. (5) Execute, monitor, and evaluate using the KPIs defined in Chapter 8. NOTE: This is a living document updated quarterly. Always verify you are using the latest version.',
 '[Chapter 1 > 1.2 How to Use This Playbook]\n\nThis playbook is a signal-to-action reference. For each identifiable business condition (a signal), there is a recommended campaign, channel, coupon, and success metric. Steps to use the playbook: (1) Identify the relevant signal from the Signal Library (Chapter 3). (2) Cross-reference the signal with the Campaign Selection Matrix (Chapter 4). (3) Retrieve the full campaign brief from the Campaign Catalogue (Chapter 5). (4) Validate channel and coupon strategy using guidance in Chapters 6 and 7. (5) Execute, monitor, and evaluate using the KPIs defined in Chapter 8. NOTE: This is a living document updated quarterly. Always verify you are using the latest version.',
 NULL, NULL, NULL, NULL, NULL),

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 2 — Business Context & Strategy Overview
-- ─────────────────────────────────────────────────────────────────────────────

-- 2-A: Chapter overview + three levers
(2, '2. Business Context & Strategy Overview', NULL, NULL, NULL, 1,
 'Chapter 2: Business Context & Strategy Overview',
 'OVERVIEW',
 'Swiggy operates a hyperlocal food delivery marketplace connecting millions of customers to thousands of restaurants across Indian cities. Revenue is driven by order frequency, average order value (AOV), and net take-rate after discounts. Marketing campaigns are designed to accelerate growth across three levers: (1) Acquisition — bringing new users onto the platform. (2) Engagement & Order Frequency — increasing orders per active user per month. (3) Retention & Loyalty — reducing churn and upgrading customers to paid membership tiers (ONE_LITE, ONE, ONE_PLUS).',
 '[Chapter 2: Business Context & Strategy Overview]\n\nSwiggy operates a hyperlocal food delivery marketplace connecting millions of customers to thousands of restaurants across Indian cities. Revenue is driven by order frequency, average order value (AOV), and net take-rate after discounts. Marketing campaigns are designed to accelerate growth across three levers: (1) Acquisition — bringing new users onto the platform. (2) Engagement & Order Frequency — increasing orders per active user per month. (3) Retention & Loyalty — reducing churn and upgrading customers to paid membership tiers (ONE_LITE, ONE, ONE_PLUS).',
 NULL, NULL, NULL, NULL, NULL),

-- 2-B: KPI table
(2, '2. Business Context & Strategy Overview', '2.1', '2.1 Key Business Metrics', NULL, 2,
 'Chapter 2 > 2.1 Key Business Metrics',
 'TABLE_DATA',
 'Key performance metrics and FY2025 targets: GMV (Gross Merchandise Value) = Sum of gross_amount across all transactions; Target: 20% YoY growth per city. Net Revenue = Sum of net_amount after all discounts; Target: Maintain >72% of GMV. AOV (Average Order Value) = net_amount / count of orders; Target: INR 320+ per order. Order Frequency = Orders per active customer per month; Target: 4.5+ orders/month. Coupon Adoption Rate = % orders with coupon applied; Target: 35–45% across active base. Campaign CTR = Clicks / Impressions; Target: Push >4%, Email >12%. Churn Rate = % customers with 0 orders in 30 days; Target: <18% monthly. Membership Upgrade Rate = NONE/ONE_LITE to ONE/ONE_PLUS upgrades per month; Target: 8% of eligible base.',
 '[Chapter 2 > 2.1 Key Business Metrics — KPI Reference Table]\n\nKey performance metrics and FY2025 targets: GMV (Gross Merchandise Value) = Sum of gross_amount across all transactions; Target: 20% YoY growth per city. Net Revenue = Sum of net_amount after all discounts; Target: Maintain >72% of GMV. AOV (Average Order Value) = net_amount / count of orders; Target: INR 320+ per order. Order Frequency = Orders per active customer per month; Target: 4.5+ orders/month. Coupon Adoption Rate = % orders with coupon applied; Target: 35–45% across active base. Campaign CTR = Clicks / Impressions; Target: Push >4%, Email >12%. Churn Rate = % customers with 0 orders in 30 days; Target: <18% monthly. Membership Upgrade Rate = NONE/ONE_LITE to ONE/ONE_PLUS upgrades per month; Target: 8% of eligible base.',
 NULL, NULL, NULL, NULL, NULL),

-- 2-C: Customer segments table
(2, '2. Business Context & Strategy Overview', '2.2', '2.2 Customer Segments', NULL, 3,
 'Chapter 2 > 2.2 Customer Segments',
 'TABLE_DATA',
 'All campaign decisions operate on these customer segments defined in dim_customer and fact_transactions: (1) New Users — Membership: NONE; signed up ≤ 30 days ago, 0–1 orders placed. (2) Occasional Orderers — Membership: NONE or ONE_LITE; 1–2 orders/month, price-sensitive, coupon-driven. (3) Regular Users — Membership: ONE_LITE or ONE; 3–5 orders/month, moderate AOV. (4) Power Users — Membership: ONE or ONE_PLUS; 6+ orders/month, high AOV, low churn risk. (5) Lapsed / At-Risk — Membership: any; no orders in 14–30 days; previously active. (6) Churned — Membership: any; no orders in 31+ days; require win-back campaigns.',
 '[Chapter 2 > 2.2 Customer Segments — Segment Definitions]\n\nAll campaign decisions operate on these customer segments defined in dim_customer and fact_transactions: (1) New Users — Membership: NONE; signed up ≤ 30 days ago, 0–1 orders placed. (2) Occasional Orderers — Membership: NONE or ONE_LITE; 1–2 orders/month, price-sensitive, coupon-driven. (3) Regular Users — Membership: ONE_LITE or ONE; 3–5 orders/month, moderate AOV. (4) Power Users — Membership: ONE or ONE_PLUS; 6+ orders/month, high AOV, low churn risk. (5) Lapsed / At-Risk — Membership: any; no orders in 14–30 days; previously active. (6) Churned — Membership: any; no orders in 31+ days; require win-back campaigns.',
 NULL, NULL, NULL, NULL, NULL),

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 3 — Signal Library
-- ─────────────────────────────────────────────────────────────────────────────

-- 3-A: Category A — Acquisition signals
(3, '3. Signal Library', '3.1', '3.1 Signal Categories', 'Category A — Acquisition Signals', 1,
 'Chapter 3 > 3.1 Signal Categories > Category A: Acquisition Signals',
 'BULLET_LIST',
 'Category A — Acquisition Signals indicate an opportunity or gap in bringing new users onto the platform. These signals should trigger PAID_404 (Paid Ads: New Users). Signals include: (1) High traffic to landing page but low sign-up conversion (>60% drop-off rate). (2) Referral programme participation below 5% of active user base. (3) Paid media impressions high but first-order rate below 8% in a city. (4) New city launch: low organic first-order rate in the first 14 days after launch.',
 '[Chapter 3 > 3.1 Signal Categories > Category A: Acquisition Signals]\n\nCategory A — Acquisition Signals indicate an opportunity or gap in bringing new users onto the platform. These signals should trigger PAID_404 (Paid Ads: New Users). Signals include: (1) High traffic to landing page but low sign-up conversion (>60% drop-off rate). (2) Referral programme participation below 5% of active user base. (3) Paid media impressions high but first-order rate below 8% in a city. (4) New city launch: low organic first-order rate in the first 14 days after launch.',
 'PAID_404', 'A', 'WELCOME50', 'PAID_MEDIA', 'HIGH'),

-- 3-B: Category B — Engagement signals
(3, '3. Signal Library', '3.1', '3.1 Signal Categories', 'Category B — Engagement & Order Frequency Signals', 2,
 'Chapter 3 > 3.1 Signal Categories > Category B: Engagement & Order Frequency Signals',
 'BULLET_LIST',
 'Category B — Engagement & Order Frequency Signals indicate a slowdown in ordering behaviour among existing users. These signals typically trigger PUSH_101 or POPUP_202. Signals include: (1) Customer order frequency drops below 2 orders/month for 2+ consecutive weeks. (2) Lunch-hour (12:00–14:00) orders down >15% week-over-week in a specific city. (3) Low coupon adoption rate (<20%) on a specific day-of-week or city. (4) AOV drop below INR 280 for a segment over a 7-day window. (5) High time_to_order_seconds (>300s) indicating in-app discovery friction. (6) Weekend order volume trailing weekday average by >25%.',
 '[Chapter 3 > 3.1 Signal Categories > Category B: Engagement & Order Frequency Signals]\n\nCategory B — Engagement & Order Frequency Signals indicate a slowdown in ordering behaviour among existing users. These signals typically trigger PUSH_101 or POPUP_202. Signals include: (1) Customer order frequency drops below 2 orders/month for 2+ consecutive weeks. (2) Lunch-hour (12:00–14:00) orders down >15% week-over-week in a specific city. (3) Low coupon adoption rate (<20%) on a specific day-of-week or city. (4) AOV drop below INR 280 for a segment over a 7-day window. (5) High time_to_order_seconds (>300s) indicating in-app discovery friction. (6) Weekend order volume trailing weekday average by >25%.',
 NULL, 'B', NULL, NULL, 'HIGH'),

-- 3-C: Category C — Retention & churn signals
(3, '3. Signal Library', '3.1', '3.1 Signal Categories', 'Category C — Retention & Churn Prevention Signals', 3,
 'Chapter 3 > 3.1 Signal Categories > Category C: Retention & Churn Prevention Signals',
 'BULLET_LIST',
 'Category C — Retention & Churn Prevention Signals indicate customers are at risk of leaving the platform. These signals require urgent campaign response to prevent revenue loss. Signals include: (1) Customer inactive for 14–21 days (at-risk window) — trigger push + email. (2) Customer inactive for 22–30 days (near-churn window) — trigger email with high-value coupon. (3) Rating drops below 3.5 on 2+ consecutive orders — satisfaction risk, requires service intervention. (4) Delivery failure rate above 5% for a geo_id in a 7-day window — operational signal triggering compensation campaign. (5) Membership renewal lapse: ONE or ONE_PLUS tier expiring in 7 days — trigger upgrade nudge via email.',
 '[Chapter 3 > 3.1 Signal Categories > Category C: Retention & Churn Prevention Signals]\n\nCategory C — Retention & Churn Prevention Signals indicate customers are at risk of leaving the platform. These signals require urgent campaign response to prevent revenue loss. Signals include: (1) Customer inactive for 14–21 days (at-risk window) — trigger push + email. (2) Customer inactive for 22–30 days (near-churn window) — trigger email with high-value coupon. (3) Rating drops below 3.5 on 2+ consecutive orders — satisfaction risk, requires service intervention. (4) Delivery failure rate above 5% for a geo_id in a 7-day window — operational signal triggering compensation campaign. (5) Membership renewal lapse: ONE or ONE_PLUS tier expiring in 7 days — trigger upgrade nudge via email.',
 'EMAIL_303', 'C', 'WEEKEND20', 'EMAIL', 'HIGH'),

-- 3-D: Category D — Monetisation & upsell signals
(3, '3. Signal Library', '3.1', '3.1 Signal Categories', 'Category D — Monetisation & Upsell Signals', 4,
 'Chapter 3 > 3.1 Signal Categories > Category D: Monetisation & Upsell Signals',
 'BULLET_LIST',
 'Category D — Monetisation & Upsell Signals indicate opportunities to increase revenue per user or reduce discount dependency. Signals include: (1) ONE_LITE customers with 4+ orders/month for 4+ consecutive weeks — ripe for upgrade to ONE tier. (2) NONE tier customers with 3+ orders/month for 8+ consecutive weeks — ripe for ONE_LITE membership offer. (3) Average discount rate for a segment exceeds 22% — discount dependency risk; begin step-down strategy. (4) Payday period (25th of month to 5th of next month) — elevated purchase intent; use PAYDAY15 coupon. (5) Raining weather flag (raining_flag = TRUE) active in a city — surge in demand expected within 2 hours; use FREESHIP coupon.',
 '[Chapter 3 > 3.1 Signal Categories > Category D: Monetisation & Upsell Signals]\n\nCategory D — Monetisation & Upsell Signals indicate opportunities to increase revenue per user or reduce discount dependency. Signals include: (1) ONE_LITE customers with 4+ orders/month for 4+ consecutive weeks — ripe for upgrade to ONE tier. (2) NONE tier customers with 3+ orders/month for 8+ consecutive weeks — ripe for ONE_LITE membership offer. (3) Average discount rate for a segment exceeds 22% — discount dependency risk; begin step-down strategy. (4) Payday period (25th of month to 5th of next month) — elevated purchase intent; use PAYDAY15 coupon. (5) Raining weather flag (raining_flag = TRUE) active in a city — surge in demand expected within 2 hours; use FREESHIP coupon.',
 NULL, 'D', 'PAYDAY15', NULL, 'MEDIUM'),

-- 3-E: Signal detection SQL — at-risk customers
(3, '3. Signal Library', '3.2', '3.2 Signal Detection Queries', 'Signal: At-Risk Customers (14-21 Days Inactive)', 5,
 'Chapter 3 > 3.2 Signal Detection Queries > Signal: At-Risk Customers (14–21 Days Inactive)',
 'SQL_SNIPPET',
 'Snowflake SQL to detect at-risk customers inactive for 14–21 days. This query should be scheduled as a daily Snowflake Task and its results used to trigger EMAIL_303 or PUSH_101 campaigns targeting the churn-prevention segment. Query: SELECT customer_id, MAX(transaction_date) AS last_order_date, DATEDIFF(''day'', MAX(transaction_date), CURRENT_DATE()) AS days_inactive FROM SWIGGY_FACT_TRANSACTIONS GROUP BY customer_id HAVING days_inactive BETWEEN 14 AND 21;',
 '[Chapter 3 > 3.2 Signal Detection Queries > Signal: At-Risk Customers (14–21 Days Inactive)]\n\nSnowflake SQL to detect at-risk customers inactive for 14–21 days. This query should be scheduled as a daily Snowflake Task and its results used to trigger EMAIL_303 or PUSH_101 campaigns. Query: SELECT customer_id, MAX(transaction_date) AS last_order_date, DATEDIFF(''day'', MAX(transaction_date), CURRENT_DATE()) AS days_inactive FROM SWIGGY_FACT_TRANSACTIONS GROUP BY customer_id HAVING days_inactive BETWEEN 14 AND 21;',
 'EMAIL_303', 'C', NULL, 'EMAIL', 'HIGH'),

-- 3-F: Signal detection SQL — weekend order dip
(3, '3. Signal Library', '3.2', '3.2 Signal Detection Queries', 'Signal: Low Weekend Order Volume', 6,
 'Chapter 3 > 3.2 Signal Detection Queries > Signal: Low Weekend Order Volume',
 'SQL_SNIPPET',
 'Snowflake SQL to detect a weekend order volume dip. Run weekly on Mondays to assess prior week weekend performance. If weekend orders are >25% below weekday daily average, trigger EMAIL_303 with WEEKEND20 coupon for the following weekend. Query: SELECT city, DAYNAME(transaction_date) AS day_name, COUNT(*) AS orders FROM SWIGGY_FACT_TRANSACTIONS WHERE transaction_date >= DATEADD(''day'', -14, CURRENT_DATE()) GROUP BY city, day_name ORDER BY city, orders;',
 '[Chapter 3 > 3.2 Signal Detection Queries > Signal: Low Weekend Order Volume]\n\nSnowflake SQL to detect a weekend order volume dip. If weekend orders are >25% below weekday daily average, trigger EMAIL_303 with WEEKEND20 coupon. Query: SELECT city, DAYNAME(transaction_date) AS day_name, COUNT(*) AS orders FROM SWIGGY_FACT_TRANSACTIONS WHERE transaction_date >= DATEADD(''day'', -14, CURRENT_DATE()) GROUP BY city, day_name ORDER BY city, orders;',
 'EMAIL_303', 'B', 'WEEKEND20', 'EMAIL', 'MEDIUM'),

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 4 — Campaign Selection Matrix
-- ─────────────────────────────────────────────────────────────────────────────

-- 4-A: Full campaign selection matrix
(4, '4. Campaign Selection Matrix', NULL, NULL, NULL, 1,
 'Chapter 4: Campaign Selection Matrix',
 'TABLE_DATA',
 'The Campaign Selection Matrix maps each detected signal to the recommended campaign. Signal → Campaign → Channel → Coupon → Target Segment → Priority: (1) New user, 0 orders → PAID_404 → PAID_MEDIA → WELCOME50 → New Users → HIGH. (2) Low coupon adoption → POPUP_202 → INAPP_POPUP → SAVE80 or FREESHIP → Occasional Orderers → MEDIUM. (3) Lunch hour dip → PUSH_101 → PUSH → SAVE80 → Regular + Power Users → HIGH. (4) At-risk (14–21 days inactive) → PUSH_101 → PUSH + EMAIL → WEEKEND20 → At-Risk Customers → HIGH. (5) Churned (31+ days inactive) → EMAIL_303 → EMAIL → WELCOME50 or SAVE80 → Churned Customers → HIGH. (6) Payday window (25th–5th) → POPUP_202 → INAPP_POPUP → PAYDAY15 → All Active Users → MEDIUM. (7) Weekend order dip → EMAIL_303 → EMAIL → WEEKEND20 → Regular + Occasional → MEDIUM. (8) Raining weather (raining_flag = TRUE) → PUSH_101 → PUSH → FREESHIP → All Active (city-level) → URGENT. (9) ONE_LITE upgrade signal (4+ orders/month) → EMAIL_303 → EMAIL + PUSH → No coupon (membership pitch) → ONE_LITE Customers → LOW. (10) High discount dependency (>22% rate) → POPUP_202 → INAPP_POPUP → PAYDAY15 step-down → Coupon-heavy segments → LOW.',
 '[Chapter 4: Campaign Selection Matrix — Signal-to-Campaign Mapping]\n\nThe Campaign Selection Matrix maps each detected signal to the recommended campaign. Signal → Campaign → Channel → Coupon → Target Segment → Priority: (1) New user, 0 orders → PAID_404 → PAID_MEDIA → WELCOME50 → New Users → HIGH. (2) Low coupon adoption → POPUP_202 → INAPP_POPUP → SAVE80 or FREESHIP → Occasional Orderers → MEDIUM. (3) Lunch hour dip → PUSH_101 → PUSH → SAVE80 → Regular + Power Users → HIGH. (4) At-risk (14–21 days inactive) → PUSH_101 → PUSH + EMAIL → WEEKEND20 → At-Risk Customers → HIGH. (5) Churned (31+ days inactive) → EMAIL_303 → EMAIL → WELCOME50 or SAVE80 → Churned Customers → HIGH. (6) Payday window (25th–5th) → POPUP_202 → INAPP_POPUP → PAYDAY15 → All Active Users → MEDIUM. (7) Weekend order dip → EMAIL_303 → EMAIL → WEEKEND20 → Regular + Occasional → MEDIUM. (8) Raining weather (raining_flag = TRUE) → PUSH_101 → PUSH → FREESHIP → All Active (city-level) → URGENT. (9) ONE_LITE upgrade signal (4+ orders/month) → EMAIL_303 → EMAIL + PUSH → No coupon (membership pitch) → ONE_LITE Customers → LOW. (10) High discount dependency (>22% rate) → POPUP_202 → INAPP_POPUP → PAYDAY15 step-down → Coupon-heavy segments → LOW.',
 NULL, NULL, NULL, NULL, NULL),

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 5 — Campaign Catalogue
-- ─────────────────────────────────────────────────────────────────────────────

-- 5-A: PUSH_101 full brief
(5, '5. Campaign Catalogue', '5.1', '5.1 PUSH_101 — Push Notification: Lunch Deals', NULL, 1,
 'Chapter 5 > 5.1 PUSH_101 — Push Notification: Lunch Deals',
 'CAMPAIGN_BRIEF',
 'Campaign ID: PUSH_101. Campaign Name: Push: Lunch Deals. Channel: PUSH (Mobile Push Notification). Primary Objective: INCREASE_ORDERS — stimulate lunch-window orders on ANDROID and IOS. Target Audience: Regular users and Power users; active within last 7 days; cities: Hyderabad and Bangalore. Send Window: 11:30 AM – 12:00 PM IST on weekdays. Recommended Coupon: SAVE80 (Flat INR 80 off, minimum order INR 249). Message Template: "Hungry? Lunch is sorted! Get FLAT ₹80 off on your next order. Order before 1 PM. Use code SAVE80." Deep Link: swiggy://home?cuisine=lunch&promo=SAVE80. Success Metrics: CTR ≥ 4.5%; Orders attributed ≥ 500/day; AOV ≥ INR 310. Suppression Rules: Exclude customers who ordered in last 3 hours; exclude ONE_PLUS members (already receive benefits). Frequency Cap: Maximum 3 push notifications per customer per week across all push campaigns.',
 '[Chapter 5 > 5.1 Campaign Brief: PUSH_101 — Push Notification: Lunch Deals]\n\nCampaign ID: PUSH_101. Campaign Name: Push: Lunch Deals. Channel: PUSH (Mobile Push Notification). Primary Objective: INCREASE_ORDERS — stimulate lunch-window orders on ANDROID and IOS. Target Audience: Regular users and Power users; active within last 7 days; cities: Hyderabad and Bangalore. Send Window: 11:30 AM – 12:00 PM IST on weekdays. Recommended Coupon: SAVE80 (Flat INR 80 off, minimum order INR 249). Message Template: "Hungry? Lunch is sorted! Get FLAT ₹80 off on your next order. Order before 1 PM. Use code SAVE80." Deep Link: swiggy://home?cuisine=lunch&promo=SAVE80. Success Metrics: CTR ≥ 4.5%; Orders attributed ≥ 500/day; AOV ≥ INR 310. Suppression Rules: Exclude customers who ordered in last 3 hours; exclude ONE_PLUS members. Frequency Cap: Max 3 push notifications per customer per week.',
 'PUSH_101', 'B', 'SAVE80', 'PUSH', 'HIGH'),

-- 5-B: POPUP_202 full brief
(5, '5. Campaign Catalogue', '5.2', '5.2 POPUP_202 — In-App Popup: 20% Off', NULL, 2,
 'Chapter 5 > 5.2 POPUP_202 — In-App Popup: 20% Off',
 'CAMPAIGN_BRIEF',
 'Campaign ID: POPUP_202. Campaign Name: In-app Popup: 20% Off. Channel: INAPP_POPUP (triggered on app open or browse). Primary Objective: COUPON_ADOPTION — drive coupon uptake among sessions without immediate order intent. Target Audience: Occasional orderers; sessions where time_to_order_seconds > 180s (discovery friction detected). Trigger Logic: App open after 5+ days of inactivity, OR customer browses more than 3 restaurant pages without adding to cart. Recommended Coupon: WEEKEND20 (20% off, max INR 100) on weekends; SAVE80 on weekdays. Creative Guidance: Full-screen modal with Swiggy orange background, single CTA "Claim Offer" — dismiss option must always be visible. Success Metrics: Popup-to-order conversion ≥ 18%; coupon_used_flag = TRUE on ≥ 40% of post-popup orders. Suppression Rules: Show maximum once per session; suppress for ONE_PLUS members.',
 '[Chapter 5 > 5.2 Campaign Brief: POPUP_202 — In-App Popup: 20% Off]\n\nCampaign ID: POPUP_202. Campaign Name: In-app Popup: 20% Off. Channel: INAPP_POPUP. Primary Objective: COUPON_ADOPTION. Target Audience: Occasional orderers; sessions where time_to_order_seconds > 180s. Trigger Logic: App open after 5+ days inactivity, OR browse >3 restaurant pages without add-to-cart. Recommended Coupon: WEEKEND20 on weekends; SAVE80 on weekdays. Success Metrics: Popup-to-order conversion ≥ 18%; coupon_used_flag on ≥ 40% of post-popup orders. Suppression: Once per session; exclude ONE_PLUS members.',
 'POPUP_202', 'B', 'WEEKEND20', 'INAPP_POPUP', 'MEDIUM'),

-- 5-C: EMAIL_303 full brief
(5, '5. Campaign Catalogue', '5.3', '5.3 EMAIL_303 — Email: Weekend Special', NULL, 3,
 'Chapter 5 > 5.3 EMAIL_303 — Email: Weekend Special',
 'CAMPAIGN_BRIEF',
 'Campaign ID: EMAIL_303. Campaign Name: Email: Weekend Special. Channel: EMAIL (transactional ESP, personalised send). Primary Objective: REACTIVATION — re-engage lapsed users with a high-value incentive. Target Audience: Churned customers (31–90 days inactive) who previously placed ≥ 3 orders. Send Window: Friday 5:00 PM – 7:00 PM IST (pre-weekend intent window). Recommended Coupon: WEEKEND20 — highlight 48-hour validity to create urgency. Subject Line: "We miss you, [First Name]! Your weekend treat is waiting." Email Body: Personalise with customer''s top cuisine and last restaurant; include 20% coupon block prominently. Success Metrics: Open rate ≥ 22%; Click-to-order rate ≥ 8%; Reactivated customers ≥ 15% of emailed base. Unsubscribe Handling: CAN-SPAM compliant; one-click unsubscribe; suppress for 90 days post-reactivation.',
 '[Chapter 5 > 5.3 Campaign Brief: EMAIL_303 — Email: Weekend Special]\n\nCampaign ID: EMAIL_303. Campaign Name: Email: Weekend Special. Channel: EMAIL. Primary Objective: REACTIVATION. Target Audience: Churned customers (31–90 days inactive), previously placed ≥ 3 orders. Send Window: Friday 5–7 PM IST. Recommended Coupon: WEEKEND20. Subject Line: "We miss you, [First Name]! Your weekend treat is waiting." Success Metrics: Open rate ≥ 22%; Click-to-order ≥ 8%; Reactivation ≥ 15% of emailed base. Unsubscribe: CAN-SPAM compliant; 90-day suppression post-reactivation.',
 'EMAIL_303', 'C', 'WEEKEND20', 'EMAIL', 'HIGH'),

-- 5-D: PAID_404 full brief
(5, '5. Campaign Catalogue', '5.4', '5.4 PAID_404 — Paid Ads: New Users', NULL, 4,
 'Chapter 5 > 5.4 PAID_404 — Paid Ads: New Users',
 'CAMPAIGN_BRIEF',
 'Campaign ID: PAID_404. Campaign Name: Paid Ads: New Users. Channel: PAID_MEDIA (Google UAC, Meta App Campaigns, Instagram). Primary Objective: ACQUISITION — drive first installs and first orders among non-users. Target Audience: Non-Swiggy users; aged 18–35; located in Hyderabad or Bangalore pincodes; food-interested audiences. Recommended Coupon: WELCOME50 (50% off, max INR 150, min order INR 199) — highest perceived value for acquisition. Ad Creative Variants: Variant A — cuisine carousel; Variant B — social proof (ratings and delivery time). Run 50/50 A/B split. Bidding Strategy: Target CPA ≤ INR 250 per first order; tCPA bidding with 7-day attribution window. Success Metrics: First-order conversion ≥ 9% of installs; CAC ≤ INR 250; Day-7 retention ≥ 35%. Frequency Cap: Max 5 impressions per user per week across paid channels. Budget Rule: Pause campaign if daily CAC exceeds INR 300 for 3 consecutive days.',
 '[Chapter 5 > 5.4 Campaign Brief: PAID_404 — Paid Ads: New Users]\n\nCampaign ID: PAID_404. Channel: PAID_MEDIA (Google UAC, Meta, Instagram). Objective: ACQUISITION. Target: Non-Swiggy users aged 18–35 in Hyderabad/Bangalore. Coupon: WELCOME50 (50% off, max INR 150). Bidding: tCPA ≤ INR 250; 7-day attribution. Success Metrics: First-order CVR ≥ 9%; CAC ≤ INR 250; D7 retention ≥ 35%. Budget Rule: Pause if CAC > INR 300 for 3 consecutive days.',
 'PAID_404', 'A', 'WELCOME50', 'PAID_MEDIA', 'HIGH'),

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 6 — Channel Strategy Guide
-- ─────────────────────────────────────────────────────────────────────────────

-- 6-A: Push — when to use / not use
(6, '6. Channel Strategy Guide', '6.1', '6.1 Push Notifications (PUSH)', 'When to Use Push / When NOT to Use Push', 1,
 'Chapter 6 > 6.1 Push Notifications > Usage Rules',
 'DECISION_LOGIC',
 'Push notifications are the highest-urgency, lowest-cost channel. USE PUSH when: (1) Signal requires action within 2–4 hours (e.g., raining weather, lunch window). (2) Customer is known to be mobile-active (ANDROID or IOS device_type). (3) Message is short, single-action, and benefit-forward. DO NOT use Push when: (1) Reactivating churned users (31+ days inactive) — use EMAIL first. (2) Offer is complex and requires explanation — use in-app popup or email. (3) Customer has already received 3+ pushes in the last 7 days (frequency cap exceeded).',
 '[Chapter 6 > 6.1 Push Notifications > Usage Rules — When to Use and When Not to Use]\n\nPush notifications are the highest-urgency, lowest-cost channel. USE PUSH when: (1) Signal requires action within 2–4 hours (e.g., raining weather, lunch window). (2) Customer is mobile-active (ANDROID or IOS). (3) Message is short, single-action, benefit-forward. DO NOT use Push when: (1) Reactivating churned users (31+ days) — use EMAIL first. (2) Offer requires explanation — use popup or email. (3) Customer received 3+ pushes in last 7 days.',
 'PUSH_101', NULL, NULL, 'PUSH', NULL),

-- 6-B: Push best practices
(6, '6. Channel Strategy Guide', '6.1', '6.1 Push Notifications (PUSH)', 'Push Best Practices', 2,
 'Chapter 6 > 6.1 Push Notifications > Best Practices',
 'BULLET_LIST',
 'Push Notification Best Practices: Title max 40 characters; include offer value in the title. Body max 90 characters; single clear CTA. Personalise with customer''s first name and favourite cuisine where data is available. A/B test emoji vs no-emoji in title (Swiggy data shows +2.1% CTR with single emoji). Schedule delivery between 11:30 AM–12:30 PM or 7:00 PM–8:30 PM IST for highest CTR.',
 '[Chapter 6 > 6.1 Push Notifications > Best Practices]\n\nPush Notification Best Practices: Title max 40 characters; include offer value in the title. Body max 90 characters; single clear CTA. Personalise with customer''s first name and favourite cuisine. A/B test emoji vs no-emoji (Swiggy data shows +2.1% CTR with single emoji). Schedule between 11:30 AM–12:30 PM or 7:00–8:30 PM IST.',
 'PUSH_101', NULL, NULL, 'PUSH', NULL),

-- 6-C: In-app popup trigger rules + creative
(6, '6. Channel Strategy Guide', '6.2', '6.2 In-App Popup (INAPP_POPUP)', 'Trigger Rules & Creative Standards', 3,
 'Chapter 6 > 6.2 In-App Popup > Trigger Rules & Creative Standards',
 'DECISION_LOGIC',
 'In-App Popup Trigger Rules: Show popup when session_duration > 90 seconds without an add-to-cart event. Show popup on app open if customer has been inactive for 5–14 days (at-risk). Do not show more than one popup per session. Do not show to ONE_PLUS members (persistent benefits). Creative Standards: Use Swiggy orange (#E8580C) as primary background. Single headline (max 7 words), single sub-headline, single CTA button. Always include a visible X dismiss button — deceptive dark patterns are prohibited. Animate the coupon code field (flash effect increases copy-rate by 31%).',
 '[Chapter 6 > 6.2 In-App Popup > Trigger Rules & Creative Standards]\n\nTrigger Rules: Show when session_duration > 90s with no add-to-cart. Show on app open after 5–14 days inactive. Max one popup per session. Suppress for ONE_PLUS. Creative Standards: Orange #E8580C background. Max 7-word headline. Always include visible dismiss button. Animated coupon code increases copy-rate by 31%.',
 'POPUP_202', NULL, NULL, 'INAPP_POPUP', NULL),

-- 6-D: Email rules
(6, '6. Channel Strategy Guide', '6.3', '6.3 Email (EMAIL)', 'Email Send Rules & Deliverability', 4,
 'Chapter 6 > 6.3 Email > Send Rules & Deliverability',
 'BULLET_LIST',
 'Email Send Rules: Never send more than 2 marketing emails per week to any single customer. Always respect unsubscribe lists and hard-bounce suppressions. Personalise subject line with customer first name — lifts open rate by 18% on average. Include plain-text fallback for all HTML emails. Deliverability Best Practices: Warm up new sending IPs gradually (ramp from 5K to 500K sends over 4 weeks). Maintain list hygiene — remove hard bounces within 24 hours. Monitor sender reputation via Google Postmaster Tools weekly. DKIM, SPF, and DMARC records must be valid at all times.',
 '[Chapter 6 > 6.3 Email > Send Rules & Deliverability Best Practices]\n\nEmail Send Rules: Max 2 marketing emails/week per customer. Respect unsubscribes and hard bounces. Personalise subject line (+18% open rate). Plain-text fallback required. Deliverability: Warm up new IPs over 4 weeks. Remove hard bounces within 24 hours. Monitor Google Postmaster. DKIM, SPF, DMARC always valid.',
 'EMAIL_303', NULL, NULL, 'EMAIL', NULL),

-- 6-E: Paid media rules
(6, '6. Channel Strategy Guide', '6.4', '6.4 Paid Media (PAID_MEDIA)', 'Budget Allocation Rules', 5,
 'Chapter 6 > 6.4 Paid Media > Budget Allocation Rules',
 'BULLET_LIST',
 'Paid Media Budget Allocation Rules: Paid media budget must not exceed 30% of total monthly marketing spend. Pause paid campaigns immediately if daily CAC exceeds INR 300 for 3 consecutive days. Always run creative A/B tests before scaling spend above INR 1 lakh per day per city. Exclude existing Swiggy users from all paid acquisition audiences using device ID suppression lists. Paid media is used exclusively for acquisition of non-users, not for re-engagement of existing customers.',
 '[Chapter 6 > 6.4 Paid Media > Budget Allocation Rules]\n\nPaid media budget must not exceed 30% of total monthly marketing spend. Pause if daily CAC > INR 300 for 3 consecutive days. Run creative A/B tests before scaling above INR 1L/day per city. Exclude existing users via device ID suppression. Paid media is for acquisition only — not re-engagement.',
 'PAID_404', 'A', 'WELCOME50', 'PAID_MEDIA', NULL),

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 7 — Coupon Strategy & Discount Management
-- ─────────────────────────────────────────────────────────────────────────────

-- 7-A: Coupon catalogue
(7, '7. Coupon Strategy & Discount Management', '7.1', '7.1 Coupon Catalogue Reference', NULL, 1,
 'Chapter 7 > 7.1 Coupon Catalogue Reference',
 'TABLE_DATA',
 'Coupon catalogue with usage guidance: WELCOME50 — Welcome 50% off (cap INR 150); Type: PCT; Min order: INR 199; Best used for first-order acquisition only. SAVE80 — Flat INR 80 off; Type: FLAT; Min order: INR 249; Best used for engagement boost and lunch promotions. FREESHIP — Free delivery flat INR 40; Type: FLAT; Min order: INR 149; Best used for weather-driven promotions and low AOV nudge. WEEKEND20 — Weekend 20% off (cap INR 100); Type: PCT; Min order: INR 299; Best used for weekend reactivation and churn prevention. PAYDAY15 — Payday 15% off (cap INR 120); Type: PCT; Min order: INR 249; Best used for payday window (25th–5th) and monetisation campaigns.',
 '[Chapter 7 > 7.1 Coupon Catalogue Reference]\n\nCoupon catalogue: WELCOME50 — 50% off, cap INR 150, min order INR 199, first-order acquisition only. SAVE80 — Flat INR 80 off, min order INR 249, engagement and lunch promos. FREESHIP — Free delivery INR 40, min order INR 149, weather promos and low AOV nudge. WEEKEND20 — 20% off, cap INR 100, min order INR 299, weekend reactivation. PAYDAY15 — 15% off, cap INR 120, min order INR 249, payday window and monetisation.',
 NULL, NULL, NULL, NULL, NULL),

-- 7-B: Coupon decision tree
(7, '7. Coupon Strategy & Discount Management', '7.2', '7.2 Coupon Selection Decision Tree', NULL, 2,
 'Chapter 7 > 7.2 Coupon Selection Decision Tree',
 'DECISION_LOGIC',
 'Coupon selection decision tree — apply rules in order, stop at first match: (1) Is the customer a new user with 0 orders? → Use WELCOME50. STOP. (2) Is the signal weather-driven (raining_flag = TRUE)? → Use FREESHIP. STOP. (3) Is the target window a weekend (Saturday or Sunday)? → Use WEEKEND20. (4) Is the target window payday period (25th–5th of month)? → Use PAYDAY15. (5) Is the signal a lunch-hour engagement dip on a weekday? → Use SAVE80. (6) Is the customer''s historical AOV below INR 250? → Use SAVE80 (flat discount is more attractive at low AOV). (7) Default for all other engagement signals → Use WEEKEND20 or PAYDAY15 based on calendar position.',
 '[Chapter 7 > 7.2 Coupon Selection Decision Tree — Which Coupon to Use]\n\nApply rules in order, stop at first match: (1) New user, 0 orders → WELCOME50. (2) Raining weather signal → FREESHIP. (3) Weekend target window → WEEKEND20. (4) Payday period (25th–5th) → PAYDAY15. (5) Lunch-hour dip on weekday → SAVE80. (6) Customer AOV historically < INR 250 → SAVE80. (7) Default for other engagement signals → WEEKEND20 or PAYDAY15 by calendar.',
 NULL, NULL, NULL, NULL, NULL),

-- 7-C: Discount guardrails
(7, '7. Coupon Strategy & Discount Management', '7.3', '7.3 Discount Guardrails', NULL, 3,
 'Chapter 7 > 7.3 Discount Guardrails',
 'COMPLIANCE',
 'Discount guardrail rules — all campaigns must comply: (1) No segment should receive discounts on more than 45% of their orders on a rolling 30-day basis. (2) Coupon stacking is disabled: total_discount_amount is capped at gross_amount × 60%. (3) WELCOME50 is single-use only; it is enforced at the database level linked to customer_id. (4) Any campaign offering average discounts > INR 100 per order requires CMO sign-off before launch. (5) Discounts to ONE_PLUS members must not duplicate their existing membership benefits to prevent over-discounting.',
 '[Chapter 7 > 7.3 Discount Guardrails — Hard Rules for All Campaigns]\n\nGuardrails: (1) Max 45% of orders discounted per segment on rolling 30 days. (2) Coupon stacking cap: total_discount_amount ≤ gross_amount × 60%. (3) WELCOME50 is single-use per customer_id. (4) Average discount > INR 100/order requires CMO approval. (5) No duplicate discounting for ONE_PLUS members.',
 NULL, NULL, NULL, NULL, NULL),

-- 7-D: Coupon ROI measurement
(7, '7. Coupon Strategy & Discount Management', '7.4', '7.4 Measuring Coupon ROI', NULL, 4,
 'Chapter 7 > 7.4 Measuring Coupon ROI',
 'DECISION_LOGIC',
 'Coupon effectiveness must be evaluated beyond simple adoption rate. Four-metric ROI framework: (1) Incremental Orders — orders from coupon users minus estimated orders those users would have placed without the coupon; requires a holdout control group. (2) Effective Discount Rate — total_discount_amount divided by gross_amount across the campaign cohort; target <22%. (3) Post-Campaign Retention — percentage of coupon users who place a second order within 14 days without needing another coupon; measures habit formation. (4) Contribution Margin Impact — net_amount minus delivery cost for the coupon cohort versus control group; determines whether the campaign is net-positive.',
 '[Chapter 7 > 7.4 Measuring Coupon ROI — Four-Metric Framework]\n\nCoupon ROI framework: (1) Incremental Orders — coupon cohort orders minus expected organic orders (holdout required). (2) Effective Discount Rate — total_discount_amount / gross_amount; target <22%. (3) Post-Campaign Retention — % who reorder within 14 days without another coupon. (4) Contribution Margin Impact — net_amount minus delivery cost vs control group.',
 NULL, NULL, NULL, NULL, NULL),

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 8 — Campaign Measurement & KPI Framework
-- ─────────────────────────────────────────────────────────────────────────────

-- 8-A: Pre-launch checklist
(8, '8. Campaign Measurement & KPI Framework', '8.1', '8.1 Pre-Launch Checklist', NULL, 1,
 'Chapter 8 > 8.1 Pre-Launch Checklist',
 'CHECKLIST',
 'Pre-launch checklist — all items must be confirmed before any campaign goes live: (1) Signal confirmed by Cortex AI data query, not assumption. (2) Target segment defined with explicit SQL filter, confirmed with data analyst. (3) Control/holdout group set to 10% of eligible audience. (4) Campaign ID, coupon, channel, and timing locked in briefing document. (5) Suppression lists applied: frequency caps, unsubscribes, recent orderers. (6) Creative assets approved by brand team. (7) UTM parameters and deep links tested in staging environment. (8) Success metrics and decision thresholds documented and signed off by campaign owner.',
 '[Chapter 8 > 8.1 Pre-Launch Checklist — Must Complete Before Any Campaign Launch]\n\nPre-launch checklist: (1) Signal confirmed via Cortex AI query. (2) Segment defined with SQL filter. (3) 10% holdout group set. (4) Campaign ID, coupon, channel, timing locked. (5) Suppression lists applied. (6) Creative approved by brand. (7) UTM + deep links tested in staging. (8) KPIs and decision thresholds signed off.',
 NULL, NULL, NULL, NULL, NULL),

-- 8-B: Campaign KPI table
(8, '8. Campaign Measurement & KPI Framework', '8.2', '8.2 Campaign KPI Table', NULL, 2,
 'Chapter 8 > 8.2 Campaign KPI Table',
 'TABLE_DATA',
 'Campaign success KPIs and measurement windows: PUSH_101 — Primary KPI: CTR; Target: ≥ 4.5%; Minimum: 3.0%; Window: 24 hours post-send. POPUP_202 — Primary KPI: Popup-to-Order Conversion Rate; Target: ≥ 18%; Minimum: 12%; Window: 48 hours post-trigger. EMAIL_303 — Primary KPI: Reactivation Rate; Target: ≥ 15%; Minimum: 8%; Window: 7 days post-send. PAID_404 — Primary KPI: First-Order Conversion Rate; Target: ≥ 9%; Minimum: 5%; Window: 7 days post-install.',
 '[Chapter 8 > 8.2 Campaign KPI Table — Performance Targets and Thresholds]\n\nCampaign KPIs: PUSH_101 → CTR target ≥ 4.5%, minimum 3.0%, measure 24 hours post-send. POPUP_202 → Popup-to-order CVR target ≥ 18%, minimum 12%, measure 48 hours post-trigger. EMAIL_303 → Reactivation rate target ≥ 15%, minimum 8%, measure 7 days post-send. PAID_404 → First-order CVR target ≥ 9%, minimum 5%, measure 7 days post-install.',
 NULL, NULL, NULL, NULL, NULL),

-- 8-C: Decision rules
(8, '8. Campaign Measurement & KPI Framework', '8.3', '8.3 Campaign Decision Rules', NULL, 3,
 'Chapter 8 > 8.3 Campaign Decision Rules',
 'DECISION_LOGIC',
 'Post-measurement decision rules: (1) PRIMARY KPI exceeds target → Scale: increase audience by 25% in next run; consider reducing coupon value by one step to improve margin. (2) PRIMARY KPI between minimum threshold and target → Maintain: A/B test creative or coupon variant to improve performance before scaling. (3) PRIMARY KPI below minimum threshold for 2 consecutive runs → Pause: conduct root-cause analysis and re-brief before relaunch. (4) Effective Discount Rate exceeds 25% → Flag to CMO for review regardless of KPI performance.',
 '[Chapter 8 > 8.3 Campaign Decision Rules — Scale / Maintain / Pause Framework]\n\nDecision rules post-measurement: KPI > target → Scale, +25% audience, consider coupon step-down. KPI between min and target → Maintain, A/B test creative or coupon. KPI < min for 2 consecutive runs → Pause, root-cause analysis required. Effective discount rate > 25% → CMO review regardless of KPI.',
 NULL, NULL, NULL, NULL, NULL),

-- 8-D: Cortex AI monitoring queries
(8, '8. Campaign Measurement & KPI Framework', '8.4', '8.4 Cortex AI Standard Monitoring Queries', NULL, 4,
 'Chapter 8 > 8.4 Cortex AI Standard Monitoring Queries',
 'BULLET_LIST',
 'Standard daily monitoring queries for the Swiggy Cortex AI chatbot: (1) "What is the order conversion rate for customers exposed to PUSH_101 in the last 7 days?" (2) "Show me the average net revenue per order by campaign, ranked highest to lowest, for this month." (3) "How many customers have been inactive for more than 14 days in Bangalore?" (4) "What percentage of at-risk customers placed an order after receiving the EMAIL_303 campaign?" (5) "Compare coupon usage rate between weekdays and weekends in Hyderabad for the last 30 days."',
 '[Chapter 8 > 8.4 Cortex AI Standard Monitoring Queries — Daily Campaign Health Checks]\n\nStandard daily monitoring queries: (1) Conversion rate for PUSH_101 in last 7 days. (2) Average net revenue per order by campaign ranked for this month. (3) Customers inactive 14+ days in Bangalore. (4) Reactivation rate for EMAIL_303 recipients. (5) Coupon usage rate weekday vs weekend in Hyderabad for last 30 days.',
 NULL, NULL, NULL, NULL, NULL),

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 9 — Special Scenario Playbooks
-- ─────────────────────────────────────────────────────────────────────────────

-- 9-A: Raining weather scenario
(9, '9. Special Scenario Playbooks', '9.1', '9.1 Scenario: Raining Weather Event', 'Response Steps', 1,
 'Chapter 9 > 9.1 Scenario: Raining Weather Event',
 'SCENARIO',
 'Raining Weather Event Playbook — execute within 2 hours of signal detection. Signal threshold: raining_flag = TRUE in ≥ 30% of transactions in the last 30 minutes for the affected city. Response steps: (1) Confirm signal via Cortex AI query on fact_transactions. (2) Activate PUSH_101 (weather variant): launch push notification with FREESHIP coupon. Message: "It''s raining in [City]! Order in and enjoy FREE delivery. Use code FREESHIP. Valid 3 hours." (3) Activate POPUP_202 (weather overlay): trigger in-app popup for all users opening the app in the affected city with rain visual creative. (4) Monitor CTR every 30 minutes — if CTR drops below 3%, switch to SAVE80 coupon variant. (5) Deactivate both campaigns 90 minutes after raining_flag returns to FALSE. Priority: URGENT.',
 '[Chapter 9 > 9.1 Scenario: Raining Weather Event — URGENT Response Playbook]\n\nExecute within 2 hours. Signal: raining_flag = TRUE in ≥ 30% of city transactions in last 30 minutes. Steps: (1) Confirm signal via Cortex AI. (2) Launch PUSH_101 with FREESHIP: "It''s raining in [City]! FREE delivery. Use FREESHIP. 3 hours." (3) Launch POPUP_202 weather overlay for city. (4) Monitor CTR every 30 min; switch to SAVE80 if CTR < 3%. (5) Deactivate 90 minutes after raining_flag clears.',
 'PUSH_101', 'D', 'FREESHIP', 'PUSH', 'URGENT'),

-- 9-B: New city launch — acquisition phase
(9, '9. Special Scenario Playbooks', '9.2', '9.2 Scenario: New City Launch', 'Day 0-7: Pure Acquisition Phase', 2,
 'Chapter 9 > 9.2 Scenario: New City Launch > Day 0–7: Acquisition Phase',
 'SCENARIO',
 'New City Launch Playbook — Day 0–7 (Pure Acquisition Phase): Run PAID_404 with elevated budget (2x city steady-state) targeting new city pincodes. Offer WELCOME50 to all new sign-ups — highest perceived value drives first-order habit. Partner with 10–15 anchor restaurants in the new city for exclusive launch deals to ensure supply-side quality. Target KPI: first-order rate ≥ 8% of installs within 7 days.',
 '[Chapter 9 > 9.2 New City Launch > Day 0–7: Pure Acquisition Phase]\n\nDay 0–7: Run PAID_404 at 2x budget for new city pincodes. Offer WELCOME50 to all sign-ups. Partner with 10–15 anchor restaurants for exclusive launch deals. Target: first-order rate ≥ 8% of installs within 7 days.',
 'PAID_404', 'A', 'WELCOME50', 'PAID_MEDIA', 'HIGH'),

-- 9-C: New city launch — engagement phase
(9, '9. Special Scenario Playbooks', '9.2', '9.2 Scenario: New City Launch', 'Day 8-21: Engagement Phase', 3,
 'Chapter 9 > 9.2 Scenario: New City Launch > Day 8–21: Engagement Phase',
 'SCENARIO',
 'New City Launch Playbook — Day 8–21 (Engagement Phase): Trigger POPUP_202 for all users who signed up but have not placed a second order. Launch PUSH_101 daily for the lunch window (11:30 AM–12:00 PM). Track order frequency closely — target ≥ 2 orders per user within the first 21 days. If order frequency falls below 1.5 orders/user, escalate to EMAIL_303 for the lagging cohort.',
 '[Chapter 9 > 9.2 New City Launch > Day 8–21: Engagement Phase]\n\nDay 8–21: Trigger POPUP_202 for users without a second order. Launch PUSH_101 daily for lunch window. Target ≥ 2 orders/user by day 21. Escalate to EMAIL_303 if frequency falls below 1.5.',
 'POPUP_202', 'B', 'SAVE80', 'INAPP_POPUP', 'HIGH'),

-- 9-D: New city launch — retention phase
(9, '9. Special Scenario Playbooks', '9.2', '9.2 Scenario: New City Launch', 'Day 22-30: Retention Phase', 4,
 'Chapter 9 > 9.2 Scenario: New City Launch > Day 22–30: Retention Phase',
 'SCENARIO',
 'New City Launch Playbook — Day 22–30 (Retention Phase): Send EMAIL_303 to any user inactive for 7+ days since sign-up (early churn in new city). Offer PAYDAY15 around the payday window (25th–5th) to drive habit formation through the first pay cycle. Success benchmark: ≥ 35% of new city users should have placed 3+ orders by day 30.',
 '[Chapter 9 > 9.2 New City Launch > Day 22–30: Retention Phase]\n\nDay 22–30: EMAIL_303 for users inactive 7+ days since sign-up. Offer PAYDAY15 during payday window. Success benchmark: ≥ 35% of new city users with 3+ orders by day 30.',
 'EMAIL_303', 'C', 'PAYDAY15', 'EMAIL', 'MEDIUM'),

-- 9-E: Festive / flash sale scenario
(9, '9. Special Scenario Playbooks', '9.3', '9.3 Scenario: Flash Sale or Festive Campaign', NULL, 5,
 'Chapter 9 > 9.3 Scenario: Flash Sale or Festive Campaign',
 'SCENARIO',
 'Flash Sale / Festive Campaign Playbook — all four campaigns activated simultaneously with a unified creative theme. Campaign activation plan: PAID_404 — acquisition push targeting non-users in key pincodes with festive creative assets; run 3–5 days before the event. PUSH_101 — day-of push to all active users with highest-value coupon (WELCOME50 for new users, SAVE80 for existing). POPUP_202 — in-app festive popup triggered on first app open during the festive window. EMAIL_303 — pre-event teaser email sent 48 hours before sale start with WEEKEND20 coupon preview. NOTE: Festive campaigns require a unified campaign tracking code. Work with BI team for multi-campaign attribution.',
 '[Chapter 9 > 9.3 Scenario: Flash Sale or Festive Campaign — Omnichannel Playbook]\n\nAll four campaigns active simultaneously. PAID_404: acquisition push 3–5 days pre-event with festive assets. PUSH_101: day-of push with highest-value coupon. POPUP_202: festive popup on first app open during sale. EMAIL_303: teaser email 48 hours before sale. NOTE: Festive campaigns need unified tracking code and multi-campaign attribution from BI team.',
 NULL, NULL, NULL, NULL, 'HIGH'),

-- ─────────────────────────────────────────────────────────────────────────────
-- CHAPTER 10 — Governance, Compliance & Appendix
-- ─────────────────────────────────────────────────────────────────────────────

-- 10-A: Approval matrix
(10, '10. Governance, Compliance & Appendix', '10.1', '10.1 Campaign Approval Matrix', NULL, 1,
 'Chapter 10 > 10.1 Campaign Approval Matrix',
 'TABLE_DATA',
 'Campaign approval matrix — who approves what and how quickly: Standard campaign (within playbook) → Approver: Campaign Manager; Turnaround: Same-day; Budget: ≤ INR 50K/day. New coupon or modified discount → Approver: Growth Lead + Finance; Turnaround: 48 hours; Budget: ≤ INR 2L/day. Festive / flash sale → Approver: CMO + Finance; Turnaround: 5 business days; Budget: No cap (board-approved). Paid media spend > INR 1L/day → Approver: VP Growth + Finance; Turnaround: 48 hours; Budget: Per quarterly budget. Emergency weather campaign → Approver: Campaign Manager (self-approve); Turnaround: 2 hours; Budget: ≤ INR 20K per event.',
 '[Chapter 10 > 10.1 Campaign Approval Matrix]\n\nApproval rules: Standard campaign (in-playbook) → Campaign Manager, same-day, ≤ INR 50K/day. New coupon → Growth Lead + Finance, 48 hours, ≤ INR 2L/day. Festive campaign → CMO + Finance, 5 business days, no cap. Paid media > INR 1L/day → VP Growth + Finance, 48 hours. Emergency weather → Campaign Manager self-approve, 2 hours, ≤ INR 20K/event.',
 NULL, NULL, NULL, NULL, NULL),

-- 10-B: Compliance
(10, '10. Governance, Compliance & Appendix', '10.2', '10.2 Data Privacy & Consent Compliance', NULL, 2,
 'Chapter 10 > 10.2 Data Privacy & Consent Compliance',
 'COMPLIANCE',
 'Data Privacy and Consent Compliance Rules: All marketing campaigns using personal data (name, email, phone, location) must comply with India''s Information Technology (Reasonable Security Practices) Rules and applicable telecom regulations. Rules: (1) Email campaigns — only send to customers with marketing_consent = TRUE in customer profile. (2) Push notifications — only send to customers who have granted notification permission on their device. (3) Customer behaviour data (order history, cuisine preferences) personalisation is permitted under Swiggy Terms of Service and Privacy Policy. (4) Customer data must never be exported from Snowflake to third-party campaign tools without DPO approval. (5) SMS marketing (currently inactive) requires DND-scrubbing via TRAI before any send.',
 '[Chapter 10 > 10.2 Data Privacy & Consent Compliance]\n\nCompliance rules: Email — marketing_consent = TRUE only. Push — device notification permission required. Behaviour personalisation allowed under ToS. Data export outside Snowflake requires DPO approval. SMS requires TRAI DND scrubbing before any send.',
 NULL, NULL, NULL, NULL, NULL),

-- 10-C: Glossary
(10, '10. Governance, Compliance & Appendix', '10.3', '10.3 Glossary of Terms', NULL, 3,
 'Chapter 10 > 10.3 Glossary of Terms',
 'GLOSSARY',
 'Glossary of key terms used in this playbook: Signal — a measurable data condition indicating a business problem or opportunity that warrants a campaign response. GMV (Gross Merchandise Value) — total gross_amount before discounts across all transactions in a period. AOV (Average Order Value) — average net_amount per transaction, post-discount. CAC (Customer Acquisition Cost) — total paid media spend divided by number of new users placing their first order. CTR (Click-Through Rate) — percentage of campaign recipients who clicked the CTA link or ad. CVR (Conversion Rate) — percentage of users who completed the desired action after campaign exposure. Holdout Group — a randomly selected subset of the target audience not exposed to the campaign, used to measure incrementality. tCPA (Target Cost Per Acquisition) — automated bidding strategy that optimises toward a defined cost per conversion. Churn — a customer who has placed no orders in the last 31+ days after previously being active. Cortex AI — Snowflake''s built-in AI/ML service powering the Swiggy natural-language marketing chatbot.',
 '[Chapter 10 > 10.3 Glossary of Terms]\n\nKey terms: Signal — measurable data condition warranting a campaign. GMV — sum of gross_amount before discounts. AOV — average net_amount per order post-discount. CAC — paid media spend / first-order new users. CTR — clicks / impressions. CVR — completions / exposures. Holdout Group — unexposed control audience for incrementality. tCPA — automated bidding to target cost per acquisition. Churn — no orders in 31+ days. Cortex AI — Snowflake AI powering the marketing chatbot.',
 NULL, NULL, NULL, NULL, NULL);