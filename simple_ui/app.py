import streamlit as st
import requests
import time
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

# Styles
st.markdown(
    """
    <style>
    .generated-text {
        background-color: #f0f2f6;
        border-radius: 10px;
        padding: 20px;
        margin: 10px 0;
    }
    .generated-text pre {
        white-space: pre-wrap;
        word-wrap: break-word;
        margin: 0;
    }
    .stButton>button {
        background-color: #FF4B4B;
        color: white;
    }
    </style>
    """,
    unsafe_allow_html=True,
)


def create_retry_session(retries=3, backoff_factor=2.0):
    session = requests.Session()
    retry = Retry(
        total=retries,
        backoff_factor=backoff_factor,
        status_forcelist=[429, 500, 502, 503, 504],
        respect_retry_after_header=True,
        raise_on_status=True,
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


def sanitize_prompt(prompt, max_length=200):
    return prompt[:max_length] if len(prompt) > max_length else prompt


def check_auth(base_url, api_token):
    headers = {
        "Authorization": f"Bearer {api_token}",
        "Content-Type": "application/json",
    }
    session = create_retry_session(retries=2, backoff_factor=0.5)
    test_response = session.post(
        f"{base_url}/generate",
        headers=headers,
        json={"inputs": "test", "parameters": {"max_new_tokens": 1}},
        timeout=20,
    )
    test_response.raise_for_status()
    time.sleep(1)  # Add delay after auth check
    return headers


def rate_limit_check():
    if "last_request_time" in st.session_state:
        elapsed = time.time() - st.session_state.last_request_time
        if elapsed < 3:
            time.sleep(3 - elapsed)
    st.session_state.last_request_time = time.time()


tab1, tab2 = st.tabs(["🐙 Text Generation", "📚 API Documentation"])

with tab1:
    st.title("🐙 LLM Text generation Demo on Intel XPUs")
    input_url = st.text_input(
        "TGI URL:", placeholder="http://localhost:8000/your-model/gpu0"
    )
    base_url = input_url.rstrip("/")
    if base_url.endswith("/generate"):
        base_url = base_url[:-9]
        st.info(f"ℹ️ Detected '/generate' in the URL. Using the base URL instead: {base_url}")
    if "headers" not in st.session_state:
        api_token = st.text_input("API Token:", type="password")
        col1, col2, col3 = st.columns([1, 4, 1])
        with col2:
            connect_clicked = st.button("Connect 🔗", use_container_width=True)
        if connect_clicked and base_url and api_token:
            try:
                headers = {
                    "Authorization": f"Bearer {api_token}",
                    "Content-Type": "application/json",
                }
                test_response = requests.post(
                    f"{base_url}/generate",
                    headers=headers,
                    json={"inputs": "test", "parameters": {"max_new_tokens": 1}},
                    timeout=20,
                )
                test_response.raise_for_status()
                time.sleep(2)
                st.success("✅ Connected to TGI server")
                st.session_state.headers = headers
                st.session_state.base_url = base_url
                st.rerun()
            except requests.exceptions.RequestException as e:
                st.error(f"Connection Error: {str(e)}")
    if "headers" in st.session_state:
        max_tokens = st.slider("Max New Tokens", 10, 1000, 100)
        temperature = st.slider("Temperature", 0.0, 2.0, 0.7)
        prompt = st.text_area(
            "Enter your prompt:",
            height=100,
            value=st.session_state.get("prompt", ""),
            help="Maximum 200 characters",
        )
        if prompt:
            prompt = sanitize_prompt(prompt)
            if len(prompt) >= 201:
                st.warning("⚠️ Prompt has been truncated to 200 characters")

        col1, col2, col3 = st.columns([1, 4, 1])
        with col2:
            if st.button("Generate 🚀", use_container_width=True) and prompt:
                rate_limit_check()
                session = create_retry_session()
                with st.spinner("🤖 Generating response..."):
                    try:
                        response = session.post(
                            f"{st.session_state.base_url}/generate",
                            headers=st.session_state.headers,
                            json={
                                "inputs": prompt,
                                "parameters": {
                                    "max_new_tokens": max_tokens,
                                    "temperature": temperature,
                                },
                            },
                            timeout=60,
                        )
                        response.raise_for_status()
                        result = response.json()
                        if (
                            not isinstance(result, list)
                            or len(result) == 0
                            or "generated_text" not in result[0]
                        ):
                            raise ValueError(
                                "Unexpected response format from the server"
                            )
                        full_text = result[0]["generated_text"]
                        st.markdown(
                            """
                            <div class="generated-text">
                                <pre>{}</pre>
                            </div>
                            """.format(
                                full_text
                            ),
                            unsafe_allow_html=True,
                        )
                    except requests.exceptions.RequestException as e:
                        st.error(f"Generation Error: {str(e)}")
    else:
        st.info("👆 Enter your TGI URL and API token to start generating text")

with tab2:
    st.markdown(
        """
    # API Documentation
    
    This demo interfaces with Text Generation Inference (TGI) server running on Intel XPUs.
    
    ## API Endpoints
    
    ### Generate Text
    **Endpoint:** `POST /generate`
    
    **Parameters:**
    - `inputs`: The prompt text to generate from
    - `parameters`:
        - `max_new_tokens`: Maximum number of tokens to generate (10-1000)
        - `temperature`: Controls randomness in generation (0.0-2.0)
    
    **Example Request:**
    ```json
    {
        "inputs": "Your prompt text here",
        "parameters": {
            "max_new_tokens": 100,
            "temperature": 0.7
        }
    }
    ```
    
    **Example Response:**
    ```json
    [
        {
            "generated_text": "Generated response will appear here"
        }
    ]
    ```
    """
    )
