import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_breakpoints/flutter_breakpoints.dart';
import 'package:path_provider/path_provider.dart';
import 'package:network_tools/network_tools.dart';
import 'screens/settings_screen.dart';
import 'screens/home_screen.dart';
import 'screens/android_screen.dart';

final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.dark);
final ValueNotifier<Color> colorSeedNotifier =
    ValueNotifier<Color>(Colors.deepPurple);
final ValueNotifier<double> textScaleNotifier = ValueNotifier<double>(1.0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load persisted appearance settings
  try {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('app_theme_mode');
    if (themeIndex != null &&
        themeIndex >= 0 &&
        themeIndex < ThemeMode.values.length) {
      themeModeNotifier.value = ThemeMode.values[themeIndex];
    }
    final seedValue = prefs.getInt('app_color_seed');
    if (seedValue != null) {
      colorSeedNotifier.value = Color(seedValue);
    }
    final ts = prefs.getDouble('app_text_scale');
    if (ts != null) {
      textScaleNotifier.value = ts.clamp(.8, 1.6);
    }
  } catch (_) {}

  // Configure network tools - required for network_tools package
  try {
    final appDocDirectory = await getApplicationDocumentsDirectory();
    await configureNetworkTools(appDocDirectory.path, enableDebugging: true);
    print('Network tools configured with path: \\${appDocDirectory.path}');
  } catch (e) {
    print('Failed to get app directory, using fallback: $e');
    // Fallback configuration if path_provider fails
    await configureNetworkTools('', enableDebugging: true);
  }

  // Determine the splash image to use
  final splashImages = [
    'assets/splash_1.jpg',
    'assets/splash_2.jpg',
    'assets/splash_3.jpg',
  ];
  final random = Random();
  final splashImage = splashImages[random.nextInt(splashImages.length)];

  runApp(MyApp(splashImage: splashImage));
}

class MyApp extends StatelessWidget {
  final String? splashImage;

  const MyApp({super.key, this.splashImage});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return ValueListenableBuilder<Color>(
          valueListenable: colorSeedNotifier,
          builder: (context, seed, _) {
            return ValueListenableBuilder<double>(
              valueListenable: textScaleNotifier,
              builder: (context, scale, _) {
                return FlutterBreakpointProvider.builder(
                  context: context,
                  child: MaterialApp(
                    title: 'LitterBox',
                    theme: ThemeData(
                      colorScheme: ColorScheme.fromSeed(
                          seedColor: seed, brightness: Brightness.light),
                      useMaterial3: true,
                    ),
                    darkTheme: ThemeData(
                      colorScheme: ColorScheme.fromSeed(
                          seedColor: seed, brightness: Brightness.dark),
                      useMaterial3: true,
                    ),
                    themeMode: mode,
                    builder: (context, child) {
                      return MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: child ?? const SizedBox.shrink(),
                      );
                    },
                    home: SplashScreen(
                        splashImage: splashImage ?? 'assets/splash_1.jpg'),
                    routes: {
                      '/settings': (context) => const SettingsScreen(),
                      '/home': (context) => const HomeScreen(),
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  final String? splashImage;

  const SplashScreen({super.key, this.splashImage});

  @override
  Widget build(BuildContext context) {
    // Navigate to the main screen after a delay
    Timer(const Duration(seconds: 3), () async {
      String route = '/home';
      try {
        final prefs = await SharedPreferences.getInstance();
        final startup = prefs.getString('startup_page');
        if (startup == 'android')
          route = '/android';
        else if (startup == 'settings') route = '/settings';
      } catch (_) {}
      if (!context.mounted) return;
      // Use named routes when possible else direct widget
      if (route == '/android') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const AndroidScreen()),
        );
      } else if (route == '/settings') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });

    return Scaffold(
      body: Center(
        child: Image.asset(splashImage ?? 'assets/splash_1.jpg'),
      ),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScreen();
  }
}
