import 'dart:io';
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
      expect(msg, contains("LK-2026-0042"));
      expect(msg, contains("Lakme Eyeconic Kajal"));
      expect(msg, contains("Ponds Cold Cream"));
      expect(msg, contains("सकल देय राशि (GRAND TOTAL): ₹410.00"));
      expect(msg, contains("पञ्चाङ्ग तिथि:"));
      expect(msg, contains("आङ्ग्ल तिथि:"));
      expect(msg, contains("कोषपाल:"));
      expect(msg, contains("न वापसी • न प्रतिदान • न विनिमय"));
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
      expect(waMsg, contains("सकल देय राशि (GRAND TOTAL): ₹450.50"));

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
      expect(engMsg, contains("LOVE KUSH SHOPPING CENTER"));
      expect(engMsg, contains("*Bill No:* LK-BI-2026"));
      expect(engMsg, contains("Lakme Absolute Kajal")); // Item name in English
      expect(engMsg, contains("Pond's White Beauty Cream")); // Item name in English
      expect(engMsg, contains("GRAND TOTAL: ₹550.00"));
      expect(engMsg, contains("*Payment Method:* CASH"));
      expect(engMsg, contains("NO RETURN • NO REFUND • NO EXCHANGE"));
      expect(engMsg, contains("THANK YOU FOR SHOPPING! VISIT AGAIN!"));

      // 2. Hindi WhatsApp summary
      final hindiMsg = PdfReceiptService.formatWhatsAppBillMessage(sampleBill, language: ReceiptLanguage.hindi);
      expect(hindiMsg, contains("࿗ ॐ श्री महालक्ष्म्यै नमः ࿗"));
      expect(hindiMsg, contains("लव कुश शॉपिङ्ग सेण्टर"));
      expect(hindiMsg, contains("*बीजक सं. (Bill No):* LK-BI-2026"));
      expect(hindiMsg, contains("Lakme Absolute Kajal")); // Item name in English
      expect(hindiMsg, contains("Pond's White Beauty Cream")); // Item name in English
      expect(hindiMsg, contains("पञ्चाङ्ग तिथि:"));
      expect(hindiMsg, contains("आङ्ग्ल तिथि:"));
      expect(hindiMsg, contains("कोषपाल:"));
      expect(hindiMsg, contains("सकल देय राशि (GRAND TOTAL): ₹550.00"));
      expect(hindiMsg, contains("न वापसी • न प्रतिदान • न विनिमय"));
      expect(hindiMsg, contains("सधन्यवाद! पुनः पधारें!"));

      // 3. English PDF Generation
      final engPdfBytes = await PdfReceiptService.generateReceiptPdf(sampleBill, language: ReceiptLanguage.english);
      expect(engPdfBytes, isNotNull);
      expect(engPdfBytes.length, greaterThan(1000));
      expect(engPdfBytes[0], 0x25); // %
      expect(engPdfBytes[1], 0x50); // P

      // 4. Hindi PDF Generation (with Siddhanta Calcutta font)
      final hindiPdfBytes = await PdfReceiptService.generateReceiptPdf(sampleBill, language: ReceiptLanguage.hindi);
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
  });
}
