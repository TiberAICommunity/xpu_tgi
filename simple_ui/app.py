import base64
import io
import json
import os
import re
import time
from pathlib import Path
from typing import Optional

import requests
import streamlit as st
from PIL import Image


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
        self.model_name = None
        self.gpu_id = 0
        self.max_context_length = 1024
        self.approximate_token_length = 4

    def get_model_context_length(self) -> int:
        """Get the model's maximum context length from info endpoint."""
        if not self.model_name:
            info = get_model_info(self.config)
            self.model_name = info.get("model_id", "").split("/")[-1]
            self.max_context_length = info.get("max_sequence_length", 4096)
        return self.max_context_length

    def format_chat_history(self, messages: list, current_prompt: str) -> str:
        """Format chat history for the model while respecting context length."""
        max_length = self.get_model_context_length()
        reserve_tokens = 500
        formatted_messages = []
        current_length = 0
        prompt_msg = f"Human: {current_prompt}\nAssistant:"
        current_length += len(prompt_msg.split()) * self.approximate_token_length
        for msg in reversed(messages):
            role = msg["role"]
            content = msg["content"]
            formatted_msg = f"{role.title()}: {content}"
            msg_tokens = len(formatted_msg.split()) * self.approximate_token_length
            if current_length + msg_tokens > (max_length - reserve_tokens):
                break
            formatted_messages.insert(0, formatted_msg)
            current_length += msg_tokens
        formatted_messages.append(prompt_msg)
        return "\n".join(formatted_messages)

    def make_request(
        self,
        prompt: str,
        parameters: dict,
        image_data: Optional[str] = None,
        messages: list = None,
    ) -> requests.Response:
        """Make secure API requests with retry and validation."""
        if not self.config.rate_limiter.can_make_request():
            raise ValueError("Rate limit exceeded")

        try:
            if not self.model_name:
                info = get_model_info(self.config)
                self.model_name = info.get("model_id", "").split("/")[-1]
            url = f"{self.config.base_url}/{self.model_name}/gpu{self.gpu_id}/generate"
            if messages:
                formatted_input = self.format_chat_history(messages, prompt)
            else:
                formatted_input = f"Human: {prompt}\nAssistant:"
            if image_data:
                inputs = f"<image>{image_data}</image>\n{formatted_input}"
            else:
                inputs = formatted_input
            validated_params = {
                "max_new_tokens": min(
                    max(1, parameters.get("max_new_tokens", 150)), 500
                ),
                "temperature": min(max(0.0, parameters.get("temperature", 0.7)), 1.0),
                "top_p": min(max(0.0, parameters.get("top_p", 0.95)), 1.0),
                "top_k": min(max(1, parameters.get("top_k", 50)), 100),
                "repetition_penalty": min(
                    max(1.0, parameters.get("repetition_penalty", 1.1)), 2.0
                ),
                "do_sample": True,
                "details": True,
            }
            payload = {
                "inputs": inputs,
                "parameters": validated_params,
                "stream": False,
            }
            response = self.session.post(
                url=url,
                headers={
                    "Authorization": f"Bearer {self.config.token}",
                    "Content-Type": "application/json",
                },
                json=payload,
                timeout=180,
                verify=True,
            )

            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            if hasattr(e, "response"):
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
        if not self.config.rate_limiter.can_make_request():
            raise ValueError("Rate limit exceeded")

        try:
            if not self.model_name:
                info = get_model_info(self.config)
                self.model_name = info.get("model_id", "").split("/")[-1]
            url = f"{self.config.base_url}/{self.model_name}/gpu{self.gpu_id}/generate"
            if messages:
                formatted_input = self.format_chat_history(messages, prompt)
            else:
                formatted_input = f"Human: {prompt}\nAssistant:"
            if image_data:
                inputs = f"<image>{image_data}</image>\n{formatted_input}"
            else:
                inputs = formatted_input
            payload = {
                "inputs": inputs,
                "parameters": {**parameters, "do_sample": True, "details": True},
                "stream": True,
            }
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
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            if hasattr(e, "response"):
                if e.response.status_code == 401:
                    raise ValueError("Invalid token")
                elif e.response.status_code == 429:
                    raise ValueError("Rate limit exceeded")
            raise ValueError(f"API request failed: {str(e)}")


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


