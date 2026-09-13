import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Professional Voice Recognition Service tuned for North Indian Accent & Languages
/// Supports Hindi (hi_IN), Indian English (en_IN), and Multilingual Hinglish.
class VoiceRecognitionService {
  static final VoiceRecognitionService _instance = VoiceRecognitionService._internal();
  factory VoiceRecognitionService() => _instance;
  VoiceRecognitionService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  bool get isListening => _speech.isListening;

  // Selected Speech Locale ('hi_IN' for Hindi, 'en_IN' for Indian English)
  String currentLocaleId = 'hi_IN';

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      currentLocaleId = prefs.getString('pos_voice_locale') ?? 'hi_IN';
      _isInitialized = await _speech.initialize(
        onError: (err) => debugPrint("Speech recognition error: ${err.errorMsg}"),
        onStatus: (status) => debugPrint("Speech recognition status: $status"),
      );
    } catch (e) {
      debugPrint("VoiceRecognitionService init exception: $e");
      _isInitialized = false;
    }
  }

  Future<void> setLocale(String localeId) async {
    currentLocaleId = localeId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pos_voice_locale', localeId);
  }

  /// Open Voice Naming Modal Sheet with live transcription & North Indian language toggle
  static Future<String?> showVoiceInputSheet(
    BuildContext context, {
    String? currentText,
    String? initialText,
    String title = "Speak Item Name",
  }) async {
    final service = VoiceRecognitionService();
    await service.init();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VoiceInputModalSheet(
        service: service,
        initialText: initialText ?? currentText ?? "",
        title: title,
      ),
    );
  }
}

class _VoiceInputModalSheet extends StatefulWidget {
  final VoiceRecognitionService service;
  final String initialText;
  final String title;

  const _VoiceInputModalSheet({
    Key? key,
    required this.service,
    required this.initialText,
    required this.title,
  }) : super(key: key);

  @override
  State<_VoiceInputModalSheet> createState() => _VoiceInputModalSheetState();
}

class _VoiceInputModalSheetState extends State<_VoiceInputModalSheet> with SingleTickerProviderStateMixin {
  late TextEditingController _textCtrl;
  bool _isListening = false;
  double _soundLevel = 0.0;
  String _activeLocale = 'hi_IN';
  late AnimationController _pulseAnim;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText);
    _activeLocale = widget.service.currentLocaleId;

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Auto-start listening on sheet open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startListening();
    });
  }

  @override
  void dispose() {
    _pulseAnim.dispose();
    widget.service._speech.stop();
    _textCtrl.dispose();
    super.dispose();
  }

  void _startListening() async {
    if (!widget.service.isInitialized) {
      final available = await widget.service._speech.initialize();
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Microphone or Speech Recognition unavailable on this device")),
          );
        }
        return;
      }
    }

    setState(() => _isListening = true);

    try {
      await widget.service._speech.listen(
        localeId: _activeLocale,
        onSoundLevelChange: (level) {
          if (mounted) setState(() => _soundLevel = level);
        },
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: false,
          partialResults: true,
          listenMode: stt.ListenMode.dictation,
        ),
        onResult: (result) {
          if (mounted) {
            setState(() {
              _textCtrl.text = _formatSpokenText(result.recognizedWords);
            });
          }
        },
      );
    } catch (e) {
      debugPrint("Error starting voice recognition: $e");
    }
  }

  void _stopListening() async {
    await widget.service._speech.stop();
    if (mounted) setState(() => _isListening = false);
  }

  String _formatSpokenText(String text) {
    if (text.isEmpty) return text;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;
    // Capitalize first letter of words if English
    if (_activeLocale.startsWith('en')) {
      return trimmed.split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isHindi = _activeLocale == 'hi_IN';

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header Row with North Indian Accent / Language Switcher
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              // Language Switcher (हिन्दी vs English-IN)
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLangChip(
                      label: "हिन्दी",
                      selected: isHindi,
                      onTap: () {
                        setState(() => _activeLocale = 'hi_IN');
                        widget.service.setLocale('hi_IN');
                        _stopListening();
                        _startListening();
                      },
                    ),
                    _buildLangChip(
                      label: "English (IN)",
                      selected: !isHindi,
                      onTap: () {
                        setState(() => _activeLocale = 'en_IN');
                        widget.service.setLocale('en_IN');
                        _stopListening();
                        _startListening();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Microphone Visualizer
          GestureDetector(
            onTap: () {
              if (_isListening) {
                _stopListening();
              } else {
                _startListening();
              }
            },
            child: AnimatedBuilder(
              animation: _pulseAnim,
              builder: (context, child) {
                final scale = _isListening ? 1.0 + (_pulseAnim.value * 0.12) + (_soundLevel * 0.05).clamp(0.0, 0.2) : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isListening
                            ? [const Color(0xFFEF4444), const Color(0xFFF97316)]
                            : [const Color(0xFF2563EB), const Color(0xFF3B82F6)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? const Color(0xFFEF4444) : const Color(0xFF2563EB)).withOpacity(0.35),
                          blurRadius: _isListening ? 16 : 8,
                          spreadRadius: _isListening ? 4 : 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isListening ? (isHindi ? "बोलिए... (सुन रहे हैं)" : "Listening... (North Indian Accent)") : "Tap Mic to Speak",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _isListening ? const Color(0xFFDC2626) : Colors.black54,
            ),
          ),
          const SizedBox(height: 18),

          // Transcribed Text Field
          TextField(
            controller: _textCtrl,
            autofocus: false,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: isHindi ? "जैसे: चूड़ियां 2.6, काजल, रजिस्टर..." : "e.g. Bangles 2.6, Kajal, Register...",
              prefixIcon: const Icon(Icons.edit_note, color: Colors.blueAccent),
              suffixIcon: _textCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () => setState(() => _textCtrl.clear()),
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons: Done / Cancel
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _stopListening();
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: const Text("Use Name", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    _stopListening();
                    final name = _textCtrl.text.trim();
                    Navigator.pop(context, name.isNotEmpty ? name : null);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLangChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E293B) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
