import base64
import io
import json
import os
import re
import time
from pathlib import Path
from typing import Optional
from io import BytesIO

import requests
import streamlit as st
from PIL import Image

import logging


class RateLimit:
    def __init__(self):
        self.last_request = 0
        self.min_interval = 0.1
        self.reset()

    def can_make_request(self) -> bool:
        now = time.time()
        if now - self.last_request >= self.min_interval:
            self.last_request = now
            return True
        return False

    def reset(self):
        self.last_request = 0


class APIClient:
    def __init__(self, config):
        self.config = config
        self.session = requests.Session()
        self.base_url = "http://localhost:8000/hermes-2-pro-tgi/gpu0"
        
        # Setup logging
        self.logger = logging.getLogger('APIClient')
        self.logger.setLevel(logging.DEBUG)
        fh = logging.FileHandler('api_client.log')
        fh.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
        self.logger.addHandler(fh)

    def format_prompt(self, prompt: str, messages: list = None) -> str:
        """Format prompt with chat history"""
        system_msg = "<|system|>\nYou are a helpful assistant.<|end|>\n"
        if messages:
            chat_history = ""
            for msg in messages:
                role = "user" if msg["role"] == "user" else "assistant"
                chat_history += f"<|{role}|>\n{msg['content']}<|end|>\n"
            return f"{system_msg}{chat_history}<|user|>\n{prompt}<|end|>\n<|assistant|>"
        return f"{system_msg}<|user|>\n{prompt}<|end|>\n<|assistant|>"

    def make_stream_request(self, prompt: str, parameters: dict, messages: list = None):
        """Make streaming API request"""
        try:
            url = f"{self.base_url}/generate"
            
            payload = {
                "inputs": self.format_prompt(prompt, messages),
                "parameters": {**parameters, "stream": True}
            }
            
            self.logger.info(f"Making request to {url}")
            self.logger.debug(f"Payload: {json.dumps(payload, indent=2)}")
            
            response = self.session.post(
                url,
                headers={
                    "Authorization": f"Bearer {self.config.token}",
                    "Content-Type": "application/json",
                },
                json=payload,
                stream=True,
                timeout=30,
            )
            
            response.raise_for_status()
            return response
            
        except Exception as e:
            self.logger.error(f"Request failed: {str(e)}")
            raise


class HistoryManager:
    def __init__(self, output_dir: Path):
        self.history_file = output_dir / "chat_history.json"
        self.max_history_size = 50

    def load(self) -> list:
        if not self.history_file.exists():
            return []
        try:
            with open(self.history_file, "r") as f:
                return json.load(f)[-self.max_history_size :]
        except (json.JSONDecodeError, IOError):
            return []

    def save(self, history: list):
        temp_file = self.history_file.with_suffix(".tmp")
        try:
            with open(temp_file, "w") as f:
                json.dump(history[-self.max_history_size :], f)
            temp_file.rename(self.history_file)
        except Exception as e:
            if temp_file.exists():
                temp_file.unlink()
            raise e


class ChatConfig:
    def __init__(self):
        self.base_url = "http://localhost:8000"
        self.output_dir = Path("chat_history")
        self.output_dir.mkdir(exist_ok=True, mode=0o755)
        self.token = os.getenv("VALID_TOKEN")
        self.rate_limiter = RateLimit()
        self.api_client = APIClient(self)
        self.history_manager = HistoryManager(self.output_dir)
        self.rate_limiter.reset()
        if not self.token:
            raise ValueError("VALID_TOKEN environment variable not set")


def get_default_params() -> dict:
    return {
        "max_new_tokens": 150,
        "temperature": 0.7,
        "top_p": 0.95,
        "top_k": 50,
        "repetition_penalty": 1.1,
    }


def sanitize_input(text: str) -> str:
    """Sanitize user input to prevent injection attacks."""
    allowed_tags = ["<image>", "</image>", "<|im_start|>", "<|im_end|>"]
    for i, tag in enumerate(allowed_tags):
        text = text.replace(tag, f"SAFE_TAG_{i}")
    text = re.sub(r"<[^>]+>", "", text)
    for i, tag in enumerate(allowed_tags):
        text = text.replace(f"SAFE_TAG_{i}", tag)
    text = "".join(char for char in text if ord(char) >= 32 or char in "\n\r\t")

    return text.strip()


