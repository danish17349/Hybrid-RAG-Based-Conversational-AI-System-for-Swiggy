###################### App title "Swiggy Bot"
###################### Python Environment - "Run on Warehouse" and select App Warehouse as "Streamlit_Warehouse"



import streamlit as st
import json
import uuid
import pandas as pd
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Swiggy Bot", page_icon="🍊", layout="wide")

session = get_active_session()

# ── Session state ─────────────────────────────────────────────────────────────
if "session_id"     not in st.session_state:
    st.session_state.session_id    = str(uuid.uuid4())
if "messages"       not in st.session_state:
    st.session_state.messages      = []
if "sp_history"     not in st.session_state:
    st.session_state.sp_history    = []

# ── SP call ───────────────────────────────────────────────────────────────────
def call_gateway(message: str) -> dict:
    try:
        rows = session.sql(
            "CALL SWIGGY_MASTER.DEV.SP_GATEWAY(?, ?, ?)",
            params=[
                st.session_state.session_id,
                json.dumps(st.session_state.sp_history),
                message,
            ],
        ).collect()
        result = rows[0][0]
        if isinstance(result, str):
            result = json.loads(result)
        if not result:
            return {"error": "Empty response", "intent": "ANALYST", "response": {"status": "error", "error": "Empty response"}}

        gw_meta = result.get("_gateway", {})
        intent = gw_meta.get("classified_intent", "ANALYST")
        confidence = gw_meta.get("confidence", 0.5)
        method = gw_meta.get("method", "")
        cross_fallback = gw_meta.get("cross_fallback_used", False)

        response = {k: v for k, v in result.items() if k != "_gateway"}

        return {
            "intent": intent,
            "intent_confidence": confidence,
            "intent_method": method,
            "cross_fallback_used": cross_fallback,
            "response": response,
        }
    except Exception as e:
        return {"error": str(e), "intent": "ANALYST", "response": {"status": "error", "error": str(e)}}

def push_history(message: str, gw: dict):
    intent = gw.get("intent", "ANALYST")
    resp   = gw.get("response", {})
    st.session_state.sp_history.append({
        "role":    "user",
        "intent":  intent,
        "message": message,
        "summary": "",
    })
    if intent == "ANALYST":
        st.session_state.sp_history.append({
            "role":    "assistant",
            "intent":  "ANALYST",
            "message": None,
            "sql":     resp.get("sql", ""),
            "summary": (resp.get("narrative") or "")[:300],
        })
    else:
        st.session_state.sp_history.append({
            "role":    "assistant",
            "intent":  "PLAYBOOK",
            "message": None,
            "summary": (resp.get("answer") or "")[:300],
        })
    if len(st.session_state.sp_history) > 12:
        st.session_state.sp_history = st.session_state.sp_history[-12:]

# ── Rendering helpers ─────────────────────────────────────────────────────────
def badge(intent: str, method: str, conf: float) -> str:
    bg  = "#FF5722" if intent == "ANALYST" else "#2E7D32"
    ico = "📊" if intent == "ANALYST" else "📖"
    return (
        f'<span style="background:{bg};color:#fff;padding:3px 10px;'
        f'border-radius:12px;font-size:12px;font-weight:600">'
        f'{ico} {intent} &nbsp;·&nbsp; {round(conf*100)}% {method}</span>'
    )


def render_analyst(resp: dict):
    narrative = resp.get("narrative", "")
    results   = resp.get("results",   [])
    sql       = resp.get("sql",        "")
    row_count = resp.get("row_count",  0)
    fallback  = resp.get("fallback_used", False)

    if narrative:
        st.markdown(narrative)

    if results:
        df = pd.DataFrame(results)
        for col in df.columns:
            try:
                df[col] = df[col].apply(lambda x: round(float(x), 2) if isinstance(x, float) else x)
            except Exception:
                pass
        st.dataframe(df, use_container_width=True, hide_index=True)
        st.caption(f"{row_count} row(s) returned" + (" · SQL was regenerated on retry" if fallback else ""))

    if sql:
        with st.expander("🔍 View generated SQL"):
            st.code(sql, language="sql")


