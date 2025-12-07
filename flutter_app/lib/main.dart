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
        useMaterial3: false,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF6D3BFF),
          secondary: const Color(0xFFFFB86B),
          surface: const Color(0xFF2F3438),
          background: const Color(0xFF222528),
        ),
        scaffoldBackgroundColor: const Color(0xFF1F2224),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF26292B),
          foregroundColor: Colors.white,
          elevation: 1,
          centerTitle: false,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF2B2F33),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        ),
        listTileTheme: const ListTileThemeData(
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        textTheme: ThemeData.dark()
            .textTheme
            .apply(bodyColor: Colors.white70, displayColor: Colors.white70),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
            backgroundColor: const Color(0xFF6D3BFF),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF26292B),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: Color(0xFF6D3BFF)),
      ),
      home: MainScreen(apiClient: apiClient),
    );
  }
}
