import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

/// Represents a point in Vedic Time: Ghati, Pal, and Vipal elapsed since Sunrise
class VedicTime {
  final int ghati; // 0..59 (1 Ghati = 24 minutes)
  final int pal;   // 0..59 (1 Pal = 24 seconds, also called Vighati)
  final double vipal; // 0..59.99 (1 Vipal = 0.4 seconds)
  final double totalSecondsSinceSunrise;

  const VedicTime({
    required this.ghati,
    required this.pal,
    required this.vipal,
    required this.totalSecondsSinceSunrise,
  });

  /// Standard numeric format: "25:00:32"
  String toNumericString({bool includeVipalDecimal = false}) {
    final gStr = ghati.toString().padLeft(2, '0');
    final pStr = pal.toString().padLeft(2, '0');
    final vStr = includeVipalDecimal
        ? vipal.toStringAsFixed(1).padLeft(4, '0')
        : vipal.round().toString().padLeft(2, '0');
    return "$gStr:$pStr:$vStr";
  }

  /// Authentic Devanagari formatted string: "२५:००:३२ घटी:पल:विपल"
  String toDevanagariString({bool includeVipalDecimal = false}) {
    return "${toDevanagariDigits(toNumericString(includeVipalDecimal: includeVipalDecimal))} (घटी:पल:विपल)";
  }

  /// Classical verbose string: "२५ घटी, ० पल, ३२ विपल"
  String toVerboseHindi() {
    return "${toDevanagariDigits(ghati)} घटी, ${toDevanagariDigits(pal)} पल, ${toDevanagariDigits(vipal.round())} विपल";
  }

  /// Convert standard Arabic numerals into authentic Devanagari digits
  static String toDevanagariDigits(dynamic value) {
    const digits = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];
    return value.toString().split('').map((char) {
      final d = int.tryParse(char);
      return d != null ? digits[d] : char;
    }).join('');
  }

  @override
  String toString() => toNumericString();
}

/// Solar timing data for a specific date and coordinates
class SolarTimings {
  final DateTime sunrise;
  final DateTime sunset;
  final Duration dayDuration;
  final Duration nightDuration;
  final double dayLengthGhatis;
  final double nightLengthGhatis;
  final bool isFromApi;

  const SolarTimings({
    required this.sunrise,
    required this.sunset,
    required this.dayDuration,
    required this.nightDuration,
    required this.dayLengthGhatis,
    required this.nightLengthGhatis,
    this.isFromApi = false,
  });
}

/// Comprehensive Hindu Vedic Panchang details
class VedicPanchang {
  final String masa;         // e.g. "भाद्रपद"
  final String paksha;       // "शुक्ल" or "कृष्ण"
  final String udayaTithi;    // e.g. "प्रतिपदा"
  final String currentTithi;  // Tithi active at current moment
  final int samvat;          // e.g. 2083
  final String vaar;         // e.g. "शनिवासर"
  final String pahar;        // e.g. "तृतीय प्रहर"
  final String muhurta;      // e.g. "विजय मुहूर्त"
  final VedicTime vedicTime;  // Current Ghati:Pal:Vipal
  final SolarTimings solar;  // Sunrise & Sunset timings

  const VedicPanchang({
    required this.masa,
    required this.paksha,
    required this.udayaTithi,
    required this.currentTithi,
    required this.samvat,
    required this.vaar,
    required this.pahar,
    required this.muhurta,
    required this.vedicTime,
    required this.solar,
  });

  /// Common Hindi day name corresponding to the Vedic Vaar
  String get commonVaar {
    switch (vaar) {
      case "सोमवासर": return "सोमवार";
      case "भौमवासर": return "मंगलवार";
      case "बुधवासर": return "बुधवार";
      case "गुरुवासर": return "गुरुवार";
      case "शुक्रवासर": return "शुक्रवार";
      case "शनिवासर": return "शनिवार";
      case "रविवासर": return "रविवार";
      default: return vaar;
    }
  }

