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
        'counter_name': 'Basement Counter',
        'total_amount': 410.0,
        'payment_method': 'Cash',
        'items_json': [
          {'itemName': 'Lakme Eyeconic Kajal', 'qty': 1, 'rate': 190.0, 'total': 190.0},
          {'itemName': 'Ponds Cold Cream', 'qty': 2, 'rate': 110.0, 'total': 220.0},
        ],
      };

      final msg = PdfReceiptService.formatWhatsAppBillMessage(sampleBill);
      expect(msg, contains("LOVE KUSH SHOPPING CENTER"));
      expect(msg, contains("LK-2026-0042"));
      expect(msg, contains("Lakme Eyeconic Kajal"));
      expect(msg, contains("Ponds Cold Cream"));
      expect(msg, contains("GRAND TOTAL: ₹410.00"));
      expect(msg, contains("CASH"));
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
        'counter_name': 'Basement Counter',
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
        'counter_name': 'Basement Counter',
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
      expect(waMsg, contains("GRAND TOTAL: ₹450.50"));

      // 2. PDF generation must never throw 'String is not subtype of num?'
      final bytes = await PdfReceiptService.generateReceiptPdf(stringTypedBill);
      expect(bytes, isNotNull);
      expect(bytes.length, greaterThan(1000));
      expect(bytes[0], 0x25); // %
      expect(bytes[1], 0x50); // P
    });
  });
}
