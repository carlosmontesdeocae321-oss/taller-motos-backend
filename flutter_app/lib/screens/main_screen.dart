import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import 'motos_list.dart';

class MainScreen extends StatelessWidget {
  final ApiClient apiClient;
  const MainScreen({Key? key, required this.apiClient}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget logoWidget;
    // Prefer bundled asset (works in APK and desktop). If not bundled, try loading
    // a file from the repo (useful during development on desktop).
    try {
      logoWidget = Image.asset('assets/logo.png', width: 220, height: 220, fit: BoxFit.contain);
    } catch (e) {
      final logoPath = Directory.current.path + '/../assets/logo.png';
      if (File(logoPath).existsSync()) {
        logoWidget = Image.file(File(logoPath), width: 220, height: 220, fit: BoxFit.contain);
      } else {
        logoWidget = CircleAvatar(
            radius: 80,
            backgroundColor: Colors.deepPurpleAccent,
            child: Icon(Icons.motorcycle, size: 80, color: Colors.white));
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              logoWidget,
              SizedBox(height: 24),
              Text('Taller Moreira',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Gestión de motos y servicios',
                  style: TextStyle(color: Colors.grey[700])),
              SizedBox(height: 32),
              SizedBox(
                width: 240,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.motorcycle),
                  label: Text('Gestionar Motos'),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              MotosListScreen(apiClient: apiClient))),
                ),
              ),
              SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
