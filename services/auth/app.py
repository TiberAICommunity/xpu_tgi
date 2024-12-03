import logging
import os
import time
from collections import defaultdict
from typing import Dict, Optional

from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

app = FastAPI(title="TGI Auth Service", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - [%(name)s] %(message)s"
)
logger = logging.getLogger(__name__)

VALID_TOKEN = os.getenv("VALID_TOKEN")
if not VALID_TOKEN:
    raise RuntimeError("VALID_TOKEN environment variable not set")
MAX_FAILED_ATTEMPTS = 5
BAN_DURATION = 300
FAILED_ATTEMPT_RESET = 1800
failed_attempts: Dict[str, int] = defaultdict(int)
ban_timestamps: Dict[str, float] = {}
last_attempt_timestamps: Dict[str, float] = {}


def is_ip_banned(ip: str) -> bool:
    if ip in ban_timestamps:
        if time.time() - ban_timestamps[ip] > BAN_DURATION:
            del ban_timestamps[ip]
            del failed_attempts[ip]
            return False
        return True
    return False


def update_failed_attempts(ip: str) -> None:
    current_time = time.time()
    if ip in last_attempt_timestamps:
        if current_time - last_attempt_timestamps[ip] > FAILED_ATTEMPT_RESET:
            failed_attempts[ip] = 0
    failed_attempts[ip] += 1
    last_attempt_timestamps[ip] = current_time
    if failed_attempts[ip] >= MAX_FAILED_ATTEMPTS:
        ban_timestamps[ip] = current_time
        logger.warning(f"IP {ip} has been banned due to too many failed attempts")


def reset_failed_attempts(ip: str) -> None:
    """Reset failed attempts for an IP after successful authentication"""
    if ip in failed_attempts:
        del failed_attempts[ip]
    if ip in last_attempt_timestamps:
        del last_attempt_timestamps[ip]
    logger.info(f"Reset failed attempts for IP {ip} after successful authentication")


@app.middleware("http")
async def ban_middleware(request: Request, call_next):
    client_ip = request.client.host
    if is_ip_banned(client_ip):
        logger.warning(f"Rejected request from banned IP: {client_ip}")
        return JSONResponse(
            status_code=403,
            content={"detail": "Too many failed attempts. Please try again later."},
        )

    return await call_next(request)


@app.get("/validate")
async def validate_token(request: Request, authorization: Optional[str] = Header(None)):
    client_ip = request.client.host
    try:
        if not authorization:
            return JSONResponse(
                status_code=401,
                content={
                    "detail": "No authorization provided",
                    "message": "Please provide a Bearer token in the Authorization header",
                    "example": "Authorization: Bearer your_token_here"
                }
            )

        if not authorization.startswith("Bearer "):
            logger.warning(f"Invalid authorization header format from IP: {client_ip}")
            update_failed_attempts(client_ip)
            return JSONResponse(
                status_code=401,
                content={
                    "detail": "Invalid authorization format",
                    "message": "Authorization header must start with 'Bearer '",
                    "example": "Authorization: Bearer your_token_here"
                }
            )
        
        token = authorization.split(" ")[1]
        if token != VALID_TOKEN:
            logger.warning(f"Invalid token attempt from IP: {client_ip}")
            update_failed_attempts(client_ip)
            return JSONResponse(
                status_code=401,
                content={
                    "detail": "Invalid token",
                    "message": "The provided token is not valid"
                }
            )

        reset_failed_attempts(client_ip)
        return JSONResponse(
            content={
                "status": "valid",
                "message": "Token is valid",
                "client_ip": client_ip
            },
            headers={"X-Auth-Status": "valid", "X-Real-IP": client_ip},
        )
        
    except Exception as e:
        logger.error(f"Error processing request from {client_ip}: {str(e)}")
        return JSONResponse(
            status_code=500,
            content={
                "detail": "Internal server error",
                "message": str(e) if app.debug else "An unexpected error occurred"
            }
        )


@app.get("/health")
async def health_check():
    return {"status": "healthy"}
