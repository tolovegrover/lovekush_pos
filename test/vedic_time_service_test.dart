import 'package:flutter_test/flutter_test.dart';
import 'package:lovekush_pos/vedic_time_service.dart';

void main() {
  group('VedicTimeService Tests', () {
    test('Calculates New Delhi Sunrise and Sunset accurately via offline NOAA algorithm', () {
      final date = DateTime(2026, 9, 12);
      final solar = VedicTimeService.calculateSolarTimings(date);

      // Delhi sunrise on Sept 12 is ~06:04 IST, sunset is ~18:30 IST
      expect(solar.sunrise.hour, 6);
      expect(solar.sunrise.minute, 4);

      expect(solar.sunset.hour, 18);
      expect(solar.sunset.minute, 30);

      // Total Ahoratra is 60 Ghatis (24 hours)
      expect((solar.dayLengthGhatis + solar.nightLengthGhatis).round(), 60);
      expect(solar.dayLengthGhatis, greaterThan(30.0)); // Daytime is ~31.09 Ghatis
    });

    test('Converts Normal Clock Time to Vedic Time (Ghati:Pal:Vipal)', () {
      // 1. Exactly at sunrise -> 00:00:00
      final sunrise = DateTime(2026, 9, 12, 6, 4, 18);
      final vtSunrise = VedicTimeService.normalToVedic(sunrise, overrideSunrise: sunrise);
      expect(vtSunrise.ghati, 0);
      expect(vtSunrise.pal, 0);
      expect(vtSunrise.vipal.round(), 0);

      // 2. 4 hours 12 minutes (252 mins) after sunrise -> 10 Ghatis, 30 Pals
      final testTime = sunrise.add(const Duration(hours: 4, minutes: 12));
      final vt = VedicTimeService.normalToVedic(testTime, overrideSunrise: sunrise);
      expect(vt.ghati, 10);
      expect(vt.pal, 30);
      expect(vt.vipal.round(), 0);
      expect(vt.toNumericString(), "10:30:00");
      expect(vt.toDevanagariString(), contains("१०:३०:००"));

      // 3. Current time ~16:04:31 -> 25 Ghatis
      final dtNow = DateTime(2026, 9, 12, 16, 4, 31);
      final vtNow = VedicTimeService.normalToVedic(dtNow, overrideSunrise: sunrise);
      expect(vtNow.ghati, 25);
      expect(vtNow.pal, 0);
      expect(vtNow.vipal.round(), 33);
    });

    test('Bidirectional conversion: Vedic to Normal and Normal to Vedic', () {
      final baseDate = DateTime(2026, 9, 12);
      final originalTime = DateTime(2026, 9, 12, 14, 25, 48);

      // 1. Normal -> Vedic
      final vedic = VedicTimeService.normalToVedic(originalTime);

      // 2. Vedic -> Normal
      final convertedBack = VedicTimeService.vedicToNormal(
        ghati: vedic.ghati,
        pal: vedic.pal,
        vipal: vedic.vipal,
        date: baseDate,
      );

      // High precision verification: difference is less than 1 second
      final diff = convertedBack.difference(originalTime).inMilliseconds.abs();
      expect(diff, lessThan(1000));
    });

    test('Calculates authentic Panchang with Udaya Tithi and Vedic Vaar', () {
      final dt = DateTime(2026, 9, 12, 13, 27, 6);
      final panchang = VedicTimeService.calculatePanchang(dt);

      expect(panchang.masa, "भाद्रपद");
      expect(panchang.paksha, "शुक्ल");
      expect(panchang.udayaTithi, "प्रतिपदा");
      expect(panchang.samvat, 2083);
      expect(panchang.vaar, "शनिवासर");
      expect(panchang.pahar, "तृतीय प्रहर");
      expect(panchang.muhurta, contains("मुहूर्त"));

      final line = panchang.toReceiptPanchangLine();
      expect(line, "भाद्रपद, शुक्ल प्रतिपदा, २०८३ विक्रम संवत् (तृतीय प्रहर)");
    });

    test('Hybrid mode returns reliable solar timings with offline fallback', () async {
      final date = DateTime(2026, 9, 12);
      final solar = await VedicTimeService.fetchSolarTimingsHybrid(
        date,
        timeout: const Duration(milliseconds: 500),
      );

      expect(solar.sunrise.hour, 6);
      expect(solar.sunrise.minute, inInclusiveRange(3, 5));
      expect(solar.sunset.hour, 18);
    });

    test('Drik Panchang Live Verification: 30-Ghati vs 60-Ghati matches drikpanchang.com', () {
      final date = DateTime(2026, 9, 12);
      final sunrise = DateTime(2026, 9, 12, 6, 4, 23);
      final sunset = DateTime(2026, 9, 12, 18, 29, 57);

      // 1. Drik Panchang at 16:32:09 in 30-Ghati mode -> 25:15:35
      final dt1632 = DateTime(2026, 9, 12, 16, 32, 9);
      final vt30 = VedicTimeService.normalToVedic30Ghati(
        dt1632,
        overrideSunrise: sunrise,
        overrideSunset: sunset,
      );
      expect(vt30.ghati, 25);
      expect(vt30.pal, 15);
      expect(vt30.vipal.round(), inInclusiveRange(34, 36));

      // 2. Drik Panchang at 16:32:09 in 60-Ghati mode -> 26:09:25
      final vt60 = VedicTimeService.normalToVedic(
        dt1632,
        overrideSunrise: sunrise,
      );
      expect(vt60.ghati, 26);
      expect(vt60.pal, 9);
      expect(vt60.vipal.round(), inInclusiveRange(24, 26));

      // 3. At Sunset in 30-Ghati mode -> Exactly 30:00:00
      final vtSunset30 = VedicTimeService.normalToVedic30Ghati(
        sunset,
        overrideSunrise: sunrise,
        overrideSunset: sunset,
      );
      expect(vtSunset30.ghati, 30);
      expect(vtSunset30.pal, 0);

      // 4. Drik Panchang at 13:27:06 in 60-Ghati mode -> 18:26:28 (with ~06:04:31 sunrise)
      final dt1327 = DateTime(2026, 9, 12, 13, 27, 6);
      final sunrise1826 = DateTime(2026, 9, 12, 6, 4, 31);
      final vt1327_60 = VedicTimeService.normalToVedic(
        dt1327,
        overrideSunrise: sunrise1826,
      );
      expect(vt1327_60.ghati, 18);
      expect(vt1327_60.pal, 26);
      expect(vt1327_60.vipal.round(), 28);

      // 5. Bidirectional 30-Ghati conversion: 25:15:35.34 back to 16:32:09
      final convertedBack = VedicTimeService.vedicToNormal30Ghati(
        ghati: vt30.ghati,
        pal: vt30.pal,
        vipal: vt30.vipal,
        date: date,
        overrideSunrise: sunrise,
        overrideSunset: sunset,
      );
      expect(convertedBack.hour, 16);
      expect(convertedBack.minute, 32);
      expect(convertedBack.second, 9);
    });
  });
}
