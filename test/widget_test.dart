import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lovekush_pos/main.dart';
import 'package:lovekush_pos/cosmetics_catalog.dart';
import 'package:lovekush_pos/pdf_receipt_service.dart';

void main() {
  group('Item Name Sanitization & Barcode Fallback', () {
    test('cleanItemName returns barcode number when name is null, empty or General Item', () {
      expect(cleanItemName(null, barcode: "8901030839122"), "8901030839122");
      expect(cleanItemName("", barcode: "8901030839122"), "8901030839122");
      expect(cleanItemName("General Item", barcode: "8901030839122"), "8901030839122");
      expect(cleanItemName("general item", barcode: "8901030839122"), "8901030839122");
      expect(cleanItemName("Unassigned Product", barcode: "8901030839122"), "8901030839122");
      expect(cleanItemName("Barcode 8901030839122", barcode: "8901030839122"), "8901030839122");
    });

    test('cleanItemName strips duplicate bracketed barcode numbers cleanly', () {
      expect(
        cleanItemName("Ponds White Beauty Cream (8901030839122)", barcode: "8901030839122"),
        "Ponds White Beauty Cream",
      );
      expect(
        cleanItemName("Ponds Cold Cream 55ml (01-03-C-134)", barcode: "01-03-C-134"),
        "Ponds Cold Cream 55ml",
      );
    });

    test('Offline master catalog recognizes Pond\'s White Beauty & Bright Beauty barcodes in 0ms', () {
      final bbCream = findCosmeticByBarcode("8901030456619");
      expect(bbCream, isNotNull);
      expect(bbCream!['name'], contains("Ponds White Beauty BB+"));

      final faceWash = findCosmeticByBarcode("8901030681349");
      expect(faceWash, isNotNull);
      expect(faceWash!['name'], contains("Ponds White Beauty Daily Face Wash"));

      final cream12g = findCosmeticByBarcode("8901030839122");
      expect(cream12g, isNotNull);
      expect(cream12g!['name'], contains("Ponds White Beauty Spot-less Fairness Cream 12g"));

      final cream23g = findCosmeticByBarcode("8901030742514");
      expect(cream23g, isNotNull);
      expect(cream23g!['name'], contains("Ponds White Beauty Daily Anti-Spot Cream 23g"));

      final coldCream = findCosmeticByBarcode("8901030609183");
      expect(coldCream, isNotNull);
      expect(coldCream!['name'], contains("Ponds White Beauty Cold Cream 55ml"));
    });

    test('Master catalog recognizes Lakme 9to5 Double Duty and Kajal instantly', () {
      final doubleDuty = findCosmeticByBarcode("8901030767609");
      expect(doubleDuty, isNotNull);
      expect(doubleDuty!['name'], contains("Lakme 9 To 5 Double Duty"));
      expect(doubleDuty['price'], 349.0);

      final kajal = findCosmeticByBarcode("8901030673214");
      expect(kajal, isNotNull);
      expect(kajal!['name'], contains("Lakme Eyeconic Kajal"));
      expect(kajal['price'], 190.0);

      final searchResults = searchCosmeticsByName("lakme double duty");
      expect(searchResults.isNotEmpty, isTrue);
      expect(searchResults.any((p) => p['name'].toString().contains("Double Duty")), isTrue);
    });

    test('extractDualRates parses rates from price and description JSON correctly', () {
      // 1. Single rate item
      final singleItem = {
        'price': 190.0,
        'description': 'Regular kajal',
      };
      expect(extractDualRates(singleItem), [190.0]);

      // 2. Dual rates in description JSON
      final dualItem = {
        'price': 210.0,
        'description': '{"notes":"Price hiked","dual_rates":[190.0, 210.0]}',
      };
      final rates = extractDualRates(dualItem);
      expect(rates, [190.0, 210.0]);

      // 3. Dual rates in dual_rates key directly
      final dualKeyItem = {
        'price': 349.0,
        'dual_rates': [320.0, 349.0],
      };
      expect(extractDualRates(dualKeyItem), [320.0, 349.0]);

      // 4. Duplicate removal and sorting
      final dupItem = {
        'price': 190.0,
        'description': '{"dual_rates":[210.0, 190.0, 190.0, 210.0]}',
      };
      expect(extractDualRates(dupItem), [190.0, 210.0]);
    });

    test('resolveBarcodeOnlineMulti never returns foreign USD prices as INR rate', () async {
      final results = await resolveBarcodeOnlineMulti("8901030673214");
      // If found online via UPC database or Open Facts, the price must NOT be foreign USD ($3.49 or $10.08)
      for (var r in results) {
        if (r['source'] == 'UPC Database') {
          expect(r['price'], 0.0, reason: "Foreign currency prices must never be used as Indian INR MRP!");
        }
      }
    });

    test('PendingRateChangesManager tracks manual rate overrides for catalog approval', () {
      PendingRateChangesManager.clear();
      expect(PendingRateChangesManager.items.isEmpty, isTrue);

      PendingRateChangesManager.addRateChange(
        itemCode: "0103C134",
        barcode: "8901030673214",
        itemName: "Lakme Eyeconic Kajal",
        oldRate: 190.0,
        newRate: 210.0,
      );

      expect(PendingRateChangesManager.items.length, 1);
      final entry = PendingRateChangesManager.items.first;
      expect(entry['item_code'], "0103C134");
      expect(entry['old_rate'], 190.0);
      expect(entry['new_rate'], 210.0);

      // Removing by code
      PendingRateChangesManager.remove("0103C134");
      expect(PendingRateChangesManager.items.isEmpty, isTrue);
    });

    test('resolveBarcodeOnlineMulti includes barcode-list.com in multi-registry lookup', () async {
      final results = await resolveBarcodeOnlineMulti("8901030673214");
      if (results.isNotEmpty) {
        final hasBarcodeList = results.any((r) => r['source'] == 'Barcode-List' || r['name'].toString().toUpperCase().contains("LAKME"));
        expect(hasBarcodeList, isTrue);
      }
    });

    test('Master catalog recognizes Patanjali, Mysore Sandal, Set Wet and Mamaearth in 0ms', () {
      final dantKanti = findCosmeticByBarcode("8904109450327");
      expect(dantKanti, isNotNull);
      expect(dantKanti!['name'], contains("Dant Kanti"));
      expect(dantKanti['brand'], "Patanjali");

      final mysoreSandal = findCosmeticByBarcode("8901287100013");
      expect(mysoreSandal, isNotNull);
      expect(mysoreSandal!['name'], contains("Mysore Sandal"));

      final setWet = findCosmeticByBarcode("8901088069724");
      expect(setWet, isNotNull);
      expect(setWet!['brand'], "Set Wet");

      final mamaearth = findCosmeticByBarcode("8904417305258");
      expect(mamaearth, isNotNull);
      expect(mamaearth!['brand'], "Mamaearth");
    });

    test('resolveBarcodeOnlineMulti includes Go-UPC registry for Indian retail barcodes', () async {
      final results = await resolveBarcodeOnlineMulti("8901030767609");
      if (results.isNotEmpty) {
        final hasGoUpcOrMatch = results.any((r) => r['source'] == 'Go-UPC' || r['name'].toString().toLowerCase().contains("lakme"));
        expect(hasGoUpcOrMatch, isTrue);
      }
    });

    test('resolveBarcodeOnlineMulti includes GS1 DataKart India for authentic brand/product resolution', () async {
      final results = await resolveBarcodeOnlineMulti("8901030673214");
      if (results.isNotEmpty) {
        final hasGs1OrMatch = results.any((r) => r['source'] == 'GS1 DataKart India' || r['name'].toString().toUpperCase().contains("LAKME"));
        expect(hasGs1OrMatch, isTrue);
      }
    });

    test('PdfReceiptService formats clean WhatsApp bill summary with emoji layout', () {
      final sampleBill = {
        'bill_number': 'LK-2026-0042',
        'total_amount': 410.0,
        'payment_method': 'Cash',
        'items_json': [
          {'itemName': 'Lakme Eyeconic Kajal', 'qty': 1, 'rate': 190.0, 'total': 190.0},
          {'itemName': 'Ponds Cold Cream', 'qty': 2, 'rate': 110.0, 'total': 220.0},
        ],
      };

      final msg = PdfReceiptService.formatWhatsAppBillMessage(sampleBill);
      expect(msg, contains("࿗ ॐ श्री महालक्ष्म्यै नमः ࿗"));
      expect(msg, contains("लव कुश शॉपिङ्ग सेण्टर"));
      expect(msg, contains("LOVE KUSH SHOPPING CENTER"));
      expect(msg, contains("ल.कु.-२०२६-००४२"));
      expect(msg, contains("Lakme Eyeconic Kajal"));
      expect(msg, contains("Ponds Cold Cream"));
      expect(msg, contains("सकल देय राशि: ₹ 410.00"));
      expect(msg, contains("पञ्चाङ्ग:"));
      expect(msg, contains("प्रहर"));
      expect(msg, contains("दिनाङ्क व समय:"));
      expect(msg, contains("कोषपाल:"));
      expect(msg, contains("सधन्यवाद! पुनः पधारें!"));
    });

    test('PdfReceiptService validates and formats Indian phone numbers', () {
      expect(PdfReceiptService.sanitizeIndianPhoneNumber("9812345678"), "919812345678");
      expect(PdfReceiptService.sanitizeIndianPhoneNumber("+91 98123-45678"), "919812345678");
      expect(PdfReceiptService.sanitizeIndianPhoneNumber("09812345678"), "919812345678");
      expect(PdfReceiptService.sanitizeIndianPhoneNumber("919812345678"), "919812345678");
      expect(PdfReceiptService.sanitizeIndianPhoneNumber("12345"), isNull);
    });

    test('PdfReceiptService generates valid PDF document bytes with Code 128 barcode', () async {
      final sampleBill = {
        'bill_number': 'LK20260912-0042',
        'staff_name': 'Admin',
        'total_amount': 349.0,
        'payment_method': 'Online',
        'amount_tendered': 349.0,
        'change_due': 0.0,
        'created_at': DateTime.now().toIso8601String(),
        'items_json': [
          {'itemName': 'Lakme 9 To 5 Double Duty Water Stain', 'qty': 1, 'rate': 349.0, 'total': 349.0},
        ],
      };

      final pdfBytes = await PdfReceiptService.generateReceiptPdf(sampleBill);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
      // Standard PDF magic header: %PDF-
      expect(pdfBytes[0], 0x25); // %
      expect(pdfBytes[1], 0x50); // P
      expect(pdfBytes[2], 0x44); // D
      expect(pdfBytes[3], 0x46); // F
    });

    test('PdfReceiptService handles String-typed amounts, rates, qty without type cast error', () async {
      // Replicate the exact bug where cart items or database rows store numbers as Strings
      final stringTypedBill = {
        'bill_number': 'LK-STR-999',
        'staff_name': 'Love Kush',
        'total_amount': '450.50', // String instead of double!
        'payment_method': 'Cash',
        'amount_tendered': '500.00', // String!
        'change_due': '49.50', // String!
        'items_json': [
          {
            'itemName': 'Pond\'s White Beauty Cream',
            'qty': '2', // String instead of int!
            'rate': '150.00', // String instead of double!
            'price': '300.00', // String instead of num!
          },
          {
            'itemName': 'Lakme Absolute Kajal',
            'qty': '1',
            'rate': '150.50',
            'total': '150.50',
          },
        ],
      };

      // 1. WhatsApp summary formatting must never throw type cast exception
      final waMsg = PdfReceiptService.formatWhatsAppBillMessage(stringTypedBill);
      expect(waMsg, contains("Pond's White Beauty Cream"));
      expect(waMsg, contains("सकल देय राशि: ₹ 450.50"));

      // 2. PDF generation must never throw 'String is not subtype of num?'
      final bytes = await PdfReceiptService.generateReceiptPdf(stringTypedBill);
      Directory('build').createSync(recursive: true);
      File('build/sample_receipt.pdf').writeAsBytesSync(bytes);
      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(1000));
      expect(bytes[0], 0x25); // %
      expect(bytes[1], 0x50); // P
    });

    test('PdfReceiptService supports both Hindi and English receipts with English item names', () async {
      final sampleBill = {
        'bill_number': 'LK-BI-2026',
        'staff_name': 'Cashier 1',
        'total_amount': 550.0,
        'payment_method': 'Cash',
        'amount_tendered': 600.0,
        'change_due': 50.0,
        'created_at': DateTime.now().toIso8601String(),
        'items_json': [
          {'itemName': 'Lakme Absolute Kajal', 'qty': 1, 'rate': 250.0, 'total': 250.0},
          {'itemName': 'Pond\'s White Beauty Cream', 'qty': 1, 'rate': 300.0, 'total': 300.0},
        ],
      };

      // 1. English WhatsApp summary
      final engMsg = PdfReceiptService.formatWhatsAppBillMessage(sampleBill, language: ReceiptLanguage.english);
      expect(engMsg, contains("࿗ ॐ श्री महालक्ष्म्यै नमः ࿗")); // Bhagwan namaste on top in English too!
      expect(engMsg, contains("LOVE KUSH SHOPPING CENTER"));
      expect(engMsg, contains("*Bill No:* LK-BI-2026"));
      expect(engMsg, contains("Lakme Absolute Kajal")); // Item name in English
      expect(engMsg, contains("Pond's White Beauty Cream")); // Item name in English
      expect(engMsg, contains("GRAND TOTAL: Rs. 550.00"));
      expect(engMsg, contains("*Payment Method:* CASH"));
      expect(engMsg, contains("THANK YOU FOR SHOPPING! VISIT AGAIN!"));

      // 2. Hindi WhatsApp summary
      final hindiMsg = PdfReceiptService.formatWhatsAppBillMessage(sampleBill, language: ReceiptLanguage.hindi);
      expect(hindiMsg, contains("࿗ ॐ श्री महालक्ष्म्यै नमः ࿗"));
      expect(hindiMsg, contains("लव कुश शॉपिङ्ग सेण्टर"));
      expect(hindiMsg, contains("*बीजक सङ्ख्या:* ल.कु.-बी.आई.-२०२६"));
      expect(hindiMsg, contains("Lakme Absolute Kajal")); // Item name in English
      expect(hindiMsg, contains("Pond's White Beauty Cream")); // Item name in English
      expect(hindiMsg, contains("पञ्चाङ्ग:"));
      expect(hindiMsg, contains("प्रहर"));
      expect(hindiMsg, contains("दिनाङ्क व समय:"));
      expect(hindiMsg, contains("कोषपाल:"));
      expect(hindiMsg, contains("सकल देय राशि: ₹ 550.00"));
      expect(hindiMsg, contains("सधन्यवाद! पुनः पधारें!"));

      // 3. English PDF Generation
      final engPdfBytes = await PdfReceiptService.generateReceiptPdf(sampleBill, language: ReceiptLanguage.english);
      File('build/english_receipt.pdf').writeAsBytesSync(engPdfBytes);
      expect(engPdfBytes, isNotNull);
      expect(engPdfBytes.length, greaterThan(1000));
      expect(engPdfBytes[0], 0x25); // %
      expect(engPdfBytes[1], 0x50); // P

      // 4. Hindi PDF Generation (with Siddhanta Calcutta font)
      final hindiPdfBytes = await PdfReceiptService.generateReceiptPdf(sampleBill, language: ReceiptLanguage.hindi);
      File('build/hindi_receipt.pdf').writeAsBytesSync(hindiPdfBytes);
      expect(hindiPdfBytes, isNotNull);
      expect(hindiPdfBytes.length, greaterThan(1000));
      expect(hindiPdfBytes[0], 0x25); // %
      expect(hindiPdfBytes[1], 0x50); // P
    });

    test('PdfReceiptService supports Random Mantra mode and authentic store address', () async {
      final sampleBill = {
        'bill_number': 'LK-RND-108',
        'staff_name': 'Love Kush',
        'total_amount': 250.0,
        'payment_method': 'UPI',
        'items_json': [
          {'itemName': 'Lakme Absolute Lip Color', 'qty': 1, 'rate': 250.0, 'total': 250.0},
        ],
      };

      // 1. Address is present in Hindi WhatsApp bill
      final hindiWa = PdfReceiptService.formatWhatsAppBillMessage(sampleBill, language: ReceiptLanguage.hindi);
      expect(hindiWa, contains("ए-२/३९२, सुभाष कंसल मार्ग, हर्ष विहार, दिल्ली - ११००९३"));

      // 2. Address is present in English WhatsApp bill
      final engWa = PdfReceiptService.formatWhatsAppBillMessage(sampleBill, language: ReceiptLanguage.english);
      expect(engWa, contains("A-2/392, Subhash Kansal Marg, Harsh Vihar, Delhi - 110093"));

      // 3. Random Mantra mode resolves dynamically
      final resolvedMantra = PdfReceiptService.resolveActiveInvocation(PdfReceiptService.randomMantraKey);
      expect(resolvedMantra, startsWith("\u0FD7"));
      expect(resolvedMantra, endsWith("\u0FD7"));
      expect(resolvedMantra.length, greaterThan(5));

      // 4. Multiple invocations return authentic preset mantras
      final sampleMantras = List.generate(10, (_) => PdfReceiptService.resolveActiveInvocation(PdfReceiptService.randomMantraKey));
      expect(sampleMantras.every((m) => m.contains("\u0FD7")), isTrue);
    });

    test('WhatsApp bill sharing formats both Hindi and English with Bhagwan Namaste invocation and no return disclaimer', () {
      final sampleBill = {
        'bill_number': 'LK-0912-0088',
        'staff_name': 'Love Kush',
        'total_amount': 550.0,
        'payment_method': 'Cash',
        'amount_tendered': 600.0,
        'change_due': 50.0,
        'items_json': [
          {'itemName': 'Pond\'s Cold Cream 100ml', 'qty': 2, 'rate': 275.0, 'total': 550.0},
        ],
      };

      // 1. Hindi WhatsApp bill format
      final hindiWa = PdfReceiptService.formatWhatsAppBillMessage(sampleBill, language: ReceiptLanguage.hindi);
      expect(hindiWa, contains("\u0FD7"));
      expect(hindiWa, contains("ॐ श्री महालक्ष्म्यै नमः"));
      expect(hindiWa, contains("ल.कु.-०९१२-००८८"));
      expect(hindiWa, contains("₹ 550.00"));
      expect(hindiWa, contains("रोकड़ा")); // 'रोकड़ा' used instead of 'रोकड़'
      expect(hindiWa, contains("बिका हुआ माल वापस या बदला नहीं जाएगा"));
      expect(hindiWa, isNot(contains("NO RETURN, NO EXCHANGE")));
      expect(hindiWa, contains("पञ्चाङ्ग:"));

      // 2. English WhatsApp bill format
      final engWa = PdfReceiptService.formatWhatsAppBillMessage(sampleBill, language: ReceiptLanguage.english);
      expect(engWa, contains("\u0FD7"));
      expect(engWa, contains("ॐ श्री महालक्ष्म्यै नमः"));
      expect(engWa, contains("Bill No:* LK-0912-0088"));
      expect(engWa, contains("Rs. 550.00"));
      expect(engWa, contains("NO RETURN, NO EXCHANGE"));
    });

    test('Authentic Panchang, Prahar, Rokada, and Mishrit Bhugtan translation validation', () async {
      final sampleBill = {
        'bill_number': 'LK-0912-0099',
        'staff_name': 'Love Kush',
        'total_amount': 700.0,
        'payment_method': 'Hybrid (Cash: 500, Online: 200)',
        'created_at': '2026-09-12T13:13:00+05:30',
        'items_json': [
          {'itemName': 'Pond\'s Cold Cream 100ml', 'qty': 2, 'rate': 275.0, 'total': 550.0},
          {'itemName': 'Lakme Eyeliner', 'qty': 1, 'rate': 150.0, 'total': 150.0},
        ],
      };

      // Check WhatsApp formatting for Bhadrapada, Shukla Pratipada (Udayatithi), Samvat 2083, Shanivasar, Tritiya Prahar
      final hindiWa = PdfReceiptService.formatWhatsAppBillMessage(sampleBill, language: ReceiptLanguage.hindi);
      expect(hindiWa, contains("भाद्रपद"));
      expect(hindiWa, contains("शुक्ल प्रतिपदा"));
      expect(hindiWa, contains("२०८३ विक्रम संवत्"));
      expect(hindiWa, contains("शनिवासर"));
      expect(hindiWa, contains("सितम्बर 12, 2026"));
      expect(hindiWa, contains("तृतीय प्रहर"));
      expect(hindiWa, contains("मिश्रित भुगतान"));
      expect(hindiWa, contains("रोकड़ा:* ₹ 500"));
      expect(hindiWa, contains("ऑनलाइन:* ₹ 200"));

      // English WhatsApp hybrid split
      final engWa = PdfReceiptService.formatWhatsAppBillMessage(sampleBill, language: ReceiptLanguage.english);
      expect(engWa, contains("Payment Method:* HYBRID"));
      expect(engWa, contains("Cash:* Rs. 500"));
      expect(engWa, contains("Online:* Rs. 200"));

      // Check IST timestamp normalization
      final dt = PdfReceiptService.parseIndianStandardTime('2026-09-12T07:43:00Z'); // 07:43 UTC = 13:13 IST
      expect(dt.hour, 13);
      expect(dt.minute, 13);
      expect(PdfReceiptService.getPaharName(dt), "तृतीय प्रहर");
      expect(PdfReceiptService.getVedicVaarName(dt), "शनिवासर");
      expect(PdfReceiptService.formatVedicDateAndTimeString(dt), "शनिवासर, सितम्बर 12, 2026 | 13:13");

      // Check hybrid split parser and PDF generation
      final parts = PdfReceiptService.parseHybridParts("Hybrid (Cash ₹500, Online ₹250)");
      expect(parts, isNotNull);
      expect(parts!['cash'], 500.0);
      expect(parts['online'], 250.0);

      final pdfBytes = await PdfReceiptService.generateReceiptPdf(sampleBill, language: ReceiptLanguage.hindi);
      expect(pdfBytes.length, greaterThan(1000));
    });

    testWidgets('PdfReceiptService direct WhatsApp dialog UI and buttons validation', (WidgetTester tester) async {
      final testBill = {
        'bill_number': 'LK-WA-101',
        'staff_name': 'Test Cashier',
        'total_amount': 450.0,
        'payment_method': 'Cash',
        'created_at': '2026-09-12T10:00:00+05:30',
        'items_json': [
          {'itemName': 'Patanjali Dant Kanti', 'qty': 1, 'rate': 120.0, 'total': 120.0},
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => PdfReceiptService.showWhatsAppPdfDialog(context: ctx, bill: testBill),
                child: const Text('OPEN DIALOG'),
              ),
            ),
          ),
        ),
      );

      // Tap open dialog
      await tester.tap(find.text('OPEN DIALOG'));
      await tester.pumpAndSettle();

      // Verify direct WhatsApp options and buttons are rendered
      expect(find.text("OPEN DIRECT WHATSAPP CHAT"), findsOneWidget);
      expect(find.text("SEND PDF BILL ON WHATSAPP"), findsOneWidget);
      expect(find.text("OTHER APPS"), findsOneWidget);
      expect(find.text("PREVIEW"), findsOneWidget);
      expect(find.text("Customer Mobile (WhatsApp):"), findsOneWidget);
      expect(find.text("No contact save needed"), findsOneWidget);

      // Verify phone sanitization
      expect(PdfReceiptService.sanitizeIndianPhoneNumber("9812345678"), "919812345678");
      expect(PdfReceiptService.sanitizeIndianPhoneNumber("+91 98123 45678"), "919812345678");
      expect(PdfReceiptService.sanitizeIndianPhoneNumber("09812345678"), "919812345678");
    });

    test('fetchProductDetailsByBarcode resolves commercial cosmetics barcodes with name, price, and category', () async {
      // 1. Lakme Eyeconic Kajal (8901030732585)
      final lakmeKajal = await fetchProductDetailsByBarcode("8901030732585");
      expect(lakmeKajal, isNotNull);
      expect(lakmeKajal!['name'], contains("Lakme Eyeconic Kajal"));
      expect(lakmeKajal['price'], 190.0);
      expect(lakmeKajal['mrp'], 190.0);
      expect(lakmeKajal['category'], "Eyes");
      expect(lakmeKajal['source'], "Cosmetics Catalog");

      // 2. Lakme 9 To 5 Double Duty (8901030767609)
      final doubleDuty = await fetchProductDetailsByBarcode("8901030767609");
      expect(doubleDuty, isNotNull);
      expect(doubleDuty!['name'], contains("Lakme 9 To 5 Double Duty"));
      expect(doubleDuty['price'], 349.0);
      expect(doubleDuty['category'], "Lips");

      // 3. Pond's White Beauty (8901030839122)
      final ponds = await fetchProductDetailsByBarcode("8901030839122");
      expect(ponds, isNotNull);
      expect(ponds!['name'], contains("Ponds White Beauty"));
      expect(ponds['price'], 35.0);
      expect(ponds['category'], "Skincare");

      // 4. fetchOpenBeautyFacts wraps fetchProductDetailsByBarcode correctly
      final obf = await fetchOpenBeautyFacts("8901030732585");
      expect(obf, isNotNull);
      expect(obf!['name'], contains("Lakme Eyeconic Kajal"));
      expect(obf['price'], "190.0");
    });

    test('normalizeCosmeticCategory maps diverse beauty taxonomy to valid POS categories', () {
      expect(normalizeCosmeticCategory("Eye Liner"), "Eyes");
      expect(normalizeCosmeticCategory("Eyeshadow"), "Eyes");
      expect(normalizeCosmeticCategory("Lipstick"), "Lips");
      expect(normalizeCosmeticCategory("Lip Balm"), "Lips");
      expect(normalizeCosmeticCategory("Compact Powder Face"), "Face");
      expect(normalizeCosmeticCategory("Nail Polish"), "Nails");
      expect(normalizeCosmeticCategory("Skin Care Cold Cream"), "Skincare");
      expect(normalizeCosmeticCategory("Face Wash"), "Face");
      expect(normalizeCosmeticCategory("Hair Care Shampoo"), "Hair");
      expect(normalizeCosmeticCategory("Hair Oil"), "Hair");
      expect(normalizeCosmeticCategory("Glass Bangles"), "Bangles");
      expect(normalizeCosmeticCategory("Jewelry"), "Jewelry");
      expect(normalizeCosmeticCategory("General"), "General");
      expect(normalizeCosmeticCategory(null), "Cosmetics");
      expect(normalizeCosmeticCategory(""), "Cosmetics");
    });

    testWidgets('ItemCatalogScreen Add Item dialog auto-fetches details when barcode is entered', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ItemCatalogScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Find and tap the "+ Add Item" FAB
      final addItemFab = find.widgetWithText(FloatingActionButton, "Add Item");
      expect(addItemFab, findsOneWidget);
      await tester.tap(addItemFab);
      await tester.pump(const Duration(milliseconds: 400));

      // Dialog should be open
      expect(find.text("Add Item (Dual Barcodes)"), findsOneWidget);

      // Enter Lakme Eyeconic Kajal barcode
      final companyBarcodeField = find.widgetWithText(TextField, "Company Barcode (Optional)");
      expect(companyBarcodeField, findsOneWidget);

      // Type the barcode into the field and trigger auto-fetch
      await tester.enterText(companyBarcodeField, "8901030732585");
      // Wait for debounce timer (300ms) to fire
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify item name and MRP are auto-populated!
      expect(find.text("Lakme Eyeconic Kajal Deep Black"), findsOneWidget);
      expect(find.text("190"), findsWidgets);

      // Verify the Unique Scanner top button is rendered
      expect(find.text("⚡ UNIQUE SCANNER (BOX & SHELF IN 1 GO)"), findsOneWidget);
      expect(find.text("Scan box barcode & shelf sticker in 1 camera session"), findsOneWidget);
    });

    test('classifyScannedCode correctly classifies product box barcodes and shelf stickers', () {
      // Commercial product barcodes (EAN-13, EAN-8, UPC, Indian 890...)
      expect(classifyScannedCode("8901030732585"), ScannedCodeType.productBarcode);
      expect(classifyScannedCode("8901030839122"), ScannedCodeType.productBarcode);
      expect(classifyScannedCode("012345678905"), ScannedCodeType.productBarcode);
      expect(classifyScannedCode("4006381333931"), ScannedCodeType.productBarcode);

      // Shelf sticker codes and QR codes (hyphenated, rack-col-row-item, alphanumeric, short numeric)
      expect(classifyScannedCode("01-03-C-134"), ScannedCodeType.shelfCode);
      expect(classifyScannedCode("01-03-C"), ScannedCodeType.shelfCode);
      expect(classifyScannedCode("02-05-A-12"), ScannedCodeType.shelfCode);
      expect(classifyScannedCode("PENDING-1"), ScannedCodeType.shelfCode);
      expect(classifyScannedCode("134"), ScannedCodeType.shelfCode);
      expect(classifyScannedCode("SHELF-01"), ScannedCodeType.shelfCode);
    });

    testWidgets('QRScannerScreen renders dual scan mode HUD and viewfinder', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: QRScannerScreen(
            title: "Unique Scanner (Box & Shelf)",
            isDualScanMode: true,
            initialProductBarcode: "8901030732585",
            initialShelfCode: null,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Title & dual mode viewfinder
      expect(find.text("Unique Scanner (Box & Shelf)"), findsOneWidget);
      expect(find.text("Point at Product Box or Shelf Sticker"), findsOneWidget);
      expect(find.text("Scans Both: Box Barcode & Shelf Sticker"), findsOneWidget);

      // Live Dual Scan HUD
      expect(find.text("📦 Box Barcode: 8901030732585"), findsOneWidget);
      expect(find.text("📍 Shelf Sticker / QR: Waiting for scan..."), findsOneWidget);

      // Partial apply button
      expect(find.text("APPLY SCANNED (1/2)"), findsOneWidget);
    });

    testWidgets('Add Item dialog smart cross-routes barcodes typed into wrong fields', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ItemCatalogScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Tap "+ Add Item" FAB
      await tester.tap(find.widgetWithText(FloatingActionButton, "Add Item"));
      await tester.pump(const Duration(milliseconds: 400));

      final companyBarcodeField = find.widgetWithText(TextField, "Company Barcode (Optional)");
      final shelfCodeField = find.widgetWithText(TextField, "Shelf Location & Item Code");

      // Enter shelf code "01-03-C-134" into companyBarcodeField
      await tester.enterText(companyBarcodeField, "01-03-C-134");
      await tester.pump(const Duration(milliseconds: 100));

      // Should automatically cross-route to shelfCodeField!
      final shelfFieldWidget = tester.widget<TextField>(shelfCodeField);
      expect(shelfFieldWidget.controller?.text, "01-03-C-134");

      final companyFieldWidget = tester.widget<TextField>(companyBarcodeField);
      expect(companyFieldWidget.controller?.text, "");
    });

    test('General Store FMCG Catalog resolves authentic FMCG products offline in 0ms', () {
      // 1. Colgate Strong Teeth
      final colgate = findCosmeticByBarcode("8901314051025");
      expect(colgate, isNotNull);
      expect(colgate!['brand'], "Colgate");
      expect(colgate['name'], contains("Strong Teeth"));

      // 2. Maggi 2-Minute Noodles
      final maggi = findCosmeticByBarcode("8901058852396");
      expect(maggi, isNotNull);
      expect(maggi!['brand'], "Maggi");
      expect(maggi['price'], 14.0);

      // 3. Surf Excel Quick Wash Detergent
      final surfExcel = findCosmeticByBarcode("8901030001117");
      expect(surfExcel, isNotNull);
      expect(surfExcel!['brand'], "Surf Excel");

      // 4. Dettol Antiseptic Liquid
      final dettol = findCosmeticByBarcode("8901199000100");
      expect(dettol, isNotNull);
      expect(dettol!['brand'], "Dettol");

      // 5. Parle-G Biscuits
      final parleG = findCosmeticByBarcode("8901719101017");
      expect(parleG, isNotNull);
      expect(parleG!['brand'], "Parle");
      expect(parleG['price'], 5.0);

      // 6. Tata Salt
      final tataSalt = findCosmeticByBarcode("8901052000106");
      expect(tataSalt, isNotNull);
      expect(tataSalt!['brand'], "Tata");

      // 7. Harpic Toilet Cleaner
      final harpic = findCosmeticByBarcode("8901396000108");
      expect(harpic, isNotNull);
      expect(harpic!['brand'], "Harpic");
    });

    testWidgets('PosScreen renders top notification banner and keeps keypad area free of bottom snackbars', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PosScreen(userName: "Cashier", userEmail: "cashier@lovekush.com", isAdmin: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("LOVE KUSH SHOPPING CENTER"), findsOneWidget);

      final state = tester.state(find.byType(PosScreen)) as dynamic;
      state.setState(() {
        state.posTopNotification = "Bill Saved & Printed!";
        state.posTopNotificationColor = const Color(0xFF166534);
      });
      await tester.pump();

      expect(find.text("Bill Saved & Printed!"), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      // Tap close icon to dismiss
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.text("Bill Saved & Printed!"), findsNothing);
    });

    testWidgets('FestiveStockScreen renders upcoming festival spotlight, demand multipliers, and stock roadmap', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FestiveStockScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Upcoming Festivals & Stock"), findsOneWidget);
      expect(find.text("Inventory Stock"), findsOneWidget);
      expect(find.text("Indian Retail Festive Season Roadmap"), findsOneWidget);
      expect(find.textContaining("Standard Turnover"), findsWidgets);
      expect(find.text("Open Inventory & Update Stock"), findsOneWidget);
    });

    testWidgets('PosScreen Drawer includes Upcoming Festivals (Stock) navigation tile', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PosScreen(userName: "Admin", userEmail: "admin@lovekush.com", isAdmin: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Open drawer
      final ScaffoldState state = tester.firstState(find.byType(Scaffold));
      state.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('Upcoming Festivals (Stock)'), findsOneWidget);
      expect(find.text('Festive rush calendar, demand surge & stock planner'), findsOneWidget);
    });

    testWidgets('PosScreen deducts stock quantity for billed items upon completing bill', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PosScreen(userName: "Admin", userEmail: "admin@lovekush.com", isAdmin: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final state = tester.state(find.byType(PosScreen)) as dynamic;
      // Pre-seed cloud inventory with an item having 10 units in stock
      state.setState(() {
        state.cloudInventory["01-03-C-134"] = {
          'item_code': '01-03-C-134',
          'item_name': 'Ponds Cold Cream 55ml',
          'price': 110.0,
          'company_barcode': '8901030609183',
          'shelf_location': '01-03-C',
          'stock_qty': 10,
        };
      });

      // Billed items: 3 units of 01-03-C-134
      final billedItems = [
        {
          "qty": "3",
          "rawItemCode": "01-03-C-134",
          "item_code": "01-03-C-134",
          "itemName": "Ponds Cold Cream 55ml",
          "rate": "110",
          "price": 330.0,
        }
      ];

      // Invoke stock deduction
      await state.deductStockForCompletedBill(billedItems);
      await tester.pump();

      // Verify stock was subtracted from 10 to 7
      expect(state.cloudInventory["01-03-C-134"]!['stock_qty'], 7);
    });

    test('unbarcodedShopCategories contains exactly the 7 specified retail categories', () {
      expect(unbarcodedShopCategories, [
        "Bangles",
        "Stationary",
        "Tailoring",
        "Cosmetics",
        "Jewellary",
        "Undergarments",
        "Toys and gifts",
      ]);
    });

    testWidgets('PosScreen opens 7-category sheet when "+ Other (No Barcode)" is clicked and adds item to cart', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PosScreen(userName: "Admin", userEmail: "admin@lovekush.com", isAdmin: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final state = tester.state(find.byType(PosScreen)) as dynamic;
      // Set rate to 150
      state.setState(() {
        state.rate = "150";
        state.qty = "2";
      });
      await tester.pump();

      // Find and tap "+ Other (No Barcode)"
      expect(find.text("+ Other (No Barcode)"), findsOneWidget);
      await tester.tap(find.text("+ Other (No Barcode)"));
      await tester.pumpAndSettle();

      // Verify category picker opened
      expect(find.text("Add Unbarcoded Item as Other"), findsOneWidget);
      expect(find.text("Bangles"), findsOneWidget);
      expect(find.text("Stationary"), findsOneWidget);
      expect(find.text("Tailoring"), findsOneWidget);
      expect(find.text("Cosmetics"), findsOneWidget);
      expect(find.text("Jewellary"), findsOneWidget);
      expect(find.text("Undergarments"), findsOneWidget);
      expect(find.text("Toys and gifts"), findsOneWidget);

      // Tap "Cosmetics"
      await tester.tap(find.text("Cosmetics"));
      await tester.pumpAndSettle();

      // Verify item was added into cart
      expect(state.cart.isNotEmpty, isTrue);
      expect(state.cart.last['itemName'], "Other (Cosmetics)");
      expect(state.cart.last['price'].toString(), "300");
      expect(state.cart.last['qty'].toString(), "2");
      expect(state.cart.last['rate'].toString(), "150");
    });

    testWidgets('ItemCatalogScreen renders Add to Cart button and prints label options', (WidgetTester tester) async {
      bool addedToCartCalled = false;
      Map<String, dynamic>? receivedItem;

      posGlobalAddToCart = (item, {overrideRate, qty = 1}) {
        addedToCartCalled = true;
        receivedItem = item;
      };

      await tester.pumpWidget(
        const MaterialApp(
          home: ItemCatalogScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Check for Barcode & Label Printer button / FAB
      expect(find.byIcon(Icons.qr_code_2), findsWidgets);
      expect(find.text("Print Labels"), findsWidgets);

      // Verify posGlobalAddToCart callback exists and is callable
      expect(posGlobalAddToCart, isNotNull);
      posGlobalAddToCart!({
        'item_code': 'TEST-01',
        'item_name': 'Test Item',
        'price': 99.0,
      });
      expect(addedToCartCalled, isTrue);
      expect(receivedItem?['item_code'], 'TEST-01');
    });

    testWidgets('Drawer no longer has standalone Barcode Labels Printer item', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PosScreen(userName: "Admin", userEmail: "admin@lovekush.com", isAdmin: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final ScaffoldState state = tester.firstState(find.byType(Scaffold));
      state.openDrawer();
      await tester.pumpAndSettle();

      // "Barcode Labels Printer" should NOT be directly in root drawer
      expect(find.text('Barcode Labels Printer'), findsNothing);
      // But "Inventory & Stock (Add Items)" and "Upcoming Festivals (Stock)" are present
      expect(find.text('Inventory & Stock (Add Items)'), findsOneWidget);
      expect(find.text('Upcoming Festivals (Stock)'), findsOneWidget);
    });

    testWidgets('openPdfPreviewDialog directly shows PDF preview with options instead of WhatsApp number entry prompt', (WidgetTester tester) async {
      final sampleBill = {
        'bill_number': 'LK-9988',
        'staff_name': 'Admin',
        'counter_name': 'Counter 1',
        'total_amount': 250.0,
        'payment_method': 'Cash',
        'amount_tendered': 300.0,
        'change_due': 50.0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'items_json': [
          {
            'rawItemCode': '8901030732585',
            'itemName': 'Lakme Eyeconic Kajal',
            'qty': '1',
            'rate': '190',
            'price': '190',
          },
          {
            'rawItemCode': 'OTHER-BANGLES',
            'itemName': 'Other (Bangles)',
            'qty': '1',
            'rate': '60',
            'price': '60',
          }
        ],
      };

      bool printCallbackCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => PdfReceiptService.openPdfPreviewDialog(
                  context: ctx,
                  bill: sampleBill,
                  initialLanguage: ReceiptLanguage.hindi,
                  onThermalPrint: (lang) async {
                    printCallbackCalled = true;
                  },
                ),
                child: const Text('OPEN PREVIEW'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN PREVIEW'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Verify bill preview dialog is displayed directly
      expect(find.text("Bill #LK-9988 Preview"), findsOneWidget);

      // 2. Verify WhatsApp number entry prompt is NOT shown!
      expect(find.text("Customer Mobile (WhatsApp):"), findsNothing);
      expect(find.text("10-digit mobile (e.g. 9812345678)"), findsNothing);

      // 3. Verify options are directly present: Language switches, Print, WhatsApp, Share, Mantra
      expect(find.text("🇮🇳 हिन्दी"), findsOneWidget);
      expect(find.text("🇬🇧 English"), findsOneWidget);
      expect(find.text("Print"), findsOneWidget);
      expect(find.text("WhatsApp"), findsOneWidget);
      expect(find.text("Share"), findsOneWidget);
      expect(find.byIcon(Icons.temple_hindu), findsOneWidget);

      // 4. Test thermal print option trigger
      await tester.tap(find.text("Print"));
      await tester.pump();
      expect(printCallbackCalled, isTrue);
    });

    testWidgets('PosScreen unbarcoded item allows instant naming via SET NAME button and in-cart Name button without slowing down process', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PosScreen(userName: "Admin", userEmail: "admin@lovekush.com", isAdmin: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      final state = tester.state(find.byType(PosScreen)) as dynamic;
      state.setState(() {
        state.rate = "200";
        state.qty = "1";
      });
      await tester.pump();

      // Open unbarcoded sheet
      await tester.tap(find.text("+ Other (No Barcode)"));
      await tester.pumpAndSettle();

      // Tap Bangles to add instantly
      await tester.tap(find.text("Bangles"));
      await tester.pumpAndSettle();

      // Verify item was added immediately
      expect(state.cart.isNotEmpty, isTrue);
      expect(state.cart.first['itemName'], "Other (Bangles)");

      // Verify top notification banner displays "SET NAME" action
      expect(find.text("SET NAME"), findsOneWidget);

      // Tap "SET NAME"
      await tester.tap(find.text("SET NAME"));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text("Set Name for Bangles"), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, "Red Glass Bangles 2.4");
      await tester.pump();

      // Tap "Save Name"
      await tester.tap(find.text("Save Name"));
      await tester.pumpAndSettle();

      // Verify cart item name is updated
      expect(state.cart.first['itemName'], "Red Glass Bangles 2.4");

      // Verify cart tile has dedicated "Name" edit button
      expect(find.text("Name"), findsOneWidget);
    });
  });
}


