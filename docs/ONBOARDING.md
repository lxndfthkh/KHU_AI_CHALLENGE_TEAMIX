# TEAMIX pre-home onboarding

Updated existing lib/onboarding.dart in place for the v7 flow. main.dart and Firebase platform configuration remain unchanged. No separate v7 app or home screen is introduced.

## Changes
- Signup: terms first, then minimum account information and password confirmation.
- Startup checks Firebase auth state. Web ?invite=TEAM24 survives screen navigation during authentication in memory.
- Invitation fixtures: TEAM24 = valid; other codes = invalid/expired. Already joined and already pending are checked against session demo membership.
- Preview displays name, description and illustrative headcount; request creates pending status, never immediate membership. Cancel/error/duplicate/success clear pending invite.
- Existing membership/pending status routes to a labelled pre-Mainhome boundary, not a completed home implementation.
- Create community: creator becomes owner without approval in demo. Removed optional immediate-join setting: participants always request approval per v7. Followed by invitation-sharing placeholder with skip.
- Kept password reset, category custom input, palette and existing TeamixApp entry class.

## Scope
Auth calls are REAL; enable email/password in Firebase and use test accounts. Terms are placeholder; consent persistence is not implemented. Memberships, invitations and requests are explicit in-memory UI demonstrations, not Firestore records. The shared-link placeholder does not issue or share fake invite links.

Not yet implemented: Firestore persistence/security rules, actual approval/rejection and notification events, actual invite issuance/redemption, Android/iOS deep links, persistent invite recovery, cross-device membership query, home UI. Do not recruit real users on this prototype.

## Local checks required
flutter pub get
 dart format lib/onboarding.dart
flutter analyze
flutter run -d chrome

Verify signup order, login failure, password confirmation, TEAM24 preview/cancel/request, duplicate request, invalid code, owner creation/share skip, logout, keyboard and narrow layouts. Existing counter widget test needs updating. Flutter/Dart compiler and visual rendering were unavailable during editing; report analyzer/runtime errors for correction.
