import streamlit as st
import requests
import os
from typing import List, Dict
import json

# Constants
BASE_URL = "http://localhost:8000/hermes-2-pro-tgi/gpu0"
VALID_TOKEN = os.getenv("VALID_TOKEN")

class TGIClient:
    def __init__(self, base_url: str, token: str):
        self.base_url = base_url
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
    
    def generate_response(self, messages: List[Dict[str, str]], max_tokens: int = 100) -> str:
        # Format the conversation history
        prompt = ""
        for msg in messages:
            role = msg["role"]
            content = msg["content"]
            prompt += f"<|{role}|>\n{content}<|end|>\n"
            
        payload = {
            "inputs": prompt,
            "parameters": {
                "max_new_tokens": max_tokens
            }
        }
        
        try:
            response = requests.post(f"{self.base_url}/generate", headers=self.headers, json=payload)
            response.raise_for_status()
            return response.json().get("generated_text", "No response text available")
        except Exception as e:
            return f"Error: {str(e)}"

def initialize_session_state():
    if "messages" not in st.session_state:
        st.session_state.messages = []
    if "client" not in st.session_state:
        st.session_state.client = TGIClient(BASE_URL, VALID_TOKEN)

def display_chat():
    st.title("Chat Interface")
    
    # Display chat messages
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.write(message["content"])
    
    # Chat input
    if prompt := st.chat_input("What would you like to know?"):
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.write(prompt)
            
        # Get bot response
        with st.chat_message("assistant"):
            response = st.session_state.client.generate_response(st.session_state.messages)
            st.write(response)
            st.session_state.messages.append({"role": "assistant", "content": response})

def display_api_docs():
    st.title("API Documentation")
    try:
        with open("API.md", "r") as f:
            content = f.read()
            st.markdown(content)
    except FileNotFoundError:
        st.error("API.md file not found in the current directory.")

def display_authentication():
    st.title("Authentication")
    if VALID_TOKEN:
        st.write("Your API token is:")
        col1, col2 = st.columns([3, 1])
        with col1:
            token_placeholder = st.empty()
            if "show_token" not in st.session_state:
                st.session_state.show_token = False
            
            if st.session_state.show_token:
                token_placeholder.text_input("Token", value=VALID_TOKEN, disabled=True)
            else:
                token_placeholder.text_input("Token", value="*" * 20, disabled=True)
        
        with col2:
            if st.button("Show/Hide"):
                st.session_state.show_token = not st.session_state.show_token
            
        st.button("Copy Token", on_click=lambda: st.write(f'<script>navigator.clipboard.writeText("{VALID_TOKEN}");</script>', unsafe_allow_html=True))
    else:
        st.error("No valid token found in environment variables.")

def main():
    initialize_session_state()
    
    tab1, tab2, tab3 = st.tabs(["Chat", "API Docs", "Authentication"])
    
    with tab1:
        display_chat()
    with tab2:
        display_api_docs()
    with tab3:
        display_authentication()

if __name__ == "__main__":
    main()