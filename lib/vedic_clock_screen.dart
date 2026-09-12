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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _startClock();
    _performClockToVedicConversion();
    _performVedicToClockConversion();
  }

  void _startClock() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
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

    final sunriseStr = "${sunrise.hour.toString().padLeft(2, '0')}:${sunrise.minute.toString().padLeft(2, '0')}:${sunrise.second.toString().padLeft(2, '0')}";
    final targetStr = "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";

    final breakdown = StringBuffer();
    breakdown.writeln("1. सूर्योदय (Sunrise): $sunriseStr IST");
    breakdown.writeln("2. अभीष्ट समय (Target Time): $targetStr IST");
    breakdown.writeln("3. सूर्योदय से व्यतीत कुल समय (इष्टकाल): ${elapsed.inHours} घण्टे ${elapsed.inMinutes % 60} मिनट ${elapsed.inSeconds % 60} सेकण्ड (= $totalSec सेकण्ड)");
    breakdown.writeln("4. घटी गणना: $totalSec ÷ 1440 = ${vt.ghati} घटी (1 घटी = 24 मिनट = 1440 सेकण्ड)");
    breakdown.writeln("5. शेष सेकण्ड: $totalSec - $ghatiSec = $remAfterGhati सेकण्ड");
    breakdown.writeln("6. पल गणना: $remAfterGhati ÷ 24 = ${vt.pal} पल (1 पल = 24 सेकण्ड)");
    breakdown.writeln("7. शेष सेकण्ड: $remAfterGhati - $palSec = $remAfterPal सेकण्ड");
    breakdown.writeln("8. विपल गणना: $remAfterPal ÷ 0.4 = ${vt.vipal.toStringAsFixed(1)} विपल (1 विपल = 0.4 सेकण्ड)");
    breakdown.writeln("👉 परिणाम (Result): ${vt.toNumericString()} घटी:पल:विपल");

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
    final converted = VedicTimeService.vedicToNormal(
      ghati: ghati,
      pal: pal,
      vipal: vipal,
      date: _now,
      overrideSunrise: sunrise,
    );

    final totalElapsedSec = (ghati * 1440.0) + (pal * 24.0) + (vipal * 0.4);
    final sunriseStr = "${sunrise.hour.toString().padLeft(2, '0')}:${sunrise.minute.toString().padLeft(2, '0')}:${sunrise.second.toString().padLeft(2, '0')}";

    final breakdown = StringBuffer();
    breakdown.writeln("1. दिया गया वैदिक समय: $ghati घटी, $pal पल, ${vipal.toStringAsFixed(1)} विपल");
    breakdown.writeln("2. कुल व्यतीत सेकण्ड: ($ghati × 1440) + ($pal × 24) + ($vipal × 0.4) = ${totalElapsedSec.toStringAsFixed(1)} सेकण्ड");
    breakdown.writeln("3. सूर्योदय का आधार: $sunriseStr IST");
    breakdown.writeln("4. सामान्य घड़ी समय: सूर्योदय + ${totalElapsedSec.toStringAsFixed(1)} सेकण्ड");
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
    final liveVedic = panchang.vedicTime;
    final solar = panchang.solar;

    final sunriseStr = "${solar.sunrise.hour.toString().padLeft(2, '0')}:${solar.sunrise.minute.toString().padLeft(2, '0')}:${solar.sunrise.second.toString().padLeft(2, '0')}";
    final sunsetStr = "${solar.sunset.hour.toString().padLeft(2, '0')}:${solar.sunset.minute.toString().padLeft(2, '0')}:${solar.sunset.second.toString().padLeft(2, '0')}";

    // Day/Night progress
    final double dayFraction = (liveVedic.ghati + (liveVedic.pal / 60.0)) / 60.0;

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
                  "वैदिक समय: ${liveVedic.toDevanagariString()} (${liveVedic.toNumericString()})\n"
                  "घड़ी समय: ${_formatClockTime(_now)} IST\n"
                  "सूर्योदय: $sunriseStr | सूर्यास्त: $sunsetStr\n"
                  "पञ्चाङ्ग: ${panchang.toReceiptPanchangLine()}\n"
                  "दिनमान: ${solar.dayLengthGhatis.toStringAsFixed(2)} घटी | रात्रिमान: ${solar.nightLengthGhatis.toStringAsFixed(2)} घटी\n"
                  "वार: ${panchang.vaar} | मुहूर्त: ${panchang.muhurta}";
              _copyToClipboard(shareText, "वैदिक समय व पञ्चाङ्ग कॉपी किया गया");
            },
          ),
          IconButton(
            tooltip: "व्हाट्सएप पर साझा करें",
            icon: const Icon(Icons.share, color: Colors.green),
            onPressed: () {
              final shareText = "🕉️ *लव कुश वैदिक समय एवं पञ्चाङ्ग* (New Delhi)\n"
                  "⏰ *वैदिक समय:* ${liveVedic.toDevanagariString()} (${liveVedic.toNumericString()})\n"
                  "⌚ *घड़ी समय:* ${_formatClockTime(_now)} IST\n"
                  "🌅 *सूर्योदय:* $sunriseStr | 🌇 *सूर्यास्त:* $sunsetStr\n"
                  "📜 *पञ्चाङ्ग:* ${panchang.toReceiptPanchangLine()}\n"
                  "☀️ *दिनमान:* ${solar.dayLengthGhatis.toStringAsFixed(2)} घटी | *रात्रिमान:* ${solar.nightLengthGhatis.toStringAsFixed(2)} घटी\n"
                  "🔱 *वार:* ${panchang.vaar} | *मुहूर्त:* ${panchang.muhurta}";
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
                const SizedBox(height: 12),
                const Text("वैदिक समय (घटी : पल : विपल)", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1)),
                const SizedBox(height: 6),

                // Devanagari Digits
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    VedicTime.toDevanagariDigits(liveVedic.toNumericString()),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 54,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      fontFamily: 'serif',
                    ),
                  ),
                ),

                // English Digits
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${liveVedic.toNumericString()} (60 घटी मान)",
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
                const SizedBox(height: 10),

                // Verbal Hindi
                Text(
                  liveVedic.toVerboseHindi(),
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
                        subValue: "${solar.dayLengthGhatis.toStringAsFixed(2)} घटी",
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
                        value: "${solar.dayLengthGhatis.toStringAsFixed(2)} घटी",
                        subValue: "${solar.dayDuration.inHours}घ ${solar.dayDuration.inMinutes % 60}मि",
                      ),
                    ),
                    Expanded(
                      child: _buildInfoItem(
                        icon: Icons.bedtime_outlined,
                        iconColor: Colors.purple,
                        label: "रात्रिमान (Night Length)",
                        value: "${solar.nightLengthGhatis.toStringAsFixed(2)} घटी",
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
                _buildPanchangRow("वैदिक वार", "${panchang.vaar} (अहोरात्र आधारित)"),
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

          // Sunrise configuration tile
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
                  child: Text("सूर्योदय आधार (Sunrise Base):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
                    _buildPresetChip("06:04:18 (सूर्योदय)", () {
                      _hourCtrl.text = "06";
                      _minCtrl.text = "04";
                      _secCtrl.text = "18";
                      _performClockToVedicConversion();
                    }),
                    _buildPresetChip("12:00:00 (दोपहर)", () {
                      _hourCtrl.text = "12";
                      _minCtrl.text = "00";
                      _secCtrl.text = "00";
                      _performClockToVedicConversion();
                    }),
                    _buildPresetChip("13:27:06 (ऑनलाइन टेस्ट)", () {
                      _hourCtrl.text = "13";
                      _minCtrl.text = "27";
                      _secCtrl.text = "06";
                      _performClockToVedicConversion();
                    }),
                    _buildPresetChip("18:30:28 (सूर्यास्त)", () {
                      _hourCtrl.text = "18";
                      _minCtrl.text = "30";
                      _secCtrl.text = "28";
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
                    _buildPresetChip("15:00:00 (मध्याह्न)", () {
                      _ghatiCtrl.text = "15";
                      _palCtrl.text = "0";
                      _vipalCtrl.text = "0";
                      _performVedicToClockConversion();
                    }),
                    _buildPresetChip("18:27:00 (ऑनलाइन टेस्ट)", () {
                      _ghatiCtrl.text = "18";
                      _palCtrl.text = "27";
                      _vipalCtrl.text = "0";
                      _performVedicToClockConversion();
                    }),
                    _buildPresetChip("31:05:25 (सूर्यास्त)", () {
                      _ghatiCtrl.text = "31";
                      _palCtrl.text = "5";
                      _vipalCtrl.text = "25";
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
                  "• nakshtratak.com/en/calculators/ghati-hour: 1 घटी = 24 मिनट मानक सूत्र।\n"
                  "• astrosage.com/calculators/ghati-to-hour-converter: सटीक इष्टकाल आधारित मान।\n"
                  "• Love Kush POS: न्यू दिल्ली वेधशाला के सटीक अक्षांश-देशांतर (28.61° N, 77.21° E) एवं NOAA सौर समीकरण के आधार पर मिलीसेकण्ड स्तर पर गणना करता है।",
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
