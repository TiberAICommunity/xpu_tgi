#!/usr/bin/env python3

import hashlib
import logging
import secrets
import time
from datetime import datetime, timezone
from pathlib import Path

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

ADJECTIVES = [
    "swift", "bright", "unique", "calm", "deep", "bold", "wise", "kind",
    "pure", "humble", "warm", "cool", "fresh", "clear", "radiant", "keen",
    "firm", "true",
]

NOUNS = [
    "wave", "star", "moon", "sun", "wind", "tree", "lake", "bird",
    "cloud", "rose", "light", "peak", "rain", "leaf", "seed", "song",
]
MIN_TOKEN_LENGTH = 32
MAX_TOKEN_LENGTH = 64
GENERATION_COOLDOWN = 1

last_generation_time = 0

def get_secure_words():
    """Get random words using cryptographically secure random numbers."""
    adj1 = ADJECTIVES[secrets.randbelow(len(ADJECTIVES))]
    adj2 = ADJECTIVES[secrets.randbelow(len(ADJECTIVES))]
    noun = NOUNS[secrets.randbelow(len(NOUNS))]
    return adj1, adj2, noun

def generate_secure_token() -> str:
    """Generate a memorable yet secure token with additional entropy."""
    global last_generation_time
    current_time = time.time()
    if current_time - last_generation_time < GENERATION_COOLDOWN:
        raise ValueError("Token generation too frequent")

    last_generation_time = current_time
    adj1, adj2, noun = get_secure_words()
    readable_part = f"{adj1}-{adj2}-{noun}"
    random_hex = secrets.token_hex(12)
    timestamp = datetime.now(timezone.utc).isoformat().encode()
    nonce = secrets.token_bytes(8)
    combined = timestamp + nonce + random_hex.encode()
    unique_hash = hashlib.blake2b(combined, digest_size=8).hexdigest()
    token = f"{readable_part}-{random_hex}-{unique_hash}"

    if not MIN_TOKEN_LENGTH <= len(token) <= MAX_TOKEN_LENGTH:
        raise ValueError("Generated token length outside acceptable range")
    return token

def save_to_auth_file(token: str, filename: str = ".auth_token_tgi") -> bool:
    """Save token to auth token file in a shell-sourceable format."""
    auth_path = Path(filename)
    try:
        auth_path.write_text(f'export VALID_TOKEN="{token}"\n')
        auth_path.chmod(0o600)  # Set appropriate permissions
        return True
    except Exception as e:
        logger.error(f"Failed to write {filename} file: {e}")
        return False

def set_env_token(token: str):
    """Set the token in .env file."""
    env_path = Path(".env")
    if env_path.exists():
        content = env_path.read_text().splitlines()
        content = [line for line in content if not line.startswith("VALID_TOKEN=")]
    else:
        content = []
    content.append(f'VALID_TOKEN="{token}"')
    env_path.write_text("\n".join(content) + "\n")
    return True

def generate_and_set() -> str:
    """Generate a new token and set it in both environment and auth file."""
    token = generate_secure_token()
    
    # Set in .env file
    set_env_token(token)
    
    # Save to .auth_token_tgi file
    save_to_auth_file(token)
    
    return token

def main():
    token = generate_secure_token()
    logger.info("\nToken generated successfully:")
    logger.info("-" * 80)
    logger.info(f"Generated at: {datetime.utcnow().isoformat()}")
    logger.info(f"Token: {token}")
    logger.info("-" * 80)
    if set_env_token(token):
        logger.info("\nToken has been set in .env file!")
    save_to_auth_file(token)
    logger.info(f"Token has been saved to .auth_token_tgi file")
    logger.info("Make sure to protect this file with appropriate permissions")
    print(token)

if __name__ == "__main__":
    main()
