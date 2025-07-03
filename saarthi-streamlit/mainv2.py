import streamlit as st

st.title("Saarthi - Your AI Assistant")

col1, col2 = st.columns(2)

with col1:
    st.subheader("Powered by Shubham and OpenAI")
    vote1 = st.button("Vote for Saarthi")

with col2:
    st.subheader("Welcome to Saarthi, your AI assistant for all your needs.")
    vote2 = st.button("Vote for CHATGPT")

if vote1:
    st.success("Thank you for voting for Saarthi! Your support is appreciated.")

if vote2:
    st.success("Thank you for voting for CHATGPT! Your support is appreciated.")


name = st.sidebar.text_input("Enter your name:")
tea = st.sidebar.selectbox("Select your favorite tea:", ["Masala Chai", "Green Tea", "Black Tea", "Lemon Tea"])


st.write(f"Hello, {name}! You selected {tea} as your favorite tea.")

with st.expander("More Information"):
    st.write("""
    1.ENTER THE NAME OF YOUR TASK \n
    2.SELECT THE DEADLINE FOR YOUR TASK \n
    3.SELECT THE PRIORITY OF YOUR TASK \n
    4.SELECT THE FIXED SCHEDULE FOR YOUR TASK
             
""")
    
st.markdown('### WELCOME TO SAARTHI, YOUR AI ASSISTANT FOR ALL YOUR NEEDS. ASK ME ANYTHING!')
st.markdown('> my own AI assistant')