  /// Full Vedic Vaar with common Hindi name: e.g. "शनिवासर (शनिवार)"
  String get fullVaarDisplay => "$vaar ($commonVaar)";

  /// Single-line authentic header for receipts and displays
  String toReceiptPanchangLine() {
    return "$masa, $paksha $udayaTithi, ${VedicTime.toDevanagariDigits(samvat)} विक्रम संवत् ($pahar)";
  }

  /// Full Vedic time string with sunrise
  String toFullVedicTimeDisplay() {
    return "${vedicTime.toDevanagariString()} | सूर्योदय: ${solar.sunrise.hour.toString().padLeft(2, '0')}:${solar.sunrise.minute.toString().padLeft(2, '0')}";
  }
}

/// Service to convert between Vedic Time and Normal Clock Time,
/// calculate authentic Panchang parameters, and provide hybrid calculation/API modes.
class VedicTimeService {
  // Default coordinates: New Delhi, India
  static const double defaultLat = 28.6139;
  static const double defaultLon = 77.2090;

  // In-memory cache for solar timings by date string (e.g. "2026-09-12_28.61_77.21")
  static final Map<String, SolarTimings> _solarCache = {};

  // Tithi names (15 Shukla + 15 Krishna)
  static const List<String> tithiNames = [
    "प्रतिपदा", "द्वितीया", "तृतीया", "चतुर्थी", "पञ्चमी",
    "षष्ठी", "सप्तमी", "अष्टमी", "नवमी", "दशमी",
    "एकादशी", "द्वादशी", "त्रयोदशी", "चतुर्दशी", "पूर्णिमा",
    "प्रतिपदा", "द्वितीया", "तृतीया", "चतुर्थी", "पञ्चमी",
    "षष्ठी", "सप्तमी", "अष्टमी", "नवमी", "दशमी",
    "एकादशी", "द्वादशी", "त्रयोदशी", "चतुर्दशी", "अमावस्या",
  ];

  // Vedic lunar months
  static const List<String> masaNames = [
    "चैत्र", "वैशाख", "ज्येष्ठ", "आषाढ़",
    "श्रावण", "भाद्रपद", "आश्विन", "कार्तिक",
    "मार्गशीर्ष", "पौष", "माघ", "फाल्गुन"
  ];

  // Authentic Vedic Vaar names (Sunday to Saturday)
  static const List<String> vedicVaars = [
    "सोमवासर", // Mon (1)
    "भौमवासर", // Tue (2)
    "बुधवासर", // Wed (3)
    "गुरुवासर", // Thu (4)
    "शुक्रवासर", // Fri (5)
    "शनिवासर", // Sat (6)
    "रविवासर", // Sun (7)
  ];

  // Traditional 30 Muhurtas of the day (each 2 Ghatis = 48 mins)
  static const List<String> muhurtaNames = [
    "रुद्र", "आहि", "मित्र", "पितृ", "वसु",
    "वाराह", "विश्वेदेवा", "विधि", "सतमुखी", "पुरुहूत",
    "वाहिनी", "नक्तञ्चरा", "वरुण", "अर्यमा", "भग",
    "गिरीश", "अजपाद", "अहिर्बुध्न्य", "पूषा", "अश्विनी",
    "यम", "अग्नि", "विधातृ", "कण्ड", "अभिजित",
    "रोहिण", "बल", "विजय", "नैरृत", "शक्र"
  ];

  // =========================================================================
  // 1. CONVERT NORMAL CLOCK TIME -> VEDIC TIME (घटी:पल:विपल)
  // =========================================================================

