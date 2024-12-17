import streamlit as st
import httpx
import asyncio
import json

class TGIClient:
    def __init__(self, base_url: str, token: str):
        self.base_url = base_url
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
    
    def generate_stream(self, messages):
        prompt = "<|system|>\nYou are a helpful AI assistant.\n<|end|>\n"
        for msg in messages:
            prompt += f"<|{msg['role']}|>\n{msg['content']}\n<|end|>\n"
        prompt += "<|assistant|>\n"
        
        last_text = ""
        with httpx.Client() as client:
            response = client.post(
                f"{self.base_url}/generate",
                headers=self.headers,
                json={
                    "inputs": prompt,
                    "parameters": {
                        "max_new_tokens": 500,
                        "stream": True
                    }
                },
                timeout=60,
                stream=True
            )
            response.raise_for_status()
            
            for line in response.iter_lines():
                if line:
                    try:
                        json_response = json.loads(line)
                        if isinstance(json_response, list) and json_response:
                            text = json_response[0].get("generated_text", "")
                            # Get only the new content
                            new_text = text[len(prompt):].strip()
                            # Yield only the delta (new tokens)
                            if new_text != last_text:
                                delta = new_text[len(last_text):]
                                last_text = new_text
                                yield delta
                    except json.JSONDecodeError:
                        continue

def initialize_session_state():
    if "messages" not in st.session_state:
        st.session_state.messages = []
    if "client" not in st.session_state:
        st.session_state.client = None

def main():
    st.title("🤖 AI Chat Interface")
    
    initialize_session_state()
    
    # First time setup
    if not st.session_state.client:
        with st.form("setup_form"):
            base_url = st.text_input("Base URL:", placeholder="http://localhost:8000/your-model/gpu0")
            api_token = st.text_input("API Token:", type="password")
            if st.form_submit_button("Connect"):
                if base_url and api_token:
                    st.session_state.client = TGIClient(base_url, api_token)
                    st.rerun()
        return

    # Display chat messages
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.markdown(message["content"])

    # Chat input
    if prompt := st.chat_input("Type your message..."):
        # Add user message
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        # Generate and display assistant response
        with st.chat_message("assistant"):
            stream = st.session_state.client.generate_stream(st.session_state.messages)
            response = st.write_stream(stream)
        st.session_state.messages.append({"role": "assistant", "content": response})

if __name__ == "__main__":
    main()