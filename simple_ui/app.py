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
        
        # Get model configuration from environment
        self.model_name = os.getenv("MODEL_NAME", "unknown-model")
        self.model_type = os.getenv("MODEL_TYPE", "TGI_LLM")  # Default to LLM if not specified
        
        # Get model limits from environment
        self.max_context_length = int(os.getenv("MAX_TOTAL_TOKENS", "1024"))
        self.max_input_length = int(os.getenv("MAX_INPUT_LENGTH", "512"))
        self.gpu_id = 0 #  default

        # Add logging setup
        self.logger = logging.getLogger('APIClient')
        self.logger.setLevel(logging.DEBUG)
        
        # Add file handler
        fh = logging.FileHandler('api_client.log')
        fh.setLevel(logging.DEBUG)
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        fh.setFormatter(formatter)
        self.logger.addHandler(fh)

    def log_to_streamlit(self, message):
        """Log messages to Streamlit UI."""
        st.text(message)

    def format_llm_prompt(self, prompt: str, messages: list = None) -> str:
        """Format prompt for LLM models (e.g., Phi-3)"""
        system_msg = "<|system|>\nYou are a helpful assistant.<|end|>\n"
        if messages:
            chat_history = ""
            for msg in messages:
                role = "user" if msg["role"] == "user" else "assistant"
                chat_history += f"<|{role}|>\n{msg['content']}<|end|>\n"
            return f"{system_msg}{chat_history}<|user|>\n{prompt}<|end|>\n<|assistant|>"
        return f"{system_msg}<|user|>\n{prompt}<|end|>\n<|assistant|>"

    def format_vlm_prompt(self, prompt: str, image_data: str = None, messages: list = None) -> str:
        """Format prompt for VLM models (e.g., LLaVA)"""
        system_msg = "<|im_start|>system\nAnswer the questions.<|im_end|>"
        if messages:
            chat_history = ""
            for msg in messages:
                role = "user" if msg["role"] == "user" else "assistant"
                content = msg["content"]
                if "image" in msg and role == "user":
                    content = f"![Image](data:image/jpeg;base64,{msg['image']})\n{content}"
                chat_history += f"<|im_start|>{role}\n{content}<|im_end|>\n"
            
            if image_data:
                prompt = f"![Image](data:image/jpeg;base64,{image_data})\n{prompt}"
            return f"{system_msg}\n{chat_history}<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n"
        
        if image_data:
            prompt = f"![Image](data:image/jpeg;base64,{image_data})\n{prompt}"
        return f"{system_msg}\n<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n"

    def preprocess_image(self, image: Image.Image) -> str:
        """Preprocess image for VLM models"""
        max_size = 200  # Reduce maximum size for smaller Base64 string
        ratio = min(max_size / image.size[0], max_size / image.size[1])
        new_size = tuple([int(x * ratio) for x in image.size])
        image = image.resize(new_size, Image.Resampling.LANCZOS)
        image = image.convert('RGB')

        # Convert to base64
        buffer = BytesIO()
        image.save(buffer, format="JPEG", quality=50)
        return base64.b64encode(buffer.getvalue()).decode('utf-8')

    def make_request(
        self,
        prompt: str,
        parameters: dict,
        image_data: Optional[str] = None,
        messages: list = None,
    ) -> requests.Response:
        """Make secure API requests with retry and validation."""
        # Create a dedicated area for logs in Streamlit
        log_container = st.empty()
        
        def update_logs(message):
            """Update logs in the Streamlit container"""
            if 'logs' not in st.session_state:
                st.session_state.logs = []
            st.session_state.logs.append(message)
            log_container.text('\n'.join(st.session_state.logs))
            self.logger.info(message)

        update_logs("Starting new API request")
        
        if not self.config.rate_limiter.can_make_request():
            update_logs("Rate limit exceeded")
            raise ValueError("Rate limit exceeded")

        try:
            # Hardcoded URL
            url = "http://localhost:8000/hermes-2-pro-tgi/gpu0/generate"
            update_logs(f"Request URL: {url}")
            
            # Format input based on model type
            if self.model_type == "TGI_VLM":
                formatted_input = self.format_vlm_prompt(prompt, image_data, messages)
            else:
                formatted_input = self.format_llm_prompt(prompt, messages)
            
            update_logs(f"Formatted input: {formatted_input}")

            payload = {
                "inputs": formatted_input,
                "parameters": parameters
            }
            
            headers = {
                "Authorization": f"Bearer {self.config.token}",
                "Content-Type": "application/json",
            }
            
            # Log request details
            update_logs(f"Making POST request to {url}")
            update_logs(f"Headers: {{'Authorization': 'Bearer ***', 'Content-Type': {headers['Content-Type']}}}")
            update_logs(f"Payload: {json.dumps(payload, indent=2)}")
            
            response = self.session.post(
                url=url,
                headers=headers,
                json=payload,
                timeout=180,
                verify=True,
            )

            update_logs(f"Response status code: {response.status_code}")
            update_logs(f"Response headers: {dict(response.headers)}")
            update_logs(f"Response content: {response.text[:500]}...")  # Log first 500 chars

            response.raise_for_status()
            return response

        except requests.exceptions.RequestException as e:
            update_logs(f"Request failed: {str(e)}")
            if hasattr(e, "response"):
                update_logs(f"Response status code: {e.response.status_code}")
                update_logs(f"Response content: {e.response.text}")
                
                if e.response.status_code == 401:
                    raise ValueError("Invalid token")
                elif e.response.status_code == 429:
                    raise ValueError("Rate limit exceeded")
            raise ValueError(f"API request failed: {str(e)}")

    def make_stream_request(
        self,
        prompt: str,
        parameters: dict,
        image_data: Optional[str] = None,
        messages: list = None,
    ):
        """Make streaming API request."""
        try:
            url = f"{self.config.base_url}/{self.model_name}/gpu{self.gpu_id}/generate"
            
            # Format input based on model type
            if self.model_type == "TGI_VLM":
                formatted_input = self.format_vlm_prompt(prompt, image_data, messages)
            else:
                formatted_input = self.format_llm_prompt(prompt, messages)

            payload = {
                "inputs": formatted_input,
                "parameters": {
                    **parameters,
                    "stream": True,
                    "details": True
                }
            }
            
            # Enhanced debug output
            print("\n=== Request Details ===")
            print(f"URL: {url}")
            print(f"Token: {self.config.token[:5]}...")  # First 5 chars only
            print(f"Model Type: {self.model_type}")
            print(f"Headers: {{'Authorization': 'Bearer ...', 'Content-Type': 'application/json'}}")
            print("\nPayload:")
            print(json.dumps(payload, indent=2))
            
            response = self.session.post(
                url,
                headers={
                    "Authorization": f"Bearer {self.config.token}",
                    "Content-Type": "application/json",
                },
                json=payload,
                stream=True,
                timeout=180,
                verify=True,
            )
            
            # Debug response
            print("\n=== Response Details ===")
            print(f"Status Code: {response.status_code}")
            print(f"Response Headers: {dict(response.headers)}")
            
            response.raise_for_status()
            return response
        except Exception as e:
            print(f"Stream request error: {str(e)}")  # Debug output
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


