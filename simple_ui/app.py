import streamlit as st
import requests
import os
from typing import List, Dict
import json
from datetime import datetime
import time

# Constants
BASE_URL = "http://localhost:8000/hermes-2-pro-tgi/gpu0"
VALID_TOKEN = os.getenv("VALID_TOKEN")

# Page config and styling
st.set_page_config(page_title="AI Text Generation", page_icon="🤖", layout="wide")

st.markdown("""
    <style>
    .stTextArea textarea { font-size: 16px; }
    .output-container {
        background-color: #f0f2f6;
        border-radius: 10px;
        padding: 20px;
        margin: 10px 0;
    }
    .header-container { margin-bottom: 20px; }
    .error-message {
        color: #ff4b4b;
        padding: 10px;
        border-radius: 5px;
        margin: 10px 0;
    }
    .success-message {
        color: #00cc00;
        padding: 10px;
        border-radius: 5px;
        margin: 10px 0;
    }
    </style>
""", unsafe_allow_html=True)

class TGIClient:
    def __init__(self, base_url: str, token: str):
        self.base_url = base_url
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
    
    def generate_response(self, messages: List[Dict[str, str]], max_tokens: int = 100) -> str:
        try:
            prompt = "<|system|>\nYou are a helpful AI assistant.\n<|end|>\n"
            for msg in messages[-4:]:
                prompt += f"<|{msg['role']}|>\n{msg['content']}\n<|end|>\n"
            prompt += "<|assistant|>\n"
            
            payload = {
                "inputs": prompt,
                "parameters": {
                    "max_new_tokens": max_tokens,
                    "stream": True
                }
            }
            
            message_placeholder = st.empty()
            full_response = ""
            start_time = time.time()
            
            with requests.post(
                f"{self.base_url}/generate", 
                headers=self.headers, 
                json=payload, 
                stream=True,
                timeout=30
            ) as response:
                response.raise_for_status()
                
                for line in response.iter_lines():
                    if line:
                        try:
                            json_response = json.loads(line)
                            if isinstance(json_response, list) and json_response:
                                chunk = json_response[0].get("generated_text", "")
                                chunk = (chunk.replace(prompt, "")
                                       .replace("<|assistant|>", "")
                                       .replace("<|end|>", "")
                                       .replace("<|system|>", "")
                                       .replace("<|user|>", ""))
                                
                                new_token = chunk[len(full_response):].strip()
                                if new_token:
                                    full_response += new_token + " "
                                    message_placeholder.markdown(full_response + "▌")
                                    
                                if time.time() - start_time > 60:
                                    raise TimeoutError("Response generation timed out")
                                    
                        except json.JSONDecodeError:
                            continue
                
                message_placeholder.markdown(full_response)
                return full_response
                
        except requests.exceptions.RequestException as e:
            error_msg = f"Network error: {str(e)}"
            st.error(error_msg)
            return error_msg
        except TimeoutError as e:
            error_msg = f"Timeout: {str(e)}"
            st.error(error_msg)
            return error_msg
        except Exception as e:
            error_msg = f"Error: {str(e)}"
            st.error(error_msg)
            return error_msg

def initialize_session_state():
    if "messages" not in st.session_state:
        st.session_state.messages = []
    if "client" not in st.session_state:
        st.session_state.client = TGIClient(BASE_URL, VALID_TOKEN)
    if "show_token" not in st.session_state:
        st.session_state.show_token = False
    if "generated_response" not in st.session_state:
        st.session_state.generated_response = None
    if "generation_time" not in st.session_state:
        st.session_state.generation_time = None

def display_generation():
    st.title("🤖 AI Text Generation Interface")
    
    # Input section
    prompt = st.text_area("Enter your prompt:", height=150, placeholder="Type your message here...")
    
    col1, col2 = st.columns(2)
    with col1:
        max_tokens = st.slider("Max tokens:", 10, 500, 100, key="max_tokens")
    with col2:
        temperature = st.slider("Temperature:", 0.1, 1.0, 0.7, key="temperature")
    
    if st.button("Generate", type="primary"):
        if not prompt or prompt.isspace():
            st.warning("Please enter a valid prompt.")
            return
            
        try:
            messages = [{"role": "user", "content": prompt.strip()}]
            st.session_state.generated_response = st.session_state.client.generate_response(messages, max_tokens)
            st.session_state.generation_time = datetime.now()
            
    # Display persistent output
    if st.session_state.generated_response:
        st.markdown("### Generated Response:")
        st.markdown(f"*Generated at: {st.session_state.generation_time.strftime('%Y-%m-%d %H:%M:%S')}*")
        st.markdown("---")
        st.markdown(st.session_state.generated_response)
        st.markdown("---")
        st.markdown(f"""
        **Generation Details:**
        - Tokens: {st.session_state.max_tokens}
        - Temperature: {st.session_state.temperature}
        - Time: {st.session_state.generation_time.strftime('%Y-%m-%d %H:%M:%S')}
        """)

def display_api_docs():
    st.title("📚 API Documentation")
    try:
        with open("API.md", "r") as f:
            content = f.read()
            st.markdown(content)
    except FileNotFoundError:
        st.error("API documentation file not found.")
        st.markdown("""
        ### Default API Documentation
        Please place your API.md file in the project directory.
        """)

def display_authentication():
    st.title("🔑 Authentication Settings")
    
    if VALID_TOKEN:
        st.write("Your API token is configured.")
        
        col1, col2 = st.columns([4, 1])
        with col1:
            if st.session_state.show_token:
                st.text_input("API Token", value=VALID_TOKEN, disabled=True)
            else:
                st.text_input("API Token", value="*" * 20, disabled=True)
        
        with col2:
            if st.button("👁️ Show/Hide"):
                st.session_state.show_token = not st.session_state.show_token
        
        st.info("Keep your API token secure and never share it with others.")
    else:
        st.error("No valid API token found in environment variables.")
        st.markdown("""
        Please set your API token in the environment variables:
        ```bash
        export VALID_TOKEN=your_token_here
        ```
        """)

def main():
    initialize_session_state()
    
    tab1, tab2, tab3 = st.tabs(["🤖 Generation", "📚 API Docs", "🔑 Authentication"])
    
    with tab1:
        display_generation()
    with tab2:
        display_api_docs()
    with tab3:
        display_authentication()

if __name__ == "__main__":
    main()