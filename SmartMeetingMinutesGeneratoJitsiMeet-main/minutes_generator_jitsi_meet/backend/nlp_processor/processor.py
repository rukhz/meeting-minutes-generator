"""
NLP Processor (Module 4): Cleans raw transcript, removes filler words,
sentence segmentation, speaker normalization.
Outputs clean, structured transcript.
"""
import re
import logging
from typing import Any

logger = logging.getLogger(__name__)

try:
    import spacy
    _nlp = spacy.load("en_core_web_sm")
except Exception:
    _nlp = None

FILLER_WORDS = {
    "um", "uh", "er", "ah", "like", "you know", "i mean", "basically",
    "actually", "literally", "honestly", "so", "well", "right", "okay",
    "hmm", "hm", "eh", "yeah", "yep", "nope",
}


def remove_fillers(text: str) -> str:
    """Remove common filler words and noise."""
    if not text or not isinstance(text, str):
        return ""
    t = text.strip()
    words = t.split()
    cleaned = []
    for w in words:
        w_lower = w.lower().strip(".,;:!?")
        if w_lower not in FILLER_WORDS and len(w_lower) > 1:
            cleaned.append(w)
    return " ".join(cleaned)


def split_sentences(text: str) -> list[str]:
    """Split text into sentences using spaCy or regex fallback."""
    if not text:
        return []
    if _nlp:
        try:
            doc = _nlp(text)
            return [s.text.strip() for s in doc.sents if s.text.strip()]
        except Exception as e:
            logger.warning("spaCy sentence split failed: %s", e)
    cleaned = re.sub(r"\s+", " ", text).strip()
    if not cleaned:
        return []
    parts = re.split(r"(?<=[.!?])\s+", cleaned)
    return [p.strip() for p in parts if p.strip()]


def normalize_speaker_label(label: str) -> str:
    """Normalize speaker labels (e.g. SPEAKER_00 -> Speaker 1)."""
    if not label:
        return "Speaker 1"
    if label.upper().startswith("SPEAKER_"):
        try:
            idx = int(label.split("_")[-1])
            return f"Speaker {idx + 1}"
        except (ValueError, IndexError):
            pass
    return label


def process_transcript(raw: dict[str, Any]) -> dict[str, Any]:
    """
    Process raw ASR output into clean transcript.
    Input: { "text": str, "segments": [{ "start", "end", "text" }] }
    Output: { "clean_text", "sentences", "segments" } with filler removal.
    """
    text = raw.get("text", "") or ""
    segments = raw.get("segments", [])

    clean_text = remove_fillers(text)
    sentences = split_sentences(clean_text)

    clean_segments = []
    for seg in segments:
        seg_text = seg.get("text", "") or ""
        seg_text_clean = remove_fillers(seg_text)
        if seg_text_clean:
            clean_segments.append({
                "start": seg.get("start"),
                "end": seg.get("end"),
                "text": seg_text_clean,
            })

    return {
        "clean_text": clean_text,
        "sentences": sentences,
        "segments": clean_segments,
        "raw_text": text,
    }