  /// Convert any standard Indian Standard Time [dt] into Vedic [VedicTime] (Ghati:Pal:Vipal)
  /// using high-precision local solar sunrise (defaults to New Delhi coordinates).
  static VedicTime normalToVedic(
    DateTime dt, {
    double lat = defaultLat,
    double lon = defaultLon,
    DateTime? overrideSunrise,
  }) {
    // 1. Determine local sunrise
    final DateTime sunrise = overrideSunrise ?? getLocalSunrise(dt, lat: lat, lon: lon);

    // 2. Compute elapsed duration from sunrise
    Duration elapsed;
    if (dt.isBefore(sunrise)) {
      // If time is before today's sunrise (e.g. 3:00 AM), it belongs to previous Vedic day
      final prevDaySunrise = getLocalSunrise(dt.subtract(const Duration(days: 1)), lat: lat, lon: lon);
      elapsed = dt.difference(prevDaySunrise);
    } else {
      elapsed = dt.difference(sunrise);
    }

    final double totalSec = elapsed.inMicroseconds / 1000000.0;

    // 1 Ghati = 24 minutes = 1440 seconds
    // 1 Pal   = 24 seconds
    // 1 Vipal = 0.4 seconds
    int ghati = (totalSec / 1440.0).floor();
    double remSec = totalSec - (ghati * 1440.0);

    int pal = (remSec / 24.0).floor();
    remSec -= (pal * 24.0);

    double vipal = remSec / 0.4;

    // Normalize boundary overflows (e.g. rounding 59.99 to 60)
    if (vipal >= 60.0) {
      vipal -= 60.0;
      pal += 1;
    }
    if (pal >= 60) {
      pal -= 60;
      ghati += 1;
    }
    ghati = ghati % 60;

    return VedicTime(
      ghati: ghati,
      pal: pal,
      vipal: vipal,
      totalSecondsSinceSunrise: totalSec,
    );
  }

  /// Convert modern clock [dt] into authentic 30-Ghati Vedic Time (Drik Panchang 30-Ghati mode)
  /// where Daytime (Sunrise to Sunset) is divided into exactly 30 Ghatis (Sunset is always 30:00:00),
  /// and Nighttime (Sunset to next Sunrise) is divided into 30 Ghatis.
  static VedicTime normalToVedic30Ghati(
    DateTime dt, {
    double lat = defaultLat,
    double lon = defaultLon,
    DateTime? overrideSunrise,
    DateTime? overrideSunset,
  }) {
    final solar = calculateSolarTimings(dt, lat: lat, lon: lon);
    final sunrise = overrideSunrise ?? solar.sunrise;
    final sunset = overrideSunset ?? solar.sunset;

    double totalGhatis;
    double totalSec;

    if (dt.isBefore(sunrise)) {
      // Prior to today's sunrise: part of previous night (Sunset to Sunrise = 30 Ghatis)
      final prevDaySunset = getLocalSunset(dt.subtract(const Duration(days: 1)), lat: lat, lon: lon);
      final nightDuration = sunrise.difference(prevDaySunset);
      final elapsed = dt.difference(prevDaySunset);
      totalSec = elapsed.inMicroseconds / 1000000.0;
      totalGhatis = (totalSec / (nightDuration.inMicroseconds / 1000000.0)) * 30.0;
    } else if (dt.isBefore(sunset) || dt.isAtSameMomentAs(sunset)) {
      // Daytime: Sunrise to Sunset = exactly 30 Ghatis
      final dayDuration = sunset.difference(sunrise);
      final elapsed = dt.difference(sunrise);
      totalSec = elapsed.inMicroseconds / 1000000.0;
      totalGhatis = (totalSec / (dayDuration.inMicroseconds / 1000000.0)) * 30.0;
    } else {
      // Nighttime: Sunset to next Sunrise = 30 Ghatis
      final nextDaySunrise = getLocalSunrise(dt.add(const Duration(days: 1)), lat: lat, lon: lon);
      final nightDuration = nextDaySunrise.difference(sunset);
      final elapsed = dt.difference(sunset);
      totalSec = elapsed.inMicroseconds / 1000000.0;
      totalGhatis = (totalSec / (nightDuration.inMicroseconds / 1000000.0)) * 30.0;
    }

    int ghati = totalGhatis.floor();
    double remGhati = totalGhatis - ghati;

    double totalPals = remGhati * 60.0;
    int pal = totalPals.floor();
    double remPal = totalPals - pal;

    double vipal = remPal * 60.0;

    if (vipal >= 60.0) {
      vipal -= 60.0;
      pal += 1;
    }
    if (pal >= 60) {
      pal -= 60;
      ghati += 1;
    }
    ghati = ghati % 60;

    return VedicTime(
      ghati: ghati,
      pal: pal,
      vipal: vipal,
      totalSecondsSinceSunrise: totalSec,
    );
  }

