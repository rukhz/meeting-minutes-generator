# Firebase Setup for Smart Meeting Minutes

This app uses Firebase for:
- **Authentication** – Login/Register (passwords stored securely in Firebase Auth)
- **Realtime Database** – User profiles, meeting minutes
- **Storage** – MP4 recordings (uploaded when user is logged in)

## What You Need

### 1. Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project (or use existing)
3. Add an Android app with your package name: `com.example.smartmeetingminutesgeneratojitsimeet`
4. Download `google-services.json` and place it in:
   ```
   Smartmeetingminutesgeneratojitsimeet/android/app/google-services.json
   ```

### 2. Enable Firebase Services

In Firebase Console:

- **Authentication** → Sign-in method → Enable **Email/Password**
- **Realtime Database** → Create database (start in test mode for development)
- **Storage** → Get started (start in test mode for development)

### 3. Realtime Database Rules

Example rules for development (in Firebase Console → Realtime Database → Rules):

```json
{
  "rules": {
    "users": {
      "$uid": {
        ".read": "$uid === auth.uid",
        ".write": "$uid === auth.uid"
      }
    }
  }
}
```

### 4. Storage Rules

Example rules (Firebase Console → Storage → Rules):

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /recordings/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### 5. Optional: FlutterFire CLI

For easier setup and iOS support, run from the Flutter app directory:

```bash
dart pub global activate flutterfire_cli
cd Smartmeetingminutesgeneratojitsimeet
flutterfire configure
```

This creates `firebase_options.dart` and configures platforms. If you use this, you may need to update `main.dart` to use `DefaultFirebaseOptions.currentPlatform` when calling `Firebase.initializeApp()`.

## Data Structure (Realtime Database)

```
users/{uid}
  - email: string
  - displayName: string
  - createdAt: timestamp

users/{uid}/meetings/{meetingId}
  - roomName: string
  - minutes: object (summary, transcript, topics, decisions, action_items, etc.)
  - recordingStorageUrl: string (Firebase Storage download URL)
  - participants: array
  - createdAt: timestamp
```

## Flow

1. **Register** – Creates user in Firebase Auth; saves profile to Realtime DB (email, displayName)
2. **Login** – Uses Firebase Auth (no passwords stored in Realtime DB)
3. **Meeting end** – If user is logged in: uploads MP4 to Storage, saves minutes + recording URL to Realtime DB
4. **Generate Minutes** – Same cloud save when user is logged in

## Troubleshooting

- **"No Firebase App"** – Ensure `google-services.json` is in `android/app/` and `Firebase.initializeApp()` runs in `main()` before `runApp()`
- **Permission denied** – Check Realtime DB and Storage rules allow authenticated users
- **Upload fails** – Verify Storage is enabled and rules allow `recordings/{userId}/*`
