# TEAMIX onboarding — B style

Branch: feature/pastel-onboarding. Existing Firebase options and platform settings are unchanged.

## Implemented
- Responsive centered mobile layout (maximum content width 440), pastel mint / butter / lilac panels and coral primary actions.
- Welcome, email signup, confirmation password, temporary terms, email login, password reset, logout.
- Firebase Authentication email/password calls are REAL. Use test accounts only; enable Email/Password in the Firebase console.
- Nickname saved to Firebase Auth displayName. No extra name/MBTI/personality survey.
- Invite code TEAM24 opens a clearly labelled demo community confirmation.
- Create-community form: name, introduction, selectable default symbol, up to two categories including custom input, join mode.
- Stops before the community home.

## Not implemented (do not treat as production)
Firestore persistence, membership routing, real invite verification/redemption, pending approvals, deep-link preservation, photo upload, home screens, consent record persistence, final legal texts. Community creation/joining and owner assignment are UI demonstrations only. Membership/invite operations need an appropriate Firestore schema and security rules or callable Functions before real data is enabled. Private placement preferences must never be exposed to owners/admins.

## Verify locally
1. flutter pub get
2. dart format lib/main.dart lib/onboarding.dart
3. flutter analyze
4. flutter run -d chrome
5. Exercise signup, duplicate email, wrong password, reset email, logout; use only test accounts.
6. Enter TEAM24 and confirm the demo; create a community with custom category; test validation and narrow viewport/keyboard.

Flutter/Dart execution was unavailable during authoring; compilation and visual rendering have not been verified. Paste any analyzer/runtime errors for correction. Existing default counter widget test must be updated when introducing new tests; it no longer represents the app. Firebase initialization failures occur before the UI and need the existing project configuration to be valid.