  // =========================================================================
  // 2. CONVERT VEDIC TIME -> NORMAL CLOCK TIME
  // =========================================================================

  /// Convert Vedic time ([ghati], [pal], [vipal]) into modern clock [DateTime] (IST)
  /// for a given calendar [date] and coordinates.
  static DateTime vedicToNormal({
    required int ghati,
    required int pal,
    double vipal = 0.0,
    required DateTime date,
    double lat = defaultLat,
    double lon = defaultLon,
    DateTime? overrideSunrise,
  }) {
    final DateTime sunrise = overrideSunrise ?? getLocalSunrise(date, lat: lat, lon: lon);

    // Total seconds elapsed since sunrise
    final double elapsedSeconds = (ghati * 1440.0) + (pal * 24.0) + (vipal * 0.4);

    final int wholeSeconds = elapsedSeconds.floor();
    final int microSeconds = ((elapsedSeconds - wholeSeconds) * 1000000).round();

    return sunrise.add(Duration(seconds: wholeSeconds, microseconds: microSeconds));
  }

  /// Convert 30-Ghati Vedic time ([ghati], [pal], [vipal]) into modern clock [DateTime] (IST)
  /// where 0-30 Ghatis represent daytime (Sunrise to Sunset) and 30-60 represent nighttime.
  static DateTime vedicToNormal30Ghati({
    required int ghati,
    required int pal,
    double vipal = 0.0,
    required DateTime date,
    double lat = defaultLat,
    double lon = defaultLon,
    DateTime? overrideSunrise,
    DateTime? overrideSunset,
  }) {
    final solar = calculateSolarTimings(date, lat: lat, lon: lon);
    final sunrise = overrideSunrise ?? solar.sunrise;
    final sunset = overrideSunset ?? solar.sunset;

    final double ghatiFraction = (ghati + (pal / 60.0) + (vipal / 3600.0));

    if (ghatiFraction <= 30.0) {
      // Daytime (Sunrise to Sunset = 30 Ghatis)
      final dayDurationUs = sunset.difference(sunrise).inMicroseconds;
      final elapsedUs = ((ghatiFraction / 30.0) * dayDurationUs).round();
      return sunrise.add(Duration(microseconds: elapsedUs));
    } else {
      // Nighttime (Sunset to next Sunrise = 30 Ghatis)
      final nextSunrise = getLocalSunrise(date.add(const Duration(days: 1)), lat: lat, lon: lon);
      final nightDurationUs = nextSunrise.difference(sunset).inMicroseconds;
      final elapsedUs = (((ghatiFraction - 30.0) / 30.0) * nightDurationUs).round();
      return sunset.add(Duration(microseconds: elapsedUs));
    }
  }

  // =========================================================================
  // 3. ASTRONOMICAL SOLAR ALGORITHM (OFFLINE NOAA EQUATION)
  // =========================================================================

