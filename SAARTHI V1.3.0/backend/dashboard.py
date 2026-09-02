import json
from datetime import date, datetime

import pandas as pd
import plotly.express as px
import requests
import streamlit as st

from core.tz import now as ist_now

DAY_ORDER = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]


def load_fixed(path="saarthi/fixed_tasks.json"):
    with open(path) as f:
        return json.load(f)


def fixed_for_date(fixed, day):
    """Weekly fixed classes -> concrete naive datetimes on `day` (a date)."""
    name = day.strftime("%A")
    return [
        {
            "title": f["Task"],
            "start": datetime.combine(day, datetime.strptime(f["Start"], "%H:%M").time()),
            "end": datetime.combine(day, datetime.strptime(f["End"], "%H:%M").time()),
            "source": "Fixed class",
        }
        for f in fixed
        if f["Day"] == name
    ]


def slots_to_local(slots, tz):
    """API slots (UTC ISO) -> naive datetimes in `tz`, so they align with fixed classes."""
    out = []
    for s in slots:
        start = pd.Timestamp(s["start"]).tz_convert(tz).tz_localize(None)
        end = pd.Timestamp(s["end"]).tz_convert(tz).tz_localize(None)
        out.append({
            "title": s["title"],
            "start": start.to_pydatetime(),
            "end": end.to_pydatetime(),
            "source": "Scheduled task",
        })
    return out


st.title("AURA")

# ── Sidebar: connection + auth (shared by every tab) ───────────────────────────
API = st.sidebar.text_input("API base URL", "http://localhost:8000")
TZ = st.sidebar.text_input("Display timezone", "Asia/Kolkata")

if "token" not in st.session_state:
    st.session_state.token = None

if st.session_state.token:
    if st.sidebar.button("Log out"):
        st.session_state.token = None
        st.rerun()
else:
    with st.sidebar.form("login"):
        email = st.text_input("Email")
        password = st.text_input("Password", type="password")
        if st.form_submit_button("Log in"):
            r = requests.post(f"{API}/login", json={"email": email, "password": password})
            if r.ok:
                st.session_state.token = r.json()["access_token"]
                st.rerun()
            else:
                st.error(r.json().get("detail", "Login failed"))

headers = {"Authorization": f"Bearer {st.session_state.token}"} if st.session_state.token else None

tab_merged, tab_schedule, tab_timetable = st.tabs(
    ["Merged Timetable", "Daily Schedule", "Fixed Timetable"]
)

# ── Merged: fixed classes + AI-scheduled tasks on one timeline ─────────────────
with tab_merged:
    if not headers:
        st.info("Log in from the sidebar to see scheduled tasks alongside fixed classes.")
    else:
        day = st.date_input("Date", date.today(), key="merged_date")

        r = requests.get(f"{API}/schedule/day", params={"date": day.isoformat()}, headers=headers)
        if not r.ok:
            st.error(r.json().get("detail", "Failed to load schedule"))
        else:
            rows = fixed_for_date(load_fixed(), day) + slots_to_local(r.json()["booked_slots"], TZ)

            if not rows:
                st.info("Nothing fixed or scheduled for this day.")
            else:
                mdf = pd.DataFrame(rows).sort_values("start")
                fig = px.timeline(
                    mdf, x_start="start", x_end="end", y="title", color="source",
                    color_discrete_map={"Fixed class": "#7f8fa6", "Scheduled task": "#e1701a"},
                )
                fig.update_yaxes(autorange="reversed")
                fig.update_xaxes(tickformat="%H:%M")
                st.plotly_chart(fig, use_container_width=True)

                mdf["start"] = mdf["start"].dt.strftime("%H:%M")
                mdf["end"] = mdf["end"].dt.strftime("%H:%M")
                st.dataframe(mdf, use_container_width=True)

# ── Fixed timetable: the recurring weekly grid ─────────────────────────────────
with tab_timetable:
    df = pd.DataFrame(load_fixed())
    df["Day"] = pd.Categorical(df["Day"], categories=DAY_ORDER, ordered=True)
    df["Course"] = df["Task"].str.split(" - ").str[0]

    # dummy common date so start/end times share one time axis
    base = date(2000, 1, 3)  # a Monday
    df["start"] = pd.to_datetime(str(base) + " " + df["Start"])
    df["end"] = pd.to_datetime(str(base) + " " + df["End"])

    fig = px.timeline(
        df.sort_values("Day"), x_start="start", x_end="end", y="Day",
        color="Course", text="Task", category_orders={"Day": DAY_ORDER},
    )
    fig.update_yaxes(autorange="reversed")
    fig.update_xaxes(tickformat="%H:%M")
    fig.update_traces(textposition="inside")
    st.plotly_chart(fig, use_container_width=True)
    st.dataframe(df[["Day", "Start", "End", "Task"]], use_container_width=True)

