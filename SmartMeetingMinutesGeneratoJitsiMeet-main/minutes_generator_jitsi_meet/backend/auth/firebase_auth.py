"""
Firebase ID token verification for Flask API.
Verifies Bearer tokens from Flutter Firebase Auth.
"""
import os
import logging
from functools import wraps
from flask import request, jsonify

logger = logging.getLogger(__name__)

_firebase_app = None


def _get_firebase_app():
    """Lazily initialize Firebase Admin SDK."""
    global _firebase_app
    if _firebase_app is not None:
        return _firebase_app
    try:
        import firebase_admin
        from firebase_admin import credentials

        if not firebase_admin._apps:
            cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
            if cred_path and os.path.isfile(cred_path):
                cred = credentials.Certificate(cred_path)
                _firebase_app = firebase_admin.initialize_app(cred)
            else:
                # Fallback: use default credentials (e.g. GCP env)
                _firebase_app = firebase_admin.initialize_app()
        else:
            _firebase_app = firebase_admin.get_app()
        return _firebase_app
    except Exception as e:
        logger.warning("Firebase Admin SDK not available: %s", e)
        return None


def verify_firebase_token(token: str) -> dict | None:
    """
    Verify Firebase ID token and return decoded claims.
    Returns None if verification fails.
    """
    try:
        from firebase_admin import auth

        app = _get_firebase_app()
        if app is None:
            return None
        decoded = auth.verify_id_token(token, check_revoked=True)
        return decoded
    except Exception as e:
        logger.warning("Token verification failed: %s", e)
        return None


def require_auth(f):
    """Decorator: require valid Firebase Bearer token. Injects `uid` and `claims` into kwargs."""

    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization")
        if not auth_header or not auth_header.startswith("Bearer "):
            return jsonify({"error": "Missing or invalid Authorization header"}), 401
        token = auth_header.split(" ", 1)[1]
        claims = verify_firebase_token(token)
        if claims is None:
            return jsonify({"error": "Invalid or expired token"}), 401
        kwargs["uid"] = claims.get("uid")
        kwargs["claims"] = claims
        return f(*args, **kwargs)

    return decorated


def optional_auth(f):
    """Decorator: optional auth. If valid token present, injects uid/claims; otherwise uid=None."""

    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization")
        kwargs["uid"] = None
        kwargs["claims"] = None
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ", 1)[1]
            claims = verify_firebase_token(token)
            if claims:
                kwargs["uid"] = claims.get("uid")
                kwargs["claims"] = claims
        return f(*args, **kwargs)

    return decorated