def is_vlm_model(config) -> bool:
    """Determine if the model is VLM based on environment variable."""
    model_type = os.getenv("TGI_MODEL_TYPE", "TGI_LLM")
    return model_type == "TGI_VLM"


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
        initial_sidebar_state="auto",
    )
    st.markdown(
        """
        <style>
        /* Custom theme */
        :root {
            --font-main: 'Poppins', sans-serif;
            --font-code: 'JetBrains Mono', monospace;
            --primary-color: #FF1493;
            --secondary-color: #FF69B4;
            --background-color: #ffffff;
        }

        /* Import Google Fonts */
        @import url('https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;500;600&display=swap');
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono&display=swap');

        /* Global styles */
        .stApp {
            background-color: var(--background-color);
            font-family: var(--font-main);
        }

        /* Headers */
        h1, h2, h3, h4, h5, h6 {
            font-family: var(--font-main);
            color: var(--secondary-color);
            font-weight: 600;
        }

        /* Chat message styling */
        .stChatMessage {
            background-color: #f8f9fa;
            border-radius: 15px;
            padding: 10px;
            margin: 5px 0;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        }

        .stChatMessage.user {
            background-color: #e3f2fd;
        }

        .stChatMessage.assistant {
            background-color: #f3e5f5;
        }

        /* Input fields */
        .stTextInput > div > div > input,
        .stTextArea > div > div > textarea {
            border-radius: 10px;
            border: 2px solid var(--primary-color) !important;
        }

        .stTextInput > div > div > input:focus,
        .stTextArea > div > div > textarea:focus {
            box-shadow: 0 0 0 2px var(--secondary-color) !important;
        }

        /* Buttons */
        .stButton > button {
            font-family: var(--font-main);
            background-color: var(--primary-color) !important;
            color: white !important;
            border-radius: 8px !important;
            padding: 0.5rem 1rem !important;
            font-weight: 500 !important;
            transition: all 0.3s ease !important;
        }

        .stButton > button:hover {
            background-color: var(--secondary-color) !important;
            box-shadow: 0 4px 8px rgba(255,20,147,0.3) !important;
            transform: translateY(-2px) !important;
        }

        /* Sidebar */
        .css-1d391kg {
            background-color: #f8f9fa;
        }

        /* File uploader */
        .stFileUploader {
            border: 2px dashed var(--primary-color);
            border-radius: 10px;
            padding: 10px;
        }

        /* Tabs styling */
        .stTabs [data-baseweb="tab-list"] {
            gap: 2px;
        }

        .stTabs [data-baseweb="tab"] {
            height: 50px;
            background-color: #ffffff;
            border-radius: 5px 5px 0 0;
            gap: 1px;
            padding: 10px 20px;
        }

        .stTabs [aria-selected="true"] {
            background-color: var(--primary-color) !important;
            color: white !important;
        }

        /* Info box styling */
        .info-box {
            background-color: #e7f3ef;
            border-left: 4px solid #2e7d32;
            padding: 1rem;
            margin: 1rem 0;
            border-radius: 4px;
        }

        /* Radio buttons */
        .stRadio > div {
            display: flex;
            gap: 20px;
        }

        .stRadio [data-baseweb="radio"] {
            margin-right: 20px;
        }

        /* Spinner */
        .stSpinner {
            text-align: center;
            color: var(--primary-color);
        }

        /* Error messages */
        .stAlert {
            border-radius: 8px;
            border: none;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        /* Chat container */
        .stChatFloatingInputContainer {
            position: fixed;
            bottom: 0;
            width: 100%;
            padding: 1rem;
            background: white;
            box-shadow: 0 -4px 6px rgba(0,0,0,0.05);
        }
        
        /* Chat messages */
        .stChatMessage {
            background-color: #f8f9fa;
            border-radius: 15px;
            padding: 15px;
            margin: 10px 0;
            max-width: 80%;
        }
        
        .stChatMessage.user {
            background-color: #e3f2fd;
            margin-left: auto;
        }
        
        .stChatMessage.assistant {
            background-color: #f3e5f5;
            margin-right: auto;
        }
        
        /* Chat input */
        .stChatInputContainer {
            padding: 10px;
            border-radius: 10px;
            border: 1px solid #e0e0e0;
            background: white;
        }
        
        .stTextInput > div > div > input {
            border-radius: 20px;
            padding: 10px 20px;
            border: 2px solid var(--primary-color);
            background: white;
        }
        </style>
        """,
        unsafe_allow_html=True,
    )

    st.markdown(
        '<h1 class="title">TGI Chat Demo on Intel XPUs</h1>',
        unsafe_allow_html=True,
    )

    tab1, tab2, tab3 = st.tabs(["💬 Chat", "📚 API Documentation", "🔑 Authentication"])

    with tab1:
        # Create a container for chat messages with scrolling
        chat_container = st.container()
        
        # Create a container for the input at the bottom
        input_container = st.container()

        # Use columns to center the input field
        col1, col2, col3 = input_container.columns([1, 2, 1])
        
        with col2:
            prompt = st.text_area(
                "Message",
                key="chat_input",
                height=100,  # Increased height
                placeholder="Type your message here...",
                label_visibility="collapsed"
            )

        # Display messages in the chat container
        with chat_container:
            # Reverse the messages to show newest at the bottom
            messages = st.session_state.get('messages', [])
            for message in messages:
                with st.chat_message(message["role"]):
                    if "image" in message:
                        st.image(message["image"])
                    st.write(message["content"])

        # Handle the input
        if prompt:
            if not config.token:
                st.error("Please configure your token first!")
                return
            
            # Add user message
            st.session_state.messages.append({"role": "user", "content": prompt})
            
            # Clear the input
            st.session_state.chat_input = ""
            
            # Rerun to update the UI
            st.rerun()

        # Generate assistant response
        if st.session_state.messages and st.session_state.messages[-1]["role"] == "user":
            with chat_container:
                with st.chat_message("assistant"):
                    message_placeholder = st.empty()
                    full_response = ""
                    try:
                        response = config.api_client.make_stream_request(
                            st.session_state.messages[-1]["content"],
                            params,
                            image_data,
                            messages=st.session_state.messages[:-1]
                        )
                        
                        for line in response.iter_lines():
                            if line:
                                try:
                                    raw_line = line.decode('utf-8')
                                    data = json.loads(raw_line)
                                    
                                    if "generated_text" in data:
                                        token = data["generated_text"]
                                        full_response = token
                                    elif "token" in data and "text" in data["token"]:
                                        token = data["token"]["text"]
                                        full_response += token
                                    else:
                                        continue
                                    
                                    message_placeholder.markdown(full_response + "▌")
                                except json.JSONDecodeError:
                                    continue
                                except Exception:
                                    continue
                        
                        if full_response:
                            message_placeholder.markdown(full_response)
                            st.session_state.messages.append(
                                {"role": "assistant", "content": full_response}
                            )
                            # Rerun to update the UI
                            st.rerun()
                        else:
                            message_placeholder.error("No response generated")
                        
                    except Exception as e:
                        st.error(f"Error generating response: {str(e)}")
                        st.info("Response error. Details: " + str(e))

    with tab2:
        st.markdown("### API Documentation")
        with open("API.md", "r") as f:
            st.markdown(f.read())

    with tab3:
        st.markdown("### 🔐 Authentication")
        new_token = st.text_input(
            "Enter API Token", value=config.token, type="password"
        )
        if st.button("Save Token"):
            config.token = new_token
            st.success("Token saved successfully!")

    # Add a section for debug logs
    with st.expander("Debug Logs", expanded=True):
        if 'logs' in st.session_state:
            st.text('\n'.join(st.session_state.logs))


if __name__ == "__main__":
    config = ChatConfig()
    main()