def validate_image(image: Image.Image) -> bool:
    """Validate image size and format."""
    try:
        max_size = 1024
        if image.width > max_size or image.height > max_size:
            return False
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG")
        if len(buffer.getvalue()) > 2 * 1024 * 1024:
            return False
        if image.mode not in ("RGB", "RGBA"):
            return False

        return True
    except Exception:
        return False


def main():
    st.set_page_config(
        page_title="TGI Chat Interface",
        page_icon="🤖",
        layout="wide",
    )

    # Initialize session state for messages
    if "messages" not in st.session_state:
        st.session_state.messages = []

    st.title("TGI Chat Demo")

    # Create tabs
    tab1, tab2, tab3 = st.tabs(["💬 Chat", "📚 API Documentation", "🔑 Authentication"])

    with tab1:
        # Chat interface
        col1, col2 = st.columns([5, 1])
        
        # Display chat history
        for message in st.session_state.messages:
            with st.chat_message(message["role"]):
                if "image" in message:
                    st.image(message["image"])
                st.write(message["content"])

        # Chat input area
        with st.container():
            # Create two columns - one for text input, one for image upload
            input_col, upload_col, send_col = st.columns([4, 1, 1])
            
            with input_col:
                user_input = st.text_input("Type your message here...", key="user_input")
            
            with upload_col:
                uploaded_file = st.file_uploader("Upload Image", type=['png', 'jpg', 'jpeg'], key="uploader")
            
            with send_col:
                send_button = st.button("Send")

            if send_button and (user_input or uploaded_file):
                if not config.token:
                    st.error("Please configure your token first!")
                    st.stop()

                # Process uploaded image if any
                image_data = None
                if uploaded_file:
                    image = Image.open(uploaded_file)
                    if validate_image(image):
                        buffered = BytesIO()
                        image.save(buffered, format="JPEG")
                        image_data = base64.b64encode(buffered.getvalue()).decode()
                        # Add image to message
                        st.chat_message("user").image(uploaded_file)
                
                # Add user message to chat
                message_content = user_input if user_input else "Image uploaded"
                st.chat_message("user").write(message_content)
                
                new_message = {"role": "user", "content": message_content}
                if image_data:
                    new_message["image"] = image_data
                st.session_state.messages.append(new_message)

                # Generate assistant response
                with st.chat_message("assistant"):
                    message_placeholder = st.empty()
                    try:
                        response = config.api_client.make_stream_request(
                            user_input,
                            get_default_params(),
                            messages=st.session_state.messages[:-1]
                        )
                        
                        full_response = ""
                        for line in response.iter_lines():
                            if line:
                                try:
                                    data = json.loads(line.decode('utf-8'))
                                    if "generated_text" in data:
                                        full_response = data["generated_text"]
                                    elif "token" in data and "text" in data["token"]:
                                        full_response += data["token"]["text"]
                                    message_placeholder.markdown(full_response + "▌")
                                except json.JSONDecodeError:
                                    continue
                        
                        message_placeholder.markdown(full_response)
                        st.session_state.messages.append({"role": "assistant", "content": full_response})
                    
                    except Exception as e:
                        st.error(f"Error: {str(e)}")

                # Clear inputs after sending
                st.session_state.user_input = ""
                st.session_state.uploader = None

        # Sidebar for parameters
        with st.sidebar:
            if st.button("Clear Chat"):
                st.session_state.messages = []
            
            st.header("Generation Parameters")
            params = get_default_params()
            params["temperature"] = st.slider("Temperature", 0.0, 1.0, 0.7)
            params["max_new_tokens"] = st.slider("Max New Tokens", 1, 500, 150)
            params["top_p"] = st.slider("Top P", 0.0, 1.0, 0.95)
            params["top_k"] = st.slider("Top K", 1, 100, 50)
            params["repetition_penalty"] = st.slider("Repetition Penalty", 1.0, 2.0, 1.1)

    with tab2:
        st.header("API Documentation")
        try:
            with open("API.md", "r") as f:
                st.markdown(f.read())
        except FileNotFoundError:
            st.warning("API documentation file (API.md) not found.")

    with tab3:
        st.header("Authentication")
        new_token = st.text_input("Enter API Token", type="password", value=config.token or "")
        if st.button("Save Token"):
            config.token = new_token
            st.success("Token saved successfully!")

    # Debug logs at the bottom
    with st.expander("Debug Logs", expanded=False):
        if 'logs' in st.session_state:
            st.code('\n'.join(st.session_state.logs))


if __name__ == "__main__":
    config = ChatConfig()
    main()
