import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/sets_screen.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.load();
  runApp(const GermanWordsApp());
}

class GermanWordsApp extends StatelessWidget {
  const GermanWordsApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Перестраиваем приложение при смене настроек (тема).
    return AnimatedBuilder(
      animation: AppSettings.instance,
      builder: (context, _) {
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
          themeMode: AppSettings.instance.themeMode,
          locale: const Locale('ru'),
          supportedLocales: const [Locale('ru'), Locale('de')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SetsScreen(),
        );
      },
    );
  }
}
