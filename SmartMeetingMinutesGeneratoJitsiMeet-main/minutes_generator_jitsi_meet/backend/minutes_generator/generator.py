"""
Minutes Generator (Module 5): Topic detection, decision extraction,
action items with owners and deadlines, executive summary.
Uses LLM (OpenAI) when available; fallback to rule-based extraction.
"""
import os
import re
import logging
from collections import Counter
from typing import Any, Optional

logger = logging.getLogger(__name__)

try:
    import spacy
    _nlp = spacy.load("en_core_web_sm")
except Exception:
    _nlp = None

# Stopwords for keyword extraction
STOPWORDS = {
    "the", "and", "for", "that", "this", "with", "from", "have", "will", "would",
    "there", "their", "about", "could", "should", "been", "were", "which", "into",
    "them", "they", "then", "than", "also", "very", "just", "your", "here", "when",
    "what", "where", "while", "because", "once", "after", "before", "our", "are",
    "was", "can", "we", "you", "he", "she", "it", "its", "of", "in", "on", "at",
    "to", "as", "a", "an", "or", "is", "be", "by", "so", "if", "not", "no", "yes",
}

DECISION_CUES = [
    "we decided", "final decision", "approved", "let's go with", "lets go with",
    "decided", "agreed", "concluded", "resolved", "decision",
]

ACTION_CUES = [
    "will ", "will do", "to do", "action item", "follow up", "need to", "needs to",
    "should ", "must ", "assigned to", "by tomorrow", "by next week",
]


def _extract_deadline(text: str) -> Optional[str]:
    patterns = [
        r"\bby tomorrow\b",
        r"\bby next week\b",
        r"\bby next month\b",
        r"\bby\s+([a-zA-Z0-9\-]+\s*){1,4}",
    ]
    lower = text.lower()
    for pat in patterns:
        m = re.search(pat, lower, re.I)
        if m:
            start, end = m.span()
            return text[start:end].strip()
    return None


def _extract_owner(text: str) -> Optional[str]:
    if _nlp:
        try:
            doc = _nlp(text)
            for ent in doc.ents:
                if ent.label_ == "PERSON":
                    return ent.text
        except Exception:
            pass
    tokens = re.findall(r"\b[A-Z][a-zA-Z]+\b", text)
    return tokens[0] if tokens else None


def extract_topics(sentences: list[str], max_per_topic: int = 5) -> list[dict[str, Any]]:
    """Group sentences into topics (naive block-based)."""
    topics = []
    for i in range(0, len(sentences), max_per_topic):
        block = sentences[i : i + max_per_topic]
        block_text = " ".join(block).strip()
        if block_text:
            topics.append({
                "title": f"Topic {len(topics) + 1}",
                "summary": block_text,
                "sentences": block,
            })
    return topics


def extract_decisions(sentences: list[str]) -> list[dict[str, Any]]:
    """Extract decision statements."""
    decisions = []
    for s in sentences:
        lower = s.lower()
        if any(cue in lower for cue in DECISION_CUES):
            decisions.append({"text": s})
    return decisions


def extract_action_items(sentences: list[str]) -> list[dict[str, Any]]:
    """Extract action items with owner and deadline."""
    items = []
    for s in sentences:
        lower = s.lower()
        if not any(cue in lower for cue in ACTION_CUES):
            continue
        owner = _extract_owner(s)
        deadline = _extract_deadline(s)
        items.append({
            "task": s,
            "description": s,
            "owner": owner,
            "deadline": deadline,
        })
    return items


def extract_keywords(text: str, top_n: int = 10) -> list[str]:
    """Extract keywords by frequency (excluding stopwords)."""
    words = re.findall(r"\b\w+\b", text.lower())
    filtered = [w for w in words if w not in STOPWORDS and len(w) > 3 and not w.isdigit()]
    if not filtered:
        return []
    freq = Counter(filtered)
    return [w for w, _ in freq.most_common(top_n)]


def _llm_summary(sentences: list[str]) -> Optional[str]:
    """Use OpenAI to generate executive summary if API key is set."""
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key or not sentences:
        return None
    try:
        from openai import OpenAI
        client = OpenAI(api_key=api_key)
        text = " ".join(sentences[:20])
        if not text:
            return None
        resp = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {
                    "role": "system",
                    "content": "You are a meeting assistant. Summarize the meeting transcript in 2-4 concise paragraphs as an executive summary.",
                },
                {"role": "user", "content": text[:4000]},
            ],
            max_tokens=500,
        )
        if resp.choices:
            return resp.choices[0].message.content
    except Exception as e:
        logger.warning("LLM summary failed: %s", e)
    return None


def generate_summary(sentences: list[str], max_sentences: int = 5) -> str:
    """Generate executive summary (LLM or heuristic)."""
    summary = _llm_summary(sentences)
    if summary:
        return summary
    return " ".join(sentences[:max_sentences]) if sentences else ""


