USE DATABASE SWIGGY_MASTER;
USE SCHEMA DEV;
USE ROLE "Dev Role";


CREATE OR REPLACE PROCEDURE SWIGGY_MASTER.DEV.SP_SQL_ANALYST("SESSION_ID" VARCHAR, "HISTORY" VARCHAR, "MESSAGE" VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run_analyst'
EXECUTE AS OWNER
AS '
import json, re, traceback
from datetime import date, datetime
from decimal import Decimal

# ── Schema context (compact but complete) ─────────────────────────────────────
SCHEMA = """
Database: SWIGGY_MASTER, Schema: DEV. Always prefix tables as SWIGGY_MASTER.DEV.<table>. IMPORTANT: Transaction data covers Dec 2024 to Dec 2025 only. Never filter by CURRENT_DATE — use ''2025-12-27''::DATE as the effective "today" for all date calculations. All monetary amounts are in INR and not USD.

SWIGGY_FACT_TRANSACTIONS  — 158 000+ rows, one row per order line
  transaction_id (PK INT), customer_id (FK→DIM_CUSTOMER INT),
  transaction_date (DATE), transaction_time (TIME),
  restaurant_product_id (FK→DIM_RESTAURANT_PRODUCT INT), quantity (INT),
  gross_amount (FLOAT), coupon_used_flag (BOOL), coupon_id (FK→DIM_COUPON VARCHAR),
  coupon_discount_amount (FLOAT), membership_tier (VARCHAR: NONE/ONE_LITE/ONE/ONE_PLUS),
  membership_benefit_amount (FLOAT), total_discount_amount (FLOAT), net_amount (FLOAT),
  geo_id (FK→DIM_GEO INT), city (VARCHAR: Hyderabad/Bangalore),
  device_type (VARCHAR: ANDROID/IOS/WEB), campaign_exposed_flag (BOOL),
  campaign_id (FK→DIM_CAMPAIGN VARCHAR), ad_clicked_flag (BOOL),
  time_to_order_seconds (INT), surge_flag (BOOL), raining_flag (BOOL),
  search_delivery_flag (BOOL), delivery_success_flag (BOOL), delivery_minutes (INT),
  feedback_left_flag (BOOL), rating (TEXT — use TRY_CAST(rating AS FLOAT) for numeric ops; NULLs exist), feedback_text (VARCHAR)

SWIGGY_DIM_CUSTOMER  — 6 000 rows
  customer_id (PK INT), customer_name, phone, email,
  gender (M/F/O), age (INT), home_geo_id (FK→DIM_GEO INT),
  home_city (Hyderabad/Bangalore), signup_date (DATE),
  membership_tier (NONE/ONE_LITE/ONE/ONE_PLUS)

SWIGGY_DIM_GEO  — 20 rows
  geo_id (PK INT), city (Hyderabad/Bangalore), state (Telangana/Karnataka), pincode (INT)

SWIGGY_DIM_RESTAURANT_PRODUCT  — 116 rows
  restaurant_product_id (PK INT), restaurant_name, product_name, city,
  restaurant_geo_id (FK→DIM_GEO INT), cuisine_tag, list_price (FLOAT)

SWIGGY_DIM_COUPON  — 6 rows
  coupon_id (PK: WELCOME50/SAVE80/FREESHIP/WEEKEND20/PAYDAY15/NONE),
  coupon_name, discount_type (PCT/FLAT/NONE), discount_value, max_discount, min_order

SWIGGY_DIM_CAMPAIGN  — 5 rows
  campaign_id (PK: PUSH_101/POPUP_202/EMAIL_303/PAID_404/NONE),
  campaign_name, channel (PUSH/INAPP_POPUP/EMAIL/PAID_MEDIA/NONE),
  objective (INCREASE_ORDERS/COUPON_ADOPTION/REACTIVATION/ACQUISITION/NONE)

FK Joins:
  fact.customer_id         = dim_customer.customer_id
  fact.geo_id              = dim_geo.geo_id
  fact.restaurant_product_id = dim_restaurant_product.restaurant_product_id
  fact.coupon_id           = dim_coupon.coupon_id
  fact.campaign_id         = dim_campaign.campaign_id
  dim_customer.home_geo_id = dim_geo.geo_id
"""

def _safe_value(v):
    """JSON-serialize edge-case Python types from Snowflake result sets."""
    if isinstance(v, (datetime, date)):
        return v.isoformat()
    if isinstance(v, Decimal):
        return float(v)
    if v is None:
        return None
    return v

def _rows_to_list(rows, max_rows: int = 500) -> tuple[list, list]:
    """Convert Snowflake result rows to a list-of-dicts and a column list."""
    if not rows:
        return [], []
    columns = list(rows[0].as_dict().keys())
    data = [
        {k: _safe_value(v) for k, v in row.as_dict().items()}
        for row in rows[:max_rows]
    ]
    return data, columns

def _build_history_context(history_json: str) -> str:
    """Build a compact text block from the last 6 analyst turns for the prompt."""
    try:
        hist = json.loads(history_json) if history_json else []
    except Exception:
        return ""
    lines = []
    for h in hist[-3:]:
        role = h.get("role", "")
        if role == "user":
            lines.append(f"USER: {h.get(''message'','''')}")
        elif role == "assistant" and h.get("intent") == "ANALYST":
            if h.get("sql"):
                lines.append(f"ASSISTANT_SQL: {h.get(''sql'','''')[:600]}")
            if h.get("summary"):
                lines.append(f"ASSISTANT_RESULT: {h.get(''summary'','''')[:300]}")
    return "\\n".join(lines)

def _build_sql_prompt(message: str, history_ctx: str, attempt: int) -> str:
    if attempt == 1:
        return f"""You are an expert Snowflake SQL analyst for Swiggy.

SCHEMA:
{SCHEMA}

CONVERSATION HISTORY (for resolving pronouns and follow-up questions):
{history_ctx or "(first question in session)"}

CURRENT QUESTION: {message}

Rules:
1. Return ONLY a valid Snowflake SELECT statement — no explanation, no markdown, no backticks.
2. Always prefix tables: SWIGGY_MASTER.DEV.<table_name>
3. Alias every computed column clearly (e.g. SUM(net_amount) AS total_net_revenue)
4. Use Snowflake date functions: DATEDIFF, DATEADD, TO_CHAR, DAYNAME, HOUR, MONTH
5. Default LIMIT 500 unless the question implies a different scope
6. If the question references a previous result ("those customers", "break it down"), 
   re-derive from the schema using the conversation history as context.
7. Surround monetary columns with ROUND(..., 2)

SQL:"""
    else:
        # Simplified retry prompt — no history, just schema + question
        return f"""Write a Snowflake SQL SELECT for this question: {message}

{SCHEMA}

Return ONLY the SQL. No backticks. Prefix tables as SWIGGY_MASTER.DEV.<table>.
SQL:"""

def _extract_sql(raw: str) -> str:
    """Pull the first SQL statement from raw LLM output."""
    # Strip markdown fences
    raw = re.sub(r"```(?:sql)?", "", raw, flags=re.IGNORECASE).strip()
    # Find SELECT ... (up to end or next blank line)
    match = re.search(r"(SELECT\\s.+)", raw, re.IGNORECASE | re.DOTALL)
    if match:
        sql = match.group(1).strip()
        # Remove any trailing commentary after a semicolon
        sql = sql.split(";")[0].strip() + ";"
        return sql
    return raw.strip()

def _validate_sql(sql: str) -> tuple[bool, str]:
    """Basic safety checks before execution."""
    upper = sql.upper()
    if not re.search(r"\\bSELECT\\b", upper):
        return False, "No SELECT statement found"
    for dangerous in ("DROP ", "DELETE ", "UPDATE ", "INSERT ", "MERGE ", "TRUNCATE ", "ALTER "):
        if dangerous in upper:
            return False, f"Dangerous keyword detected: {dangerous.strip()}"
    return True, "ok"

def _generate_narrative(session, question: str, data: list, columns: list) -> str:
    """Ask LLM to narrate the result in 2-3 sentences."""
    if not data:
        return "The query returned no results."
    preview = json.dumps(data[:10], default=str)
    prompt = f"""You are a concise Swiggy data analyst.
Question asked: "{question}"
Query result (first {min(len(data),10)} of {len(data)} rows): {preview}
Columns: {columns}

Write 2-3 plain-English sentences summarising the key finding.
Highlight the most important number or trend.
End with one actionable marketing recommendation if warranted.
No bullet points, no markdown, just clear prose."""
    try:
        row = session.sql(
            "SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.1-8b'', ?) AS resp",
            params=[prompt]
        ).collect()[0]
        return str(row["RESP"]).strip()
    except Exception:
        return f"Query returned {len(data)} row(s) across {len(columns)} column(s)."

# ── Main handler ──────────────────────────────────────────────────────────────
def run_analyst(session, session_id: str, history: str, message: str) -> dict:
    history_ctx = _build_history_context(history)
    last_error  = None

    for attempt in (1, 2):   # two SQL-generation attempts
        try:
            prompt  = _build_sql_prompt(message, history_ctx if attempt == 1 else "", attempt)
            llm_row = session.sql(
                "SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.1-70b'', ?) AS resp",
                params=[prompt]
            ).collect()[0]
            raw_sql  = str(llm_row["RESP"]).strip()
            clean_sql = _extract_sql(raw_sql)

            valid, reason = _validate_sql(clean_sql)
            if not valid:
                last_error = f"SQL validation failed: {reason}"
                continue

            rows = session.sql(clean_sql).collect()
            data, columns = _rows_to_list(rows)
            narrative = _generate_narrative(session, message, data, columns)

            # Persist the turn
            _persist_turn(session, session_id, "assistant", "ANALYST", None, {
                "sql": clean_sql, "narrative": narrative,
                "row_count": len(data), "columns": columns
            }, clean_sql, narrative)

            return {
                "status":        "success",
                "sql":           clean_sql,
                "narrative":     narrative,
                "results":       data,
                "columns":       columns,
                "row_count":     len(data),
                "fallback_used": attempt > 1,
                "error":         None,
            }

        except Exception as e:
            last_error = str(e)
            continue   # try next attempt

    # Both attempts failed — graceful degradation
    return {
        "status":        "error",
        "sql":           None,
        "narrative":     f"I wasn''t able to generate a valid SQL query for that question. "
                         f"Try rephrasing, or ask something like ''show total orders by city''. "
                         f"Technical detail: {last_error}",
        "results":       [],
        "columns":       [],
        "row_count":     0,
        "fallback_used": True,
        "error":         last_error,
    }

def _persist_turn(session, session_id, role, intent, user_msg, resp_dict, sql, summary):
    """Write a conversation turn to the history table. Non-fatal if it fails."""
    try:
        row = session.sql(
            "SELECT COALESCE(MAX(turn_number),0)+1 AS n "
            "FROM SWIGGY_MASTER.DEV.SWIGGY_CONVERSATION_HISTORY WHERE session_id=?",
            params=[session_id]
        ).collect()[0]
        turn = int(row["N"])
        resp_json = json.dumps(resp_dict, default=str)
        session.sql(
            """INSERT INTO SWIGGY_MASTER.DEV.SWIGGY_CONVERSATION_HISTORY
               (session_id, turn_number, role, intent, user_message,
                response_json, sql_generated, summary)
               SELECT ?,?,?,?,?,PARSE_JSON(?),?,?""",
            params=[session_id, turn, role, intent,
                    user_msg, resp_json, sql, summary]
        ).collect()
    except Exception:
        pass   # persistence failure is non-fatal
';