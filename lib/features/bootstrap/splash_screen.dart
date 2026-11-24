import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shown for the moment it takes to read the keystore and decide whether this handset is paired
/// and whether anyone is signed in.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant_menu_rounded, size: 56, color: MeedColors.brand),
              SizedBox(height: 20),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      );
}