def render_playbook(resp: dict):
    answer    = resp.get("answer",    "")
    campaigns = resp.get("campaigns", [])
    coupons   = resp.get("coupons",   [])
    priority  = resp.get("priority",  "")
    citations = resp.get("citations", [])
    fallback  = resp.get("fallback_used", False)

    if answer:
        st.markdown(answer)

    if any([campaigns, coupons, priority]):
        st.markdown("---")
        tags = []

        for c in campaigns:
            tags.append(
                f'<span style="background:#E64A19;color:#fff;padding:5px 14px;'
                f'border-radius:20px;font-size:13px;font-weight:600;margin-right:6px;'
                f'display:inline-block;margin-bottom:6px">📢 {c}</span>'
            )
        for c in coupons:
            tags.append(
                f'<span style="background:#1565C0;color:#fff;padding:5px 14px;'
                f'border-radius:20px;font-size:13px;font-weight:600;margin-right:6px;'
                f'display:inline-block;margin-bottom:6px">🎟 {c}</span>'
            )
        if priority:
            p_colors = {"URGENT": "#B71C1C", "HIGH": "#E65100",
                        "MEDIUM": "#F57F17", "LOW": "#2E7D32"}
            bg = p_colors.get(priority, "#546E7A")
            tags.append(
                f'<span style="background:{bg};color:#fff;padding:5px 14px;'
                f'border-radius:20px;font-size:13px;font-weight:600;margin-right:6px;'
                f'display:inline-block;margin-bottom:6px">⚡ {priority}</span>'
            )

        st.markdown("".join(tags), unsafe_allow_html=True)
        st.markdown("")

    if citations:
        with st.expander(f"📚 Playbook sources ({len(citations)})"):
            for i, c in enumerate(citations, 1):
                full_path = c.get("full_path", c.get("chapter_title", ""))
                chunk     = c.get("chunk_text_raw", "")
                ctype     = c.get("chunk_type", "")
                camp      = c.get("campaign_id_ref", "")
                coupon    = c.get("coupon_id_ref", "")
                priority_c= c.get("priority_level", "")

                st.markdown(f"**Source {i}** — `{full_path}`")
                meta = "  ·  ".join(filter(None, [
                    f"Campaign: `{camp}`"   if camp      else "",
                    f"Coupon: `{coupon}`"   if coupon    else "",
                    f"Priority: `{priority_c}`" if priority_c else "",
                ]))
                if meta:
                    st.caption(meta)
                if ctype == "SQL_SNIPPET":
                    st.code(chunk, language="sql")
                else:
                    st.markdown(f"> {chunk}")
                if i < len(citations):
                    st.divider()

    if fallback:
        st.caption("⚠️ Based on general knowledge — not found in playbook")

def render_error(resp: dict, cross: bool = False):
    msg = "Both ANALYST and PLAYBOOK paths failed. " if cross else ""
    st.error(
        f"{msg}Could not generate a response. Try rephrasing — "
        f"use *show me / how many / compare* for data, "
        f"or *which campaign / what coupon / how should I* for strategy."
    )
    err = resp.get("error", "")
    if err:
        with st.expander("Technical detail"):
            st.code(str(err))


def render_assistant_bubble(msg: dict):
    intent = msg.get("intent",     "ANALYST")
    method = msg.get("method",     "")
    conf   = float(msg.get("confidence", 0.5))
    resp   = msg.get("response",   {})
    cross  = msg.get("cross_fallback", False)

    st.markdown(badge(intent, method, conf), unsafe_allow_html=True)
    st.markdown("")

    if cross:
        st.warning("Primary path failed — answer from fallback handler.")

    status = resp.get("status", "error")
    if status != "success":
        render_error(resp, cross)
    elif intent == "ANALYST":
        render_analyst(resp)
    else:
        render_playbook(resp)

# ── Sidebar ───────────────────────────────────────────────────────────────────
with st.sidebar:
    st.markdown("## 🍊 Swiggy Bot")
    st.caption("Marketing data + campaign strategy, one chat.")
    st.divider()

    st.markdown("**📊 Data questions**")
    st.markdown("- Show me revenue by city this month")
    st.markdown("- Top 5 restaurants by orders in Bangalore")
    st.markdown("- Average delivery time and rating by city")
    st.markdown("- Coupon vs non-coupon revenue breakdown")

    st.divider()

    st.markdown("**📖 Strategy questions**")
    st.markdown("- Which campaign for churned users?")
    st.markdown("- What do I do when it's raining?")
    st.markdown("- Best coupon for new users with 0 orders?")
    st.markdown("- Strategy for a new city launch")

    st.divider()

    if st.button("🗑️ Clear conversation", use_container_width=True):
        st.session_state.messages   = []
        st.session_state.sp_history = []
        st.session_state.session_id = str(uuid.uuid4())
        st.rerun()

    st.caption(f"Session `{st.session_state.session_id[:8]}…`")

# ── Header ────────────────────────────────────────────────────────────────────
st.markdown("## Swiggy Marketing Assistant")
st.markdown(
    "Ask about **data** (📊 analytics, trends, revenue) "
    "or **campaign strategy** (📖 playbook, recommendations, coupons). "
    "I'll route your question automatically."
)
st.divider()

# ── Chat history ──────────────────────────────────────────────────────────────
for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        if msg["role"] == "user":
            st.markdown(msg["content"])
        else:
            render_assistant_bubble(msg)

# ── Chat input ────────────────────────────────────────────────────────────────
if prompt := st.chat_input("Ask about Swiggy data or marketing strategy…"):

    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        with st.spinner("Thinking…"):
            gw = call_gateway(prompt)

        intent = gw.get("intent",            "ANALYST")
        conf   = float(gw.get("intent_confidence", 0.5))
        method = gw.get("intent_method",     "")
        resp   = gw.get("response",          {})
        cross  = gw.get("cross_fallback_used", False)

        bubble = {
            "role":           "assistant",
            "intent":         intent,
            "confidence":     conf,
            "method":         method,
            "response":       resp,
            "cross_fallback": cross,
        }
        render_assistant_bubble(bubble)

    push_history(prompt, gw)
    st.session_state.messages.append(bubble)
