"""
Firestore (Module 6): Primary database for meeting metadata, transcripts,
summaries, topics, action items. Uses subcollections where appropriate.
"""
import os
import logging
from typing import Any, Optional

logger = logging.getLogger(__name__)

_db = None


def get_db():
    """Lazily initialize Firestore client."""
    global _db
    if _db is not None:
        return _db
    try:
        import firebase_admin
        from firebase_admin import firestore

        if not firebase_admin._apps:
            cred_path = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
            if cred_path and os.path.isfile(cred_path):
                from firebase_admin import credentials
                cred = credentials.Certificate(cred_path)
                firebase_admin.initialize_app(cred)
            else:
                firebase_admin.initialize_app()
        _db = firestore.client()
        return _db
    except Exception as e:
        logger.warning("Firestore not available: %s", e)
        return None


# Collection names (Firestore schema)
USERS = "users"
MEETINGS = "meetings"
TRANSCRIPTS = "transcripts"  # subcollection under meetings
ACTION_ITEMS = "action_items"  # subcollection under meetings


def save_meeting(uid: str, meeting_id: str, data: dict[str, Any]) -> bool:
    """
    Save meeting metadata. Creates users/{uid}/meetings/{meeting_id}.
    """
    db = get_db()
    if db is None:
        return False
    try:
        ref = db.collection(USERS).document(uid).collection(MEETINGS).document(meeting_id)
        ref.set(data, merge=True)
        return True
    except Exception as e:
        logger.error("Save meeting failed: %s", e)
        return False


def get_meeting(uid: str, meeting_id: str) -> Optional[dict[str, Any]]:
    """Get meeting by user and meeting ID."""
    db = get_db()
    if db is None:
        return None
    try:
        ref = db.collection(USERS).document(uid).collection(MEETINGS).document(meeting_id)
        doc = ref.get()
        if doc.exists:
            d = doc.to_dict()
            d["id"] = doc.id
            return d
    except Exception as e:
        logger.error("Get meeting failed: %s", e)
    return None


def update_meeting_status(uid: str, meeting_id: str, status: str, extra: Optional[dict] = None) -> bool:
    """Update meeting status: live | bot_joining | recording | processing | completed | failed."""
    db = get_db()
    if db is None:
        return False
    try:
        ref = db.collection(USERS).document(uid).collection(MEETINGS).document(meeting_id)
        data = {"status": status}
        if extra:
            data.update(extra)
        ref.set(data, merge=True)
        return True
    except Exception as e:
        logger.error("Update meeting status failed: %s", e)
        return False


def save_transcript(
    uid: str,
    meeting_id: str,
    transcript: list[dict],
    clean_transcript: str = "",
    raw_transcript: str = "",
) -> bool:
    """Save transcript as subcollection document."""
    db = get_db()
    if db is None:
        return False
    try:
        ref = db.collection(USERS).document(uid).collection(MEETINGS).document(meeting_id)
        ref.collection(TRANSCRIPTS).document("raw").set({
            "segments": transcript,
            "text": raw_transcript,
        })
        ref.collection(TRANSCRIPTS).document("clean").set({
            "text": clean_transcript,
        })
        return True
    except Exception as e:
        logger.error("Save transcript failed: %s", e)
        return False


def save_action_items(uid: str, meeting_id: str, items: list[dict]) -> bool:
    """Save action items as subcollection."""
    db = get_db()
    if db is None:
        return False
    try:
        col = db.collection(USERS).document(uid).collection(MEETINGS).document(meeting_id).collection(ACTION_ITEMS)
        for i, item in enumerate(items):
            col.document(str(i)).set(item)
        return True
    except Exception as e:
        logger.error("Save action items failed: %s", e)
        return False


def save_full_minutes(uid: str, meeting_id: str, minutes: dict[str, Any]) -> bool:
    """Save full minutes to meeting doc and subcollections."""
    db = get_db()
    if db is None:
        return False
    try:
        ref = db.collection(USERS).document(uid).collection(MEETINGS).document(meeting_id)
        ref.set({
            "status": "completed",
            "summary": minutes.get("summary", ""),
            "participants": minutes.get("participants", []),
            "topics": minutes.get("topics", []),
            "decisions": minutes.get("decisions", []),
            "action_items": minutes.get("action_items", []),
            "transcript": minutes.get("transcript", []),
            "clean_transcript": minutes.get("clean_transcript", ""),
            "raw_transcript": minutes.get("raw_transcript", ""),
            "metadata": minutes.get("metadata", {}),
        }, merge=True)
        save_transcript(
            uid,
            meeting_id,
            minutes.get("transcript", []),
            clean_transcript=minutes.get("clean_transcript", ""),
            raw_transcript=minutes.get("raw_transcript", ""),
        )
        save_action_items(uid, meeting_id, minutes.get("action_items", []))
        return True
    except Exception as e:
        logger.error("Save full minutes failed: %s", e)
        return False