  /// Compute high-precision solar timings (Sunrise, Sunset, Day/Night duration)
  /// 100% offline using the official NOAA Solar Calculation algorithm.
  static SolarTimings calculateSolarTimings(
    DateTime date, {
    double lat = defaultLat,
    double lon = defaultLon,
    double tzOffsetHours = 5.5, // Indian Standard Time (IST = UTC+05:30)
  }) {
    final cacheKey = "${date.year}-${date.month}-${date.day}_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}";
    if (_solarCache.containsKey(cacheKey)) {
      return _solarCache[cacheKey]!;
    }

    // Day of year (N)
    final startOfYear = DateTime(date.year, 1, 1);
    final int N = date.difference(startOfYear).inDays + 1;

    final double lngHour = lon / 15.0;

    // Approximate event times
    final double tRise = N + ((6.0 - lngHour) / 24.0);
    final double tSet = N + ((18.0 - lngHour) / 24.0);

    DateTime? solveEvent(double t, bool isSunrise) {
      // 1. Sun's mean anomaly
      final double M = (0.9856 * t) - 3.289;

      // 2. Sun's true longitude
      final double L = (M +
              (1.916 * math.sin(M * math.pi / 180.0)) +
              (0.020 * math.sin(2 * M * math.pi / 180.0)) +
              282.634) %
          360.0;

      // 3. Sun's right ascension (RA)
      double RA = (math.atan(0.91764 * math.tan(L * math.pi / 180.0)) * 180.0 / math.pi) % 360.0;

      // Adjust RA into the same quadrant as L
      final double lQuadrant = (L / 90.0).floor() * 90.0;
      final double raQuadrant = (RA / 90.0).floor() * 90.0;
      RA = (RA + (lQuadrant - raQuadrant)) / 15.0; // In hours

      // 4. Sun's declination
      final double sinDec = 0.39782 * math.sin(L * math.pi / 180.0);
      final double cosDec = math.cos(math.asin(sinDec));

      // 5. Sun's local hour angle (Zenith: 90°50' = 90.8333° standard atmospheric refraction)
      const double zenith = 90.8333;
      final double cosH = (math.cos(zenith * math.pi / 180.0) - (sinDec * math.sin(lat * math.pi / 180.0))) /
          (cosDec * math.cos(lat * math.pi / 180.0));

      if (cosH > 1.0 || cosH < -1.0) return null; // Polar night / day

      double H = isSunrise
          ? (360.0 - (math.acos(cosH) * 180.0 / math.pi))
          : (math.acos(cosH) * 180.0 / math.pi);
      H = H / 15.0;

      // 6. Local mean time
      final double T = H + RA - (0.06571 * t) - 6.622;

      // 7. Adjust to UTC then local timezone (IST)
      final double ut = (T - lngHour) % 24.0;
      final double localT = (ut + tzOffsetHours) % 24.0;

      final int h = localT.floor();
      final double remMins = (localT - h) * 60.0;
      final int m = remMins.floor();
      final int s = ((remMins - m) * 60.0).round();

      return DateTime(date.year, date.month, date.day, h, m, s);
    }

    final DateTime sunrise = solveEvent(tRise, true) ?? DateTime(date.year, date.month, date.day, 6, 4, 18);
    final DateTime sunset = solveEvent(tSet, false) ?? DateTime(date.year, date.month, date.day, 18, 30, 28);

    final dayDuration = sunset.difference(sunrise);
    final nightDuration = const Duration(hours: 24) - dayDuration;

    final double dayLengthGhatis = dayDuration.inSeconds / 1440.0;
    final double nightLengthGhatis = 60.0 - dayLengthGhatis;

    final timings = SolarTimings(
      sunrise: sunrise,
      sunset: sunset,
      dayDuration: dayDuration,
      nightDuration: nightDuration,
      dayLengthGhatis: dayLengthGhatis,
      nightLengthGhatis: nightLengthGhatis,
      isFromApi: false,
    );

    _solarCache[cacheKey] = timings;
    return timings;
  }

  /// Get local sunrise time for a date
  static DateTime getLocalSunrise(DateTime date, {double lat = defaultLat, double lon = defaultLon}) {
    return calculateSolarTimings(date, lat: lat, lon: lon).sunrise;
  }

