import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, Clipboard, ClipboardData, MethodChannel;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

// ==========================================
// LOVE KUSH POS - PDF RECEIPT & WHATSAPP SERVICE
// ==========================================

/// Language options for receipts and invoices
enum ReceiptLanguage {
  hindi,
  english,
}

class PdfReceiptService {
  static const String defaultInvocation = "࿗ ॐ श्री महालक्ष्म्यै नमः ࿗";
  static const String prefKeyMantra = 'receipt_invocation_mantra';

  /// Currently configured auspicious invocation mantra
  static String currentInvocation = defaultInvocation;

  /// Curated authentic Sanskrit Mangalacharan Mantras for shopkeeper selection
  static const List<Map<String, String>> presetMantras = [
    {
      'id': 'mahalakshmi',
      'deity': 'श्री महालक्ष्मी',
      'title': 'श्री महालक्ष्मी (धन-वैभव व व्यापार)',
      'occasion': 'दुकान व व्यापार समृद्धि, नित्य पूजन',
      'mantra': '࿗ ॐ श्री महालक्ष्म्यै नमः ࿗',
    },
    {
      'id': 'durga',
      'deity': 'माँ दुर्गा',
      'title': 'माँ दुर्गा (शक्ति व रक्षा)',
      'occasion': 'दुर्गा भक्त, नवरात्रि, सर्वबाधा निवारण',
      'mantra': '࿗ ॐ दुं दुर्गायै नमः ࿗',
    },
    {
      'id': 'krishna',
      'deity': 'श्री कृष्ण',
      'title': 'श्री कृष्ण (प्रेम व भक्ति)',
      'occasion': 'जन्माष्टमी, कृष्ण भक्त, आनन्द',
      'mantra': '࿗ ॐ श्रीकृष्णाय नमः ࿗',
    },
    {
      'id': 'vasudeva',
      'deity': 'भगवान विष्णु',
      'title': 'भगवान विष्णु (वासुदेव)',
      'occasion': 'एकादशी, सत्यनारायण पूजन, शान्ति',
      'mantra': '࿗ ॐ नमो भगवते वासुदेवाय ࿗',
    },
    {
      'id': 'ganesha',
      'deity': 'श्री गणेश',
      'title': 'श्री गणेश (विघ्नहर्ता व शुभ-लाभ)',
      'occasion': 'गणेशोत्सव, कार्य सिद्धि, शुभ मुहूर्त',
      'mantra': '࿗ ॐ श्री गणेशाय नमः ࿗',
    },
    {
      'id': 'ram',
      'deity': 'श्री राम',
      'title': 'श्री राम (मर्यादा व धर्म)',
      'occasion': 'रामनवमी, दीपोत्सव, विजय',
      'mantra': '࿗ जय श्री राम ࿗',
    },
    {
      'id': 'hanuman',
      'deity': 'श्री हनुमान',
      'title': 'श्री हनुमान (संकटमोचन व बल)',
      'occasion': 'हनुमान जयन्ती, मंगलवार/शनिवार, निर्भयता',
      'mantra': '࿗ ॐ श्री हनुमते नमः ࿗',
    },
    {
      'id': 'shiva',
      'deity': 'भगवान शिव',
      'title': 'भगवान शिव (महादेव व कल्याण)',
      'occasion': 'महाशिवरात्रि, सावन मास, कल्याण',
      'mantra': '࿗ ॐ नमः शिवाय ࿗',
    },
    {
      'id': 'radheshyam',
      'deity': 'राधे-श्याम',
      'title': 'राधे-श्याम (युगल सरकार)',
      'occasion': 'राधाष्टमी, ब्रज भक्ति, मधुरता',
      'mantra': '࿗ ॐ श्री राधेश्यामाय नमः ࿗',
    },
    {
      'id': 'saraswati',
      'deity': 'माँ सरस्वती',
      'title': 'माँ सरस्वती (विद्या व ज्ञान)',
      'occasion': 'वसन्त पञ्चमी, कला व विद्या वृद्धि',
      'mantra': '࿗ ॐ ऐं सरस्वत्यै नमः ࿗',
    },
    {
      'id': 'surya',
      'deity': 'भगवान सूर्य',
      'title': 'भगवान सूर्य (आरोग्य व तेज)',
      'occasion': 'रविवार, छठ पर्व, आरोग्यता व यश',
      'mantra': '࿗ ॐ सूर्याय नमः ࿗',
    },
    {
      'id': 'gayatri',
      'deity': 'गायत्री मन्त्र',
      'title': 'गायत्री मन्त्र (सद्बुद्धि व तेज)',
      'occasion': 'नित्य सन्ध्या वंदन, आत्मशुद्धि',
      'mantra': '࿗ ॐ भूर्भुवः स्वः ࿗',
    },
  ];

  static const String randomMantraKey = '__RANDOM_MANTRA__';

  /// Ensure text is enclosed in authentic 4-dotted Sathiya (࿗)
  static String ensureSathiya(String text) {
    String clean = text.trim();
    if (clean.isEmpty) return defaultInvocation;
    clean = clean.replaceAll("卐", "\u0FD7");
    if (!clean.startsWith("\u0FD7")) {
      clean = "\u0FD7 $clean";
    }
    if (!clean.endsWith("\u0FD7")) {
      clean = "$clean \u0FD7";
    }
    return clean;
  }

  /// Returns a freshly selected random mantra from the authentic Vedic/Pauranic collection
  static String getRandomMantra() {
    final rand = math.Random();
    final item = presetMantras[rand.nextInt(presetMantras.length)];
    return ensureSathiya(item['mantra']!);
  }

  /// Resolve the active invocation for bill generation (evaluates random mode dynamically)
  static String resolveActiveInvocation([String? explicitInvocation]) {
    final candidate = explicitInvocation ?? currentInvocation;
    if (candidate == randomMantraKey) {
      return getRandomMantra();
    }
    return ensureSathiya(candidate);
  }

