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

def main():
    initialize_session_state()
    
    st.title("🤖 AI Text Generation Interface")
    
    # Input section
    prompt = st.text_area("Enter your prompt:", height=150, placeholder="Type your message here...")
    
    col1, col2 = st.columns(2)
    with col1:
        max_tokens = st.slider("Max tokens:", 10, 500, 100)
    with col2:
        temperature = st.slider("Temperature:", 0.1, 1.0, 0.7)
    
    if st.button("Generate", type="primary"):
        if not prompt or prompt.isspace():
            st.warning("Please enter a valid prompt.")
            return
            
        st.markdown("### Generated Response:")
        st.markdown(f"*Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*")
        
        try:
            messages = [{"role": "user", "content": prompt.strip()}]
            response = st.session_state.client.generate_response(messages, max_tokens)
            
            if response and not response.startswith("Error"):
                st.markdown("---")
                st.markdown(response)
                st.markdown("---")
                st.markdown(f"""
                **Generation Details:**
                - Tokens: {max_tokens}
                - Temperature: {temperature}
                - Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
                """)
        except Exception as e:
            st.error(f"Generation error: {str(e)}")

if __name__ == "__main__":
    main()