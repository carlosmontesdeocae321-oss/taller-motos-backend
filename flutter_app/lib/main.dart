import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'services/api_client.dart';
import 'screens/main_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Determine base URL depending on platform:
    // - Android emulator: 10.0.2.2
    // - Web / Desktop (Windows/macOS/Linux): localhost
    String baseUrl;
    if (kIsWeb) {
      baseUrl = 'http://localhost:3000';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      baseUrl = 'http://10.0.2.2:3000';
    } else {
      baseUrl = 'http://localhost:3000';
    }

    final apiClient = ApiClient(baseUrl);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Moreira Taller',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF2B2F33), // slightly dark
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFF232629),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF33373B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          margin: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        ),
        textTheme: ThemeData.dark()
            .textTheme
            .apply(bodyColor: Colors.white70, displayColor: Colors.white70),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            backgroundColor: Colors.deepPurple,
          ),
        ),
      ),
      home: MainScreen(apiClient: apiClient),
    );
  }
}
