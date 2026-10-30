# Amar Hisab Mobile

Flutter Android application for the existing Amar Hisab project.

## Architecture
- Flutter app lives in this `mobile/` directory.
- Uses the existing Amar Hisab Express API and PostgreSQL backend.
- Local offline storage and automatic synchronization will be added in a later phase.
- Keep Android work on the `android-flutter` branch. Do not merge into `main` until tested and approved.

## Local setup
From this directory, run:

```powershell
flutter create --project-name amar_hisab_mobile --platforms android .
.\scripts\set-app-name.ps1
flutter pub get
flutter run
```

This generates the native Android platform files in this directory while retaining the app source. Review generated changes before committing.
