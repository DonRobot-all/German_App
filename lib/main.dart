import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/sets_screen.dart';

void main() => runApp(const GermanWordsApp());

class GermanWordsApp extends StatelessWidget {
  const GermanWordsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Немецкие слова',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      themeMode: ThemeMode.system,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('de')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SetsScreen(),
    );
  }
}
