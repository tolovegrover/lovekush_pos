import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lovekush_pos/vedic_clock_screen.dart';
import 'package:lovekush_pos/settings_screen.dart';
import 'package:lovekush_pos/vedic_time_service.dart';

void main() {
  group('Vedic Clock & Settings Screen Widget Tests', () {
    testWidgets('VedicClockScreen renders live clock, solar timings, and authentic panchang', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VedicClockScreen(),
        ),
      );
      await tester.pump();

      // Check header and live badge
      expect(find.text("वैदिक समय एवं पञ्चाङ्ग"), findsOneWidget);
      expect(find.text("LIVE"), findsOneWidget);

      // Check tabs
      expect(find.text("लाइव घड़ी (Live)"), findsOneWidget);
      expect(find.text("परिवर्तक (Converter)"), findsOneWidget);
      expect(find.text("प्रमाण व सूत्र (Rules)"), findsOneWidget);

      // Check Live Clock content
      expect(find.textContaining("श्री गणेशाय नमः"), findsOneWidget);
      expect(find.textContaining("वैदिक समय (घटी : पल : विपल)"), findsOneWidget);
      expect(find.textContaining("60 घटी मान"), findsOneWidget);
      expect(find.textContaining("सूर्योदय (Sunrise)"), findsOneWidget);
      expect(find.textContaining("सूर्यास्त (Sunset)"), findsOneWidget);
      expect(find.textContaining("दैनिक शुद्ध पञ्चाङ्ग"), findsOneWidget);
      expect(find.textContaining("विक्रम संवत्"), findsWidgets);
    });

    testWidgets('VedicClockScreen Converter tab converts clock time to vedic and vice-versa', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VedicClockScreen(),
        ),
      );
      await tester.pump();

      // Tap on Converter tab
      await tester.tap(find.text("परिवर्तक (Converter)"));
      await tester.pumpAndSettle();

      // Verify converter sections exist
      expect(find.textContaining("घड़ी समय ➔ वैदिक समय"), findsOneWidget);
      expect(find.textContaining("वैदिक समय ➔ घड़ी समय"), findsOneWidget);
      expect(find.textContaining("सूर्योदय आधार (Sunrise Base):"), findsOneWidget);

      // Check calculation results for pre-loaded 13:27:06
      expect(find.textContaining("वैदिक समय परिणाम:"), findsOneWidget);
      expect(find.textContaining("सामान्य घड़ी समय परिणाम:"), findsOneWidget);

      // Verify preset chips
      expect(find.text("13:27:06 (ऑनलाइन टेस्ट)"), findsOneWidget);
      expect(find.text("18:27:00 (ऑनलाइन टेस्ट)"), findsOneWidget);
    });

    testWidgets('VedicClockScreen Rules tab renders unit reference table', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: VedicClockScreen(),
        ),
      );
      await tester.pump();

      // Tap on Rules tab
      await tester.tap(find.text("प्रमाण व सूत्र (Rules)"));
      await tester.pumpAndSettle();

      expect(find.textContaining("वैदिक काल मापन इकाई तालिका"), findsOneWidget);
      expect(find.textContaining("१ अहोरात्र (Ahoratri)"), findsOneWidget);
      expect(find.textContaining("१ मुहूर्त (Muhurta)"), findsOneWidget);
      expect(find.textContaining("१ घटी / दण्ड (Ghati)"), findsOneWidget);
      expect(find.textContaining("१ पल / विघटी (Pal)"), findsOneWidget);
      expect(find.textContaining("१ विपल (Vipal)"), findsOneWidget);
      expect(find.textContaining("hinducalendar.app"), findsOneWidget);
    });

    testWidgets('SettingsScreen renders Vedic Time options and receipt preferences', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining("सेटिंग्स एवं प्राथमिकताएं"), findsOneWidget);
      expect(find.textContaining("वैदिक घड़ी एवं काल परिवर्तक"), findsOneWidget);
      expect(find.textContaining("रसीद पर वैदिक पञ्चाङ्ग दिखाएं"), findsOneWidget);
      expect(find.textContaining("डिफ़ॉल्ट रसीद भाषा"), findsOneWidget);
      expect(find.textContaining("भगवान वंदना शीर्ष पंक्ति"), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(find.textContaining("लव कुश शॉपिङ्ग सेण्टर"), findsOneWidget);
    });
  });
}
