USE DATABASE SWIGGY_MASTER;
USE SCHEMA DEV;
USE ROLE "Dev Role";

-- =============================================================================
-- STEP 1 — VERIFY ROW COUNT AND STRUCTURE
-- =============================================================================

SELECT
    chapter_number,
    chapter_title,
    COUNT(*)          AS chunks_in_chapter,
    MIN(chunk_type)   AS sample_type
FROM SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_CHUNKS
GROUP BY chapter_number, chapter_title
ORDER BY chapter_number;

SELECT COUNT(*) AS total_chunks FROM SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_CHUNKS;


-- =============================================================================
-- STEP 2 — GENERATE EMBEDDINGS USING SNOWFLAKE CORTEX
-- =============================================================================
-- Model: e5-base-v2 via SNOWFLAKE.CORTEX.EMBED_TEXT_768()
-- This produces a 768-dimensional FLOAT vector suitable for cosine similarity
-- search. The embedding is computed on chunk_text (breadcrumb-enriched) to
-- ensure the vector captures hierarchical context, not just raw body text.
--
-- NOTE: EMBED_TEXT_768 is a Cortex function available in most Snowflake regions.
--       If your region only supports EMBED_TEXT_1024, change:
--         - The model string to 'multilingual-e5-large'
--         - The column type above to VECTOR(FLOAT, 1024)
-- =============================================================================

UPDATE SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_CHUNKS
SET
    embedding  = SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', chunk_text),
    updated_at = CURRENT_TIMESTAMP();

SELECT * FROM SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_CHUNKS limit 5;

-- Spot-check: confirm embeddings populated
SELECT
    chunk_id,
    full_path,
    chunk_type,
    VECTOR_L2_DISTANCE(
        embedding,
        SNOWFLAKE.CORTEX.EMBED_TEXT_768('e5-base-v2', 'Which campaign should I run for churned customers?')
    ) AS l2_distance
FROM SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_CHUNKS
ORDER BY l2_distance ASC
LIMIT 5;


-- =============================================================================
-- STEP 3 — CREATE CORTEX SEARCH SERVICE
-- =============================================================================
-- Cortex Search provides a fully managed hybrid search (keyword + vector) index
-- on top of the chunks table. It is the retrieval backbone of the RAG chatbot.
--
-- Key design choices:
--   • ON chunk_text        → the enriched text column is the primary search body
--   • ATTRIBUTES (...)     → structured metadata columns exposed for pre-filtering
--                            so the LLM can scope retrieval to a specific chapter,
--                            campaign, coupon, or channel before semantic search
--   • TARGET_LAG = '1 day' → re-index daily; change to '1 hour' for near-real-time
--                            updates if chunks are added/modified frequently
-- =============================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_SEARCH_SVC
    ON chunk_text
    ATTRIBUTES
        chapter_number,
        chapter_title,
        section_number,
        section_title,
        subsection_title,
        chunk_type,
        campaign_id_ref,
        signal_category,
        coupon_id_ref,
        channel_ref,
        priority_level,
        full_path,
        chunk_text_raw        -- returned for clean display without the breadcrumb prefix
    WAREHOUSE = COMPUTE_WH   -- replace with your actual warehouse name
    TARGET_LAG = '30 days'
    AS (
        SELECT
            chunk_id,
            source_document,
            chapter_number,
            chapter_title,
            section_number,
            section_title,
            subsection_title,
            chunk_sequence,
            full_path,
            chunk_type,
            chunk_text_raw,
            chunk_text,
            campaign_id_ref,
            signal_category,
            coupon_id_ref,
            channel_ref,
            priority_level,
            created_at
        FROM SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_CHUNKS
        WHERE embedding IS NOT NULL   -- only fully processed chunks are indexed
    );


-- =============================================================================
-- STEP 4 — SAMPLE SEARCH QUERIES (TEST THE SERVICE)
-- =============================================================================
-- Use the Cortex Search REST API or the Python SDK from Streamlit as below.
-- These SQL SELECT equivalents demonstrate how to invoke the service for testing.
-- =============================================================================

-- Test 1: "What campaign should I run for at-risk customers?"
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_SEARCH_SVC',
        '{
           "query": "What campaign should I run for at-risk customers who have been inactive for 2 weeks?",
           "columns": ["full_path", "chunk_text_raw", "campaign_id_ref", "priority_level"],
           "limit": 3
         }'
    )
) AS search_results;

-- Test 2: "Which coupon should I use on a rainy day?"
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_SEARCH_SVC',
        '{
           "query": "Which coupon should I offer when it is raining?",
           "columns": ["full_path", "chunk_text_raw", "coupon_id_ref", "channel_ref"],
           "limit": 3
         }'
    )
) AS search_results;

-- Test 3: Pre-filter to Chapter 5 (Campaign Catalogue) only
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_SEARCH_SVC',
        '{
           "query": "What is the email campaign for reactivating churned users?",
           "columns": ["full_path", "chunk_text_raw", "campaign_id_ref"],
           "filter": {"@eq": {"chapter_number": 5}},
           "limit": 3
         }'
    )
) AS search_results;

-- Test 4: Filter to URGENT priority signals only
SELECT PARSE_JSON(
    SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
        'SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_SEARCH_SVC',
        '{
           "query": "What should I do immediately when there is a weather signal?",
           "columns": ["full_path", "chunk_text_raw", "priority_level", "coupon_id_ref"],
           "filter": {"@eq": {"priority_level": "URGENT"}},
           "limit": 3
         }'
    )
) AS search_results;