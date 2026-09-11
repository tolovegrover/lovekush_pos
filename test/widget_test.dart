import 'package:flutter_test/flutter_test.dart';
import 'package:lovekush_pos/main.dart';
import 'package:lovekush_pos/cosmetics_catalog.dart';

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
  });
}
