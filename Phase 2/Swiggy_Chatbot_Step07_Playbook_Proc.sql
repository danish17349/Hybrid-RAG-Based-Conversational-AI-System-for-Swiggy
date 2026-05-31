USE DATABASE SWIGGY_MASTER;
USE SCHEMA DEV;
USE ROLE "Dev Role";

CREATE OR REPLACE PROCEDURE SWIGGY_MASTER.DEV.SP_PLAYBOOK_RAG("SESSION_ID" VARCHAR, "HISTORY" VARCHAR, "MESSAGE" VARCHAR)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run_rag'
EXECUTE AS OWNER
AS '
import json, re, traceback

SEARCH_SVC  = ''SWIGGY_MASTER.DEV.SWIGGY_PLAYBOOK_SEARCH_SVC''
LLM_MODEL   = ''llama3.1-70b''
TOP_K       = 3
RETURN_COLS = ["full_path","chunk_text_raw","chapter_title",
               "campaign_id_ref","coupon_id_ref","channel_ref",
               "priority_level","chunk_type"]

# ── Helpers ───────────────────────────────────────────────────────────────────
def _build_history_for_rag(history_json: str) -> tuple[list, str]:
    """Return (hist_list, compact_text) for the last 4 RAG turns."""
    try:
        hist = json.loads(history_json) if history_json else []
    except Exception:
        return [], ""
    rag_turns = [h for h in hist if h.get("intent") == "PLAYBOOK"]
    lines = []
    for h in rag_turns[-4:]:
        role = h.get("role","")
        if role == "user":
            lines.append(f"USER: {h.get(''message'','''')}")
        elif role == "assistant":
            lines.append(f"ASSISTANT: {h.get(''summary'','''')[:300]}")
    return hist, "\\n".join(lines)

def _enhance_query(session, history_text: str, message: str) -> str:
    """Use LLM to rewrite the search query, resolving anaphora from history."""
    if not history_text:
        return message   # no history → no enhancement needed
    prompt = f"""A user is asking about Swiggy marketing campaigns.
Conversation history:
{history_text}
New message: "{message}"

Rewrite the new message as a standalone, self-contained search query that resolves
any pronouns or references to earlier conversation turns.
Return ONLY the rewritten query — no explanation, no quotes."""
    try:
        row = session.sql(
            "SELECT SNOWFLAKE.CORTEX.COMPLETE(?, ?) AS resp",
            params=[''llama3.1-8b'', prompt]
        ).collect()[0]
        enhanced = str(row["RESP"]).strip()
        return enhanced if enhanced else message
    except Exception:
        return message

def _search(session, query: str, top_k: int = TOP_K) -> list:
    """Execute CORTEX.SEARCH_PREVIEW and return result list."""
    payload = json.dumps({
        "query":   query,
        "columns": RETURN_COLS,
        "limit":   top_k,
    })
    try:
        rows = session.sql(
            "SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(?, ?)) AS r",
            params=[SEARCH_SVC, payload]
        ).collect()
        result_obj = rows[0]["R"]
        if isinstance(result_obj, str):
            result_obj = json.loads(result_obj)
        return result_obj.get("results", [])
    except Exception:
        return []

def _build_rag_prompt(question: str, history_text: str, chunks: list,
                      fallback_no_chunks: bool) -> str:
    if fallback_no_chunks:
        return f"""You are the Swiggy Marketing Strategy AI with expertise in
campaign planning and Swiggy''s marketing operations.

A marketing manager asked: "{question}"

The playbook knowledge base returned no results. Answer using your general knowledge
of food delivery marketing best practices. Clearly state your response is based on
general marketing knowledge, not the Swiggy playbook.

Answer:"""

    context_blocks = "\\n\\n---\\n\\n".join(
        f"[Source {i+1}: {c.get(''full_path'','''')}]\\n{c.get(''chunk_text_raw'','''')}"
        for i, c in enumerate(chunks)
    )
    return f"""You are the Swiggy Marketing Strategy AI, an expert on Swiggy''s
Marketing Campaign Playbook v2.0.

{"CONVERSATION HISTORY (for context):" + chr(10) + history_text + chr(10) if history_text else ""}
CURRENT QUESTION: "{question}"

Using ONLY the playbook excerpts below, provide:
1. A direct answer (2–3 sentences)
2. Recommended campaign(s): state the campaign ID, channel, and coupon to use
3. Key conditions, thresholds, or guardrails to observe
4. Priority level (URGENT/HIGH/MEDIUM/LOW) if applicable

If the excerpts do not contain relevant information, say so clearly.
Do NOT invent campaign details not found in the excerpts.

PLAYBOOK EXCERPTS:
{context_blocks}

ANSWER:"""