  /// Get local sunset time for a date
  static DateTime getLocalSunset(DateTime date, {double lat = defaultLat, double lon = defaultLon}) {
    return calculateSolarTimings(date, lat: lat, lon: lon).sunset;
  }

  // =========================================================================
  // 4. HYBRID API MODE (ONLINE FETCH WITH INSTANT OFFLINE FALLBACK)
  // =========================================================================

  /// Hybrid method to fetch solar data: tries public API endpoint (sunrise-sunset.org)
  /// with timeout, and seamlessly falls back to the high-precision offline NOAA model.
  static Future<SolarTimings> fetchSolarTimingsHybrid(
    DateTime date, {
    double lat = defaultLat,
    double lon = defaultLon,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final cacheKey = "${date.year}-${date.month}-${date.day}_${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}";
    if (_solarCache.containsKey(cacheKey) && _solarCache[cacheKey]!.isFromApi) {
      return _solarCache[cacheKey]!;
    }

    try {
      final dateStr = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
      final uri = Uri.parse("https://api.sunrise-sunset.org/json?lat=$lat&lng=$lon&date=$dateStr&formatted=0");

      final response = await http.get(uri).timeout(timeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'] != null) {
          final results = data['results'];
          // Convert UTC ISO 8601 strings to IST (+05:30)
          final utcSunrise = DateTime.parse(results['sunrise']).toUtc();
          final utcSunset = DateTime.parse(results['sunset']).toUtc();

          final istSunrise = utcSunrise.add(const Duration(hours: 5, minutes: 30));
          final istSunset = utcSunset.add(const Duration(hours: 5, minutes: 30));

          final dayDuration = istSunset.difference(istSunrise);
          final nightDuration = const Duration(hours: 24) - dayDuration;

          final timings = SolarTimings(
            sunrise: istSunrise,
            sunset: istSunset,
            dayDuration: dayDuration,
            nightDuration: nightDuration,
            dayLengthGhatis: dayDuration.inSeconds / 1440.0,
            nightLengthGhatis: 60.0 - (dayDuration.inSeconds / 1440.0),
            isFromApi: true,
          );

          _solarCache[cacheKey] = timings;
          return timings;
        }
      }
    } catch (_) {
      // Graceful offline fallback
    }

    // Default to precise offline NOAA mathematical model
    return calculateSolarTimings(date, lat: lat, lon: lon);
  }

  // =========================================================================
  // 5. COMPLETE VEDIC PANCHANG CALCULATION
  // =========================================================================

  /// Calculate comprehensive Panchang and Vedic Time details for any given [dt]
  static VedicPanchang calculatePanchang(
    DateTime dt, {
    double lat = defaultLat,
    double lon = defaultLon,
  }) {
    final solar = calculateSolarTimings(dt, lat: lat, lon: lon);
    final vedicTime = normalToVedic(dt, lat: lat, lon: lon, overrideSunrise: solar.sunrise);

    // Determine Vedic day: if before sunrise, belongs to previous civil day
    final DateTime effectiveDate = dt.isBefore(solar.sunrise)
        ? dt.subtract(const Duration(days: 1))
        : dt;

    // 1. Calculate Udayatithi (Tithi at sunrise) and current tithi
    final udayaResult = _calculateTithiAt(solar.sunrise);
    final currentResult = _calculateTithiAt(dt);

    final String udayaTithi = tithiNames[udayaResult.tithiIndex];
    final String currentTithi = tithiNames[currentResult.tithiIndex];
    final String paksha = udayaResult.tithiIndex < 15 ? "शुक्ल" : "कृष्ण";

    // 2. Masa (Lunar Month) from Sidereal Sun
    final String masa = masaNames[udayaResult.masaIndex];

    // 3. Vikram Samvat
    int samvat = effectiveDate.year + 57;
    if (effectiveDate.month < 3 || (effectiveDate.month == 3 && effectiveDate.day < 20)) {
      samvat -= 1;
    }

    // 4. Vedic Vaar (Sunrise to Sunrise)
    final int effectiveWeekday = effectiveDate.weekday;
    final String vaar = vedicVaars[(effectiveWeekday - 1) % 7];

    // 5. Prahar (8 per day)
    final String pahar = getPraharName(dt, solar);

    // 6. Muhurta (30 per day, each 2 Ghatis)
    final int muhurtaIndex = (vedicTime.ghati ~/ 2) % 30;
    final String muhurta = "${muhurtaNames[muhurtaIndex]} मुहूर्त";

    return VedicPanchang(
      masa: masa,
      paksha: paksha,
      udayaTithi: udayaTithi,
      currentTithi: currentTithi,
      samvat: samvat,
      vaar: vaar,
      pahar: pahar,
      muhurta: muhurta,
      vedicTime: vedicTime,
      solar: solar,
    );
  }

