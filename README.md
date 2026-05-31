# 🍊 Swiggy Marketing Assistant — RAG Chatbot on Snowflake

A production-grade AI chatbot for Swiggy's marketing team, built entirely inside Snowflake using Cortex AI. Ask data questions in plain English and get SQL-powered answers. Ask strategy questions and get playbook-grounded recommendations — all in one conversational interface.

---

## 📌 Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Data Model](#data-model)
- [The Marketing Playbook (RAG Knowledge Base)](#the-marketing-playbook-rag-knowledge-base)
- [Project Structure](#project-structure)
- [Setup & Deployment (Step-by-Step)](#setup--deployment-step-by-step)
- [How It Works](#how-it-works)
  - [Intent Classification (Gateway)](#1-intent-classification-gateway)
  - [SQL Analyst Path](#2-sql-analyst-path)
  - [Playbook RAG Path](#3-playbook-rag-path)
- [Campaigns & Coupons Reference](#campaigns--coupons-reference)
- [Example Queries](#example-queries)
- [Design Decisions](#design-decisions)
- [Limitations & Known Gotchas](#limitations--known-gotchas)


---

## Project Overview

Swiggy's marketing team needs two things simultaneously: quick access to operational data (orders, revenue, customer activity) and strategic guidance on when to run which campaign. Traditionally these live in separate tools — a BI dashboard and a PDF playbook.

This project collapses both into a single chat interface powered by:

- **Snowflake Cortex** for LLM inference, vector embeddings, and hybrid search
- **Snowpark Python** stored procedures for all business logic
- **Streamlit in Snowflake** for the UI — zero external infrastructure

A marketing manager types a question. The bot automatically detects whether it is a **data question** or a **strategy question**, routes it to the appropriate handler, and returns either a dataframe + narrative or a playbook-grounded recommendation with campaign/coupon badges.

---

## Architecture

```
User (Streamlit UI)
        │
        ▼
  SP_GATEWAY  ──── Intent Classification (llama3.1-8b)
   │        │
   ▼        ▼
SP_SQL_ANALYST    SP_PLAYBOOK_RAG
   │                    │
   ▼                    ▼
Snowflake Tables   Cortex Search Service
(Star Schema)      (SWIGGY_PLAYBOOK_CHUNKS)
   │                    │
   └────────┬───────────┘
            ▼
    LLM Generation (llama3.1-70b)
            │
            ▼
  SWIGGY_CONVERSATION_HISTORY
```

**Three-layer design:**

1. **Data Layer** — Star schema (fact + 5 dim tables) + vector store (playbook chunks with 768-dim embeddings)
2. **Application Layer** — Three Python stored procedures (Gateway, Analyst, RAG) running inside Snowflake via Snowpark
3. **Presentation Layer** — Streamlit app embedded in Snowflake, no external hosting

---

## Tech Stack

| Component | Technology |
|---|---|
| Cloud Data Platform | Snowflake |
| LLM Inference | Snowflake Cortex (`llama3.1-8b`, `llama3.1-70b`) |
| Embeddings | `SNOWFLAKE.CORTEX.EMBED_TEXT_768` (e5-base-v2, 768 dims) |
| Vector + Keyword Search | Snowflake Cortex Search Service (hybrid BM25 + vector) |
| Business Logic | Snowpark Python 3.11 Stored Procedures |
| UI | Streamlit in Snowflake (SiS) |
| Data Warehouse Pattern | Star Schema |
| Languages | SQL, Python |

---

## Data Model

All tables live in `SWIGGY_MASTER.DEV`.

### Fact Table

**`SWIGGY_FACT_TRANSACTIONS`** — 158,000+ rows, one row per order line  
Covers: **December 2024 – December 2025** | Cities: **Hyderabad, Bangalore** only

| Column | Type | Notes |
|---|---|---|
| `transaction_id` | INT (PK) | |
| `customer_id` | INT (FK) | → DIM_CUSTOMER |
| `transaction_date` | DATE | |
| `transaction_time` | TIME | |
| `restaurant_product_id` | INT (FK) | → DIM_RESTAURANT_PRODUCT |
| `quantity` | INT | |
| `gross_amount` | FLOAT | INR, before discounts |
| `coupon_used_flag` | BOOL | |
| `coupon_id` | VARCHAR (FK) | → DIM_COUPON |
| `coupon_discount_amount` | FLOAT | |
| `membership_tier` | VARCHAR | NONE / ONE_LITE / ONE / ONE_PLUS |
| `membership_benefit_amount` | FLOAT | |
| `total_discount_amount` | FLOAT | |
| `net_amount` | FLOAT | INR, post-discount |
| `geo_id` | INT (FK) | → DIM_GEO |
| `city` | VARCHAR | Hyderabad / Bangalore |
| `device_type` | VARCHAR | ANDROID / IOS / WEB |
| `campaign_exposed_flag` | BOOL | |
| `campaign_id` | VARCHAR (FK) | → DIM_CAMPAIGN |
| `ad_clicked_flag` | BOOL | |
| `time_to_order_seconds` | INT | |
| `surge_flag` | BOOL | |
| `raining_flag` | BOOL | |
| `delivery_success_flag` | BOOL | |
| `delivery_minutes` | INT | |
| `rating` | TEXT | Use `TRY_CAST(rating AS FLOAT)` — NULLs exist |
| `feedback_text` | VARCHAR | |

### Dimension Tables

**`SWIGGY_DIM_CUSTOMER`** — 6,000 rows  
`customer_id`, `customer_name`, `phone`, `email`, `gender (M/F/O)`, `age`, `home_geo_id`, `home_city`, `signup_date`, `membership_tier`

**`SWIGGY_DIM_GEO`** — 20 rows  
`geo_id`, `city`, `state`, `pincode`

**`SWIGGY_DIM_RESTAURANT_PRODUCT`** — 116 rows  
`restaurant_product_id`, `restaurant_name`, `product_name`, `city`, `restaurant_geo_id`, `cuisine_tag`, `list_price`

**`SWIGGY_DIM_COUPON`** — 6 rows  
`coupon_id` (WELCOME50 / SAVE80 / FREESHIP / WEEKEND20 / PAYDAY15 / NONE), `coupon_name`, `discount_type`, `discount_value`, `max_discount`, `min_order`

**`SWIGGY_DIM_CAMPAIGN`** — 5 rows  
`campaign_id` (PUSH_101 / POPUP_202 / EMAIL_303 / PAID_404 / NONE), `campaign_name`, `channel`, `objective`

> **Important:** All monetary amounts are in **INR**. Never use `CURRENT_DATE` in queries — use `'2025-12-27'::DATE` as the effective "today" since the dataset ends there.

---

## The Marketing Playbook (RAG Knowledge Base)

The Swiggy Marketing Campaign Playbook v2.0 is a 10-chapter strategy document chunked and vectorized into `SWIGGY_PLAYBOOK_CHUNKS`.

### Chapter Overview

| # | Chapter | What it covers |
|---|---|---|
| 1 | Executive Summary | Playbook purpose, scope |
| 2 | Customer Segmentation | Signal categories A (new), B (active), C (at-risk), D (churned) |
| 3 | Signal Framework | Data conditions that trigger campaign responses |
| 4 | Coupon Strategy | Which coupon to use for each signal |
| 5 | Campaign Catalogue | Detailed briefs for all 4 campaigns |
| 6 | Channel Strategy | PUSH vs EMAIL vs INAPP vs PAID — when and why |
| 7 | KPI Framework | CTR, CVR, AOV, GMV, CAC, holdout groups, tCPA |
| 8 | Cortex AI Monitoring | Standard daily chatbot query templates |
| 9 | Special Scenarios | Rain event, new city launch (3 phases), festive/flash sale |
| 10 | Governance & Compliance | Approval matrix, data privacy rules, glossary |

### Chunking Strategy

- H2 sections → one or more chunks depending on content volume
- H3 subsections → always independent chunks
- Tables, decision trees, and SQL snippets → isolated as their own chunks
- Every chunk gets a **breadcrumb prefix** in `chunk_text`:  
  `[Chapter 9 > 9.1 Scenario: Raining Weather Event — URGENT Response Playbook]`  
  This ensures the embedding model captures hierarchical context, not just local text.
- `chunk_text_raw` stores the clean body (no prefix) — used for display and citations
- Metadata columns (`campaign_id_ref`, `coupon_id_ref`, `priority_level`, `channel_ref`) enable structured pre-filtering before vector search

---

## Project Structure

```
swiggy-rag-chatbot/
│
├── Step01_Setup.sql                          # Role, DB, schema, warehouse setup (ACCOUNTADMIN)
├── Step02_DataIngestion.sql                  # Manual CSV ingestion instructions
├── Step03_Playbook_Chunking_RAG.sql          # DDL + INSERT for SWIGGY_PLAYBOOK_CHUNKS
├── Step04_Vectorization_CortexSS.sql         # Embeddings + Cortex Search Service creation
├── Step05_Gateway_Proc.sql                   # SP_GATEWAY — intent classification + routing
├── Step06_Analyst_Proc.sql                   # SP_SQL_ANALYST — text-to-SQL handler
├── Step07_Playbook_Proc.sql                  # SP_PLAYBOOK_RAG — RAG handler
└── Step08_StreamlitApp.py                    # Streamlit UI (run inside Snowflake)
```

---

## Setup & Deployment (Step-by-Step)

### Prerequisites

- Snowflake account with Cortex AI enabled
- `ACCOUNTADMIN` role access for initial setup
- Cortex cross-region enabled: `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION'`

### Step 1 — Environment Setup

Run `Step01_Setup.sql` as `ACCOUNTADMIN`. This creates:
- `Dev Role` with appropriate grants
- `SWIGGY_MASTER` database (Dev / UAT / Prod schemas)
- `STREAMLIT_APPS` database with public grants
- `STREAMLIT_COMPUTE_POOL` (CPU_X64_XS, 1–3 nodes)
- `STREAMLIT_WAREHOUSE` (XSmall)

Replace `AMAN` with your Snowflake username on the `GRANT ROLE` line.

### Step 2 — Data Ingestion

Switch to `Dev Role`. Use Snowflake's Data Load UI or COPY INTO to load the Swiggy CSV files into `SWIGGY_MASTER.DEV`. Then run:

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA SWIGGY_MASTER.DEV TO ROLE "Dev Role";
-- (requires ACCOUNTADMIN for this one line only)
```

### Step 3 — Playbook Chunking

Run `Step03_Playbook_Chunking_RAG.sql` as `Dev Role`. This creates the `SWIGGY_PLAYBOOK_CHUNKS` table and inserts all 40+ chunks from the 10-chapter playbook.

### Step 4 — Vectorization + Search Service

Run `Step04_Vectorization_CortexSS.sql` as `Dev Role`:

```sql
-- Generate 768-dim embeddings for all chunks
UPDATE SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_CHUNKS
SET embedding = SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', chunk_text),
    updated_at = CURRENT_TIMESTAMP();

-- Create Cortex Search Service (hybrid keyword + vector index)
CREATE OR REPLACE CORTEX SEARCH SERVICE SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_SEARCH_SVC
    ON chunk_text
    ATTRIBUTES chapter_number, chapter_title, campaign_id_ref, ...
    WAREHOUSE = COMPUTE_WH
    TARGET_LAG = '30 days'
    AS (SELECT ... FROM SWIGGY_PLAYBOOK_CHUNKS WHERE embedding IS NOT NULL);
```

> **Note:** If your Snowflake region only supports `EMBED_TEXT_1024`, change the model to `multilingual-e5-large` and the column type to `VECTOR(FLOAT, 1024)`.

### Step 5–7 — Stored Procedures

Run each SQL file in order as `Dev Role`:

```sql
-- Step 5: Gateway (intent router)
CALL SWIGGY_MASTER.DEV.SP_GATEWAY('session-id', '[]', 'test message');

-- Step 6: SQL Analyst
CALL SWIGGY_MASTER.DEV.SP_SQL_ANALYST('session-id', '[]', 'Top 5 restaurants by orders in Bangalore');

-- Step 7: Playbook RAG
CALL SWIGGY_MASTER.DEV.SP_PLAYBOOK_RAG('session-id', '[]', 'What campaign for churned users?');
```

### Step 8 — Streamlit App

In Snowflake UI: **Projects → Streamlit → + Streamlit App**

- App name: `Swiggy Bot`
- Database: `STREAMLIT_APPS`
- Schema: `PUBLIC`
- Warehouse: `STREAMLIT_WAREHOUSE`
- Python environment: **Run on Warehouse**

Paste the contents of `Step08_StreamlitApp.py` into the editor and click Run.

---

## How It Works

### 1. Intent Classification (Gateway)

`SP_GATEWAY` receives every user message and classifies it using `llama3.1-8b`:

```
ANALYST  → user wants to SEE DATA: numbers, metrics, tables, rankings, counts, trends
PLAYBOOK → user wants STRATEGY ADVICE: which campaign to run, which coupon, how to handle a scenario
```

The last 4 conversation turns are included in the classification prompt for context. If the LLM output is ambiguous, it defaults to `ANALYST`.

After classification, the gateway calls the primary SP. If that fails, it **cross-falls** to the other SP and flags the response accordingly.

### 2. SQL Analyst Path

`SP_SQL_ANALYST` handles all data questions:

1. **Prompt construction** — full schema context (all 6 tables, FK joins, column descriptions, date range constraint, INR currency note) is injected into the LLM prompt
2. **SQL generation** — `llama3.1-70b` writes a Snowflake SELECT statement
3. **Validation** — checks for SELECT keyword, blocks dangerous keywords (DROP, DELETE, UPDATE, INSERT, MERGE, TRUNCATE, ALTER)
4. **Execution** — runs against Snowflake, returns up to 500 rows
5. **Narrative generation** — LLM writes a 2–3 sentence plain-English summary of the results with one actionable recommendation
6. **Retry** — if attempt 1 fails, a simpler prompt is tried (attempt 2)

The UI renders results as a Streamlit dataframe + expandable SQL code block.

### 3. Playbook RAG Path

`SP_PLAYBOOK_RAG` handles all strategy questions:

1. **Query enhancement** — `llama3.1-8b` rewrites the user's question into a standalone query, resolving pronouns from conversation history (anaphora resolution)
2. **Retrieval** — Cortex Search returns the top 3 most relevant chunks (hybrid BM25 + vector similarity)
3. **3-level fallback** — enhanced query → raw message → first 5 words of message
4. **RAG prompt construction** — retrieved chunks are formatted as context blocks with their source paths
5. **Answer generation** — `llama3.1-70b` generates a structured answer: direct response, recommended campaigns/coupons, conditions/guardrails, priority level
6. **Metadata extraction** — campaign IDs, coupon codes, and priority levels are regex-extracted from the answer for badge rendering

The UI renders the answer as markdown + colored badges for campaigns, coupons, and priority, plus an expandable citations panel showing the exact playbook excerpts used.

---

## Campaigns & Coupons Reference

### Campaigns

| ID | Channel | Objective |
|---|---|---|
| `PUSH_101` | Push notification | Increase orders / weather triggers |
| `POPUP_202` | In-app popup | Coupon adoption / engagement |
| `EMAIL_303` | Email | Reactivation of churned/at-risk users |
| `PAID_404` | Paid media | Acquisition / new city launch |

### Coupons

| ID | Type | Best for |
|---|---|---|
| `WELCOME50` | % discount | New users — first order |
| `SAVE80` | Flat INR discount | Existing users — high-value orders |
| `FREESHIP` | Free delivery | Weather events / impulse orders |
| `WEEKEND20` | % discount | Weekend engagement / festive |
| `PAYDAY15` | % discount | Payday window (25th–5th of month) |

### Signal Categories (Customer Segments)

| Signal | Segment | Description |
|---|---|---|
| A | New users | Acquisition — 0 orders placed |
| B | Active users | Engagement — regular orderers needing frequency boost |
| C | At-risk users | Retention — declining order frequency |
| D | Churned users | Reactivation — no orders in 31+ days |

---

## Example Queries

### Data Questions (ANALYST path)

```
Top 9 restaurants by revenue in Hyderabad
Show me monthly revenue trend for Bangalore
Average delivery time and rating by city
Coupon vs non-coupon revenue breakdown
How many customers have been inactive for more than 14 days?
Compare order volume on rainy days vs non-rainy days
```

### Strategy Questions (PLAYBOOK path)

```
Which campaign should I run for churned users?
What do I do when it's raining?
Best coupon for new users with 0 orders?
Strategy for a new city launch
How do I handle a lunch-hour dip in orders?
What does the playbook say about festive campaigns?
What is the approval process for emergency weather campaigns?
```

---

## Design Decisions

**Why classify intent with a small model instead of rules/keywords?**  
Rule-based classification ("if the message contains 'show me' → ANALYST") breaks on natural language variation. An LLM classifier handles paraphrases, context-dependent queries, and ambiguous phrasing much more robustly. Using the small 8b model keeps latency low since this is on the critical path.

**Why breadcrumb prefixes in chunk_text?**  
An isolated chunk like "Activate PUSH_101 with FREESHIP coupon" has no context about when or why. The breadcrumb prefix `[Chapter 9 > 9.1 Raining Weather Event — URGENT]` ensures the embedding model captures hierarchical context. This significantly improves retrieval precision for specific scenario queries.

**Why hybrid search (Cortex Search) over pure vector similarity?**  
Pure vector search can miss exact campaign IDs like `PUSH_101` or `FREESHIP` if the query uses different phrasing. Pure keyword search misses semantic queries like "what should I do when orders drop at lunch." Hybrid combines both and consistently outperforms either alone.

**Why EXECUTE AS OWNER on stored procedures?**  
Users only need `EXECUTE` privilege on the SPs — they never need direct table access. This is a least-privilege security pattern. The application layer is the controlled interface; the data layer is protected behind it.

**Why `'2025-12-27'::DATE` instead of `CURRENT_DATE`?**  
The dataset ends in December 2025. Using `CURRENT_DATE` (currently 2026) in date range filters like "last 7 days" or "this month" would return zero rows. This constraint is baked into the schema prompt given to the LLM.

---

## Limitations & Known Gotchas

- **`rating` column is TEXT** — always use `TRY_CAST(rating AS FLOAT)` for numeric operations. NULLs exist.
- **Cities are Hyderabad and Bangalore only** — no other cities in the dataset.
- **Transaction data ends December 2025** — all date-relative queries use `'2025-12-27'` as today.
- **Cortex Search `TARGET_LAG = '30 days'`** — if you add new chunks to the playbook, the search index won't reflect them for up to 30 days. Set to `'1 hour'` for near-real-time updates during active development.
- **Embeddings must be generated before creating Cortex Search Service** — the service filters to `WHERE embedding IS NOT NULL`.
- **Streamlit session state is in-memory** — clearing the browser tab loses conversation history. The persistent `SWIGGY_CONVERSATION_HISTORY` table is the durable record.
- **All amounts are INR** — do not interpret revenue figures as USD.
- **The 8b model can misclassify ambiguous queries** — e.g. "compare campaign performance" might go to ANALYST (data) or PLAYBOOK (strategy guidance). The cross-fallback handles this gracefully.

---

*Built with Snowflake Cortex AI | Swiggy Marketing Analytics & Ops | FY 2025*