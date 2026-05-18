# Firestore Schema Design

## Collection Structure

```
users/{userId}
  - email: string
  - name: string
  - role: "user" | "admin"
  - created_at: timestamp

  meetings/{meetingId}                    # subcollection
    - room_name: string
    - title: string
    - status: "created" | "live" | "bot_joining" | "recording" | "processing" | "completed" | "failed"
    - user_id: string
    - created_at: timestamp
    - summary: string (when completed)
    - participants: array
    - topics: array
    - decisions: array
    - action_items: array
    - transcript: array
    - clean_transcript: string
    - raw_transcript: string
    - metadata: map

    transcripts/{docId}                   # subcollection
      - segments: array [{ start, end, speaker, text }]
      - text: string (raw transcript)

    transcripts/clean                      # subcollection
      - text: string (clean transcript)

    action_items/{docId}                  # subcollection
      - task: string
      - description: string
      - owner: string
      - deadline: string

admin/{docId}                             # admin-only
  - (dashboard config, analytics, etc.)
```

## Indexes

Create composite indexes for common queries:

- `users/{userId}/meetings`: `created_at` DESC (meeting history)
- `users/{userId}/meetings`: `status` + `created_at` (filter by status)

## Example Document

```json
{
  "users/abc123/meetings/room1_20250210_1200": {
    "room_name": "room1",
    "title": "Project Sync",
    "status": "completed",
    "user_id": "abc123",
    "created_at": "2025-02-10T12:00:00Z",
    "summary": "Meeting summary...",
    "participants": [{"name": "Speaker 1"}, {"name": "Speaker 2"}],
    "topics": [{"title": "Topic 1", "summary": "..."}],
    "decisions": [{"text": "We agreed to..."}],
    "action_items": [
      {"task": "Send report", "owner": "John", "deadline": "by next week"}
    ],
    "transcript": [
      {"start": 0.0, "end": 2.5, "speaker": "Speaker 1", "text": "Hello..."}
    ]
  }
}
```
