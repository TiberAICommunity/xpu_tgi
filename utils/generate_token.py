#!/usr/bin/env python3

import hashlib
import logging
import secrets
import time
from datetime import UTC, datetime
from pathlib import Path

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

ADJECTIVES = [
    "swift",
    "bright",
    "unique",
    "calm",
    "deep",
    "bold",
    "wise",
    "kind",
    "pure",
    "humble",
    "warm",
    "cool",
    "fresh",
    "clear",
    "radiant",
    "keen",
    "firm",
    "true",
]

NOUNS = [
    "wave",
    "star",
    "moon",
    "sun",
    "wind",
    "tree",
    "lake",
    "bird",
    "cloud",
    "rose",
    "light",
    "peak",
    "rain",
    "leaf",
    "seed",
    "song",
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

    # Rate limiting
    current_time = time.time()
    if current_time - last_generation_time < GENERATION_COOLDOWN:
        raise ValueError("Token generation too frequent")
    last_generation_time = current_time
    adj1, adj2, noun = get_secure_words()
    readable_part = f"{adj1}-{adj2}-{noun}"
    random_hex = secrets.token_hex(12)  # unrahul: could be more
    timestamp = datetime.now(UTC).isoformat().encode()
    nonce = secrets.token_bytes(8)
    combined = timestamp + nonce + random_hex.encode()
    unique_hash = hashlib.blake2b(combined, digest_size=8).hexdigest()
    token = f"{readable_part}-{random_hex}-{unique_hash}"
    if not MIN_TOKEN_LENGTH <= len(token) <= MAX_TOKEN_LENGTH:
        raise ValueError("Generated token length outside acceptable range")

    return token


def save_to_auth_file(token: str) -> bool:
    """Save token to .auth_token file."""
    auth_path = Path(".auth_token")
    try:
        auth_path.write_text(token)
        return True
    except Exception as e:
        logger.error(f"Failed to write .auth_token file: {e}")
        return False


def set_env_token(token: str):
    """Set the token in .env file."""
    env_path = Path(".env")
    if env_path.exists():
        content = env_path.read_text().splitlines()
        content = [line for line in content if not line.startswith("VALID_TOKEN=")]
    else:
        content = []

    content.append(f"VALID_TOKEN={token}")
    env_path.write_text("\n".join(content) + "\n")
    return True


def prompt_user_for_auth_file() -> bool:
    """Prompt user about creating .auth_token file."""
    logger.warning("\nSecurity Notice:")
    logger.warning("You can save the token to .auth_token file for automatic loading.")
    logger.warning("However, please be aware that:")
    logger.warning("1. This file will contain your authentication token in plain text")
    logger.warning("2. Anyone with access to this file can use your token")
    logger.warning(
        "3. Consider using environment variables for production environments"
    )

    while True:
        response = input(
            "\nDo you want to save the token to .auth_token? (yes/no): "
        ).lower()
        if response in ["yes", "y", "no", "n"]:
            return response in ["yes", "y"]
        logger.error("Please answer 'yes' or 'no'")


def main():
    token = generate_secure_token()
    logger.info("\nToken generated successfully:")
    logger.info("-" * 80)
    logger.info(f"Generated at: {datetime.utcnow().isoformat()}")
    logger.info(f"Token: {token}")
    logger.info("-" * 80)

    if set_env_token(token):
        logger.info("\nToken has been set in .env file!")
    if prompt_user_for_auth_file():
        if save_to_auth_file(token):
            logger.info("Token has been saved to .auth_token file")
            logger.info("Make sure to protect this file with appropriate permissions")
            Path(".auth_token").chmod(0o600)
        else:
            logger.error("Failed to save token to .auth_token file")
    logger.info("\nYou can now start any model with this token")
    print(token)


if __name__ == "__main__":
    main()
