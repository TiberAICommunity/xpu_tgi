import streamlit as st
import requests
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry

st.set_page_config(
    page_title="LLM Text generation Demo on Intel XPUs", page_icon="🐙", layout="wide"
)

st.markdown(
    """
<style>
    /* Main container */
    .main {
        padding: 2rem;
        max-width: 1200px !important;
        margin: 0 auto;
    }
    
    /* Headers */
    h1 {
        color: #1E88E5;
        font-size: 2.5rem !important;
        font-weight: 700 !important;
        margin-bottom: 2rem !important;
    }
    
    /* Input fields */
    .stTextInput > div > div > input {
        padding: 0.5rem 1rem;
        font-size: 1.1rem;
        border-radius: 8px;
    }
    
    /* Buttons */
    .stButton > button {
        width: auto !important;
        padding: 0.5rem 2rem;
        font-size: 1.1rem;
        font-weight: 600;
        border-radius: 8px;
        transition: all 0.3s ease;
        min-width: 150px;
        max-width: 300px;
        display: inline-block;
        background-color: #FF69B4 !important;
        color: white !important;
        border: none !important;
    }
    
    .stButton > button:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(255,105,180,0.3);
        background-color: #FF1493 !important; 
    }
    
    /* Generated text container */
    .generated-text {
        background-color: #f8f9fa;
        padding: 2rem;
        border-radius: 10px;
        margin: 1rem auto;
        width: 100%;
        max-width: 1200px;
        min-width: 300px;
        line-height: 1.6;
        box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    }
    
    /* API docs */
    .api-docs {
        padding: 2.5rem;
        background-color: #f8f9fa;
        border-radius: 12px;
        box-shadow: 0 2px 12px rgba(0,0,0,0.05);
    }
    
    /* Success/Error messages */
    .stSuccess, .stError, .stInfo {
        padding: 1rem;
        border-radius: 8px;
        font-weight: 500;
    }
    
    /* Sliders */
    .stSlider {
        padding-top: 1rem;
        padding-bottom: 1rem;
    }
    
    /* Tabs */
    .stTabs [data-baseweb="tab-list"] {
        gap: 2rem;
    }
    
    .stTabs [data-baseweb="tab"] {
        font-size: 1.2rem;
        font-weight: 600;
    }
    
    /* Center the generate button */
    .stButton {
        text-align: center;
        margin: 2rem 0;
        display: flex;
        justify-content: center;
    }
    
    /* Spinner alignment */
    .stSpinner {
        text-align: center;
        margin: 1rem auto;
    }
    
    .generated-text pre {
        background-color: #e9ecef;
        padding: 1rem;
        border-radius: 8px;
        margin: 1rem 0;
        white-space: pre-wrap;
        font-family: monospace;
    }
    
    /* Note blocks */
    blockquote {
        background-color: #e7f3ec;
        border-left: 4px solid #2e7d32;
        padding: 1rem;
        margin: 1rem 0;
        border-radius: 0 8px 8px 0;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    
    blockquote p {
        color: #1b5e20;
        margin: 0;
        font-size: 1rem;
        line-height: 1.6;
    }
    
    /* Code blocks */
    pre {
        background-color: #f8f9fa;
        padding: 1rem;
        border-radius: 8px;
        border: 1px solid #e9ecef;
        overflow-x: auto;
    }
    
    code {
        font-family: 'Roboto Mono', monospace;
        font-size: 0.9rem;
    }
    
    /* Headers hierarchy */
    h2 {
        color: #2196F3;
        font-size: 1.8rem !important;
        margin-top: 2rem !important;
        padding-bottom: 0.5rem;
        border-bottom: 2px solid #e9ecef;
    }
    
    h3 {
        color: #1976D2;
        font-size: 1.5rem !important;
        margin-top: 1.5rem !important;
    }
    
    /* Lists */
    ul, ol {
        padding-left: 1.5rem;
        margin: 1rem 0;
    }
    
    li {
        margin: 0.5rem 0;
        line-height: 1.6;
    }
    
    /* Tables */
    table {
        width: 100%;
        border-collapse: collapse;
        margin: 1rem 0;
    }
    
    th, td {
        padding: 0.75rem;
        border: 1px solid #dee2e6;
    }
    
    th {
        background-color: #f8f9fa;
        font-weight: 600;
    }
    
    /* Important notes */
    .note {
        background-color: #e3f2fd;
        border-left: 4px solid #2196F3;
        padding: 1rem;
        margin: 1rem 0;
        border-radius: 0 8px 8px 0;
    }
    
    .warning {
        background-color: #fff3e0;
        border-left: 4px solid #ff9800;
        padding: 1rem;
        margin: 1rem 0;
        border-radius: 0 8px 8px 0;
    }
</style>
""",
    unsafe_allow_html=True,
)


def create_retry_session(retries=3, backoff_factor=0.5):
    session = requests.Session()
    retry = Retry(
        total=retries,
        backoff_factor=backoff_factor,
        status_forcelist=[429, 500, 502, 503, 504],
    )
    adapter = HTTPAdapter(max_retries=retry)
    session.mount("http://", adapter)
    return session


tab1, tab2 = st.tabs(["🐙 Text Generation", "📚 API Documentation"])

with tab1:
    st.title("🐙 LLM Text generation Demo on Intel XPUs")
    input_url = st.text_input(
        "TGI URL:", placeholder="http://localhost:8000/your-model/gpu0"
    )
    base_url = input_url.rstrip('/generate').rstrip('/')
    if input_url and input_url != base_url:
        st.info("ℹ️ Detected '/generate' in the URL. Using the base URL instead: " + base_url)
    api_token = st.text_input("API Token:", type="password")
    col1, col2, col3 = st.columns([1, 4, 1])
    with col2:
        connect_clicked = st.button("Connect 🔗", use_container_width=True)
    if connect_clicked or (base_url and api_token):
        try:
            headers = {
                "Authorization": f"Bearer {api_token}",
                "Content-Type": "application/json",
            }
            test_response = requests.post(
                f"{base_url}/generate",
                headers=headers,
                json={"inputs": "test", "parameters": {"max_new_tokens": 1}},
                timeout=10,
            )
            test_response.raise_for_status()
            st.success("✅ Connected to TGI server")
            max_tokens = st.slider("Max New Tokens", 10, 1000, 100)
            temperature = st.slider("Temperature", 0.0, 2.0, 0.7)
            prompt = st.text_area(
                "Enter your prompt:",
                height=100,
                value=st.session_state.get("prompt", ""),
            )
            col1, col2, col3 = st.columns([1, 4, 1])
            with col2:
                if st.button("Generate 🚀", use_container_width=True) and prompt:
                    session = create_retry_session()
                    with st.spinner("🤖 Generating response..."):
                        try:
                            response = session.post(
                                f"{base_url}/generate",
                                headers=headers,
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
                        except (requests.exceptions.RequestException, ValueError) as e:
                            st.error(f"Generation Error: {str(e)}")
        except requests.exceptions.RequestException as e:
            st.error(f"Connection Error: {str(e)}")
    else:
        st.info("👆 Enter your TGI URL and API token to start generating text")

with tab2:
    try:
        with open("API.md", "r") as f:
            api_docs = f.read().strip()
        with st.container():
            st.markdown('<div class="api-docs">', unsafe_allow_html=True)
            st.markdown(api_docs)
            st.markdown("</div>", unsafe_allow_html=True)
    except FileNotFoundError:
        st.error("API documentation file (API.md) not found!")