def _extract_campaigns(text: str) -> list:
    return list(dict.fromkeys(re.findall(
        r''\\b(PUSH_101|POPUP_202|EMAIL_303|PAID_404)\\b'', text, re.IGNORECASE
    )))

def _extract_coupons(text: str) -> list:
    return list(dict.fromkeys(re.findall(
        r''\\b(WELCOME50|SAVE80|FREESHIP|WEEKEND20|PAYDAY15)\\b'', text, re.IGNORECASE
    )))

def _extract_priority(chunks: list) -> str:
    order = {"URGENT": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3}
    best  = None
    for c in chunks:
        p = str(c.get("priority_level", "") or "")
        if p in order:
            if best is None or order[p] < order[best]:
                best = p
    return best or ""

def _persist_turn(session, session_id, role, intent, user_msg, resp_dict, summary):
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
                    user_msg, resp_json, None, summary]
        ).collect()
    except Exception:
        pass

# ── Main handler ──────────────────────────────────────────────────────────────
def run_rag(session, session_id: str, history: str, message: str) -> dict:
    hist_list, history_text = _build_history_for_rag(history)
    fallback_used = False
    chunks_used   = []

    # ── Retrieval: 3-attempt fallback chain ───────────────────────────────────
    # Attempt 1: LLM-enhanced query (resolves multi-turn anaphora)
    enhanced_q = _enhance_query(session, history_text, message)
    chunks = _search(session, enhanced_q)

    if not chunks:
        fallback_used = True
        # Attempt 2: raw message as query
        chunks = _search(session, message)

    if not chunks:
        # Attempt 3: first 5 words — very broad
        short_q = " ".join(message.split()[:5])
        chunks  = _search(session, short_q)

    # ── Generation ────────────────────────────────────────────────────────────
    fallback_no_chunks = len(chunks) == 0
    prompt  = _build_rag_prompt(message, history_text, chunks, fallback_no_chunks)

    try:
        row    = session.sql(
            "SELECT SNOWFLAKE.CORTEX.COMPLETE(?, ?) AS resp",
            params=[LLM_MODEL, prompt]
        ).collect()[0]
        answer = str(row["RESP"]).strip()
    except Exception as e:
        # Last-resort fallback: return raw chunk text
        if chunks:
            answer = ("Here are the most relevant sections from the playbook:\\n\\n" +
                      "\\n\\n".join(f"[{c.get(''full_path'','''')}]\\n{c.get(''chunk_text_raw'','''')}"
                                  for c in chunks[:3]))
        else:
            answer = f"I was unable to retrieve an answer from the playbook. Error: {e}"
        fallback_used = True

    campaigns = _extract_campaigns(answer)
    coupons   = _extract_coupons(answer)
    priority  = _extract_priority(chunks)
    summary   = answer[:400]

    # Serialize citations for JSON storage
    citations = [
        {k: str(v) if v is not None else "" for k, v in c.items()}
        for c in chunks
    ]

    result = {
        "status":            "success",
        "answer":            answer,
        "citations":         citations,
        "campaigns":         campaigns,
        "coupons":           coupons,
        "priority":          priority,
        "search_query_used": enhanced_q,
        "fallback_used":     fallback_used,
        "fallback_no_chunks": fallback_no_chunks,
        "error":             None,
    }

    _persist_turn(session, session_id, "assistant", "PLAYBOOK", None, result, summary)
    return result
';