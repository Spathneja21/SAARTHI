import streamlit as st

st.title("Saarthi - Your AI Assistant")

if st.button("Deploy your AI"):
    st.success("Your AI will be running shortly...")

add_table = st.checkbox("ADD YOUR TABLE")

if add_table:
    st.write("Table has been added.")

fixed_schedule = st.radio("Select you fixed schedule:",["SLEEPTIME","WORKING TIME","PLAY TIME"])

st.write(f"You selected: {fixed_schedule}. Good choice!")

complexity = st.slider("Select the priority of your task:", 1, 5, 3)

st.write(f"Your task priority is set to: {complexity}.")

priority = st.number_input("priority of your task:", min_value=1, max_value=5, step=1)

task_name = st.text_input("Enter the name of your task:")
if task_name:
    st.write(f"Your task name is: {task_name}.")

deadline = st.date_input("Select the deadline for your task:")