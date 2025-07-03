import streamlit as st
import pandas as pd
import plotly.express as px
from datetime import datetime

st.title("🧠 Saarthi - Weekly Timetable Grid")

uploaded_file = st.file_uploader("Upload your fixed_tasks.csv", type=["csv"])
if uploaded_file:
    df = pd.read_csv(uploaded_file)

    # Format correction
    df["Start_dt"] = pd.to_datetime("2025-01-01 " + df["Start"], format="%Y-%m-%d %H:%M")
    df["End_dt"] = pd.to_datetime("2025-01-01 " + df["End"], format="%Y-%m-%d %H:%M")

    # Ensure proper weekday order
    weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    df["Day"] = pd.Categorical(df["Day"], categories=weekdays, ordered=True)

    # Create timeline
    fig = px.timeline(
        df,
        x_start="Start_dt",
        x_end="End_dt",
        y="Day",
        color="Task",
        title="📅 Weekly Academic Schedule",
        hover_name="Task",
        hover_data={"Start": True, "End": True}
    )

    fig.update_yaxes(categoryorder="array", categoryarray=weekdays)
    fig.update_layout(
        xaxis_title="Time",
        yaxis_title="Day",
        xaxis=dict(
            tickformat="%H:%M",
            range=[
                datetime.strptime("08:00", "%H:%M"),
                datetime.strptime("18:00", "%H:%M")
            ]
        ),
        height=600
    )

    st.plotly_chart(fig, use_container_width=True)
