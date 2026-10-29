# TEAMIX home preview

This branch launches directly into the native Flutter groups home, bypassing authentication and Firebase initialization. Firebase configuration files and dependencies are retained. Restore initialization before connecting real backend features.

- Pastel rounded joined-group cards (2), followed by one pending-group card.
- At most two demo activity summaries per group; all group/activity content is mock data.
- Circular add/account actions, no bottom navigation.
- Add opens a preview action sheet; create/join/detail flows are not implemented and show explicit preview messages.
- Account opens a preview sheet with a switch between populated and empty states.
- Uses device status/navigation bars rather than painting mock system chrome.
- No bundled Pretendard font: font fallback depends on the device, so typography may differ from the SVG reference.

Run locally: `flutter pub get`, `flutter run`.
Check locally: `flutter analyze`, `flutter test`.
Flutter execution was not available during authoring; tests are included but have not been run.
