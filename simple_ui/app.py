import streamlit as st
import httpx
import asyncio
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
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;600&display=swap');
    
    .main {
        font-family: 'Inter', sans-serif;
    }
    
    .stTextArea textarea {
        font-family: 'Inter', sans-serif;
        font-size: 16px;
        border-radius: 10px;
        border: 2px solid #e0e0e0;
    }
    
    .output-container {
        background-color: #f8f9fa;
        border-radius: 12px;
        padding: 24px;
        margin: 16px 0;
        border: 1px solid #e9ecef;
        box-shadow: 0 2px 4px rgba(0,0,0,0.05);
    }
    
    .chat-message {
        padding: 16px;
        margin: 8px 0;
        border-radius: 8px;
        line-height: 1.5;
    }
    
    .user-message {
        background-color: #e3f2fd;
        margin-left: 20%;
    }
    
    .assistant-message {
        background-color: #f5f5f5;
        margin-right: 20%;
    }
    
    /* Add more custom styles... */
    </style>
""", unsafe_allow_html=True)

class TGIClient:
    def __init__(self, base_url: str, token: str):
        self.base_url = base_url
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
    
    async def generate_response(self, messages: List[Dict[str, str]], max_tokens: int = 100):
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
        
        async with httpx.AsyncClient() as client:
            async with client.stream(
                'POST',
                f"{self.base_url}/generate",
                headers=self.headers,
                json=payload,
                timeout=60
            ) as response:
                response.raise_for_status()
                full_response = ""
                
                async for chunk in response.aiter_bytes():
                    if chunk:
                        try:
                            chunk_str = chunk.decode()
                            for line in chunk_str.split('\n'):
                                if line.strip():
                                    json_response = json.loads(line)
                                    if isinstance(json_response, list) and json_response:
                                        text = json_response[0].get("generated_text", "")
                                        new_content = text[len(prompt):].strip()
                                        if new_content != full_response:
                                            delta = new_content[len(full_response):]
                                            full_response = new_content
                                            yield delta
                        except json.JSONDecodeError:
                            continue

def initialize_session_state():
    if "messages" not in st.session_state:
        st.session_state.messages = []
    if "base_url" not in st.session_state:
        st.session_state.base_url = ""  # Empty by default
    if "api_token" not in st.session_state:
        st.session_state.api_token = ""
    if "chat_history" not in st.session_state:
        st.session_state.chat_history = []
    if "show_token" not in st.session_state:
        st.session_state.show_token = False
    if "generated_response" not in st.session_state:
        st.session_state.generated_response = None
    if "generation_time" not in st.session_state:
        st.session_state.generation_time = None
    if "is_configured" not in st.session_state:
        st.session_state.is_configured = False
    if "client" not in st.session_state:
        st.session_state.client = None

async def test_connection(client: TGIClient) -> bool:
    try:
        # Test with a minimal prompt
        test_messages = [{"role": "user", "content": "Hi"}]
        await client.generate_response(test_messages, max_tokens=10)
        return True
    except httpx.HTTPStatusError as e:
        st.error(f"HTTP Error: {e.response.status_code} - {e.response.url}")
        return False
    except httpx.RequestError as e:
        st.error(f"Connection Error: {str(e)}")
        return False
    except Exception as e:
        st.error(f"Connection test failed: {str(e)}")
        return False

def display_generation():
    st.title("🤖 AI Text Generation Interface")
    
    # Display chat history using Streamlit's chat interface
    for message in st.session_state.chat_history:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])
    
    # Chat input
    if prompt := st.chat_input("Enter your message..."):
        # Display user message
        with st.chat_message("user"):
            st.markdown(prompt)
        st.session_state.chat_history.append({"role": "user", "content": prompt})
        
        # Display assistant response with streaming
        with st.chat_message("assistant"):
            try:
                stream = st.session_state.client.generate_response(
                    st.session_state.chat_history,
                    max_tokens=100
                )
                response = st.write_stream(stream)
                st.session_state.chat_history.append({
                    "role": "assistant",
                    "content": response
                })
            except Exception as e:
                st.error(f"Generation error: {str(e)}")

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

def display_configuration():
    st.title("⚙️ Configuration Settings")
    
    # Current configuration display
    st.markdown("### Current Configuration")
    current_config = {
        "Base URL": st.session_state.base_url,
        "API Token": "•" * 12 if st.session_state.api_token else "Not set"
    }
    
    for key, value in current_config.items():
        st.info(f"**{key}:** {value}")
    
    st.markdown("---")
    st.markdown("### Update Configuration")
    
    # URL input
    new_base_url = st.text_input(
        "Base URL:",
        value=st.session_state.base_url,
        placeholder="http://localhost:8000/your-model/gpu0"
    )
    
    # Token input with show/hide functionality
    col1, col2 = st.columns([4, 1])
    with col1:
        new_token = st.text_input(
            "API Token:",
            value=st.session_state.api_token,
            type="password" if not st.session_state.show_token else "default",
            placeholder="Enter your API token"
        )
    if st.button("Test and Save Configuration", type="primary"):
        if not new_base_url or not new_token:
            st.error("Please provide both Base URL and API Token.")
            return
            
        client = TGIClient(new_base_url, new_token)
        
        with st.spinner("Testing connection..."):
            if asyncio.run(test_connection(client)):
                st.session_state.base_url = new_base_url
                st.session_state.api_token = new_token
                st.session_state.client = client
                st.success("✅ Connection tested and configuration saved successfully!")
            else:
                st.error("❌ Connection test failed. Please check your settings and try again.")

def main():
    initialize_session_state()
    
    # If not configured, show only the configuration screen
    if not st.session_state.is_configured:
        st.title("🔑 Initial Setup")
        st.markdown("Please configure your API connection to continue.")
        
        new_base_url = st.text_input(
            "Base URL:",
            value=st.session_state.base_url,
            placeholder="http://localhost:8000/your-model/gpu0"
        )
        
        new_token = st.text_input(
            "API Token:",
            value=st.session_state.api_token,
            type="password" if not st.session_state.show_token else "default",
            placeholder="Enter your API token"
        )
        

        if st.button("Connect", type="primary"):
            if not new_base_url or not new_token:
                st.error("Please provide both Base URL and API Token.")
                return
                
            client = TGIClient(new_base_url, new_token)
            
            with st.spinner("Testing connection..."):
                if asyncio.run(test_connection(client)):
                    st.session_state.base_url = new_base_url
                    st.session_state.api_token = new_token
                    st.session_state.client = client
                    st.session_state.is_configured = True
                    st.success("✅ Connection successful! Redirecting to main interface...")
                    time.sleep(1)  # Give user time to see the success message
                    st.rerun()
        
        return
    
    # If configured, show the main UI with tabs
    tab1, tab2, tab3 = st.tabs(["🤖 Generation", "📚 API Docs", "⚙️ Configuration"])
    
    with tab1:
        display_generation()
    with tab2:
        display_api_docs()
    with tab3:
        display_configuration()

if __name__ == "__main__":
    main()