def run_diarization(segments: list[dict], audio_path: Optional[str] = None) -> dict[str, Any]:
    """Speaker diarization (pyannote when available, else single speaker)."""
    try:
        from pyannote.audio import Pipeline
        token = os.environ.get("PYANNOTE_AUTH_TOKEN", "")
        if token and audio_path:
            pipeline = Pipeline.from_pretrained(
                "pyannote/speaker-diarization",
                use_auth_token=token,
            )
            diar = pipeline(audio_path)
            speakers = set()
            labeled = []
            for turn, _, label in diar.itertracks(yield_label=True):
                spk = f"Speaker {int(label.split('_')[-1]) + 1}" if "SPEAKER_" in str(label).upper() else str(label)
                speakers.add(spk)
                for seg in segments:
                    s, e = seg.get("start"), seg.get("end")
                    if s is not None and e is not None:
                        if not (e <= turn.start or s >= turn.end):
                            labeled.append({**seg, "speaker": spk})
                            break
            return {"speakers": sorted(speakers), "segments": labeled}
    except Exception as e:
        logger.warning("Diarization failed: %s", e)
    speakers = ["Speaker 1"]
    labeled = [{**s, "speaker": "Speaker 1"} for s in segments]
    return {"speakers": speakers, "segments": labeled}


def _map_speakers_to_real_names(
    diar: dict[str, Any],
    participant_list: list[dict],
) -> tuple[dict[str, str], list[str]]:
    """
    Map diarization labels (Speaker 1, Speaker 2, ...) to real participant names.
    Uses speaking order (first appearance) and participant count alignment.
    Returns (speaker_to_name, list of names used for participants).
    """
    participant_names = [p.get("name", "").strip() or "Participant" for p in participant_list if p.get("name")]
    if not participant_names:
        speakers = diar.get("speakers", [])
        return {s: s for s in speakers}, list(speakers)

    segments = diar.get("segments", [])
    order_of_first_appearance = []
    seen = set()
    for seg in segments:
        spk = seg.get("speaker") or "Speaker 1"
        if spk not in seen:
            seen.add(spk)
            order_of_first_appearance.append(spk)

    speaker_to_name = {}
    for i, spk in enumerate(order_of_first_appearance):
        if i < len(participant_names):
            speaker_to_name[spk] = participant_names[i]
        else:
            speaker_to_name[spk] = spk

    for spk in diar.get("speakers", []):
        if spk not in speaker_to_name:
            speaker_to_name[spk] = spk

    names_used = [speaker_to_name.get(s, s) for s in order_of_first_appearance]
    if not names_used and participant_names:
        names_used = participant_names[: len(diar.get("speakers", []))]
    return speaker_to_name, names_used


def generate_minutes(
    clean_transcript: dict[str, Any],
    audio_path: Optional[str] = None,
    participant_list: Optional[list[dict]] = None,
) -> dict[str, Any]:
    """
    Generate full meeting minutes JSON.
    Input: process_transcript() output.
    participant_list: optional [{"id": "...", "name": "..."}] from Jitsi for real names.
    Output: structured minutes with real participant names when provided.
    """
    from datetime import datetime

    sentences = clean_transcript.get("sentences", [])
    segments = clean_transcript.get("segments", [])
    clean_text = clean_transcript.get("clean_text", "")

    topics = extract_topics(sentences)
    decisions = extract_decisions(sentences)
    action_items = extract_action_items(sentences)
    keywords = extract_keywords(clean_text)
    summary = generate_summary(sentences)

    diar = run_diarization(segments, audio_path)
    participant_list = participant_list or []
    speaker_to_name, names_used = _map_speakers_to_real_names(diar, participant_list)

    participants = [{"name": n} for n in names_used] if names_used else [{"name": n} for n in diar.get("speakers", [])]

    transcript_entries = []
    for s in diar.get("segments", []):
        spk = s.get("speaker", "Speaker 1")
        real_name = speaker_to_name.get(spk, spk)
        transcript_entries.append({
            "start": s.get("start"),
            "end": s.get("end"),
            "speaker": real_name,
            "text": s.get("text", ""),
            "timestamp": _format_timestamp(s.get("start"), s.get("end")),
        })

    action_items_with_names = []
    for item in action_items:
        owner = item.get("owner")
        if owner and isinstance(owner, str) and (owner.startswith("Speaker ") or owner in speaker_to_name):
            owner = speaker_to_name.get(owner, owner)
        action_items_with_names.append({**item, "owner": owner})

    return {
        "meeting_date": datetime.utcnow().strftime("%Y-%m-%d"),
        "participants": participants,
        "topics": topics,
        "decisions": decisions,
        "action_items": action_items_with_names,
        "summary": summary,
        "transcript": transcript_entries,
        "metadata": {
            "generated_at": datetime.utcnow().isoformat() + "Z",
            "keywords": keywords,
        },
    }


def _format_timestamp(start: Any, end: Any) -> str:
    """Format start/end as a readable timestamp string."""
    if start is None and end is None:
        return ""
    try:
        s = float(start) if start is not None else 0.0
        e = float(end) if end is not None else 0.0
        return f"{s:.1f}s – {e:.1f}s"
    except (TypeError, ValueError):
        return ""
