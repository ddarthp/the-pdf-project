import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'core/view_preferences.dart';
import 'features/viewer/ui/viewer_screen.dart';

/// Root of The PDF Project.
class ThePdfProjectApp extends StatefulWidget {
  const ThePdfProjectApp({super.key});

  @override
  State<ThePdfProjectApp> createState() => _ThePdfProjectAppState();
}

class _ThePdfProjectAppState extends State<ThePdfProjectApp> {
  final _preferences = ViewPreferences();

  @override
  void dispose() {
    _preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _preferences,
      builder: (context, _) => MaterialApp(
        title: 'The PDF Project',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _preferences.themeMode,
        home: ViewerScreen(preferences: _preferences),
      ),
    );
  }
}
