import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'vedic_time_service.dart';

class VedicClockScreen extends StatefulWidget {
  const VedicClockScreen({Key? key}) : super(key: key);

  @override
  State<VedicClockScreen> createState() => _VedicClockScreenState();
}

class _VedicClockScreenState extends State<VedicClockScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  // Converter 1: Clock -> Vedic
  final TextEditingController _hourCtrl = TextEditingController(text: "13");
  final TextEditingController _minCtrl = TextEditingController(text: "27");
  final TextEditingController _secCtrl = TextEditingController(text: "06");
  final TextEditingController _customSunriseCtrl = TextEditingController(text: "06:04:18");
  VedicTime? _convertedVedicTime;
  String _converter1Breakdown = "";

  // Converter 2: Vedic -> Clock
  final TextEditingController _ghatiCtrl = TextEditingController(text: "18");
  final TextEditingController _palCtrl = TextEditingController(text: "27");
  final TextEditingController _vipalCtrl = TextEditingController(text: "00");
  DateTime? _convertedClockTime;
  String _converter2Breakdown = "";

  // Mode: 60 Ghati (24h Ahoratra) vs 30 Ghati (12h cycle)
  bool _is30GhatiMode = false;
  bool _converter30GhatiMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _startClock();
    _performClockToVedicConversion();
    _performVedicToClockConversion();
  }

  void _startClock() {
    // 1 Vipal = 0.4 seconds = 400 milliseconds.
    // Ticking every 400ms allows the Vedic Vipal counter to increment smoothly 1-by-1
    _ticker = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _tabController.dispose();
    _hourCtrl.dispose();
    _minCtrl.dispose();
    _secCtrl.dispose();
    _customSunriseCtrl.dispose();
    _ghatiCtrl.dispose();
    _palCtrl.dispose();
    _vipalCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseCustomSunrise() {
    final text = _customSunriseCtrl.text.trim();
    final parts = text.split(':');
    if (parts.length >= 2) {
      final h = int.tryParse(parts[0]) ?? 6;
      final m = int.tryParse(parts[1]) ?? 4;
      final s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 18) : 0;
      return DateTime(_now.year, _now.month, _now.day, h, m, s);
    }
    return null;
  }

  void _performClockToVedicConversion() {
    final h = int.tryParse(_hourCtrl.text.trim()) ?? _now.hour;
    final m = int.tryParse(_minCtrl.text.trim()) ?? _now.minute;
    final s = int.tryParse(_secCtrl.text.trim()) ?? _now.second;

    final targetTime = DateTime(_now.year, _now.month, _now.day, h, m, s);
    final sunrise = _parseCustomSunrise() ?? VedicTimeService.getLocalSunrise(_now);
    final sunriseStr = "${sunrise.hour.toString().padLeft(2, '0')}:${sunrise.minute.toString().padLeft(2, '0')}:${sunrise.second.toString().padLeft(2, '0')}";
    final targetStr = "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";

    if (_converter30GhatiMode) {
      final solar = VedicTimeService.calculateSolarTimings(targetTime);
      final sunset = solar.sunset;
      final sunsetStr = "${sunset.hour.toString().padLeft(2, '0')}:${sunset.minute.toString().padLeft(2, '0')}:${sunset.second.toString().padLeft(2, '0')}";
      final dayDuration = sunset.difference(sunrise);
      final daySec = dayDuration.inSeconds;
      final ghatiLenSec = daySec / 30.0;

      final vt = VedicTimeService.normalToVedic30Ghati(
        targetTime,
        overrideSunrise: sunrise,
        overrideSunset: sunset,
      );

      final elapsed = targetTime.difference(sunrise);
      final totalSec = elapsed.inSeconds;

      final breakdown = StringBuffer();
      breakdown.writeln("1. पद्धति: द्रिक पञ्चाङ्ग ३० घटी दिनमान मान (Drik Panchang 30-Ghati Mode)");
      breakdown.writeln("2. सूर्योदय: $sunriseStr IST | सूर्यास्त: $sunsetStr IST");
      breakdown.writeln("3. कुल दिनमान: ${dayDuration.inHours}घ ${dayDuration.inMinutes % 60}मि ${dayDuration.inSeconds % 60}से (= $daySec सेकण्ड)");
      breakdown.writeln("4. १ घटी का मान: $daySec ÷ 30 = ${ghatiLenSec.toStringAsFixed(2)} सेकण्ड (~${(ghatiLenSec / 60).floor()} मिनट ${(ghatiLenSec % 60).round()} सेकण्ड)");
      breakdown.writeln("5. सूर्योदय से व्यतीत समय: ${elapsed.inHours}घ ${elapsed.inMinutes % 60}मि ${elapsed.inSeconds % 60}से (= $totalSec सेकण्ड)");
      breakdown.writeln("6. घटी गणना: ($totalSec ÷ $daySec) × 30 = ${vt.ghati} घटी");
      breakdown.writeln("7. पल व विपल: ${vt.pal} पल, ${vt.vipal.toStringAsFixed(1)} विपल");
      breakdown.writeln("👉 द्रिक पञ्चाङ्ग परिणाम: ${vt.toNumericString()} घटी:पल:विपल");
      breakdown.writeln("⚡ द्रिक पञ्चाङ्ग प्रमाण: दिनमान के अनुपात से सूर्यास्त पर ठीक ३०:००:०० घटी होती है।");

      setState(() {
        _convertedVedicTime = vt;
        _converter1Breakdown = breakdown.toString();
      });
      return;
    }

    // 60-Ghati fixed Ishtakala mode
    final vt = VedicTimeService.normalToVedic(targetTime, overrideSunrise: sunrise);

    Duration elapsed;
    if (targetTime.isBefore(sunrise)) {
      final prevDaySunrise = sunrise.subtract(const Duration(days: 1));
      elapsed = targetTime.difference(prevDaySunrise);
    } else {
      elapsed = targetTime.difference(sunrise);
    }

    final totalSec = elapsed.inSeconds;
    final ghatiSec = vt.ghati * 1440;
    final remAfterGhati = totalSec - ghatiSec;
    final palSec = vt.pal * 24;
    final remAfterPal = remAfterGhati - palSec;

    final breakdown = StringBuffer();
    breakdown.writeln("1. पद्धति: ६० घटी इष्टकाल मान (Fixed 24-minute Ghati Mode)");
    breakdown.writeln("2. सूर्योदय (Sunrise): $sunriseStr IST");
    breakdown.writeln("3. अभीष्ट समय (Target Time): $targetStr IST");
    breakdown.writeln("4. सूर्योदय से व्यतीत कुल समय (इष्टकाल): ${elapsed.inHours} घण्टे ${elapsed.inMinutes % 60} मिनट ${elapsed.inSeconds % 60} सेकण्ड (= $totalSec सेकण्ड)");
    breakdown.writeln("5. घटी गणना: $totalSec ÷ 1440 = ${vt.ghati} घटी (1 घटी = 24 मिनट = 1440 सेकण्ड)");
    breakdown.writeln("6. शेष सेकण्ड: $totalSec - $ghatiSec = $remAfterGhati सेकण्ड");
    breakdown.writeln("7. पल गणना: $remAfterGhati ÷ 24 = ${vt.pal} पल (1 पल = 24 सेकण्ड)");
    breakdown.writeln("8. शेष सेकण्ड: $remAfterGhati - $palSec = $remAfterPal सेकण्ड");
    breakdown.writeln("9. विपल गणना: $remAfterPal ÷ 0.4 = ${vt.vipal.toStringAsFixed(1)} विपल (1 विपल = 0.4 सेकण्ड)");
    breakdown.writeln("👉 इष्टकाल परिणाम: ${vt.toNumericString()} घटी:पल:विपल");
    breakdown.writeln("⚡ गति नियम (2.5x Speed Rule): 1 सामान्य घंटा = 2.5 घटी (2 घटी 30 पल)। 60 घटी ÷ 24 घंटे = 2.5 गुना गति।");

    setState(() {
      _convertedVedicTime = vt;
      _converter1Breakdown = breakdown.toString();
    });
  }

  void _performVedicToClockConversion() {
    final ghati = int.tryParse(_ghatiCtrl.text.trim()) ?? 0;
    final pal = int.tryParse(_palCtrl.text.trim()) ?? 0;
    final vipal = double.tryParse(_vipalCtrl.text.trim()) ?? 0.0;

    final sunrise = _parseCustomSunrise() ?? VedicTimeService.getLocalSunrise(_now);
    final sunriseStr = "${sunrise.hour.toString().padLeft(2, '0')}:${sunrise.minute.toString().padLeft(2, '0')}:${sunrise.second.toString().padLeft(2, '0')}";

    if (_converter30GhatiMode) {
      final solar = VedicTimeService.calculateSolarTimings(_now);
      final sunset = solar.sunset;
      final sunsetStr = "${sunset.hour.toString().padLeft(2, '0')}:${sunset.minute.toString().padLeft(2, '0')}:${sunset.second.toString().padLeft(2, '0')}";
      final dayDuration = sunset.difference(sunrise);

      final converted = VedicTimeService.vedicToNormal30Ghati(
        ghati: ghati,
        pal: pal,
        vipal: vipal,
        date: _now,
        overrideSunrise: sunrise,
        overrideSunset: sunset,
      );

      final breakdown = StringBuffer();
      breakdown.writeln("1. पद्धति: द्रिक पञ्चाङ्ग ३० घटी दिनमान मान");
      breakdown.writeln("2. दिया गया वैदिक समय: $ghati घटी, $pal पल, ${vipal.toStringAsFixed(1)} विपल");
      breakdown.writeln("3. सूर्योदय: $sunriseStr IST | सूर्यास्त: $sunsetStr IST");
      breakdown.writeln("4. कुल दिनमान: ${dayDuration.inHours}घ ${dayDuration.inMinutes % 60}मि ${dayDuration.inSeconds % 60}से");
      breakdown.writeln("5. दिनमान आनुपातिक गणना: ($ghati + $pal/60 + ${vipal.toStringAsFixed(1)}/3600) ÷ 30");
      breakdown.writeln("👉 परिणाम (Result): ${_formatClockTime(converted)} IST (${_format12HourTime(converted)})");

      setState(() {
        _convertedClockTime = converted;
        _converter2Breakdown = breakdown.toString();
      });
      return;
    }

    // 60-Ghati fixed Ishtakala mode
    final converted = VedicTimeService.vedicToNormal(
      ghati: ghati,
      pal: pal,
      vipal: vipal,
      date: _now,
      overrideSunrise: sunrise,
    );

    final totalElapsedSec = (ghati * 1440.0) + (pal * 24.0) + (vipal * 0.4);

    final breakdown = StringBuffer();
    breakdown.writeln("1. पद्धति: ६० घटी इष्टकाल मान");
    breakdown.writeln("2. दिया गया वैदिक समय: $ghati घटी, $pal पल, ${vipal.toStringAsFixed(1)} विपल");
    breakdown.writeln("3. कुल व्यतीत सेकण्ड: ($ghati × 1440) + ($pal × 24) + ($vipal × 0.4) = ${totalElapsedSec.toStringAsFixed(1)} सेकण्ड");
    breakdown.writeln("4. सूर्योदय का आधार: $sunriseStr IST");
    breakdown.writeln("5. सामान्य घड़ी समय: सूर्योदय + ${totalElapsedSec.toStringAsFixed(1)} सेकण्ड");
    breakdown.writeln("👉 परिणाम (Result): ${_formatClockTime(converted)} IST");

    setState(() {
      _convertedClockTime = converted;
      _converter2Breakdown = breakdown.toString();
    });
  }

  String _formatClockTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return "$h:$m:$s";
  }

  String _format12HourTime(DateTime dt) {
    final h12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    return "${h12.toString().padLeft(2, '0')}:$m:$s $ampm";
  }

  String _formatVedicDateString(DateTime dt) {
    const hindiMonths = [
      "जनवरी", "फरवरी", "मार्च", "अप्रैल", "मई", "जून",
      "जुलाई", "अगस्त", "सितम्बर", "अक्टूबर", "नवम्बर", "दिसम्बर"
    ];
    return "${hindiMonths[dt.month - 1]} ${dt.day}, ${dt.year}";
  }

  void _copyToClipboard(String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareToWhatsApp(String text) async {
    final encoded = Uri.encodeComponent(text);
    final uri = Uri.parse("https://wa.me/?text=$encoded");
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _copyToClipboard(text, "कॉपी किया गया (WhatsApp लिंक नहीं खुला)");
    }
  }

  @override
  Widget build(BuildContext context) {
    final panchang = VedicTimeService.calculatePanchang(_now);
    final liveVedic = _is30GhatiMode
        ? VedicTimeService.normalToVedic30Ghati(_now)
        : panchang.vedicTime;
    final solar = panchang.solar;

    final sunriseStr = "${solar.sunrise.hour.toString().padLeft(2, '0')}:${solar.sunrise.minute.toString().padLeft(2, '0')}:${solar.sunrise.second.toString().padLeft(2, '0')}";
    final sunsetStr = "${solar.sunset.hour.toString().padLeft(2, '0')}:${solar.sunset.minute.toString().padLeft(2, '0')}:${solar.sunset.second.toString().padLeft(2, '0')}";

    // Day/Night progress
    final double dayFraction = _is30GhatiMode
        ? (liveVedic.ghati + (liveVedic.pal / 60.0)) / 30.0
        : (liveVedic.ghati + (liveVedic.pal / 60.0)) / 60.0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text("वैदिक समय एवं पञ्चाङ्ग", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87)),
            Text("Vedic Clock • नई दिल्ली (New Delhi, IST)", style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                const Text("LIVE", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            tooltip: "कॉपी करें (Copy Details)",
            icon: const Icon(Icons.copy, color: Colors.black87),
            onPressed: () {
              final shareText = "🕉️ लव कुश वैदिक समय एवं पञ्चाङ्ग (New Delhi)\n"
                  "वैदिक समय: ${liveVedic.toDevanagariString()} (${liveVedic.toNumericString()}) [${_is30GhatiMode ? 'द्रिक ३० घटी' : '६० घटी इष्टकाल'}]\n"
                  "वैदिक वार: ${panchang.fullVaarDisplay}\n"
                  "दिनांक व समय: ${panchang.fullVaarDisplay}, ${_formatVedicDateString(_now)} | ${_formatClockTime(_now)} IST\n"
                  "सूर्योदय: $sunriseStr | सूर्यास्त: $sunsetStr\n"
                  "पञ्चाङ्ग: ${panchang.toReceiptPanchangLine()}\n"
                  "दिनमान: ${solar.dayLengthGhatis.toStringAsFixed(2)} घटी | रात्रिमान: ${solar.nightLengthGhatis.toStringAsFixed(2)} घटी\n"
                  "मुहूर्त: ${panchang.muhurta}";
              _copyToClipboard(shareText, "वैदिक समय व पञ्चाङ्ग कॉपी किया गया");
            },
          ),
          IconButton(
            tooltip: "व्हाट्सएप पर साझा करें",
            icon: const Icon(Icons.share, color: Colors.green),
            onPressed: () {
              final shareText = "🕉️ *लव कुश वैदिक समय एवं पञ्चाङ्ग* (New Delhi)\n"
                  "⏰ *वैदिक समय:* ${liveVedic.toDevanagariString()} (${liveVedic.toNumericString()}) [${_is30GhatiMode ? 'द्रिक ३० घटी' : '६० घटी इष्टकाल'}]\n"
                  "🔱 *वैदिक वार:* ${panchang.fullVaarDisplay}\n"
                  "📅 *दिनांक व समय:* ${panchang.fullVaarDisplay}, ${_formatVedicDateString(_now)} | ${_formatClockTime(_now)} IST\n"
                  "🌅 *सूर्योदय:* $sunriseStr | 🌇 *सूर्यास्त:* $sunsetStr\n"
                  "📜 *पञ्चाङ्ग:* ${panchang.toReceiptPanchangLine()}\n"
                  "☀️ *दिनमान:* ${solar.dayLengthGhatis.toStringAsFixed(2)} घटी | *रात्रिमान:* ${solar.nightLengthGhatis.toStringAsFixed(2)} घटी\n"
                  "✨ *मुहूर्त:* ${panchang.muhurta}";
              _shareToWhatsApp(shareText);
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFB45309),
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: const Color(0xFFD97706),
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.access_time_filled, size: 20), text: "लाइव घड़ी (Live)"),
            Tab(icon: Icon(Icons.sync_alt, size: 20), text: "परिवर्तक (Converter)"),
            Tab(icon: Icon(Icons.menu_book, size: 20), text: "प्रमाण व सूत्र (Rules)"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: LIVE VEDIC CLOCK & PANCHANG
          _buildLiveClockTab(liveVedic, panchang, solar, sunriseStr, sunsetStr, dayFraction),

          // TAB 2: BIDIRECTIONAL CONVERTER
          _buildConverterTab(sunriseStr),

          // TAB 3: RULES & FORMULAS
          _buildRulesTab(),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: LIVE VEDIC CLOCK
  // ==========================================
  Widget _buildLiveClockTab(
    VedicTime liveVedic,
    VedicPanchang panchang,
    SolarTimings solar,
    String sunriseStr,
    String sunsetStr,
    double dayFraction,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. HERO LIVE VEDIC CLOCK CARD
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB45309), Color(0xFFD97706), Color(0xFFF59E0B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.amber.shade300.withOpacity(0.5), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text("卐  श्री गणेशाय नमः  卐", style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ],
                ),
                const SizedBox(height: 8),

                // Authentic Devanagari Vedic Panchang & Vedic Vaar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    "${panchang.masa}, ${panchang.paksha} पक्ष, ${VedicTime.toDevanagariDigits(panchang.samvat)} विक्रम संवत् • वैदिक वार: ${panchang.fullVaarDisplay}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 30 Ghati vs 60 Ghati Mode Toggle
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _is30GhatiMode = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: !_is30GhatiMode ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            "60 घटी (इष्टकाल - 24m)",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: !_is30GhatiMode ? const Color(0xFFB45309) : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _is30GhatiMode = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: _is30GhatiMode ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            "30 घटी (द्रिक पञ्चाङ्ग)",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _is30GhatiMode ? const Color(0xFFB45309) : Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                const Text("वैदिक समय (घटी : पल : विपल)", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1)),
                const SizedBox(height: 6),

                // Devanagari Digits
                Builder(builder: (context) {
                  final timeStr = "${liveVedic.ghati.toString().padLeft(2, '0')}:${liveVedic.pal.toString().padLeft(2, '0')}:${liveVedic.vipal.round().toString().padLeft(2, '0')}";
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      VedicTime.toDevanagariDigits(timeStr),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 54,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        fontFamily: 'serif',
                      ),
                    ),
                  );
                }),

                // English Digits
                Builder(builder: (context) {
                  final timeStr = "${liveVedic.ghati.toString().padLeft(2, '0')}:${liveVedic.pal.toString().padLeft(2, '0')}:${liveVedic.vipal.round().toString().padLeft(2, '0')}";
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "$timeStr (${_is30GhatiMode ? 'द्रिक ३० घटी मान' : '६० घटी इष्टकाल'})",
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                  );
                }),
                const SizedBox(height: 10),

                // Verbal Hindi
                Text(
                  "${VedicTime.toDevanagariDigits(liveVedic.ghati)} घटी, ${VedicTime.toDevanagariDigits(liveVedic.pal)} पल, ${VedicTime.toDevanagariDigits(liveVedic.vipal.round())} विपल",
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const Divider(color: Colors.white24, height: 24),

                // Gregorian Comparison
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text("ग्रेगोरियन समय (IST)", style: TextStyle(color: Colors.white70, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(
                          _formatClockTime(_now),
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(_format12HourTime(_now), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                    Container(height: 36, width: 1, color: Colors.white30),
                    Column(
                      children: [
                        const Text("इष्टकाल (व्यतीत समय)", style: TextStyle(color: Colors.white70, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(
                          "${(liveVedic.totalSecondsSinceSunrise / 3600).floor()}घ ${((liveVedic.totalSecondsSinceSunrise % 3600) / 60).floor()}मि",
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text("${liveVedic.totalSecondsSinceSunrise.round()} सेकण्ड", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ],
                ),

                // Single-line Gregorian Date and Time with Vedic Vaar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Colors.amberAccent),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          "${panchang.fullVaarDisplay}, ${_formatVedicDateString(_now)} | ${_formatClockTime(_now)} IST",
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),

                // Speed Ratio Banner
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, color: Colors.amberAccent, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _is30GhatiMode
                              ? "द्रिक ३० घटी मान: सूर्योदय 00:00 • सूर्यास्त ठीक 30:00:00 घटी • 1 घटी = ~24m 51s"
                              : "इष्टकाल ६० घटी मान: 1 सेकण्ड = 2.5 विपल • 24 मिनट = 1 घटी • 2.5x गति",
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. SPEED RATIO EXPLANATION CARD (WHY VEDIC TIME RUNS 2.5X FASTER)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.speed, color: Color(0xFFD97706), size: 20),
                    SizedBox(width: 8),
                    Text("वैदिक समय की गति तेज क्यों होती है? (2.5x Speed)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF92400E))),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  "वैदिक प्रणाली में 24 घण्टे के अहोरात्र को 60 घटियों में बाँटा गया है (24 के स्थान पर 60)।\n"
                  "अतः वैदिक समय सामान्य घड़ी से ठीक २.५ गुना तेज (60 ÷ 24 = 2.5x) चलता है:",
                  style: TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("आधुनिक घड़ी (24h)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                            SizedBox(height: 4),
                            Text("• 1 सेकण्ड = 1 सेकण्ड\n• 1 मिनट = 60 सेकण्ड\n• 1 घण्टा = 60 मिनट\n• 24 घण्टे = 1 दिन", style: TextStyle(fontSize: 11, height: 1.4)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade300)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text("वैदिक घड़ी (60 घटी)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF92400E))),
                            SizedBox(height: 4),
                            Text("• 1 सेकण्ड = 2.5 विपल (तेज)\n• 24 सेकण्ड = 1 पल (तेज)\n• 24 मिनट = 1 घटी (तेज)\n• 60 घटी = 1 दिन (2.5x)", style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF92400E))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "प्रत्येक 1 घण्टे में वैदिक समय ठीक +2 घटी 30 पल (+2.5 घटी) आगे बढ़ता है।",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. DAY PROGRESS BAR (60 GHATIS)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("अहोरात्र चक्र (Ahoratra Cycle)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                    Text("${(dayFraction * 60).toStringAsFixed(1)} / 60 घटी", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: dayFraction.clamp(0.0, 1.0),
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFD97706)),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text("सूर्योदय (00:00 घटी)", style: TextStyle(fontSize: 10, color: Colors.black54)),
                    Text("मध्याह्न (15:00)", style: TextStyle(fontSize: 10, color: Colors.black54)),
                    Text("सूर्यास्त (~31:00)", style: TextStyle(fontSize: 10, color: Colors.black54)),
                    Text("पूर्ण दिन (60:00)", style: TextStyle(fontSize: 10, color: Colors.black54)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. SOLAR TIMINGS CARD
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.wb_sunny, color: Color(0xFFD97706), size: 20),
                    SizedBox(width: 8),
                    Text("सूर्य चक्र एवं दिनमान (Solar Timings - New Delhi)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF92400E))),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.wb_twilight,
                        iconColor: Colors.orange,
                        label: "सूर्योदय (Sunrise)",
                        value: "$sunriseStr AM",
                        subValue: "00:00:00 घटी",
                      ),
                    ),
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.nightlight_round,
                        iconColor: Colors.indigo,
                        label: "सूर्यास्त (Sunset)",
                        value: "$sunsetStr PM",
                        subValue: _is30GhatiMode ? "30:00:00 घटी (द्रिक मान)" : "${solar.dayLengthGhatis.toStringAsFixed(2)} घटी",
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.wb_sunny_outlined,
                        iconColor: Colors.amber.shade800,
                        label: "दिनमान (Day Length)",
                        value: _is30GhatiMode ? "30.00 घटी (३० घटी मान)" : "${solar.dayLengthGhatis.toStringAsFixed(2)} घटी",
                        subValue: "${solar.dayDuration.inHours}घ ${solar.dayDuration.inMinutes % 60}मि",
                      ),
                    ),
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.bedtime_outlined,
                        iconColor: Colors.purple,
                        label: "रात्रिमान (Night Length)",
                        value: _is30GhatiMode ? "30.00 घटी (३० घटी मान)" : "${solar.nightLengthGhatis.toStringAsFixed(2)} घटी",
                        subValue: "${solar.nightDuration.inHours}घ ${solar.nightDuration.inMinutes % 60}मि",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. AUTHENTIC PANCHANG CARD
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.auto_stories, color: Colors.blueAccent, size: 20),
                    SizedBox(width: 8),
                    Text("दैनिक शुद्ध पञ्चाङ्ग (Authentic Vedic Panchang)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A))),
                  ],
                ),
                const Divider(height: 20),
                _buildPanchangRow("विक्रम संवत्", "${VedicTime.toDevanagariDigits(panchang.samvat)} संवत् (${panchang.samvat})"),
                _buildPanchangRow("मास एवं पक्ष", "${panchang.masa}, ${panchang.paksha} पक्ष"),
                _buildPanchangRow("उदय तिथि", "${panchang.udayaTithi} (सूर्योदय कालीन)"),
                _buildPanchangRow("वर्तमान तिथि", panchang.currentTithi),
                _buildPanchangRow("वैदिक वार (Vedic Vaar)", "${panchang.fullVaarDisplay} • अहोरात्र (सूर्योदय) आधारित"),
                _buildPanchangRow("वर्तमान प्रहर", panchang.pahar),
                _buildPanchangRow("वर्तमान मुहूर्त", panchang.muhurta),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long, size: 18, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "बिल रसीद प्रारूप: ${panchang.toReceiptPanchangLine()}",
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E3A8A)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: BIDIRECTIONAL CONVERTER
  // ==========================================
  Widget _buildConverterTab(String defaultSunrise) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Notice banner explaining how to match online
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: const [
                Icon(Icons.verified, color: Color(0xFFD97706), size: 24),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "यह परिवर्तक hinducalendar.app, nakshtratak.com एवं astrosage.com के 100% प्रामाणिक सूत्रों पर आधारित है। किसी भी ऑनलाइन सेवा से मिलान के लिये नीचे समय दर्ज करें।",
                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E), height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Mode Toggle for Converter: 60 Ghati (Ishtakala) vs 30 Ghati (Drik Panchang Dinamana)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _converter30GhatiMode = false;
                      });
                      _performClockToVedicConversion();
                      _performVedicToClockConversion();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: !_converter30GhatiMode ? const Color(0xFFD97706) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "६० घटी (इष्टकाल • स्थिर २४m)",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: !_converter30GhatiMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _converter30GhatiMode = true;
                      });
                      _performClockToVedicConversion();
                      _performVedicToClockConversion();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _converter30GhatiMode ? const Color(0xFFD97706) : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "३० घटी (द्रिक पञ्चाङ्ग • दिनमान)",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _converter30GhatiMode ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Sunrise configuration tile (Deshantar base)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.wb_twilight, color: Colors.orange, size: 20),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text("सूर्योदय आधार (देशान्तर 77.21° E नई दिल्ली):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                SizedBox(
                  width: 90,
                  height: 36,
                  child: TextField(
                    controller: _customSunriseCtrl,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) {
                      _performClockToVedicConversion();
                      _performVedicToClockConversion();
                    },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  tooltip: "आज का सूर्योदय रिसेट करें",
                  onPressed: () {
                    _customSunriseCtrl.text = "06:04:18";
                    _performClockToVedicConversion();
                    _performVedicToClockConversion();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // SECTION A: Normal Clock -> Vedic Time
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD97706).withOpacity(0.3)),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.schedule, color: Color(0xFFD97706), size: 20),
                    SizedBox(width: 8),
                    Text("1. घड़ी समय ➔ वैदिक समय (Normal to Vedic)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF92400E))),
                  ],
                ),
                const SizedBox(height: 12),

                // Quick presets
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildPresetChip("वर्तमान (Now)", () {
                      _hourCtrl.text = _now.hour.toString().padLeft(2, '0');
                      _minCtrl.text = _now.minute.toString().padLeft(2, '0');
                      _secCtrl.text = _now.second.toString().padLeft(2, '0');
                      _performClockToVedicConversion();
                    }),
                    _buildPresetChip("16:32:09 (द्रिक ३० घटी -> 25:15:35)", () {
                      _hourCtrl.text = "16";
                      _minCtrl.text = "32";
                      _secCtrl.text = "09";
                      _customSunriseCtrl.text = "06:04:23";
                      _converter30GhatiMode = true;
                      _performClockToVedicConversion();
                    }),
                    _buildPresetChip("16:31:38 (द्रिक ३० घटी -> 25:14:20)", () {
                      _hourCtrl.text = "16";
                      _minCtrl.text = "31";
                      _secCtrl.text = "38";
                      _customSunriseCtrl.text = "06:04:23";
                      _converter30GhatiMode = true;
                      _performClockToVedicConversion();
                    }),
                    _buildPresetChip("13:27:06 (द्रिक ६० घटी -> 18:26:28)", () {
                      _hourCtrl.text = "13";
                      _minCtrl.text = "27";
                      _secCtrl.text = "06";
                      _customSunriseCtrl.text = "06:04:31";
                      _converter30GhatiMode = false;
                      _performClockToVedicConversion();
                    }),
                    _buildPresetChip("06:04:18 (सूर्योदय)", () {
                      _hourCtrl.text = "06";
                      _minCtrl.text = "04";
                      _secCtrl.text = "18";
                      _performClockToVedicConversion();
                    }),
                    _buildPresetChip("18:29:57 (सूर्यास्त)", () {
                      _hourCtrl.text = "18";
                      _minCtrl.text = "29";
                      _secCtrl.text = "57";
                      _performClockToVedicConversion();
                    }),
                  ],
                ),
                const SizedBox(height: 14),

                // Inputs
                Row(
                  children: [
                    _buildTimeInputCol("घण्टा (HH)", _hourCtrl),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text(":", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                    _buildTimeInputCol("मिनट (MM)", _minCtrl),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text(":", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                    _buildTimeInputCol("सेकण्ड (SS)", _secCtrl),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onPressed: _performClockToVedicConversion,
                      child: const Text("गणना करें", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Result Box
                if (_convertedVedicTime != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("वैदिक समय परिणाम:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                            Text(
                              "${_convertedVedicTime!.toNumericString()} (घटी:पल:विपल)",
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFFB45309)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "देवनागरी: ${_convertedVedicTime!.toDevanagariString()}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                        ),
                        Text(
                          "शास्त्रीय शब्द: ${_convertedVedicTime!.toVerboseHindi()}",
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const Divider(height: 16),
                        const Text("गणना का प्रमाण व चरण (Step-by-step):", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                        const SizedBox(height: 4),
                        Text(_converter1Breakdown, style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.4)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // SECTION B: Vedic Time -> Normal Clock
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.history_toggle_off, color: Colors.blueAccent, size: 20),
                    SizedBox(width: 8),
                    Text("2. वैदिक समय ➔ घड़ी समय (Vedic to Normal)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A))),
                  ],
                ),
                const SizedBox(height: 12),

                // Quick presets
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildPresetChip("00:00:00 (सूर्योदय)", () {
                      _ghatiCtrl.text = "0";
                      _palCtrl.text = "0";
                      _vipalCtrl.text = "0";
                      _performVedicToClockConversion();
                    }),
                    _buildPresetChip("25:15:35 (द्रिक ३० -> 16:32:09)", () {
                      _ghatiCtrl.text = "25";
                      _palCtrl.text = "15";
                      _vipalCtrl.text = "35";
                      _customSunriseCtrl.text = "06:04:23";
                      _converter30GhatiMode = true;
                      _performVedicToClockConversion();
                    }),
                    _buildPresetChip("25:14:20 (द्रिक ३० -> 16:31:38)", () {
                      _ghatiCtrl.text = "25";
                      _palCtrl.text = "14";
                      _vipalCtrl.text = "20";
                      _customSunriseCtrl.text = "06:04:23";
                      _converter30GhatiMode = true;
                      _performVedicToClockConversion();
                    }),
                    _buildPresetChip("18:26:28 (द्रिक ६० -> 13:27:06)", () {
                      _ghatiCtrl.text = "18";
                      _palCtrl.text = "26";
                      _vipalCtrl.text = "28";
                      _customSunriseCtrl.text = "06:04:31";
                      _converter30GhatiMode = false;
                      _performVedicToClockConversion();
                    }),
                    _buildPresetChip("30:00:00 (सूर्यास्त ३० घटी)", () {
                      _ghatiCtrl.text = "30";
                      _palCtrl.text = "0";
                      _vipalCtrl.text = "0";
                      _converter30GhatiMode = true;
                      _performVedicToClockConversion();
                    }),
                    _buildPresetChip("31:03:17 (सूर्यास्त ६० घटी)", () {
                      _ghatiCtrl.text = "31";
                      _palCtrl.text = "3";
                      _vipalCtrl.text = "17";
                      _converter30GhatiMode = false;
                      _performVedicToClockConversion();
                    }),
                  ],
                ),
                const SizedBox(height: 14),

                // Inputs
                Row(
                  children: [
                    _buildTimeInputCol("घटी (0-59)", _ghatiCtrl),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text(":", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                    _buildTimeInputCol("पल (0-59)", _palCtrl),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text(":", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                    _buildTimeInputCol("विपल (0-59)", _vipalCtrl),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onPressed: _performVedicToClockConversion,
                      child: const Text("गणना करें", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Result Box
                if (_convertedClockTime != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("सामान्य घड़ी समय परिणाम:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                            Text(
                              "${_formatClockTime(_convertedClockTime!)} IST",
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.blueAccent),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "12-घण्टे प्रारूप: ${_format12HourTime(_convertedClockTime!)} IST",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        ),
                        const Divider(height: 16),
                        const Text("गणना का प्रमाण व चरण (Step-by-step):", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                        const SizedBox(height: 4),
                        Text(_converter2Breakdown, style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.4)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: RULES & FORMULAS
  // ==========================================
  Widget _buildRulesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("वैदिक काल मापन इकाई तालिका (Unit Reference Table)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                const SizedBox(height: 12),
                Table(
                  border: TableBorder.all(color: Colors.grey.shade300),
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(2.5),
                    2: FlexColumnWidth(3.3),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey.shade100),
                      children: const [
                        Padding(padding: EdgeInsets.all(8), child: Text("वैदिक इकाई", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text("आधुनिक समय", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text("गणना सूत्र / नियम", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                    _buildTableRow("१ अहोरात्र (Ahoratri)", "२४ घण्टे (24 Hours)", "६० घटी (सूर्योदय से अगला सूर्योदय)"),
                    _buildTableRow("१ मुहूर्त (Muhurta)", "४८ मिनट (48 Mins)", "२ घटी (दिन में कुल ३० मुहूर्त)"),
                    _buildTableRow("१ घटी / दण्ड (Ghati)", "२४ मिनट (24 Mins)", "घटी × २४ = मिनट (= १४४० सेकण्ड)"),
                    _buildTableRow("१ पल / विघटी (Pal)", "२४ सेकण्ड (24 Secs)", "पल × २४ = सेकण्ड (१ घटी = ६० पल)"),
                    _buildTableRow("१ विपल (Vipal)", "०.४ सेकण्ड (0.4 Sec)", "विपल × ०.४ = सेकण्ड (१ पल = ६० विपल)"),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("वैदिक समय की गति २.५ गुना तेज क्यों होती है? (Mathematical Proof of 2.5x Speed)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF92400E))),
                SizedBox(height: 10),
                Text(
                  "अक्सर लोग यह देखकर आश्चर्यचकित होते हैं कि वैदिक समय की घटी और पल सामान्य घड़ी से तेज चल रहे हैं। यह कोई त्रुटि नहीं है, अपितु प्रामाणिक खगोलीय गणित का नियम है:\n\n"
                  "१. एक पूर्ण अहोरात्र (पृथ्वी का एक घूर्णन) = २४ आधुनिक घण्टे = ६० वैदिक घटी।\n"
                  "२. गति अनुपात: ६० घटी ÷ २४ घण्टे = २.५ गुना (2.5x)।\n"
                  "३. १ आधुनिक घण्टा = ठीक २.५ घटी (२ घटी ३० पल)।\n"
                  "४. १ आधुनिक मिनट = ठीक २.५ पल (२ पल ३० विपल)।\n"
                  "५. १ आधुनिक सेकण्ड = ठीक २.५ विपल (क्योंकि १ विपल = ०.४ सेकण्ड)।\n\n"
                  "६. कुल दिन का चक्र:\n"
                  "   • आधुनिक दिन = २४ × ६० × ६० = ८६,४०० सेकण्ड\n"
                  "   • वैदिक दिन = ६० × ६० × ६० = २,१६,००० विपल\n"
                  "   • २,१६,००० ÷ ८६,४०० = ठीक २.५ (२.५ गुना विपल प्रति सेकण्ड)\n\n"
                  "अतः यदि आपकी कलाई घड़ी पर १ घण्टा व्यतीत होता है, तो वैदिक घड़ी पर २ घटी ३० पल आगे बढ़ेगा।",
                  style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black87),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Online verification references card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("ऑनलाइन सेवा मिलान संदर्भ (Online Verification)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF92400E))),
                SizedBox(height: 10),
                Text(
                  "• hinducalendar.app/ghati-pal: सूर्योदय को 00:00:00 मानकर घटी-पल गणना करता है।\n"
                  "• drikpanchang.com: ३० घटी दिनमान मान (डिफ़ॉल्ट) एवं ६० घटी इष्टकाल मान दोनों प्रदान करता है।\n"
                  "• nakshtratak.com/en/calculators/ghati-hour: 1 घटी = 24 मिनट मानक सूत्र।\n"
                  "• astrosage.com/calculators/ghati-to-hour-converter: सटीक इष्टकाल आधारित मान।\n"
                  "• Love Kush POS: न्यू दिल्ली वेधशाला के सटीक अक्षांश-देशांतर (28.61° N, 77.21° E) एवं NOAA सौर समीकरण के आधार पर मिलीसेकण्ड स्तर पर गणना करता है।",
                  style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black87),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Deshantara (Longitude) & City Variation Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("स्थान भेद एवं देशान्तर संस्कार (Deshantara & Longitude Effect)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A))),
                SizedBox(height: 10),
                Text(
                  "विभिन्न शहरों अथवा ऑनलाइन सेवाओं में समय में अन्तर आने का मुख्य कारण देशान्तर (Longitude) और अक्षांश (Latitude) का भेद होता है:\n\n"
                  "१. देशान्तर क्या है? (What is Deshantara):\n"
                  "   भारतीय मानक समय (IST) ८२.५०° पूर्व देशान्तर (प्रयागराज/मिर्ज़ापुर) पर आधारित है।\n"
                  "   जबकि नई दिल्ली का देशान्तर ७७.२१° पूर्व है।\n"
                  "   अन्तर = ८२.५०° - ७७.२१° = ५.२९° (डिग्री)।\n"
                  "   १ डिग्री = ४ मिनट समय अन्तर ➔ ५.२९° × ४ = २१ मिनट १० सेकण्ड!\n\n"
                  "२. स्थानीय सूर्योदय भेद (Local Sunrise):\n"
                  "   वैदिक समय (इष्टकाल) सूर्योदय से प्रारम्भ होता है। सूर्योदय का समय प्रत्येक नगर के देशान्तर और अक्षांश पर निर्भर करता है।\n"
                  "   • नई दिल्ली: सूर्योदय ~०६:०४ IST (देशान्तर 77.21° E)\n"
                  "   • उज्जैन (प्राचीन अवन्तिका): सूर्योदय ~०६:१२ IST (देशान्तर 75.76° E)\n"
                  "   • कोलकाता: सूर्योदय ~०५:२२ IST (देशान्तर 88.36° E)\n\n"
                  "३. निष्कर्ष:\n"
                  "   यदि किसी ऑनलाइन सेवा में सूर्योदय आधार ५-१० मिनट आगे-पीछे लिया गया हो (जैसे उज्जैन या मानक LMT), तो वैदिक समय में अन्तर दिखाई देगा। लव कुश POS न्यू दिल्ली के वास्तविक देशान्तर (77.21° E) के अनुसार सूक्ष्म गणना करता है।",
                  style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black87),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Prahars of the day
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text("अष्ट प्रहर विवरण (8 Prahars of Day & Night)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A8A))),
                SizedBox(height: 10),
                Text(
                  "१. प्रथम प्रहर: प्रातः ०६:०० से ०९:००\n"
                  "२. द्वितीय प्रहर: प्रातः ०९:०० से १२:००\n"
                  "३. तृतीय प्रहर: दोपहर १२:०० से ०३:००\n"
                  "४. चतुर्थ प्रहर: अपराह्न ०३:०० से ०६:००\n"
                  "५. सायं प्रहर: सायं ०६:०० से रात्रि ०९:००\n"
                  "६. निशीथ प्रहर: रात्रि ०९:०० से १२:००\n"
                  "७. मध्यरात्रि प्रहर: रात्रि १२:०० से ०३:००\n"
                  "८. ब्रह्ममुहूर्त प्रहर: रात्रि ०३:०० से प्रातः ०६:००",
                  style: TextStyle(fontSize: 12, height: 1.5, color: Colors.black87),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Vedic Vaars (7 Days) Reference Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("सप्त वैदिक वार / वासर नामावली (7 Authentic Vedic Days)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF92400E))),
                const SizedBox(height: 8),
                const Text(
                  "वैदिक काल गणना में वार (वासर) का निर्धारण अहोरात्र (सूर्योदय से अगले सूर्योदय) के आधार पर होता है, मध्यरात्रि १२:०० बजे नहीं। प्रत्येक दिन का नाम उसके अधिष्ठाता आकाशीय ग्रह के नाम पर है:",
                  style: TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
                ),
                const SizedBox(height: 10),
                Table(
                  border: TableBorder.all(color: Colors.grey.shade300),
                  columnWidths: const {
                    0: FlexColumnWidth(2.0),
                    1: FlexColumnWidth(2.5),
                    2: FlexColumnWidth(3.5),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: Colors.amber.shade50),
                      children: const [
                        Padding(padding: EdgeInsets.all(8), child: Text("ग्रेगोरियन वार", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text("वैदिक वासर नाम", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        Padding(padding: EdgeInsets.all(8), child: Text("अधिष्ठाता ग्रह / संस्कृत पर्याय", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                    ),
                    _buildTableRow("रविवार (Sunday)", "रविवासर", "सूर्य देव (भानुवासर / आदित्यवासर)"),
                    _buildTableRow("सोमवार (Monday)", "सोमवासर", "चन्द्र देव (इन्दुवासर)"),
                    _buildTableRow("मंगलवार (Tuesday)", "भौमवासर", "मंगल देव (मङ्गलवासर / कुजवासर)"),
                    _buildTableRow("बुधवार (Wednesday)", "बुधवासर", "बुध देव (सौम्यवासर)"),
                    _buildTableRow("गुरुवार (Thursday)", "गुरुवासर", "देवगुरु बृहस्पति (बृहस्पतिवासर)"),
                    _buildTableRow("शुक्रवार (Friday)", "शुक्रवासर", "शुक्र देव (भृगुवासर)"),
                    _buildTableRow("शनिवार (Saturday)", "शनिवासर", "शनि देव (मन्दवासर / सौरिवासर)"),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    children: const [
                      Icon(Icons.wb_sunny_outlined, size: 16, color: Color(0xFFD97706)),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "अहोरात्र नियम: यदि रात्रि ०२:०० बजे (मध्यरात्रि के बाद) समय देखा जाए, तब भी सूर्योदय न होने तक पूर्व दिवस का ही वैदिक वार रहता है।",
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ==========================================
  // HELPER WIDGETS
  // ==========================================
  TableRow _buildTableRow(String col1, String col2, String col3) {
    return TableRow(
      children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(col1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        Padding(padding: const EdgeInsets.all(8), child: Text(col2, style: const TextStyle(fontSize: 12))),
        Padding(padding: const EdgeInsets.all(8), child: Text(col3, style: const TextStyle(fontSize: 11, color: Colors.black87))),
      ],
    );
  }

  Widget _buildTimeInputCol(String label, TextEditingController ctrl) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(color: Colors.grey.shade300),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String subValue,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
              Text(subValue, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPanchangRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
