Flutter client for Taller de Motos Moreira

Quick start

Prerequisites:
- Flutter SDK installed
- Android emulator or iOS simulator

From this folder:

```powershell
cd c:\backend\flutter_app
flutter pub get
flutter run
```

Notes about backend
- When running on Android emulator, set `BASE_URL = http://10.0.2.2:3000` (the app already uses this by default in `main.dart`).
- On iOS simulator use `http://localhost:3000`.
- For a physical device, use your machine IP (e.g. `http://192.168.x.y:3000`).

Included files
- `lib/services/api_client.dart` - simple API client using `dio`
- `lib/models/moto.dart` - Moto model
- `lib/screens` - minimal screens: list and detail

Next steps
- Add services list and invoice generation UI
- Add authentication if needed
