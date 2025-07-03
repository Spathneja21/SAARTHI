import streamlit as st
st.title("Saarthi - Your AI Assistant")
st.subheader("Powered by Shubham and OpenAI")
st.text("Welcome to Saarthi, your AI assistant for all your needs. Ask me anything!")
st.write("This is my own Ai assistant")

chai = st.selectbox("Your trusted AI:", ["Saarthi", "ChatGPT", "Bard", "Claude"])
st.write(f"You selected: {chai}. Good choice!")

st.success("Saarthi app is running successfully!")