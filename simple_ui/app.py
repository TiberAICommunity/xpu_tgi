import streamlit as st
import httpx
import json
from typing import List, Dict, Optional, AsyncGenerator

# Page config
st.set_page_config(page_title="AI Chat Interface", page_icon="🤖", layout="wide")

# System message and model config
SYSTEM_MESSAGE = """
You are a helpful and knowledgeable AI assistant.
Your name is Hermes-2.
Address all members in the conversation clearly and professionally.
Use markdown formatting when appropriate, especially for code blocks.
"""

MODEL_CONFIG = {
    'avatar': "🤖",
}

class Conversation:
    def __init__(self, memory_size: int = 5):
        self.messages: List[Dict[str, str]] = []
        self.memory_size = memory_size

    def add_message(self, role: str, content: str):
        self.messages.append({"role": role, "content": content})
        # Keep only the last N messages
        self.messages = self.messages[-self.memory_size:]

    def format_for_tgi(self) -> str:
        # Format messages in a more chat-like format
        formatted_messages = []
        for msg in self.messages[-self.memory_size:]:
            if msg["role"] == "user":
                formatted_messages.append(f"<|user|>\n{msg['content']}\n<|end|>")
            elif msg["role"] == "assistant":
                formatted_messages.append(f"<|assistant|>\n{msg['content']}\n<|end|>")
        
        return "\n".join(formatted_messages)

    def clear(self):
        self.messages = []

class TGIModelManager:
    def __init__(self, base_url: str, token: str, system_message: str):
        self.base_url = base_url
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        self.system_message = system_message
    
    async def generate_stream(self, messages: str) -> AsyncGenerator[str, None]:
        # Format the complete prompt with system message and chat markers
        prompt = f"<|system|>\n{self.system_message}\n<|end|>\n{messages}\n<|assistant|>\n"
        
        async with httpx.AsyncClient() as client:
            async with client.stream(
                'POST',
                f"{self.base_url}/generate",
                headers=self.headers,
                json={
                    "inputs": prompt,
                    "parameters": {
                        "max_new_tokens": 500,
                        "temperature": 0.7,
                        "stream": True,
                        "stop": ["<|end|>", "<|user|>", "<|system|>"]  # Add stop tokens
                    }
                },
                timeout=60
            ) as response:
                response.raise_for_status()
                last_text = ""
                
                async for line in response.aiter_lines():
                    if line:
                        try:
                            json_response = json.loads(line)
                            if isinstance(json_response, list) and json_response:
                                text = json_response[0].get("generated_text", "")
                                new_text = text[len(prompt):].strip()
                                if new_text != last_text:
                                    delta = new_text[len(last_text):]
                                    if delta:
                                        last_text = new_text
                                        yield delta
                        except json.JSONDecodeError:
                            continue

def get_help():
    return """
    ### Hello! 👋
    I'm an AI assistant that can help you with various tasks. Here are some commands:
    - `/help`: Shows this help message
    - `/clear`: Clears the chat history
    - `/about`: Shows information about this app
    
    Or just type your message and I'll respond!
    """

def about_app():
    return """
    ### About This App
    This is an AI chat interface powered by the TGI (Text Generation Inference) model.
    It provides streaming responses and maintains conversation context.
    """

# Initialize session state
if "conversation" not in st.session_state:
    st.session_state.conversation = Conversation()
if "model_manager" not in st.session_state:
    st.session_state.model_manager = None

# Setup form if not configured
if not st.session_state.model_manager:
    st.title("🤖 AI Chat Interface - Setup")
    with st.form("setup_form"):
        base_url = st.text_input(
            "Base URL:", 
            placeholder="http://localhost:8000/your-model/gpu0",
            help="The base URL of your TGI model endpoint"
        )
        api_token = st.text_input(
            "API Token:", 
            type="password",
            help="Your API authentication token"
        )
        if st.form_submit_button("Connect"):
            if base_url and api_token:
                st.session_state.model_manager = TGIModelManager(
                    base_url=base_url,
                    token=api_token,
                    system_message=SYSTEM_MESSAGE
                )
                st.rerun()
            else:
                st.error("Please provide both Base URL and API Token.")
    st.stop()

# Main chat interface
st.title("🤖 AI Chat Interface")

# Display chat history
for message in st.session_state.conversation.messages:
    with st.chat_message(
        message["role"], 
        avatar=MODEL_CONFIG['avatar'] if message["role"] == "assistant" else None
    ):
        st.markdown(message["content"])

# Chat input
if prompt := st.chat_input("Type your message..."):
    # Handle commands
    if prompt.startswith('/'):
        command = prompt[1:]
        command_response = None
        if command == "help":
            command_response = get_help()
        elif command == "clear":
            st.session_state.conversation.clear()
            st.rerun()
        elif command == "about":
            command_response = about_app()
        
        if command_response:
            with st.chat_message("system", avatar="ℹ️"):
                st.write(command_response)
    else:
        # Display user message
        with st.chat_message("user"):
            st.markdown(prompt)
        st.session_state.conversation.add_message("user", prompt)
        
        # Generate and display assistant response
        with st.chat_message("assistant", avatar=MODEL_CONFIG['avatar']):
            message_placeholder = st.empty()
            full_response = ""
            
            # Get the stream generator
            stream_gen = st.session_state.model_manager.generate_stream(
                st.session_state.conversation.format_for_tgi()
            )
            
            # Use write_stream to handle the streaming
            try:
                import asyncio
                async def process_stream():
                    async for chunk in stream_gen:
                        yield chunk
                
                response = st.write_stream(process_stream())
                st.session_state.conversation.add_message("assistant", response)
            except Exception as e:
                st.error(f"Error generating response: {str(e)}")