  /// Load the persistent invocation mantra from storage
  static Future<String> loadSavedInvocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefKeyMantra);
      if (saved != null && saved.trim().isNotEmpty) {
        if (saved == randomMantraKey) {
          currentInvocation = randomMantraKey;
        } else {
          currentInvocation = ensureSathiya(saved);
        }
      }
    } catch (_) {}
    return currentInvocation;
  }

  /// Save selected invocation mantra
  static Future<void> saveInvocation(String mantra) async {
    if (mantra == randomMantraKey) {
      currentInvocation = randomMantraKey;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefKeyMantra, randomMantraKey);
      } catch (_) {}
      return;
    }
    final sanitized = ensureSathiya(mantra);
    currentInvocation = sanitized;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKeyMantra, sanitized);
    } catch (_) {}
  }

  static pw.Font? _cachedSiddhantaCalcutta;
  static pw.Font? _cachedHindiRegular;
  static pw.Font? _cachedHindiBold;

  /// Load and cache Siddhanta Calcutta (and Noto Serif fallback) TrueType fonts offline from bundled assets
  static Future<pw.ThemeData> _loadTheme() async {
    if (_cachedSiddhantaCalcutta != null) {
      final fallbacks = <pw.Font>[_cachedSiddhantaCalcutta!];
      if (_cachedHindiRegular != null) fallbacks.add(_cachedHindiRegular!);
      if (_cachedHindiBold != null) fallbacks.add(_cachedHindiBold!);
      return pw.ThemeData.withFont(
        base: _cachedSiddhantaCalcutta ?? pw.Font.helvetica(),
        bold: _cachedSiddhantaCalcutta ?? pw.Font.helveticaBold(),
        fontFallback: fallbacks,
      );
    }

    // 1. Primary authentic Calcutta style font: Siddhanta Calcutta
    if (_cachedSiddhantaCalcutta == null) {
      try {
        final data = await rootBundle.load("assets/fonts/siddhanta-calcutta.ttf");
        _cachedSiddhantaCalcutta = pw.Font.ttf(data);
      } catch (_) {
        try {
          final file = File("assets/fonts/siddhanta-calcutta.ttf");
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            _cachedSiddhantaCalcutta = pw.Font.ttf(bytes.buffer.asByteData());
          }
        } catch (_) {}
      }
    }

    // 2. Secondary Book Serif fallbacks: Noto Serif Devanagari
    if (_cachedHindiRegular == null) {
      try {
        final data = await rootBundle.load("assets/fonts/NotoSerifDevanagari-Regular.ttf");
        _cachedHindiRegular = pw.Font.ttf(data);
      } catch (_) {
        try {
          final file = File("assets/fonts/NotoSerifDevanagari-Regular.ttf");
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            _cachedHindiRegular = pw.Font.ttf(bytes.buffer.asByteData());
          }
        } catch (_) {}
      }
    }

    if (_cachedHindiBold == null) {
      try {
        final data = await rootBundle.load("assets/fonts/NotoSerifDevanagari-Bold.ttf");
        _cachedHindiBold = pw.Font.ttf(data);
      } catch (_) {
        try {
          final file = File("assets/fonts/NotoSerifDevanagari-Bold.ttf");
          if (file.existsSync()) {
            final bytes = await file.readAsBytes();
            _cachedHindiBold = pw.Font.ttf(bytes.buffer.asByteData());
          }
        } catch (_) {}
      }
    }

    final fallbacks = <pw.Font>[];
    if (_cachedSiddhantaCalcutta != null) fallbacks.add(_cachedSiddhantaCalcutta!);
    if (_cachedHindiRegular != null) fallbacks.add(_cachedHindiRegular!);
    if (_cachedHindiBold != null) fallbacks.add(_cachedHindiBold!);

    if (fallbacks.isNotEmpty) {
      return pw.ThemeData.withFont(
        base: _cachedSiddhantaCalcutta ?? pw.Font.helvetica(),
        bold: _cachedSiddhantaCalcutta ?? pw.Font.helveticaBold(),
        fontFallback: fallbacks,
      );
    }
    return pw.ThemeData.base();
  }

  /// Format Devanagari text for authentic Calcutta-style ligatures and compound letters
  /// in Siddhanta Calcutta font. Substitutes conjuncts (e.g. ङ्ग, ण्ट, क्त, प्त, द्ध, त्र, श्र,
  /// ष्ट, ष्ठ, ञ्च, श्व, श्च, स्त, etc.), half-consonants without halants, repha (र्), and
  /// reorders Chhoti-Ee (U+093F) to produce authentic classical typography without uncompounded letters.
  static String _fixDevanagari(String text) {
    if (text.isEmpty) return text;

    // 1. Map Vedic 4-dot Sathiya
    String res = text.replaceAll("卐", "\u0FD7");

    // 2. High-priority whole-phrase and complex conjunct replacements
    const Map<String, String> phraseLigatures = {
      // Shri
      "श्री": "\uF37D\u0940",
      "श्र": "\uF37D",
      // Mahalakshmi & Lakshmi
      "महालक्ष्म्यै": "महाल\uF35E\uF350यै",
      "लक्ष्म्यै": "ल\uF35E\uF350यै",
      "लक्ष्मीः": "ल\uF35Eमीः",
      "लक्ष्मी": "ल\uF35Eमी",
      // Krishna & Vishnu
      "कृष्णाय": "क\u0943\uF35Aणाय",
      "कृष्ण": "क\u0943\uF35Aण",
      "विष्णुपत्नी": "वि\uF35Aणुप\uF4B1नी",
      "विष्णु": "वि\uF35Aणु",
      "विद्महे": "वि\uF48Cहे",
      "प्रचोदयात्": "\uF374चोदया\uF346",
      "तत्सवितुर्वरेण्यं": "\uF444सवितुव\u093E\uF306रेण्यं",
      "भगवते": "भगवते",
      "वासुदेवाय": "वासुदेवाय",
      "दुर्गायै": "दुगा\uF306यै",
      "दुर्गा": "दुगा\uF306",
      "सूर्याय": "सूया\uF306य",
      "सूर्य": "सूय\uF306",
      "सरस्वत्यै": "सर\uF35Bव\uF346यै",
      "सरस्वती": "सर\uF35Bवती",
      "स्वः": "\uF35Bवः",
      "स्व": "\uF35Bव",
      "स्म": "\uF35Bम",
      "हर्ष": "हष\uF306",
      "मार्ग": "माग\uF306",
      "पर्ची": "पची\uF306",
      "ङ्ग्ल": "\uF59F\uF5F5",
      "सङ्ख्या": "स\uF59F\uF6FC\uF58F\u093E",
      "संख्या": "स\uF59F\uF6FC\uF58F\u093E",
    };

    for (final entry in phraseLigatures.entries) {
      res = res.replaceAll(entry.key, entry.value);
    }

    // 3. Calcutta-style stacked conjuncts & authentic classical 2-consonant ligatures
    const Map<String, String> conjunctMap = {
      // Stacked Calcutta conjuncts for Nga (ङ् + consonant)
      "ङ्ग": "\uF59F\uF5EB",
      "ङ्क": "\uF59F\uF5BA",
      "ङ्ख": "\uF59F\uF5E6",
      "ङ्घ": "\uF59F\uF5F7",
      // Authentic Calcutta conjuncts for Na (ण् + consonant)
      "ण्ट": "\uF345\u091F",
      "ण्ठ": "\uF345\u0920",
      "ण्ड": "\uF345\u0921",
      "ण्ढ": "\uF345\u0922",
      "ण्ण": "\uF442",
      // Classical fused 2-consonant ligatures
      "क्त": "\uF3FF",
      "प्त": "\uF4B1",
      "त्त": "\uF444",
      "द्ध": "\uF469",
      "द्य": "\uF48E",
      "द्व": "\uF493",
      "द्म": "\uF48C",
      "द्ब": "\uF47C",
      "द्भ": "\uF480",
      "ष्ट": "\uF4E7",
      "ष्ठ": "\uF4E8",
      "ञ्च": "\uF433",
      "ञ्ज": "\uF437",
      "श्च": "\uF4DD",
      "श्व": "\uF4E5",
      "श्न": "\uF4E0",
      "श्ल": "\uF4E1",
      "न्त": "\uF4A4",
      "न्त्र": "\uF4A7",
      "न्न": "\uF4AB",
      "क्ष": "\uF106",
      "ज्ञ": "\uF339",
      "त्र": "\uF36E",
      "प्र": "\uF374",
      "क्र": "\uF363",
      "ग्र": "\uF365",
      "घ्र": "\uF366",
      "द्र": "\uF370",
      "ध्र": "\uF371",
      "ब्र": "\uF376",
      "भ्र": "\uF377",
      "म्र": "\uF379",
      "व्र": "\uF37C",
      "स्र": "\uF37F",
      "ह्र": "\uF380",
      "ल्ल": "\uF4D5",
      "ग्ध": "\uF5ED",
      "ग्न": "\uF414",
      "त्न": "\uF449",
      "त्व": "\uF44A",
      "स्न": "\uF4F5",
      "क्न": "\uF407",
      "क्म": "\uF409",
      "क्ल": "\uF40D",
      "क्व": "\uF411",
      "ज्ज": "\uF429",
      "च्च": "\uF41A",
      "म्ब": "\uF4CE",
      "म्ल": "\uF4CF",
      "ह्ल": "\uF500",
      "ह्न": "\uF4F8",
      "ह्म": "\uF4FB",
      "ह्य": "\uF4FD",
      "ह्व": "\uF6D1",
    };

    for (final entry in conjunctMap.entries) {
      res = res.replaceAll(entry.key, entry.value);
    }

    // 4. Half consonants without halants (seamless ligature appearance)
    const Map<String, String> halfConsonants = {
      "क्": "\uF33A",
      "ख्": "\uF33B",
      "ग्": "\uF33C",
      "घ्": "\uF33D",
      "च्": "\uF33E",
      "ज्": "\uF33F",
      "झ्": "\uF340",
      "ञ्": "\uF343",
      "ण्": "\uF345",
      "त्": "\uF346",
      "थ्": "\uF347",
      "ध्": "\uF348",
      "न्": "\uF34A",
      "प्": "\uF34B",
      "फ्": "\uF34C",
      "ब्": "\uF34D",
      "भ्": "\uF34E",
      "म्": "\uF350",
      "य्": "\uF351",
      "ल्": "\uF353",
      "व्": "\uF356",
      "श्": "\uF358",
      "ष्": "\uF35A",
      "स्": "\uF35B",
    };

    for (final entry in halfConsonants.entries) {
      // Lookahead: only replace with half-consonant if immediately followed by another consonant or PUA ligature.
      // If at end of word or before whitespace/punctuation (e.g. संवत्, जगत्), it preserves full letter with halant!
      final exp = RegExp("${RegExp.escape(entry.key)}(?=[\\u0915-\\u0939\\uF100-\\uF8FF])");
      res = res.replaceAll(exp, entry.value);
    }

    // 5. Repha: र् followed by consonant (+ matras) -> moves repha glyph \uF306 after the consonant and vowel matras
    final rephaExp = RegExp(r'र्([\u0915-\u0939\uF100-\uF8FF][\u093E\u0940-\u094C\u0902]*)');
    res = res.replaceAllMapped(rephaExp, (m) => '${m.group(1)}\uF306');

    // 6. Chhoti-Ee (\u093F) visual reordering before preceding consonant cluster/ligature
    final eeExp = RegExp(r'((?:[\uF33A-\uF35F]|[\uF100-\uF8FF])*[\u0915-\u0939\uF100-\uF8FF])[\u093F]');
    res = res.replaceAllMapped(eeExp, (m) => '\u093F${m.group(1)}');

    return res;
  }

  /// Convert standard Arabic numerals into authentic Devanagari digits (e.g. 2083 -> २०८३, or 'LK-2026' -> 'LK-२०२६')
  static String toDevanagariDigits(dynamic value) {
    const digits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    return value.toString().split('').map((char) {
      final d = int.tryParse(char);
      return d != null ? digits[d] : char;
    }).join('');
  }

  /// Parse bill created_at and always normalize to Indian Standard Time (IST, UTC+05:30)
  static DateTime parseIndianStandardTime(dynamic rawDate) {
    if (rawDate == null) {
      final nowUtc = DateTime.now().toUtc();
      final ist = nowUtc.add(const Duration(hours: 5, minutes: 30));
      return DateTime(ist.year, ist.month, ist.day, ist.hour, ist.minute, ist.second);
    }
    if (rawDate is DateTime) {
      final utc = rawDate.toUtc();
      final ist = utc.add(const Duration(hours: 5, minutes: 30));
      return DateTime(ist.year, ist.month, ist.day, ist.hour, ist.minute, ist.second);
    }
    try {
      final str = rawDate.toString().trim();
      if (str.isEmpty) {
        final nowUtc = DateTime.now().toUtc();
        final ist = nowUtc.add(const Duration(hours: 5, minutes: 30));
        return DateTime(ist.year, ist.month, ist.day, ist.hour, ist.minute, ist.second);
      }

      final hasExplicitTz = str.endsWith('Z') || RegExp(r'[+-]\d{2}(:\d{2})?$').hasMatch(str);

      if (hasExplicitTz) {
        final parsedUtc = DateTime.parse(str).toUtc();
        final ist = parsedUtc.add(const Duration(hours: 5, minutes: 30));
        return DateTime(ist.year, ist.month, ist.day, ist.hour, ist.minute, ist.second);
      } else {
        // Naive date string, e.g. "2026-09-12 13:13:00" or "2026-09-12T13:13:00"
        final parsed = DateTime.parse(str);
        return DateTime(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second);
      }
    } catch (_) {
      final nowUtc = DateTime.now().toUtc();
      final ist = nowUtc.add(const Duration(hours: 5, minutes: 30));
      return DateTime(ist.year, ist.month, ist.day, ist.hour, ist.minute, ist.second);
    }
  }

  /// Calculate traditional Hindu Panchang Tithi for any given bill DateTime
  /// Computes authentic Udayatithi (tithi prevailing at sunrise in New Delhi, ~06:04 IST)
  static String _formatPanchangTithi(DateTime dt) {
    const tithiNames = [
      "प्रतिपदा", "द्वितीया", "तृतीया", "चतुर्थी", "पञ्चमी",
      "षष्ठी", "सप्तमी", "अष्टमी", "नवमी", "दशमी",
      "एकादशी", "द्वादशी", "त्रयोदशी", "चतुर्दशी", "पूर्णिमा",
      "प्रतिपदा", "द्वितीया", "तृतीया", "चतुर्थी", "पञ्चमी",
      "षष्ठी", "सप्तमी", "अष्टमी", "नवमी", "दशमी",
      "एकादशी", "द्वादशी", "त्रयोदशी", "चतुर्दशी", "अमावस्या",
    ];

    const masaNames = [
      "चैत्र", "वैशाख", "ज्येष्ठ", "आषाढ़",
      "श्रावण", "भाद्रपद", "आश्विन", "कार्तिक",
      "मार्गशीर्ष", "पौष", "माघ", "फाल्गुन"
    ];

    try {
      // In Vedic Jyotish & Panchang (New Delhi), the day's civil tithi is determined by Udayatithi (Sunrise ~06:04 IST = 00:34 UTC)
      // If time is before sunrise, it belongs to the previous day's sunrise
      final DateTime sunriseDt = (dt.hour < 6)
          ? dt.subtract(const Duration(days: 1))
          : dt;

      int y = sunriseDt.year;
      int m = sunriseDt.month;
      // Sunrise at ~06:04 IST = 00:34 UTC
      final double d = sunriseDt.day + (0.0 + 34.0 / 60.0) / 24.0;
      if (m <= 2) {
        y -= 1;
        m += 12;
      }
      final int a = (y / 100).floor();
      final int b = 2 - a + (a / 4).floor();
      final double jd = (365.25 * (y + 4716)).floor() + (30.6001 * (m + 1)).floor() + d + b - 1524.5;
      final double t = (jd - 2451545.0) / 36525.0;

      final double l0 = (280.46646 + 36000.76983 * t + 0.0003032 * t * t) % 360.0;
      final double mSun = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) % 360.0;
      final double mSunRad = mSun * math.pi / 180.0;
      final double cSun = (1.914602 - 0.004817 * t) * math.sin(mSunRad) + 0.019993 * math.sin(2 * mSunRad);
      final double sunLong = (l0 + cSun + 360.0) % 360.0;

      final double lPrime = (218.3164477 + 481267.88123421 * t) % 360.0;
      final double dMoon = (297.8501921 + 445267.1114034 * t) % 360.0;
      final double mPrime = (134.9633964 + 477198.8675055 * t) % 360.0;
      final double fMoon = (93.2720950 + 483202.0175233 * t) % 360.0;

      final double dRad = dMoon * math.pi / 180.0;
      final double mpRad = mPrime * math.pi / 180.0;
      final double fRad = fMoon * math.pi / 180.0;

      final double moonLong = (lPrime +
          6.288774 * math.sin(mpRad) +
          1.274027 * math.sin(2 * dRad - mpRad) +
          0.658314 * math.sin(2 * dRad) +
          0.213618 * math.sin(2 * mpRad) -
          0.185116 * math.sin(mSunRad) -
          0.114332 * math.sin(2 * fRad) +
          360.0) % 360.0;

      final double diff = (moonLong - sunLong + 360.0) % 360.0;
      final int tithiIndex = (diff / 12.0).floor() % 30;
      final bool isShukla = tithiIndex < 15;
      final String paksha = isShukla ? "शुक्ल" : "कृष्ण";
      final String tithi = tithiNames[tithiIndex];

      final double siderealSun = (sunLong - 24.2 + 360.0) % 360.0;
      final int rashi = (siderealSun / 30.0).floor();
      final int masaIndex = (rashi + 1) % 12;
      final String masa = masaNames[masaIndex];

      int samvat = sunriseDt.year + 57;
      if (sunriseDt.month < 3 || (sunriseDt.month == 3 && sunriseDt.day < 20)) {
        samvat -= 1;
      }

      final String pahar = getPaharName(dt);

      return "$masa, $paksha $tithi, ${toDevanagariDigits(samvat)} विक्रम संवत् ($pahar)";
    } catch (_) {
      return "तिथि पञ्चाङ्ग";
    }
  }

  /// Traditional Indian Pahar (प्रहर) of the day based on 8 prahars of day/night (in IST)
  static String getPaharName(DateTime dt, {bool verbose = false}) {
    final hour = dt.hour;
    if (hour >= 6 && hour < 9) {
      return verbose ? "प्रथम प्रहर (प्रातः)" : "प्रथम प्रहर";
    } else if (hour >= 9 && hour < 12) {
      return verbose ? "द्वितीय प्रहर (पूर्वाह्न)" : "द्वितीय प्रहर";
    } else if (hour >= 12 && hour < 15) {
      return verbose ? "तृतीय प्रहर (मध्याह्न)" : "तृतीय प्रहर";
    } else if (hour >= 15 && hour < 18) {
      return verbose ? "चतुर्थ प्रहर (अपराह्न)" : "चतुर्थ प्रहर";
    } else if (hour >= 18 && hour < 21) {
      return verbose ? "सायं प्रहर (प्रदोष)" : "सायं प्रहर";
    } else if (hour >= 21 && hour < 24) {
      return "निशीथ प्रहर";
    } else if (hour >= 0 && hour < 3) {
      return "मध्यरात्रि प्रहर";
    } else {
      return "ब्रह्ममुहूर्त प्रहर";
    }
  }

  /// Format authentic Vedic Vaar based on sunrise-to-sunrise (अहोरात्र) Vedic day cycle
  /// Classical Sanskrit/Vedic names: शनिवासर, रविवासर, सोमवासर, etc.
  static String getVedicVaarName(DateTime dt) {
    // In Vedic Jyotish, the day begins at Sunrise (~06:00 IST in New Delhi)
    final int effectiveWeekday = dt.hour < 6
        ? (dt.weekday - 2 + 7) % 7 + 1
        : dt.weekday;

    const vedicVaars = [
      "सोमवासर", // Mon (1)
      "भौमवासर", // Tue (2)
      "बुधवासर", // Wed (3)
      "गुरुवासर", // Thu (4)
      "शुक्रवासर", // Fri (5)
      "शनिवासर", // Sat (6)
      "रविवासर", // Sun (7)
    ];
    return vedicVaars[(effectiveWeekday - 1) % 7];
  }

  /// Format Gregorian date and time in Hindi with authentic Vedic Vaar in a single clean line
  /// Example: "शनिवासर, सितम्बर 12, 2026 | 13:27"
  static String formatVedicDateAndTimeString(DateTime dt) {
    const hindiMonths = [
      "जनवरी", "फरवरी", "मार्च", "अप्रैल", "मई", "जून",
      "जुलाई", "अगस्त", "सितम्बर", "अक्टूबर", "नवम्बर", "दिसम्बर"
    ];
    final String vaar = getVedicVaarName(dt);
    final String monthName = hindiMonths[dt.month - 1];
    final String timeStr =
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    return "$vaar, $monthName ${dt.day}, ${dt.year} | $timeStr";
  }

  /// Format dynamic Gregorian date and time in English in a single clean line
  /// Example: "Saturday, September 12, 2026 | 13:27"
  static String formatEnglishDateAndTimeString(DateTime dt) {
    const englishDays = [
      "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ];
    const englishMonths = [
      "January", "February", "March", "April", "May", "June",
      "July", "August", "September", "October", "November", "December"
    ];
    final String dayName = englishDays[(dt.weekday - 1) % 7];
    final String monthName = englishMonths[dt.month - 1];
    final String timeStr =
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    return "$dayName, $monthName ${dt.day}, ${dt.year} | $timeStr";
  }

  /// Format bill number string in Devanagari script for Hindi receipts
  static String formatBillNumberHindi(String billNo) {
    if (billNo.isEmpty || billNo == "N/A") return billNo;
    String text = billNo
        .replaceAll(RegExp(r'LK[-_]?', caseSensitive: false), 'ल.कु.-')
        .replaceAll(RegExp(r'STR', caseSensitive: false), 'एस.टी.आर.')
        .replaceAll(RegExp(r'RND', caseSensitive: false), 'आर.एन.डी.')
        .replaceAll(RegExp(r'BI', caseSensitive: false), 'बी.आई.');
    return toDevanagariDigits(text);
  }

  /// Extract cash and online split components from a hybrid payment method string
  static Map<String, double>? parseHybridParts(String method) {
    if (!method.toLowerCase().contains("hybrid") && !method.contains("मिश्र")) {
      return null;
    }
    final cashMatch = RegExp(r'(?:cash|रोकड़(?:ा)?)[^\d]*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(method);
    final onlineMatch = RegExp(r'(?:online|ऑनलाइन)[^\d]*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(method);

    final double? cash = cashMatch != null ? double.tryParse(cashMatch.group(1)!.replaceAll(',', '')) : null;
    final double? online = onlineMatch != null ? double.tryParse(onlineMatch.group(1)!.replaceAll(',', '')) : null;

    if (cash != null || online != null) {
      return {
        'cash': cash ?? 0.0,
        'online': online ?? 0.0,
      };
    }
    return null;
  }

  static String _formatAmount(double val) {
    return val % 1 == 0 ? val.toInt().toString() : val.toStringAsFixed(2);
  }

  /// Render currency and price text with a proportionally scaled and bold Rupee symbol (₹)
  /// so it matches the optical weight and height of Arabic numerals in both Hindi & English receipts
  static pw.Widget priceRichText(
    String text, {
    required double fontSize,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    PdfColor color = PdfColors.black,
    pw.TextAlign textAlign = pw.TextAlign.left,
  }) {
    if (!text.contains('₹')) {
      return pw.Text(
        text,
        textAlign: textAlign,
        style: pw.TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: color),
      );
    }

    final spans = <pw.InlineSpan>[];
    final parts = text.split('₹');
    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isNotEmpty) {
        spans.add(
          pw.TextSpan(
            text: parts[i],
            style: pw.TextStyle(fontSize: fontSize, fontWeight: fontWeight, color: color),
          ),
        );
      }
      if (i < parts.length - 1) {
        // Boost Rupee symbol size by ~28% and set bold weight so it visually balances with Arabic numerals
        spans.add(
          pw.TextSpan(
            text: '₹',
            style: pw.TextStyle(
              fontSize: fontSize * 1.28,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
        );
      }
    }

    return pw.RichText(
      textAlign: textAlign,
      text: pw.TextSpan(children: spans),
    );
  }

  /// Format payment method in classical Sanskritized Hindi
  static String _paymentModeSanskrit(String method) {
    final m = method.toLowerCase();
    if (m.contains("hybrid") || m.contains("मिश्र")) {
      return method
          .replaceAll(RegExp(r'hybrid', caseSensitive: false), 'मिश्रित भुगतान')
          .replaceAll(RegExp(r'cash', caseSensitive: false), 'रोकड़ा')
          .replaceAll(RegExp(r'online', caseSensitive: false), 'ऑनलाइन');
    }
    if (m == "cash" || m.contains("cash") || m == "रोकड़") return "रोकड़ा";
    if (m.contains("online") || m.contains("upi") || m.contains("gpay") || m.contains("paytm")) return "ऑनलाइन (डिजिटल / UPI)";
    if (m.contains("card")) return "कार्ड भुगतान";
    return method;
  }

  /// Format payment method in Hindi (alias)
  static String _paymentModeHindi(String method) => _paymentModeSanskrit(method);
  /// Robust double parser for String, num, double, int, or null
  static double _toDouble(dynamic val, [double defaultVal = 0.0]) {
    if (val == null) return defaultVal;
    if (val is num) return val.toDouble();
    if (val is String) {
      if (val.trim().isEmpty) return defaultVal;
      final cleaned = val.replaceAll(RegExp(r'[^0-9.-]'), '').trim();
      return double.tryParse(cleaned) ?? defaultVal;
    }
    return defaultVal;
  }

  /// Robust int parser for String, num, int, or null
  static int _toInt(dynamic val, [int defaultVal = 1]) {
    if (val == null) return defaultVal;
    if (val is num) return val.toInt();
    if (val is String) {
      if (val.trim().isEmpty) return defaultVal;
      final cleaned = val.replaceAll(RegExp(r'[^0-9.-]'), '').trim();
      final d = double.tryParse(cleaned);
      if (d != null) return d.toInt();
    }
    return defaultVal;
  }

  /// Robust items extractor supporting List or JSON-encoded String
  static List<dynamic> _extractItems(dynamic raw) {
    if (raw is List) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) return decoded;
      } catch (_) {}
    }
    return [];
  }

  /// Generate a clean, minimal, thermal-style PDF receipt document for a bill
  static Future<Uint8List> generateReceiptPdf(
    Map<String, dynamic> bill, {
    Uint8List? logoBytes,
    PdfPageFormat? pageFormat,
    ReceiptLanguage language = ReceiptLanguage.hindi,
    String? invocation,
  }) async {
    final String candidateInvocation = invocation ??
        (bill['invocation_mantra']?.toString().trim().isNotEmpty == true
            ? bill['invocation_mantra'].toString().trim()
            : currentInvocation);
    final String effectiveInvocation = resolveActiveInvocation(candidateInvocation);

    final theme = await _loadTheme();
    final doc = pw.Document(theme: theme);

    // 1. Extract and sanitize bill metadata
    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final String staffName = (bill['staff_name'] ?? "Staff").toString();
    final double totalAmount = _toDouble(bill['total_amount']);
    final String paymentMethod = (bill['payment_method'] ?? "Cash").toString();
    final hybridParts = parseHybridParts(paymentMethod);
    final bool isHybrid = hybridParts != null;
    final double amountTendered = _toDouble(bill['amount_tendered'], totalAmount);
    final double changeDue = _toDouble(bill['change_due'], amountTendered > totalAmount ? (amountTendered - totalAmount) : 0.0);

    final DateTime billDate = parseIndianStandardTime(bill['created_at']);
    final String formattedDate =
        "${billDate.day.toString().padLeft(2, '0')}-${billDate.month.toString().padLeft(2, '0')}-${billDate.year} ${billDate.hour.toString().padLeft(2, '0')}:${billDate.minute.toString().padLeft(2, '0')}";

    // 2. Load store logo image if not provided
    Uint8List? effectiveLogo = logoBytes;
    if (effectiveLogo == null) {
      try {
        final byteData = await rootBundle.load("assets/logo_bw.jpg");
        effectiveLogo = byteData.buffer.asUint8List();
      } catch (_) {
        try {
          final file = File("assets/logo_bw.jpg");
          if (file.existsSync()) {
            effectiveLogo = await file.readAsBytes();
          }
        } catch (_) {}
      }
    }

    final pw.ImageProvider? logoImage = effectiveLogo != null ? pw.MemoryImage(effectiveLogo) : null;

    // 3. Extract items safely
    final rawItems = _extractItems(bill['items_json']);
    final List<_ReceiptItem> receiptItems = [];
    int totalQty = 0;

    for (int i = 0; i < rawItems.length; i++) {
      final item = rawItems[i] is Map ? rawItems[i] as Map : {};
      String itemName = (item['itemName'] ?? item['item'] ?? 'General Item').toString().split('\n').first.trim();
      final qty = _toInt(item['qty'], 1);
      final rate = _toDouble(item['rate'], 0.0);
      final lineTotal = _toDouble(item['total'] ?? item['price'], qty * rate);
      totalQty += qty;

      receiptItems.add(_ReceiptItem(
        name: itemName,
        qty: qty,
        rate: rate,
        lineTotal: lineTotal,
      ));
    }

    // 4. Build Minimal Thermal-Style Receipt Content
    List<pw.Widget> buildReceiptWidgets(pw.Context context) {
      return [
        // Store Logo (Centered & Crisp)
        if (logoImage != null) ...[
          pw.Center(
            child: pw.Container(
              width: 48,
              height: 48,
              margin: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
            ),
          ),
        ],

        // Store Titles & Header
        // Sanskrit Bhagwan Namaste Invocation with Satiya (Always on top for both Hindi & English)
        pw.Center(
          child: pw.Text(
            _fixDevanagari(effectiveInvocation),
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ),
        pw.SizedBox(height: 3),

        if (language == ReceiptLanguage.hindi) ...[
          pw.Center(
            child: pw.Text(
              _fixDevanagari("लव कुश"),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              _fixDevanagari("शॉपिङ्ग सेण्टर"),
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              _fixDevanagari("ए-२/३९२, सुभाष कंसल मार्ग, हर्ष विहार, दिल्ली - ११००९३"),
              style: pw.TextStyle(
                fontSize: 6.8,
                fontWeight: pw.FontWeight.normal,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              _fixDevanagari("*** खुदरा रोकड़ा बीजक ***"),
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
        ] else ...[
          pw.Center(
            child: pw.Text(
              "LOVE KUSH",
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.Center(
            child: pw.Text(
              "SHOPPING CENTER",
              style: pw.TextStyle(
                fontSize: 10.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "A-2/392, Subhash Kansal Marg, Harsh Vihar, Delhi - 110093",
              style: pw.TextStyle(
                fontSize: 6.8,
                fontWeight: pw.FontWeight.normal,
                color: PdfColors.grey800,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              "*** RETAIL CASH MEMO ***",
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
        ],

        // Bill No & Code 128 Barcode
        if (billNo != "N/A" && billNo.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Center(
            child: pw.Text(
              language == ReceiptLanguage.hindi
                  ? _fixDevanagari("बीजक सङ्ख्या: ${formatBillNumberHindi(billNo)}")
                  : "BILL NO: $billNo",
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.black,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: billNo,
              width: 140,
              height: 26,
              drawText: false,
            ),
          ),
        ],

        // Tithi (Panchang & English), Koshapala, Payment Mode
        pw.SizedBox(height: 4),
        if (language == ReceiptLanguage.hindi) ...[
          pw.Text(
            _fixDevanagari("पञ्चाङ्ग: ${_formatPanchangTithi(billDate)}"),
            style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.black),
          ),
          pw.SizedBox(height: 1.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _fixDevanagari("दिनाङ्क व समय: ${formatVedicDateAndTimeString(billDate)}"),
                style: const pw.TextStyle(fontSize: 7.2, color: PdfColors.black),
              ),
            ],
          ),
          pw.SizedBox(height: 1.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _fixDevanagari("कोषपाल: $staffName"),
                style: const pw.TextStyle(fontSize: 7.2, color: PdfColors.black),
              ),
              pw.Text(
                _fixDevanagari("भुगतान विधि: ${isHybrid ? 'मिश्रित भुगतान' : _paymentModeSanskrit(paymentMethod)}"),
                style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ],
          ),
          if (isHybrid) ...[
            pw.SizedBox(height: 1.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  _fixDevanagari("भुगतान विभाजन:"),
                  style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey700),
                ),
                priceRichText(
                  "रोकड़ा ₹${_formatAmount(hybridParts['cash']!)}  •  ऑनलाइन ₹${_formatAmount(hybridParts['online']!)}",
                  fontSize: 7.0,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                  textAlign: pw.TextAlign.right,
                ),
              ],
            ),
          ],
        ] else ...[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                "Date & Time: ${formatEnglishDateAndTimeString(billDate)}",
                style: const pw.TextStyle(fontSize: 7.2, color: PdfColors.black),
              ),
            ],
          ),
          pw.SizedBox(height: 1.5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Cashier: $staffName", style: const pw.TextStyle(fontSize: 7.2, color: PdfColors.black)),
              pw.Text(
                "Payment: ${isHybrid ? 'HYBRID' : paymentMethod.toUpperCase()}",
                style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ],
          ),
          if (isHybrid) ...[
            pw.SizedBox(height: 1.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Payment Split:", style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey700)),
                priceRichText(
                  "Cash ₹${_formatAmount(hybridParts['cash']!)}  •  Online ₹${_formatAmount(hybridParts['online']!)}",
                  fontSize: 7.0,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                  textAlign: pw.TextAlign.right,
                ),
              ],
            ),
          ],
        ],

        // Dashed Tear Line
        pw.SizedBox(height: 2),
        pw.Divider(thickness: 0.8, color: PdfColors.black, borderStyle: pw.BorderStyle.dashed),

        // Column Headers (Sanskritized terms for item & amount)
        pw.Row(
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("वस्तु विवरण")
                    : "ITEM",
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ),
            pw.Expanded(
              flex: 4,
              child: pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("मात्रा × दर")
                    : "QTY x RATE",
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("राशि")
                    : "AMOUNT",
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
            ),
          ],
        ),
        pw.Divider(thickness: 0.5, color: PdfColors.grey600, borderStyle: pw.BorderStyle.dashed),

        // Item Rows with exact column-by-column alignment
        for (final item in receiptItems) ...[
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 5,
                  child: pw.Text(
                    _fixDevanagari(item.name),
                    style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
                  ),
                ),
                pw.Expanded(
                  flex: 4,
                  child: pw.Center(
                    child: priceRichText(
                      "${item.qty} × ₹${item.rate.toStringAsFixed(2)}",
                      fontSize: 7.5,
                      color: PdfColors.grey900,
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
                ),
                pw.Expanded(
                  flex: 3,
                  child: pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: priceRichText(
                      "₹${item.lineTotal.toStringAsFixed(2)}",
                      fontSize: 7.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Dashed Divider
        pw.Divider(thickness: 0.8, color: PdfColors.black, borderStyle: pw.BorderStyle.dashed),

        // Totals & Paid Details (Sanskritized labels)
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              language == ReceiptLanguage.hindi
                  ? _fixDevanagari("कुल वस्तुएँ: ${receiptItems.length} (सकल मात्रा: $totalQty)")
                  : "Total Items: ${receiptItems.length} (Qty: $totalQty)",
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              language == ReceiptLanguage.hindi
                  ? _fixDevanagari("सकल देय राशि:")
                  : "TOTAL AMOUNT:",
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
            ),
            priceRichText(
              "₹${totalAmount.toStringAsFixed(2)}",
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
              textAlign: pw.TextAlign.right,
            ),
          ],
        ),
        if (isHybrid) ...[
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("रोकड़ा भुगतान:")
                    : "Cash Paid:",
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
              ),
              priceRichText(
                "₹${_formatAmount(hybridParts['cash']!)}",
                fontSize: 7.5,
                color: PdfColors.black,
                textAlign: pw.TextAlign.right,
              ),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("ऑनलाइन भुगतान:")
                    : "Online Paid:",
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
              ),
              priceRichText(
                "₹${_formatAmount(hybridParts['online']!)}",
                fontSize: 7.5,
                color: PdfColors.black,
                textAlign: pw.TextAlign.right,
              ),
            ],
          ),
          if (changeDue > 0) ...[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  language == ReceiptLanguage.hindi
                      ? _fixDevanagari("अवशिष्ट प्रतिदेय राशि:")
                      : "Change Return:",
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                ),
                priceRichText(
                  "₹${changeDue.toStringAsFixed(2)}",
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                  textAlign: pw.TextAlign.right,
                ),
              ],
            ),
          ],
        ] else if (paymentMethod.toLowerCase().contains("cash") || amountTendered > totalAmount) ...[
          pw.SizedBox(height: 2),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("प्राप्त राशि:")
                    : "Paid Money:",
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
              ),
              priceRichText(
                "₹${amountTendered.toStringAsFixed(2)}",
                fontSize: 7.5,
                color: PdfColors.black,
                textAlign: pw.TextAlign.right,
              ),
            ],
          ),
          if (changeDue > 0) ...[
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  language == ReceiptLanguage.hindi
                      ? _fixDevanagari("अवशिष्ट प्रतिदेय राशि:")
                      : "Change Return:",
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                ),
                priceRichText(
                  "₹${changeDue.toStringAsFixed(2)}",
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                  textAlign: pw.TextAlign.right,
                ),
              ],
            ),
          ],
        ],

        // Dashed Divider
        pw.Divider(thickness: 0.8, color: PdfColors.black, borderStyle: pw.BorderStyle.dashed),

        // Footer Thank You
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                language == ReceiptLanguage.hindi
                    ? _fixDevanagari("*** सधन्यवाद! पुनः पधारें! ***")
                    : "*** THANK YOU FOR SHOPPING! VISIT AGAIN ***",
                style: pw.TextStyle(
                  fontSize: language == ReceiptLanguage.hindi ? 8.5 : 6.8,
                  fontWeight: language == ReceiptLanguage.hindi ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: PdfColors.black,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    // Default to standard 80mm continuous receipt roll
    final PdfPageFormat format = pageFormat ??
        const PdfPageFormat(
          80 * PdfPageFormat.mm,
          double.infinity,
          marginAll: 4 * PdfPageFormat.mm,
        );

    if (format.height == double.infinity) {
      doc.addPage(
        pw.Page(
          pageFormat: format,
          build: (pw.Context context) {
            return pw.Container(
              color: PdfColors.white,
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: buildReceiptWidgets(context),
              ),
            );
          },
        ),
      );
    } else {
      doc.addPage(
        pw.MultiPage(
          pageFormat: format,
          margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          build: (pw.Context context) => [
            pw.Center(
              child: pw.Container(
                width: 76 * PdfPageFormat.mm,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: buildReceiptWidgets(context),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return doc.save();
  }

  /// Format a clean, human-readable WhatsApp text receipt message (Hindi or English)
  static String formatWhatsAppBillMessage(
    Map<String, dynamic> bill, {
    ReceiptLanguage language = ReceiptLanguage.hindi,
    String? invocation,
  }) {
    final String candidateInvocation = invocation ??
        (bill['invocation_mantra']?.toString().trim().isNotEmpty == true
            ? bill['invocation_mantra'].toString().trim()
            : currentInvocation);
    final String effectiveInvocation = resolveActiveInvocation(candidateInvocation);

    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final double totalAmount = _toDouble(bill['total_amount']);
    final String paymentMethod = (bill['payment_method'] ?? "Cash").toString();
    final hybridParts = parseHybridParts(paymentMethod);
    final bool isHybrid = hybridParts != null;
    final String staffName = (bill['staff_name'] ?? "स्टाफ").toString();
    final rawItems = _extractItems(bill['items_json']);

    final DateTime billDate = parseIndianStandardTime(bill['created_at']);
    final String formattedDate =
        "${billDate.day.toString().padLeft(2, '0')}-${billDate.month.toString().padLeft(2, '0')}-${billDate.year} ${billDate.hour.toString().padLeft(2, '0')}:${billDate.minute.toString().padLeft(2, '0')}";

    final StringBuffer buffer = StringBuffer();

    if (language == ReceiptLanguage.hindi) {
      buffer.writeln(effectiveInvocation);
      buffer.writeln("🧾 *लव कुश शॉपिङ्ग सेण्टर*");
      buffer.writeln("   *LOVE KUSH SHOPPING CENTER*");
      buffer.writeln("📍 *पता:* ए-२/३९२, सुभाष कंसल मार्ग, हर्ष विहार, दिल्ली - ११००९३");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("📋 *बीजक सङ्ख्या:* ${formatBillNumberHindi(billNo)}");
      buffer.writeln("🗓️ *पञ्चाङ्ग:* ${_formatPanchangTithi(billDate)}");
      buffer.writeln("📅 *दिनाङ्क व समय:* ${formatVedicDateAndTimeString(billDate)}");
      buffer.writeln("👤 *कोषपाल:* $staffName");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("*वस्तु सूची:*");

      for (int i = 0; i < rawItems.length; i++) {
        final item = rawItems[i] is Map ? rawItems[i] as Map : {};
        // Item names always preserved in English as requested
        String itemName = (item['itemName'] ?? item['item'] ?? 'Item').toString().split('\n').first.trim();
        final qty = _toInt(item['qty'], 1);
        final rate = _toDouble(item['rate'], 0.0);
        final lineTotal = _toDouble(item['total'] ?? item['price'], qty * rate);
        buffer.writeln("${i + 1}. $itemName");
        buffer.writeln("    └ ${qty}x @ ₹${rate.toStringAsFixed(2)} = ₹${lineTotal.toStringAsFixed(2)}");
      }

      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("💰 *सकल देय राशि: ₹${totalAmount.toStringAsFixed(2)}*");
      if (isHybrid) {
        buffer.writeln("💳 *भुगतान विधि:* मिश्रित भुगतान");
        buffer.writeln("    └ *रोकड़ा:* ₹${_formatAmount(hybridParts['cash']!)}  •  *ऑनलाइन:* ₹${_formatAmount(hybridParts['online']!)}");
      } else {
        buffer.writeln("💳 *भुगतान विधि:* ${_paymentModeSanskrit(paymentMethod)}");
      }
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("🙏 *सधन्यवाद! पुनः पधारें!*");
      buffer.writeln("🌿 _डिजिटल पीडीएफ बीजक संलग्न है।_");
    } else {
      buffer.writeln(effectiveInvocation);
      buffer.writeln("🧾 *LOVE KUSH SHOPPING CENTER*");
      buffer.writeln("📍 *Address:* A-2/392, Subhash Kansal Marg, Harsh Vihar, Delhi - 110093");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("📋 *Bill No:* $billNo");
      buffer.writeln("📅 *Date & Time:* ${formatEnglishDateAndTimeString(billDate)}");
      buffer.writeln("👤 *Cashier:* $staffName");
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("*Items Purchased:*");

      for (int i = 0; i < rawItems.length; i++) {
        final item = rawItems[i] is Map ? rawItems[i] as Map : {};
        // Item names preserved in English
        String itemName = (item['itemName'] ?? item['item'] ?? 'Item').toString().split('\n').first.trim();
        final qty = _toInt(item['qty'], 1);
        final rate = _toDouble(item['rate'], 0.0);
        final lineTotal = _toDouble(item['total'] ?? item['price'], qty * rate);
        buffer.writeln("${i + 1}. $itemName");
        buffer.writeln("    └ ${qty}x @ ₹${rate.toStringAsFixed(2)} = ₹${lineTotal.toStringAsFixed(2)}");
      }

      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("💰 *GRAND TOTAL: ₹${totalAmount.toStringAsFixed(2)}*");
      if (isHybrid) {
        buffer.writeln("💳 *Payment Method:* HYBRID");
        buffer.writeln("    └ *Cash:* ₹${_formatAmount(hybridParts['cash']!)}  •  *Online:* ₹${_formatAmount(hybridParts['online']!)}");
      } else {
        buffer.writeln("💳 *Payment Method:* ${paymentMethod.toUpperCase()}");
      }
      buffer.writeln("━━━━━━━━━━━━━━━━━━━━");
      buffer.writeln("🙏 *THANK YOU FOR SHOPPING! VISIT AGAIN!*");
      buffer.writeln("🌿 _Digital PDF Bill attached._");
    }

    return buffer.toString();
  }

  /// Clean and validate an Indian mobile number
  static String? sanitizeIndianPhoneNumber(String raw) {
    String clean = raw.replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (clean.length == 10) {
      return "91$clean";
    } else if (clean.length == 11 && clean.startsWith('0')) {
      return "91${clean.substring(1)}";
    } else if (clean.length == 12 && clean.startsWith('91')) {
      return clean;
    }
    return null;
  }

  static const MethodChannel _whatsAppChannel = MethodChannel('com.lovekush.pos/whatsapp');

  /// Attempt to share PDF directly to WhatsApp using native Android Intent (bypassing system chooser)
  static Future<bool> _sharePdfDirectWhatsApp({
    required Uint8List pdfBytes,
    required String filename,
    String? phone,
    String? caption,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? success = await _whatsAppChannel.invokeMethod<bool>(
        'sharePdfToWhatsApp',
        {
          'pdfBytes': pdfBytes,
          'filename': filename,
          'phone': phone,
          'caption': caption,
        },
      );
      return success == true;
    } catch (e) {
      debugPrint("Native WhatsApp direct share error: $e");
      return false;
    }
  }

  /// Send PDF bill file directly via WhatsApp / system share sheet
  static Future<void> sharePdfBill({
    required BuildContext context,
    required Map<String, dynamic> bill,
    String? phone,
    ReceiptLanguage language = ReceiptLanguage.hindi,
    String? invocation,
    bool forceSystemShare = false,
  }) async {
    try {
      final String billNo = (bill['bill_number'] ?? "N/A").toString();
      final String safeBillNo = billNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final pdfBytes = await generateReceiptPdf(bill, language: language, invocation: invocation);
      final double totalAmount = _toDouble(bill['total_amount']);
      final langTag = language == ReceiptLanguage.hindi ? "Hindi" : "English";

      final cleanPhone = phone != null ? sanitizeIndianPhoneNumber(phone) : null;
      if (cleanPhone != null) {
        await Clipboard.setData(ClipboardData(text: cleanPhone));
      }

      final filename = "LoveKush_${langTag}_Bill_$safeBillNo.pdf";
      final subject = "Love Kush Shopping Center ($langTag) - Bill #$billNo (₹${totalAmount.toStringAsFixed(2)})";
      final caption = language == ReceiptLanguage.hindi
          ? "🧾 लव कुश शॉपिङ्ग सेण्टर\nबीजक: #$billNo | राशि: ₹${totalAmount.toStringAsFixed(2)}\n🙏 सधन्यवाद! पुनः पधारें!"
          : "🧾 Love Kush Shopping Center\nBill: #$billNo | Amount: ₹${totalAmount.toStringAsFixed(2)}\n🙏 Thank you! Visit again!";

      // If on Android and system chooser not explicitly forced, send directly to WhatsApp!
      if (!forceSystemShare && !kIsWeb && Platform.isAndroid) {
        final bool sentDirect = await _sharePdfDirectWhatsApp(
          pdfBytes: pdfBytes,
          filename: filename,
          phone: cleanPhone,
          caption: caption,
        );

        if (sentDirect) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  cleanPhone != null
                      ? (language == ReceiptLanguage.hindi
                          ? "WhatsApp पर सीधे PDF भेजा जा रहा है (+${cleanPhone})!"
                          : "Opening WhatsApp directly for +${cleanPhone} with PDF bill!")
                      : (language == ReceiptLanguage.hindi
                          ? "WhatsApp पर PDF बीजक खोला जा रहा है..."
                          : "Opening WhatsApp directly with PDF bill..."),
                ),
                duration: const Duration(seconds: 4),
                backgroundColor: const Color(0xFF047857),
              ),
            );
          }
          return;
        }
      }

      // Fallback to system share sheet (if WhatsApp not installed or explicitly requested)
      if (cleanPhone != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Phone +$cleanPhone copied! Select contact to share PDF."),
            duration: const Duration(seconds: 4),
            backgroundColor: const Color(0xFF047857),
          ),
        );
      }

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: filename,
        subject: subject,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("PDF Share Error: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Send formatted text summary directly to customer's WhatsApp chat
  static Future<void> sendWhatsAppTextMessage({
    required BuildContext context,
    required Map<String, dynamic> bill,
    String? phone,
    ReceiptLanguage language = ReceiptLanguage.hindi,
    String? invocation,
  }) async {
    try {
      final String messageText = formatWhatsAppBillMessage(bill, language: language, invocation: invocation);
      final cleanPhone = phone != null ? sanitizeIndianPhoneNumber(phone) : null;

      if (cleanPhone != null) {
        final waUri = Uri.parse("https://wa.me/$cleanPhone?text=${Uri.encodeComponent(messageText)}");
        final launched = await launchUrl(waUri, mode: LaunchMode.externalApplication);
        if (!launched) {
          await sharePdfBill(context: context, bill: bill, phone: phone, language: language, invocation: invocation);
        }
      } else {
        final waUri = Uri.parse("whatsapp://send?text=${Uri.encodeComponent(messageText)}");
        bool launched = false;
        try {
          launched = await launchUrl(waUri, mode: LaunchMode.externalApplication);
        } catch (_) {
          launched = false;
        }
        if (!launched) {
          await sharePdfBill(context: context, bill: bill, language: language, invocation: invocation);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("WhatsApp Error: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Default shareBill now defaults to sending the PDF document directly!
  static Future<void> shareBill({
    required BuildContext context,
    required Map<String, dynamic> bill,
    String? phone,
    ReceiptLanguage language = ReceiptLanguage.hindi,
  }) => sharePdfBill(context: context, bill: bill, phone: phone, language: language);

  /// Show dialog to select from 10+ preset auspicious Sanskrit mantras or enter a custom one
  static void showMantraSelectionDialog({
    required BuildContext context,
    String? currentMantra,
    Function(String selectedMantra)? onSelected,
  }) {
    showDialog(
      context: context,
      builder: (dialogCtx) {
        String activeMantra = currentMantra ?? currentInvocation;
        final TextEditingController customCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFFEA580C), size: 24),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "मंगलाचरण मन्त्र चुनें",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                        Text(
                          "Select Auspicious Invocation Mantra for Receipts",
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54, size: 20),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Random Mantra Option (Automatic shuffle on every bill)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFEF3C7), Color(0xFFFDE68A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: activeMantra == randomMantraKey ? const Color(0xFFD97706) : Colors.amber.shade400,
                            width: activeMantra == randomMantraKey ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: Radio<String>(
                            value: randomMantraKey,
                            groupValue: activeMantra,
                            activeColor: const Color(0xFFB45309),
                            onChanged: (val) async {
                              if (val != null) {
                                await saveInvocation(val);
                                setDialogState(() => activeMantra = val);
                                onSelected?.call(val);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("🎲 यादृच्छिक मन्त्र सक्रिय! प्रत्येक बिल पर नया पावन मन्त्र मुद्रित होगा।"),
                                      backgroundColor: Color(0xFF047857),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  Navigator.pop(dialogCtx);
                                }
                              }
                            },
                          ),
                          title: const Row(
                            children: [
                              Icon(Icons.shuffle_rounded, size: 18, color: Color(0xFF92400E)),
                              SizedBox(width: 6),
                              Text(
                                "दैनिक / यादृच्छिक मन्त्र (Random Mantra)",
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF78350F)),
                              ),
                            ],
                          ),
                          subtitle: const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              "प्रत्येक बिल पर स्वतः नया पावन मन्त्र (श्री कृष्ण, दुर्गा माँ, महालक्ष्मी, शिव, गणेश, राम आदि)",
                              style: TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                            ),
                          ),
                          onTap: () async {
                            await saveInvocation(randomMantraKey);
                            setDialogState(() => activeMantra = randomMantraKey);
                            onSelected?.call(randomMantraKey);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("🎲 यादृच्छिक मन्त्र सक्रिय! प्रत्येक बिल पर नया पावन मन्त्र मुद्रित होगा।"),
                                  backgroundColor: Color(0xFF047857),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              Navigator.pop(dialogCtx);
                            }
                          },
                        ),
                      ),

                      // Preset Mantras List
                      ...presetMantras.map((m) {
                        final mantraText = m['mantra']!;
                        final isSelected = activeMantra == mantraText;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFFF7ED) : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFF97316) : Colors.grey.shade300,
                              width: isSelected ? 1.8 : 1,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            leading: Radio<String>(
                              value: mantraText,
                              groupValue: activeMantra,
                              activeColor: const Color(0xFFEA580C),
                              onChanged: (val) async {
                                if (val != null) {
                                  await saveInvocation(val);
                                  setDialogState(() => activeMantra = val);
                                  onSelected?.call(val);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text("मन्त्र अद्यतन: $val"),
                                        backgroundColor: const Color(0xFF047857),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                    Navigator.pop(dialogCtx);
                                  }
                                }
                              },
                            ),
                            title: Text(
                              mantraText,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isSelected ? const Color(0xFF9A3412) : Colors.black87,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                "${m['title']} • ${m['occasion']}",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? const Color(0xFFC2410C) : Colors.black54,
                                ),
                              ),
                            ),
                            onTap: () async {
                              await saveInvocation(mantraText);
                              setDialogState(() => activeMantra = mantraText);
                              onSelected?.call(mantraText);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("मन्त्र अद्यतन: $mantraText"),
                                    backgroundColor: const Color(0xFF047857),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                Navigator.pop(dialogCtx);
                              }
                            },
                          ),
                        );
                      }).toList(),

                      const Divider(height: 20),

                      // Custom Mantra Section
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blueGrey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.edit_note, color: Colors.blueAccent, size: 20),
                                SizedBox(width: 6),
                                Text(
                                  "अपनी पसंद का मन्त्र लिखें (Custom Mantra):",
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              "साँथिया (࿗) स्वतः आगे व पीछे जोड़ दिया जाएगा। (e.g. ॐ दुं दुर्गायै नमः)",
                              style: TextStyle(fontSize: 11, color: Colors.black54),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: customCtrl,
                                    decoration: InputDecoration(
                                      hintText: "उदा. ॐ दुं दुर्गायै नमः",
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFEA580C),
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: () async {
                                    final text = customCtrl.text.trim();
                                    if (text.isNotEmpty) {
                                      final customMantra = ensureSathiya(text);
                                      await saveInvocation(customMantra);
                                      setDialogState(() => activeMantra = customMantra);
                                      onSelected?.call(customMantra);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text("कस्टम मन्त्र सेट किया: $customMantra"),
                                            backgroundColor: const Color(0xFF047857),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                        Navigator.pop(dialogCtx);
                                      }
                                    }
                                  },
                                  child: const Text("लागू करें", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text("रद्द करें (Cancel)", style: TextStyle(color: Colors.black54)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Show interactive WhatsApp & PDF options dialog with bilingual switcher
  static void showWhatsAppPdfDialog({
    required BuildContext context,
    required Map<String, dynamic> bill,
    ReceiptLanguage initialLanguage = ReceiptLanguage.hindi,
  }) {
    final phoneController = TextEditingController();
    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final double totalAmount = _toDouble(bill['total_amount']);
    final rawItems = _extractItems(bill['items_json']);
    ReceiptLanguage selectedLanguage = initialLanguage;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isHindi = selectedLanguage == ReceiptLanguage.hindi;
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title Row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.share, color: Color(0xFF25D366), size: 24),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                "Send Bill on WhatsApp / PDF",
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Bilingual Switcher Segmented Control
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      selectedLanguage = ReceiptLanguage.hindi;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isHindi ? const Color(0xFF111827) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: isHindi ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))] : null,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text("🇮🇳 ", style: TextStyle(fontSize: 14)),
                                          Text(
                                            "हिन्दी बिल",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: isHindi ? Colors.white : Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    setDialogState(() {
                                      selectedLanguage = ReceiptLanguage.english;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: !isHindi ? const Color(0xFF111827) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: !isHindi ? [const BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))] : null,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Text("🇬🇧 ", style: TextStyle(fontSize: 14)),
                                          Text(
                                            "English Bill",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: !isHindi ? Colors.white : Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Bill Info Chip
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  "Bill: #$billNo",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text("${rawItems.length} items", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                              const SizedBox(width: 8),
                              Text(
                                "₹${totalAmount.toStringAsFixed(2)}",
                                style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF047857), fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Customer Phone Number Input
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              isHindi ? "ग्राहक का मोबाइल (WhatsApp):" : "Customer Mobile (WhatsApp):",
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87),
                            ),
                            Text(
                              isHindi ? "बिना नम्बर सेव किये" : "No contact save needed",
                              style: const TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: phoneController,
                          keyboardType: TextInputType.phone,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: isHindi ? "१० अंकों का मोबाइल (उदा. 9812345678)" : "10-digit mobile (e.g. 9812345678)",
                            prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF0D9488)),
                            prefixText: "+91 ",
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Mangalacharan Mantra Selector Bar (Shows active mantra / random badge)
                        if (isHindi) ...[
                          InkWell(
                            onTap: () {
                              showMantraSelectionDialog(
                                context: context,
                                currentMantra: currentInvocation,
                                onSelected: (newMantra) {
                                  setDialogState(() {});
                                },
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFDBA74)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.temple_hindu, size: 16, color: Color(0xFFEA580C)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      currentInvocation == randomMantraKey
                                          ? "🎲 यादृच्छिक मन्त्र (Random Mantra on Every Bill)"
                                          : currentInvocation,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF9A3412),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    "बदलें",
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEA580C)),
                                  ),
                                  const Icon(Icons.chevron_right, size: 16, color: Color(0xFFEA580C)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Action Button 1: Send Direct WhatsApp Chat Message (Instant, no saving number required)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.chat, color: Colors.white, size: 20),
                          label: Text(
                            isHindi ? "सीधे WHATSAPP चैट खोलें (Direct Chat)" : "OPEN DIRECT WHATSAPP CHAT",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF25D366),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            final phone = phoneController.text.trim();
                            Navigator.pop(ctx);
                            sendWhatsAppTextMessage(
                              context: context,
                              bill: bill,
                              phone: phone.isNotEmpty ? phone : null,
                              language: selectedLanguage,
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        // Action Button 2: Direct WhatsApp PDF file (Opens WhatsApp directly, no system chooser)
                        ElevatedButton.icon(
                          icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                          label: Text(
                            isHindi ? "WHATSAPP पर PDF बीजक भेजें" : "SEND PDF BILL ON WHATSAPP",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E), // Deep Teal
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            final phone = phoneController.text.trim();
                            Navigator.pop(ctx);
                            sharePdfBill(
                              context: context,
                              bill: bill,
                              phone: phone.isNotEmpty ? phone : null,
                              language: selectedLanguage,
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        // Action Buttons Row: Preview & Other Apps / System Share
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.visibility, color: Color(0xFF2563EB), size: 16),
                                label: Text(
                                  isHindi ? "बिल देखें" : "PREVIEW",
                                  style: const TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  side: const BorderSide(color: Color(0xFF2563EB)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  openPdfPreviewDialog(
                                    context: context,
                                    bill: bill,
                                    initialLanguage: selectedLanguage,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.share, color: Colors.black87, size: 16),
                                label: Text(
                                  isHindi ? "अन्य ऐप्स" : "OTHER APPS",
                                  style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 11),
                                  side: const BorderSide(color: Colors.grey),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () {
                                  final phone = phoneController.text.trim();
                                  Navigator.pop(ctx);
                                  sharePdfBill(
                                    context: context,
                                    bill: bill,
                                    phone: phone.isNotEmpty ? phone : null,
                                    language: selectedLanguage,
                                    forceSystemShare: true,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                isHindi ? "रद्द" : "CANCEL",
                                style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Open local interactive vector PDF preview screen inside the app with bilingual toggle
  static void openPdfPreviewDialog({
    required BuildContext context,
    required Map<String, dynamic> bill,
    ReceiptLanguage initialLanguage = ReceiptLanguage.hindi,
    Future<void> Function(ReceiptLanguage language)? onThermalPrint,
  }) {
    final String billNo = (bill['bill_number'] ?? "N/A").toString();
    final String safeBillNo = billNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    ReceiptLanguage selectedLanguage = initialLanguage;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setPreviewState) {
            final isHindi = selectedLanguage == ReceiptLanguage.hindi;
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
                child: Scaffold(
                  backgroundColor: Colors.white,
                  appBar: AppBar(
                    title: Text(
                      "PDF Invoice - Bill #$billNo",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    backgroundColor: const Color(0xFF111827),
                    iconTheme: const IconThemeData(color: Colors.white),
                    actions: [
                      // Language Toggle Buttons in AppBar
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                if (selectedLanguage != ReceiptLanguage.hindi) {
                                  setPreviewState(() {
                                    selectedLanguage = ReceiptLanguage.hindi;
                                  });
                                }
                              },
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isHindi ? const Color(0xFF2563EB) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                                ),
                                child: Text(
                                  "🇮🇳 हिन्दी",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isHindi ? FontWeight.bold : FontWeight.normal,
                                    color: isHindi ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                if (selectedLanguage != ReceiptLanguage.english) {
                                  setPreviewState(() {
                                    selectedLanguage = ReceiptLanguage.english;
                                  });
                                }
                              },
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: !isHindi ? const Color(0xFF2563EB) : Colors.transparent,
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                                ),
                                child: Text(
                                  "🇬🇧 English",
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: !isHindi ? FontWeight.bold : FontWeight.normal,
                                    color: !isHindi ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (onThermalPrint != null)
                        IconButton(
                          icon: const Icon(Icons.print, color: Color(0xFF10B981)),
                          tooltip: "Print to Bluetooth Thermal Printer",
                          onPressed: () => onThermalPrint(selectedLanguage),
                        ),
                      IconButton(
                        icon: const Icon(Icons.share, color: Color(0xFF25D366)),
                        tooltip: "Send on WhatsApp",
                        onPressed: () {
                          Navigator.pop(ctx);
                          showWhatsAppPdfDialog(
                            context: context,
                            bill: bill,
                            initialLanguage: selectedLanguage,
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: "Close",
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  body: PdfPreview(
                    key: ValueKey(selectedLanguage),
                    build: (format) => generateReceiptPdf(
                      bill,
                      pageFormat: format,
                      language: selectedLanguage,
                    ),
                    allowPrinting: true,
                    allowSharing: true,
                    canChangePageFormat: true,
                    canChangeOrientation: false,
                    pageFormats: const <String, PdfPageFormat>{
                      '80mm Thermal (3-inch)': PdfPageFormat(
                        80 * PdfPageFormat.mm,
                        double.infinity,
                        marginAll: 4 * PdfPageFormat.mm,
                      ),
                      '58mm Thermal (2-inch)': PdfPageFormat(
                        58 * PdfPageFormat.mm,
                        double.infinity,
                        marginAll: 2 * PdfPageFormat.mm,
                      ),
                    },
                    initialPageFormat: const PdfPageFormat(
                      80 * PdfPageFormat.mm,
                      double.infinity,
                      marginAll: 4 * PdfPageFormat.mm,
                    ),
                    pdfFileName: "LoveKush_${selectedLanguage == ReceiptLanguage.hindi ? 'Hindi' : 'English'}_Bill_$safeBillNo.pdf",
                    maxPageWidth: 420,
                    loadingWidget: const Center(
                      child: CircularProgressIndicator(),
                    ),
                    onError: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text("Error previewing PDF: $error", style: const TextStyle(color: Colors.red)),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ReceiptItem {
  final String name;
  final int qty;
  final double rate;
  final double lineTotal;

  const _ReceiptItem({
    required this.name,
    required this.qty,
    required this.rate,
    required this.lineTotal,
  });
}
