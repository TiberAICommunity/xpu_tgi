import base64
import hashlib
import logging
import secrets
from datetime import datetime
from pathlib import Path

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def generate_secure_token() -> str:
    """Generate a cryptographically secure token."""
    random_bytes = secrets.token_bytes(32)
    timestamp = datetime.utcnow().isoformat().encode()
    combined = random_bytes + timestamp
    hashed = hashlib.sha3_256(combined).digest()
    return base64.urlsafe_b64encode(hashed).decode("utf-8").rstrip("=")


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


def main():
    token = generate_secure_token()
    logger.info("\nToken generated successfully:")
    logger.info("-" * 80)
    logger.info(f"Generated at: {datetime.utcnow().isoformat()}")
    logger.info(f"Token: {token}")
    logger.info("-" * 80)

    # Set in environment
    if set_env_token(token):
        logger.info("\nToken has been set in .env file!")
        logger.info("You can now start any model with this token")


if __name__ == "__main__":
    main()
