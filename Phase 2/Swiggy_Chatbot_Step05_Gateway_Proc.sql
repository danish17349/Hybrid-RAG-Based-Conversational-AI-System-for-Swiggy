USE DATABASE SWIGGY_MASTER;
USE SCHEMA DEV;
USE ROLE "Dev Role";

CREATE OR REPLACE PROCEDURE SWIGGY_MASTER.DEV.SP_GATEWAY("SESSION_ID" VARCHAR, "HISTORY" VARCHAR, "MESSAGE" VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'gateway'
EXECUTE AS OWNER
AS '
import json, re, traceback, uuid

def llm_classify(session, history_text, message):
    prompt = f"""You are an intent classifier for a Swiggy food-delivery marketing chatbot.
Classify the user''''s CURRENT MESSAGE into exactly one category:

ANALYST — user wants to SEE DATA: numbers, metrics, tables, rankings, counts,
  revenue figures, order stats, customer lists, delivery times, ratings,
  trend analysis, comparisons, or any factual lookup from the database.
  Examples:
  - "Top 9 restaurants in Hyderabad"
  - "Top 9 restaurants by revenue in Hyderabad"
  - "Top 9 restaurants by orders in Bangalore"
  - "Top 5 restaurants by orders in Bangalore"
  - "Show me revenue by city this month"
  - "Average delivery time and rating by city"
  - "Coupon vs non-coupon revenue breakdown"
  - "Monthly revenue trend"
  - "How many orders last week?"
  - "List inactive customers in Bangalore"

PLAYBOOK — user wants STRATEGY ADVICE: which campaign to run, which coupon
  to offer, how to handle a marketing scenario, channel recommendations,
  or guidance from the marketing playbook.
  Examples:
  - "Which campaign for churned users?"
  - "What do I do when it''''s raining?"
  - "Best coupon for new users with 0 orders?"
  - "Strategy for a new city launch"
  - "How do I handle a lunch-hour dip?"
  - "Which channel for reactivation?"
  - "What does the playbook say about festive campaigns?"
  - "Should I run a push notification for at-risk users?"

KEY DISTINCTION: If the user asks to SEE, LIST, COUNT, RANK, or COMPARE data
(even restaurants, campaigns, customers, cities) → ANALYST.
If the user asks what TO DO, which action to TAKE, wants ADVICE, or asks
about handling a SITUATION → PLAYBOOK.

Conversation context:
{history_text or "(first message)"}

CURRENT MESSAGE: "{message}"

Respond with exactly one word: ANALYST or PLAYBOOK"""

    try:
        row = session.sql(
            "SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.1-8b'', ?) AS resp",
            params=[prompt]
        ).collect()[0]
        raw = str(row["RESP"]).strip().upper()
        if "ANALYST" in raw:
            return {"intent": "ANALYST", "confidence": 0.85, "method": "llm"}
        elif "PLAYBOOK" in raw:
            return {"intent": "PLAYBOOK", "confidence": 0.85, "method": "llm"}
        else:
            return {"intent": "ANALYST", "confidence": 0.50, "method": "llm_unclear"}
    except Exception as e:
        return {"intent": "ANALYST", "confidence": 0.50, "method": "llm_error", "error": str(e)}

def classify_intent(session, history, message):
    try:
        hist = json.loads(history) if history else []
    except Exception:
        hist = []

    history_text = "\\n".join(
        "[{}]: {}".format(
            h.get("role", "").upper(),
            h.get("message") or h.get("summary", "")
        )
        for h in hist[-4:]
    )

    return llm_classify(session, history_text, message)

def _call_sp(session, sp_name, session_id, history, message):
    try:
        rows = session.sql(
            f"CALL SWIGGY_MASTER.DEV.{sp_name}(?, ?, ?)",
            params=[session_id, history, message]
        ).collect()
        result = rows[0][0]
        if isinstance(result, str):
            result = json.loads(result)
        return result or {}
    except Exception as e:
        return {"status": "error", "error": str(e), "narrative": "", "answer": ""}

def _persist_user_turn(session, session_id, message, intent):
    try:
        row = session.sql(
            "SELECT COALESCE(MAX(turn_number),0)+1 AS n "
            "FROM SWIGGY_MASTER.DEV.SWIGGY_CONVERSATION_HISTORY WHERE session_id=?",
            params=[session_id]
        ).collect()[0]
        turn = int(row["N"])
        session.sql(
            """INSERT INTO SWIGGY_MASTER.DEV.SWIGGY_CONVERSATION_HISTORY
               (session_id, turn_number, role, message, intent, created_at)
               SELECT ?, ?, ''user'', ?, ?, CURRENT_TIMESTAMP()""",
            params=[session_id, turn, message, intent]
        ).collect()
    except Exception:
        pass

def _get_turn_number(session, session_id):
    try:
        row = session.sql(
            "SELECT COALESCE(MAX(turn_number),0) AS N FROM SWIGGY_MASTER.DEV.SWIGGY_CONVERSATION_HISTORY WHERE session_id=?",
            params=[session_id]
        ).collect()[0]
        return int(row["N"])
    except Exception:
        return 0

def _is_success(resp):
    return resp.get("status") == "success" and not resp.get("error")

def gateway(session, session_id, history, message):
    if not session_id:
        session_id = str(uuid.uuid4())

    clf = classify_intent(session, history, message)
    intent     = clf.get("intent", "ANALYST")
    confidence = clf.get("confidence", 0.5)
    clf_method = clf.get("method", "fallback")

    _persist_user_turn(session, session_id, message, intent)

    primary_sp  = "SP_SQL_ANALYST"  if intent == "ANALYST"  else "SP_PLAYBOOK_RAG"
    fallback_sp = "SP_PLAYBOOK_RAG" if intent == "ANALYST"  else "SP_SQL_ANALYST"

    primary_resp = _call_sp(session, primary_sp, session_id, history, message)

    cross_fallback_used = False
    final_resp = primary_resp

    if not _is_success(primary_resp):
        fallback_resp = _call_sp(session, fallback_sp, session_id, history, message)
        if _is_success(fallback_resp):
            final_resp = fallback_resp
            cross_fallback_used = True
            intent = "PLAYBOOK" if intent == "ANALYST" else "ANALYST"

    try:
        turn = _get_turn_number(session, session_id) + 1
        summary = ""
        if intent == "ANALYST":
            summary = (final_resp.get("narrative") or "")[:300]
        else:
            summary = (final_resp.get("answer") or "")[:300]
        session.sql(
            """INSERT INTO SWIGGY_MASTER.DEV.SWIGGY_CONVERSATION_HISTORY
               (session_id, turn_number, role, message, intent, created_at)
               SELECT ?, ?, ''assistant'', ?, ?, CURRENT_TIMESTAMP()""",
            params=[session_id, turn, summary, intent]
        ).collect()
    except Exception:
        pass

    final_resp["_gateway"] = {
        "classified_intent":   intent,
        "confidence":          confidence,
        "method":              clf_method,
        "cross_fallback_used": cross_fallback_used,
        "session_id":          session_id,
    }

    return final_resp
';