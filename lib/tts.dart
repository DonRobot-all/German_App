import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'settings.dart';

/// Озвучка немецких слов системным синтезатором речи.
class Speaker {
  Speaker._();
  static final Speaker instance = Speaker._();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _failed = false;

  Future<void> _init() async {
    if (_ready || _failed) return;
    try {
      await _tts.setLanguage('de-DE');
      _ready = true;
    } catch (_) {
      _failed = true;
    }
  }

  Future<void> speak(String text) async {
    await _init();
    if (!_ready) return;
    try {
      await _tts.setSpeechRate(AppSettings.instance.speechRate);
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Нет синтезатора или немецкого голоса: тихо ничего не делаем.
    }
  }
}

/// Кнопка «произнести». При [autoPlay] и включённой автоозвучке слово
/// произносится сразу, как только кнопка появилась на экране.
class SpeakButton extends StatefulWidget {
  const SpeakButton({
    super.key,
    required this.text,
    this.autoPlay = false,
    this.size = 24,
  });

  final String text;
  final bool autoPlay;
  final double size;

  @override
  State<SpeakButton> createState() => _SpeakButtonState();
}

class _SpeakButtonState extends State<SpeakButton> {
  @override
  void initState() {
    super.initState();
    if (widget.autoPlay && AppSettings.instance.autoSpeak) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Speaker.instance.speak(widget.text);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Произнести',
      iconSize: widget.size,
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.volume_up_outlined),
      onPressed: () => Speaker.instance.speak(widget.text),
    );
  }
}
