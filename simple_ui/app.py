import streamlit as st
import requests
import time

st.set_page_config(
    page_title="LLM Text generation Demo on Intel XPUs",
    page_icon="🤖",
)
st.markdown(
    """
<style>
    /* Main container */
    .main {
        padding: 2rem;
    }
    
    /* Headers */
    h1 {
        color: #1E88E5;
        font-size: 2.5rem !important;
        font-weight: 700 !important;
        margin-bottom: 2rem !important;
    }
    
    h3 {
        color: #333;
        font-size: 1.5rem !important;
        margin-top: 1.5rem !important;
    }
    
    /* Input fields */
    .stTextInput > div > div > input {
        padding: 0.5rem 1rem;
        font-size: 1.1rem;
        border-radius: 8px;
    }
    
    /* Buttons */
    .stButton > button {
        width: 100%;
        padding: 0.5rem 1rem;
        font-size: 1.1rem;
        font-weight: 600;
        border-radius: 8px;
        transition: all 0.3s ease;
    }
    .stButton > button:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    }
    
    /* Sample prompts */
    .sample-prompt {
        background-color: #f8f9fa;
        padding: 1rem;
        border-radius: 8px;
        margin-bottom: 1rem;
    }
    
    /* Generated text container */
    .generated-text {
        background-color: #f8f9fa;
        padding: 2rem;
        border-radius: 10px;
        border-left: 5px solid #1E88E5;
        margin-top: 1rem;
        margin-bottom: 1rem;
    }
    
    .generated-text h3 {
        margin-top: 0 !important;
        margin-bottom: 1rem !important;
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
    
    /* Sample prompt info box */
    .sample-prompt-box {
        background-color: #E3F2FD;
        border-left: 5px solid #1E88E5;
        padding: 1rem;
        border-radius: 4px;
        font-size: 0.9rem;
        margin: 1rem 0;
        color: #1565C0;
    }
</style>
""",
    unsafe_allow_html=True,
)

SAMPLE_PROMPT = """Write a creative story about a robot learning to paint. The story should:
- Be around 200 words
- Have a clear beginning, middle, and end
- Include descriptive details about the robot's journey
- End with a meaningful conclusion"""

tab1, tab2 = st.tabs(["🤖 Text Generation", "📚 API Documentation"])

with tab1:
    st.title("🤖 LLM Text generation Demo on Intel XPUs")
    base_url = st.text_input(
        "TGI URL:", placeholder="http://localhost:8000/your-model/gpu0"
    )
    api_token = st.text_input("API Token:", type="password")
    if base_url and api_token:
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
            max_tokens = st.slider("Max New Tokens", 10, 1000, 200)
            temperature = st.slider("Temperature", 0.0, 2.0, 0.7)
            if st.button("Use Sample Prompt"):
                st.session_state.prompt = SAMPLE_PROMPT
            st.markdown(
                """
            <style>
            .sample-prompt-box {
                background-color: #E3F2FD;
                border-left: 5px solid #1E88E5;
                padding: 1rem;
                border-radius: 4px;
                font-size: 0.9rem;
                margin: 1rem 0;
                color: #1565C0;
            }
            </style>
            """,
                unsafe_allow_html=True,
            )

            prompt = st.text_area(
                "Enter your prompt:",
                height=100,
                value=st.session_state.get("prompt", ""),
            )
            st.markdown('<div class="sample-prompt-box">', unsafe_allow_html=True)
            st.markdown("**Try this sample prompt:**")
            st.markdown(SAMPLE_PROMPT)
            st.markdown("</div>", unsafe_allow_html=True)

            if st.button("Generate") and prompt:
                progress_text = st.empty()
                loading_emojis = ["🤔", "💭", "⚡", "🔮", "✨"]
                loading_thread_active = True

                def loading_animation():
                    i = 0
                    while loading_thread_active:
                        progress_text.markdown(
                            f"### Generating {loading_emojis[i % len(loading_emojis)]}"
                        )
                        time.sleep(0.3)  # Control animation speed
                        i += 1

                import threading

                loading_thread = threading.Thread(target=loading_animation)
                loading_thread.start()
                try:
                    response = requests.post(
                        f"{base_url}/generate",
                        headers=headers,
                        json={
                            "inputs": prompt,
                            "parameters": {
                                "max_new_tokens": max_tokens,
                                "temperature": temperature,
                            },
                        },
                        timeout=30,
                    )
                    loading_thread_active = False
                    loading_thread.join()
                    progress_text.empty()
                    result = response.json()
                    st.markdown('<div class="generated-text">', unsafe_allow_html=True)
                    st.markdown("### Generated Text:")
                    st.write(result[0]["generated_text"])
                    st.markdown("</div>", unsafe_allow_html=True)
                except requests.exceptions.RequestException as e:
                    st.error(f"Generation Error: {str(e)}")
        except requests.exceptions.RequestException as e:
            st.error(f"Connection Error: {str(e)}")
    else:
        st.info("👆 Enter your TGI URL and API token to start generating text")

with tab2:
    st.title("📚 API Documentation")

    # Read and display API.md
    try:
        with open("API.md", "r") as f:
            api_docs = f.read()

        # Add some styling to the docs
        st.markdown(
            """
        <style>
        .api-docs {
            padding: 2rem;
            background-color: #f8f9fa;
            border-radius: 10px;
        }
        </style>
        """,
            unsafe_allow_html=True,
        )

        with st.container():
            st.markdown('<div class="api-docs">', unsafe_allow_html=True)
            st.markdown(api_docs)
            st.markdown("</div>", unsafe_allow_html=True)

    except FileNotFoundError:
        st.error("API documentation file (API.md) not found!")
