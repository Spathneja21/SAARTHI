import streamlit as st
import pandas as pd

st.title("Saarthi - Your AI Assistant")

file = st.file_uploader("final.csv", type=["csv"])
if file:
    df = pd.read_csv(file)
    st.subheader("Data Preview")
    st.dataframe(df)
    # st.write(df.describe())

if file:
    day = df["Day"].unique()
    selected_task = st.selectbox("Select a task:", day)
    filtered_df = df[df["Day"] == selected_task]
    st.dataframe(filtered_df)