def get_model_info(config) -> dict:
    """Get model information from the API."""
    try:
        response = requests.get(
            f"{config.base_url}/info",
            headers={"Authorization": f"Bearer {config.token}"},
            timeout=10,
        )
        response.raise_for_status()
        return response.json()
    except Exception:
        return {}


def is_vlm_model(model_info: dict) -> bool:
    model_name = model_info.get("model_name", "").lower()
    vlm_indicators = ["llava", "visual", "multimodal", "vlm"]
    return any(indicator in model_name for indicator in vlm_indicators)


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
        try:
            model_info = get_model_info(config)
            is_vlm = is_vlm_model(model_info)
            if is_vlm:
                model_type = st.radio(
                    "Model Capabilities",
                    ["Text (LLM)", "Visual (VLM)"],
                    help="This model supports both text and visual inputs",
                )
            else:
                model_type = "Text (LLM)"
                st.info("This model supports text input only")
        except Exception as e:
            st.warning(
                "Could not detect model capabilities. Defaulting to text-only mode."
            )
            model_type = "Text (LLM)"
        if "messages" not in st.session_state:
            st.session_state.messages = []
        for message in st.session_state.messages:
            with st.chat_message(message["role"]):
                if "image" in message:
                    st.image(message["image"])
                st.write(message["content"])
        image_data = None
        if model_type == "Visual (VLM)":
            uploaded_file = st.file_uploader(
                "Upload an image", type=["jpg", "jpeg", "png"]
            )
            if uploaded_file:
                try:
                    image = Image.open(uploaded_file)
                    if not validate_image(image):
                        st.error(
                            "Image must be RGB, max 1024x1024 pixels, and under 2MB"
                        )
                        image = None
                    else:
                        st.image(image, caption="Uploaded Image")
                except Exception as e:
                    st.error(f"Error loading image: {str(e)}")
                    image = None
        with st.sidebar:
            st.header("Generation Parameters")
            params = get_default_params()
            params["temperature"] = st.slider(
                "Temperature", 0.0, 1.0, params["temperature"]
            )
            params["max_new_tokens"] = st.number_input(
                "Max New Tokens", 1, 250, params["max_new_tokens"]
            )
            params["top_p"] = st.slider("Top P", 0.0, 1.0, params["top_p"])
            params["top_k"] = st.number_input("Top K", 1, 100, params["top_k"])
            params["repetition_penalty"] = st.slider(
                "Repetition Penalty", 1.0, 2.0, params["repetition_penalty"]
            )
        if prompt := st.chat_input("Enter your message"):
            if not config.token:
                st.error("Please configure your token first!")
                return
            with st.chat_message("user"):
                if model_type == "Visual (VLM)" and uploaded_file:
                    st.image(image)
                st.write(prompt)
            message_data = {"role": "user", "content": prompt}
            if model_type == "Visual (VLM)" and uploaded_file:
                try:
                    buffered = io.BytesIO()
                    image.save(buffered, format="JPEG")
                    image_data = base64.b64encode(buffered.getvalue()).decode()
                    message_data["image"] = image_data
                except Exception as e:
                    st.error(f"Error processing image: {str(e)}")
                    image_data = None
            st.session_state.messages.append(message_data)
            with st.spinner("Connecting..."):
                try:
                    response = config.api_client.make_stream_request(
                        prompt,
                        params,
                        image_data,
                        messages=st.session_state.messages[
                            :-1
                        ],  # Exclude the current message
                    )
                    with st.chat_message("assistant"):
                        message_placeholder = st.empty()
                        full_response = ""
                        for line in response.iter_lines():
                            if line:
                                try:
                                    data = json.loads(line)
                                    if "token" in data:
                                        token = data["token"]["text"]
                                        full_response += token
                                        message_placeholder.markdown(
                                            full_response + "▌"
                                        )
                                except json.JSONDecodeError:
                                    continue
                        message_placeholder.markdown(full_response)
                    st.session_state.messages.append(
                        {"role": "assistant", "content": full_response}
                    )
                except Exception as e:
                    st.error(f"Error generating response: {str(e)}")
                    st.info("If the error persists, try using text-only mode")

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


if __name__ == "__main__":
    config = ChatConfig()
    main()