  /// Internal astronomical celestial coordinate calculation for Tithi & Masa
  static _AstronomicalResult _calculateTithiAt(DateTime dt) {
    // Convert IST to UTC moment
    final utc = dt.subtract(const Duration(hours: 5, minutes: 30));
    int y = utc.year;
    int m = utc.month;
    final double d = utc.day + (utc.hour + utc.minute / 60.0 + utc.second / 3600.0) / 24.0;
    if (m <= 2) {
      y -= 1;
      m += 12;
    }
    final int a = (y / 100).floor();
    final int b = 2 - a + (a / 4).floor();
    final double jd = (365.25 * (y + 4716)).floor() + (30.6001 * (m + 1)).floor() + d + b - 1524.5;
    final double t = (jd - 2451545.0) / 36525.0;

    // Sun longitude
    final double l0 = (280.46646 + 36000.76983 * t + 0.0003032 * t * t) % 360.0;
    final double mSun = (357.52911 + 35999.05029 * t - 0.0001537 * t * t) % 360.0;
    final double mSunRad = mSun * math.pi / 180.0;
    final double cSun = (1.914602 - 0.004817 * t) * math.sin(mSunRad) + 0.019993 * math.sin(2 * mSunRad);
    final double sunLong = (l0 + cSun + 360.0) % 360.0;

    // Moon longitude
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

    // Tithi elongation
    final double diff = (moonLong - sunLong + 360.0) % 360.0;
    final int tithiIndex = (diff / 12.0).floor() % 30;

    // Sidereal solar sign (Masa)
    final double siderealSun = (sunLong - 24.2 + 360.0) % 360.0;
    final int rashi = (siderealSun / 30.0).floor();
    final int masaIndex = (rashi + 1) % 12;

    return _AstronomicalResult(tithiIndex: tithiIndex, masaIndex: masaIndex);
  }

  /// Prahar name based on 8 Prahars of day & night
  static String getPraharName(DateTime dt, SolarTimings solar) {
    final hour = dt.hour;
    if (hour >= 6 && hour < 9) {
      return "प्रथम प्रहर";
    } else if (hour >= 9 && hour < 12) {
      return "द्वितीय प्रहर";
    } else if (hour >= 12 && hour < 15) {
      return "तृतीय प्रहर";
    } else if (hour >= 15 && hour < 18) {
      return "चतुर्थ प्रहर";
    } else if (hour >= 18 && hour < 21) {
      return "सायं प्रहर";
    } else if (hour >= 21 && hour < 24) {
      return "निशीथ प्रहर";
    } else if (hour >= 0 && hour < 3) {
      return "मध्यरात्रि प्रहर";
    } else {
      return "ब्रह्ममुहूर्त प्रहर";
    }
  }
}

class _AstronomicalResult {
  final int tithiIndex;
  final int masaIndex;
  const _AstronomicalResult({required this.tithiIndex, required this.masaIndex});
}