# ── Daily schedule: AI-booked slots, add task, run scheduler ───────────────────
with tab_schedule:
    if not headers:
        st.info("Log in from the sidebar to view and create tasks.")
    else:
        with st.expander("Add task"):
            # Outside the form on purpose: widgets inside st.form don't rerun the
            # script until submit, so `disabled=` would read a stale value and the
            # deadline fields could never be enabled before the first submit.
            has_deadline = st.checkbox("Has deadline")

            with st.form("add_task", clear_on_submit=True):
                title = st.text_input("Title")
                category = st.selectbox(
                    "Category",
                    ["deep_work", "admin", "learning", "meeting", "personal", "health"],
                )
                energy = st.selectbox(
                    "Energy required", ["very_low", "low", "medium", "high", "peak"]
                )
                duration = st.number_input("Estimated duration (minutes)", min_value=5, value=60, step=5)
                priority = st.slider("Priority", 1, 10, 5)
                deadline_date = st.date_input("Deadline date", date.today(), disabled=not has_deadline)
                deadline_time = st.time_input("Deadline time", ist_now().time(), disabled=not has_deadline)

                if st.form_submit_button("Create task"):
                    params = {
                        "title": title,
                        "category": category,
                        "energy_requirement": energy,
                        "estimated_duration": int(duration),
                        "priority": priority,
                    }
                    if has_deadline:
                        params["deadline"] = datetime.combine(deadline_date, deadline_time).isoformat()

                    r = requests.post(f"{API}/tasks", params=params, headers=headers)
                    if r.ok:
                        st.success(f"Created task '{r.json()['title']}'")
                    else:
                        st.error(r.json().get("detail", "Failed to create task"))

        col_run, col_clear = st.columns(2)

        with col_run:
            if st.button("Run scheduler (allocate pending tasks)"):
                r = requests.post(f"{API}/schedule/cpsat", headers=headers)
                if r.ok:
                    st.success(f"Scheduled {len(r.json().get('scheduled', []))} chunk(s)")
                else:
                    st.error(r.json().get("detail", "Scheduling failed"))

        with col_clear:
            # Clears the schedule only — the tasks stay, so this is one click
            # away from being undone by re-running the scheduler.
            if st.button("Clear schedule", type="secondary"):
                r = requests.delete(f"{API}/schedule/slots", headers=headers)
                if r.ok:
                    st.success(f"Deleted {r.json()['deleted']} slot(s)")
                    st.rerun()
                else:
                    st.error(r.json().get("detail", "Failed to clear schedule"))

        day = st.date_input("Date", date.today(), key="schedule_date")

        r = requests.get(f"{API}/schedule/day", params={"date": day.isoformat()}, headers=headers)
        if not r.ok:
            st.error(r.json().get("detail", "Failed to load schedule"))
        else:
            data = r.json()
            slots = data["booked_slots"]
            gaps = data["free_gaps"]

            st.metric("Total booked", f"{data['total_booked_minutes']} min")

            if slots:
                sdf = pd.DataFrame(slots)
                sdf["start"] = pd.to_datetime(sdf["start"])
                sdf["end"] = pd.to_datetime(sdf["end"])

                # Readable hover fields: raw ISO strings and bare ints are
                # unreadable in a tooltip. Deadline is nullable.
                sdf["estimated"] = sdf["estimated_duration"].astype(str) + " min"
                sdf["booked"] = (
                    (sdf["end"] - sdf["start"]).dt.total_seconds() // 60
                ).astype(int).astype(str) + " min"
                deadline = pd.to_datetime(sdf["deadline"], errors="coerce")
                sdf["due"] = deadline.dt.strftime("%d %b %H:%M").fillna("no deadline")

                fig = px.timeline(
                    sdf, x_start="start", x_end="end", y="title",
                    color="category",
                    hover_data=["estimated", "booked", "due", "priority",
                                "status", "created_by", "slot_id"],
                )
                fig.update_yaxes(autorange="reversed")
                st.plotly_chart(fig, use_container_width=True)
                st.dataframe(sdf, use_container_width=True)
            else:
                st.info("No booked slots for this day.")

            if gaps:
                st.subheader("Free gaps")
                st.dataframe(pd.DataFrame(gaps), use_container_width=True)
