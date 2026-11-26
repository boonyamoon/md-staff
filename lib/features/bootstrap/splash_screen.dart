import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shown for the moment it takes to read the keystore and decide whether this handset is paired
/// and whether anyone is signed in.
///
/// It continues the native launch screen: the same colour, with the logo at the same size in the
/// same place, so the hand-over between the two cannot be seen. The colour is therefore the app
/// icon's and not the branch's, which nothing before this point can know.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const background = Color(0xFFFF5A10);
  static const logo = AssetImage('assets/images/splash_logo.png');

  /// Matches the iOS launch image and the Android splash icon.
  static const logoSize = 288.0;

  /// White status bar text, as over the launch screen. Only the status bar is named, so that nothing
  /// about the navigation bar outlives this screen; every screen after it has an app bar, which sets
  /// its own.
  static const statusBar = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  );

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _logoRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logoRequested) return;
    _logoRequested = true;
    // Keeps the native launch screen up until the logo is decoded, instead of showing a frame of
    // bare colour in between.
    final binding = WidgetsBinding.instance..deferFirstFrame();
    precacheImage(SplashScreen.logo, context).whenComplete(binding.allowFirstFrame);
  }

  @override
  Widget build(BuildContext context) => const AnnotatedRegion<SystemUiOverlayStyle>(
        value: SplashScreen.statusBar,
        child: Scaffold(
          backgroundColor: SplashScreen.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Image(
                  image: SplashScreen.logo,
                  width: SplashScreen.logoSize,
                  height: SplashScreen.logoSize,
                  semanticLabel: 'MeeD Staff',
                ),
              ),
              // Placed on its own so that it cannot push the logo off centre.
              Align(
                alignment: Alignment(0, 0.65),
                child: SizedBox.square(
                  dimension: 28,
                  child: CircularProgressIndicator(strokeWidth: 3, color: Color(0xFFFFF7E4)),
                ),
              ),
            ],
          ),
        ),
      );
}
