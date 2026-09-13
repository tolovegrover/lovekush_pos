import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pdf_receipt_service.dart';
import 'size_variant_service.dart';

/// Service providing comprehensive Bill Editing, Cancellation (Voiding),
/// Stock Reconciliation, and Audit History Tracking for Love Kush POS.
class BillManagementService {
  /// Extract only genuine product line items (filtering out internal metadata objects)
  static List<Map<String, dynamic>> extractItems(dynamic rawItemsJson) {
    List<dynamic> list = [];
    if (rawItemsJson is List) {
      list = rawItemsJson;
    } else if (rawItemsJson is String && rawItemsJson.isNotEmpty) {
      try {
        final decoded = json.decode(rawItemsJson);
        if (decoded is List) list = decoded;
      } catch (_) {}
    }

    final result = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        if (m['_is_meta'] == true) continue; // Skip audit metadata
        result.add(m);
      }
    }
    return result;
  }

  /// Extract internal metadata map containing edit history and cancellation info
  static Map<String, dynamic>? extractMeta(dynamic rawItemsJson) {
    List<dynamic> list = [];
    if (rawItemsJson is List) {
      list = rawItemsJson;
    } else if (rawItemsJson is String && rawItemsJson.isNotEmpty) {
      try {
        final decoded = json.decode(rawItemsJson);
        if (decoded is List) list = decoded;
      } catch (_) {}
    }

    for (final e in list) {
      if (e is Map && e['_is_meta'] == true) {
        return Map<String, dynamic>.from(e);
      }
    }
    return null;
  }

  /// Returns true if the bill has been cancelled / voided
  static bool isCancelled(Map<String, dynamic> bill) {
    final pm = (bill['payment_method'] ?? '').toString().toUpperCase();
    if (pm.startsWith('CANCELLED') || pm.startsWith('VOID')) return true;
    final meta = extractMeta(bill['items_json']);
    return meta != null && (meta['status'] == 'cancelled' || meta['is_cancelled'] == true);
  }

  /// Returns true if the bill has one or more recorded edits
  static bool isEdited(Map<String, dynamic> bill) {
    return getEditHistory(bill).isNotEmpty;
  }

  /// Returns all edit history entries for this bill
  static List<Map<String, dynamic>> getEditHistory(Map<String, dynamic> bill) {
    final meta = extractMeta(bill['items_json']);
    if (meta == null) return [];
    final history = meta['edit_history'];
    if (history is List) {
      return history.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  /// Returns cancellation metadata details if available
  static Map<String, dynamic>? getCancellationInfo(Map<String, dynamic> bill) {
    final meta = extractMeta(bill['items_json']);
    if (meta != null && (meta['status'] == 'cancelled' || meta['is_cancelled'] == true)) {
      return meta;
    }
    final pm = (bill['payment_method'] ?? '').toString();
    if (pm.toUpperCase().startsWith('CANCELLED')) {
      return {
        'status': 'cancelled',
        'cancellation_reason': pm,
        'cancelled_at': bill['created_at'],
        'cancelled_by': bill['staff_name'] ?? 'Staff',
      };
    }
    return null;
  }

  /// Reconcile inventory stock: restore items if deleted/reduced, deduct if added/increased
  static Future<void> reconcileStock({
    required List<Map<String, dynamic>> oldItems,
    required List<Map<String, dynamic>> newItems,
    Map<String, Map<String, dynamic>>? inMemoryInventory,
  }) async {
    // Map of code -> net quantity difference (newQty - oldQty)
    final Map<String, int> netDeltas = {};

    for (final it in oldItems) {
      final code = (it['rawItemCode'] ?? it['item_code'] ?? '').toString().trim();
      final qty = int.tryParse(it['qty']?.toString() ?? '1') ?? 1;
      if (code.isNotEmpty) {
        netDeltas[code] = (netDeltas[code] ?? 0) - qty;
      }
    }

    for (final it in newItems) {
      final code = (it['rawItemCode'] ?? it['item_code'] ?? '').toString().trim();
      final qty = int.tryParse(it['qty']?.toString() ?? '1') ?? 1;
      if (code.isNotEmpty) {
        netDeltas[code] = (netDeltas[code] ?? 0) + qty;
      }
    }

    // Apply net deltas: delta > 0 means sold more (deduct), delta < 0 means returned (restore)
    for (final entry in netDeltas.entries) {
      final code = entry.key;
      final delta = entry.value;
      if (delta == 0) continue;

      try {
        final res = await Supabase.instance.client
            .from('inventory')
            .select('item_code, stock_qty')
            .or('item_code.eq.$code,company_barcode.eq.$code')
            .maybeSingle();

        if (res != null) {
          final dbCode = res['item_code'].toString();
          int cur = (res['stock_qty'] as num?)?.toInt() ?? 10;
          // delta > 0 means sold more -> subtract delta; delta < 0 means returned -> add -delta
          int next = cur - delta;
          if (next < 0) next = 0;

          await Supabase.instance.client
              .from('inventory')
              .update({'stock_qty': next})
              .eq('item_code', dbCode);

          if (inMemoryInventory != null && inMemoryInventory.containsKey(dbCode)) {
            inMemoryInventory[dbCode]!['stock_qty'] = next;
          }
        }
      } catch (e) {
        debugPrint("Error reconciling stock for $code: $e");
      }
    }
  }

  /// Restore all sold quantities back into inventory when a bill is cancelled
  static Future<void> restoreAllStock({
    required List<Map<String, dynamic>> items,
    Map<String, Map<String, dynamic>>? inMemoryInventory,
  }) async {
    for (final it in items) {
      final code = (it['rawItemCode'] ?? it['item_code'] ?? '').toString().trim();
      final qty = int.tryParse(it['qty']?.toString() ?? '1') ?? 1;
      if (code.isEmpty || qty <= 0) continue;

      try {
        final res = await Supabase.instance.client
            .from('inventory')
            .select('item_code, stock_qty')
            .or('item_code.eq.$code,company_barcode.eq.$code')
            .maybeSingle();

        if (res != null) {
          final dbCode = res['item_code'].toString();
          int cur = (res['stock_qty'] as num?)?.toInt() ?? 10;
          int next = cur + qty;

          await Supabase.instance.client
              .from('inventory')
              .update({'stock_qty': next})
              .eq('item_code', dbCode);

          if (inMemoryInventory != null && inMemoryInventory.containsKey(dbCode)) {
            inMemoryInventory[dbCode]!['stock_qty'] = next;
          }
        }
      } catch (e) {
        debugPrint("Error restoring stock for $code: $e");
      }
    }
  }

  /// Cancel / Void a bill in Supabase and update local map
  static Future<bool> executeCancellation({
    required Map<String, dynamic> bill,
    required String reason,
    required String userName,
    Map<String, Map<String, dynamic>>? inMemoryInventory,
  }) async {
    final billId = bill['id'];
    if (billId == null) return false;

    final genuineItems = extractItems(bill['items_json']);
    final currentMeta = extractMeta(bill['items_json']) ?? {};
    final originalPayment = (bill['payment_method'] ?? 'Cash').toString();

    // 1. Restore stock in inventory
    await restoreAllStock(items: genuineItems, inMemoryInventory: inMemoryInventory);

    // 2. Prepare cancellation metadata
    currentMeta['_is_meta'] = true;
    currentMeta['status'] = 'cancelled';
    currentMeta['is_cancelled'] = true;
    currentMeta['cancelled_at'] = DateTime.now().toUtc().toIso8601String();
    currentMeta['cancelled_by'] = userName;
    currentMeta['cancellation_reason'] = reason;
    currentMeta['original_payment_method'] = originalPayment;

    final updatedItemsJson = [...genuineItems, currentMeta];
    final cleanReason = reason.replaceAll('[', '(').replaceAll(']', ')').trim();
    final newPaymentMethod = "CANCELLED [$cleanReason | By: $userName]";

    // 3. Update Supabase
    try {
      await Supabase.instance.client.from('bills').update({
        'payment_method': newPaymentMethod,
        'items_json': updatedItemsJson,
      }).eq('id', billId);

      // Mutate local bill object
      bill['payment_method'] = newPaymentMethod;
      bill['items_json'] = updatedItemsJson;
      return true;
    } catch (e) {
      debugPrint("Supabase error cancelling bill: $e");
      return false;
    }
  }

  /// Show Dialog to confirm and cancel a bill
  static Future<bool> showCancelBillDialog(
    BuildContext context, {
    required Map<String, dynamic> bill,
    required String userName,
    Map<String, Map<String, dynamic>>? inMemoryInventory,
    VoidCallback? onCancelled,
  }) async {
    if (isCancelled(bill)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This bill is already cancelled.")),
      );
      return false;
    }

    final billNo = (bill['bill_number'] ?? 'N/A').toString();
    final rawTotal = bill['total_amount'];
    final double total = rawTotal is num ? rawTotal.toDouble() : (double.tryParse(rawTotal?.toString() ?? '0') ?? 0.0);
    final items = extractItems(bill['items_json']);

    final reasonCtrl = TextEditingController(text: "Customer returned items");
    String selectedChip = "Customer returned items";

    final reasonsList = [
      "Customer returned items",
      "Billing error / Duplicate bill",
      "Customer walked out / Cancelled",
      "Payment failed / Cancelled",
      "Other reason",
    ];

    bool isSubmitting = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => StatefulBuilder(
        builder: (ctx, setDState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.cancel_outlined, color: Colors.red, size: 24),
                SizedBox(width: 8),
                Text("Cancel / Void Bill", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.red)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Bill #$billNo • ₹${total % 1 == 0 ? total.toInt() : total.toStringAsFixed(2)}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF991B1B)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "Items: ${items.length} units • Staff: ${bill['staff_name'] ?? userName}",
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFF991B1B)),
                            SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                "Cancelling will restore inventory stock for all items and subtract ₹ from daily sales collection.",
                                style: TextStyle(fontSize: 11, color: Color(0xFF7F1D1D), height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text("Select Reason for Cancellation:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: reasonsList.map((r) {
                      final isSel = selectedChip == r;
                      return ChoiceChip(
                        label: Text(r, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : Colors.black87)),
                        selected: isSel,
                        selectedColor: Colors.red.shade700,
                        backgroundColor: Colors.grey.shade100,
                        onSelected: (val) {
                          if (val) {
                            setDState(() {
                              selectedChip = r;
                              if (r != "Other reason") {
                                reasonCtrl.text = r;
                              } else {
                                reasonCtrl.clear();
                              }
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: "Enter specific cancellation explanation...",
                      labelText: "Cancellation Reason (Required)",
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dCtx, false),
                child: const Text("Keep Bill"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                onPressed: isSubmitting
                    ? null
                    : () async {
                        final reason = reasonCtrl.text.trim();
                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Please enter a reason for cancellation")),
                          );
                          return;
                        }

                        setDState(() => isSubmitting = true);
                        final ok = await executeCancellation(
                          bill: bill,
                          reason: reason,
                          userName: userName,
                          inMemoryInventory: inMemoryInventory,
                        );
                        setDState(() => isSubmitting = false);

                        if (context.mounted) {
                          Navigator.pop(dCtx, ok);
                        }
                      },
                child: isSubmitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text("Confirm Cancellation", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Bill #$billNo has been cancelled. Stock restored."),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
      if (onCancelled != null) onCancelled();
      return true;
    }
    return false;
  }

  /// Show Full-Screen / Modal Dialog to Edit an Existing Bill
  static Future<bool> showEditBillDialog(
    BuildContext context, {
    required Map<String, dynamic> bill,
    required String userName,
    Map<String, Map<String, dynamic>>? inMemoryInventory,
    VoidCallback? onUpdated,
  }) async {
    if (isCancelled(bill)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot edit a cancelled bill.")),
      );
      return false;
    }

    final billNo = (bill['bill_number'] ?? 'N/A').toString();
    final rawOriginalTotal = bill['total_amount'];
    final double originalTotal = rawOriginalTotal is num
        ? rawOriginalTotal.toDouble()
        : (double.tryParse(rawOriginalTotal?.toString() ?? '0') ?? 0.0);

    final originalItems = extractItems(bill['items_json']);
    final currentMeta = extractMeta(bill['items_json']) ?? {};
    final existingHistory = getEditHistory(bill);

    // Deep copy items to mutable edit list
    List<Map<String, dynamic>> editableItems = originalItems
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    String paymentMethod = (bill['payment_method'] ?? 'Cash').toString();
    if (paymentMethod.startsWith('Hybrid')) {
      paymentMethod = 'Hybrid';
    } else if (paymentMethod.toLowerCase().contains('online') || paymentMethod.toLowerCase().contains('upi')) {
      paymentMethod = 'Online';
    } else {
      paymentMethod = 'Cash';
    }

    final reasonCtrl = TextEditingController();
    final reasonPresets = [
      "Customer returned 1 item",
      "Rate correction",
      "Item exchange",
      "Added extra item",
      "Payment mode corrected",
    ];

    bool isSubmitting = false;

    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (ctx, setBState) {
          // Calculate running total
          double computedTotal = 0.0;
          for (final it in editableItems) {
            final qty = double.tryParse(it['qty']?.toString() ?? '1') ?? 1.0;
            final rate = double.tryParse(it['rate']?.toString() ?? '0') ?? 0.0;
            computedTotal += (qty * rate);
          }

          final diff = computedTotal - originalTotal;

          return Container(
            height: MediaQuery.of(context).size.height * 0.90,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Drag Handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                ),

                // Sheet Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.edit_note, color: Color(0xFF2563EB), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Edit Bill #$billNo", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text("Original Total: ₹${originalTotal % 1 == 0 ? originalTotal.toInt() : originalTotal.toStringAsFixed(2)} • ${originalItems.length} items",
                                style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(bCtx, false),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Comparison Banner
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: diff == 0
                      ? Colors.grey.shade50
                      : (diff < 0 ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB)),
                  child: Row(
                    children: [
                      Text(
                        "New Total: ₹${computedTotal % 1 == 0 ? computedTotal.toInt() : computedTotal.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: diff < 0 ? const Color(0xFF047857) : (diff > 0 ? const Color(0xFFB45309) : Colors.black87),
                        ),
                      ),
                      const Spacer(),
                      if (diff != 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: diff < 0 ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            diff < 0
                                ? "Refund Due: ₹${(-diff) % 1 == 0 ? (-diff).toInt() : (-diff).toStringAsFixed(2)}"
                                : "Collect Extra: ₹${diff % 1 == 0 ? diff.toInt() : diff.toStringAsFixed(2)}",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: diff < 0 ? const Color(0xFF065F46) : const Color(0xFF92400E),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Editable Items List
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: editableItems.length,
                    separatorBuilder: (_, index) => const Divider(height: 16),
                    itemBuilder: (ctx, idx) {
                      final it = editableItems[idx];
                      final name = (it['itemName'] ?? it['item'] ?? 'Item').toString().split('\n').first.trim();
                      final qty = int.tryParse(it['qty']?.toString() ?? '1') ?? 1;
                      final rate = double.tryParse(it['rate']?.toString() ?? '0') ?? 0.0;
                      final lineTotal = qty * rate;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Item Name & Rate
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                const SizedBox(height: 2),
                                Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    InkWell(
                                      onTap: () => _promptEditItemRate(context, it, setBState),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            "₹${rate % 1 == 0 ? rate.toInt() : rate.toStringAsFixed(2)} / unit",
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(width: 4),
                                          const Icon(Icons.edit, size: 12, color: Color(0xFF2563EB)),
                                        ],
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () async {
                                        final selected = await SizeVariantService.showSizeSelectorModal(
                                          context,
                                          itemName: name,
                                          currentRate: rate,
                                          inMemoryInventory: inMemoryInventory,
                                        );
                                        if (selected != null) {
                                          setBState(() {
                                            it['rate'] = selected.rate % 1 == 0 ? selected.rate.toInt().toString() : selected.rate.toString();
                                            final newName = selected.fullName ?? SizeVariantService.formatItemWithSize(name, selected.sizeLabel);
                                            it['item'] = newName;
                                            it['itemName'] = newName;
                                            it['price'] = (qty * selected.rate).round().toString();
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3E8FF),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFFD8B4FE)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.straighten, size: 10, color: Color(0xFF7E22CE)),
                                            const SizedBox(width: 2),
                                            Text(
                                              SizeVariantService.extractSizeLabel(name) ?? "Size",
                                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7E22CE)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Quantity Adjuster (- [qty] +)
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InkWell(
                                  onTap: () {
                                    if (qty > 1) {
                                      setBState(() {
                                        it['qty'] = (qty - 1).toString();
                                        it['price'] = ((qty - 1) * rate).round().toString();
                                      });
                                    }
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Icon(Icons.remove, size: 14),
                                  ),
                                ),
                                Text("$qty", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                InkWell(
                                  onTap: () {
                                    setBState(() {
                                      it['qty'] = (qty + 1).toString();
                                      it['price'] = ((qty + 1) * rate).round().toString();
                                    });
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    child: Icon(Icons.add, size: 14),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 12),
                          // Line Total
                          SizedBox(
                            width: 60,
                            child: Text(
                              "₹${lineTotal % 1 == 0 ? lineTotal.toInt() : lineTotal.toStringAsFixed(0)}",
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),

                          // Delete Item
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            onPressed: () {
                              if (editableItems.length <= 1) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("A bill must contain at least 1 item. Cancel the bill instead.")),
                                );
                                return;
                              }
                              setBState(() {
                                editableItems.removeAt(idx);
                              });
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // Add Item Toolbar & Reason
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    border: Border(top: BorderSide(color: Colors.grey.shade200)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text("Add Item to Bill", style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                            onPressed: () => _promptAddNewItem(context, editableItems, setBState),
                          ),
                          const Spacer(),
                          // Payment mode selector
                          DropdownButton<String>(
                            value: paymentMethod,
                            underline: const SizedBox(),
                            isDense: true,
                            items: const [
                              DropdownMenuItem(value: 'Cash', child: Text("Cash", style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'Online', child: Text("Online (UPI)", style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'Hybrid', child: Text("Hybrid", style: TextStyle(fontSize: 12))),
                            ],
                            onChanged: (val) {
                              if (val != null) setBState(() => paymentMethod = val);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Reason Presets
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: reasonPresets.map((r) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text(r, style: const TextStyle(fontSize: 10)),
                                padding: EdgeInsets.zero,
                                onPressed: () => reasonCtrl.text = r,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: reasonCtrl,
                        decoration: const InputDecoration(
                          hintText: "Reason for edit (Required for audit history)...",
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),

                // Save Changes Button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                      label: Text(
                        "Save Changes (New Total: ₹${computedTotal % 1 == 0 ? computedTotal.toInt() : computedTotal.toStringAsFixed(2)})",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final reason = reasonCtrl.text.trim();
                              if (reason.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Please enter a reason for this edit (audit history)")),
                                );
                                return;
                              }

                              setBState(() => isSubmitting = true);

                              // 1. Reconcile stock differences
                              await reconcileStock(
                                oldItems: originalItems,
                                newItems: editableItems,
                                inMemoryInventory: inMemoryInventory,
                              );

                              // 2. Build audit log record
                              final editEntry = {
                                'edited_at': DateTime.now().toUtc().toIso8601String(),
                                'edited_by': userName,
                                'reason': reason,
                                'old_total': originalTotal,
                                'new_total': computedTotal,
                                'old_payment_method': bill['payment_method'],
                                'new_payment_method': paymentMethod,
                                'old_items_count': originalItems.length,
                                'new_items_count': editableItems.length,
                              };

                              final List<dynamic> updatedHistory = List.from(existingHistory)..add(editEntry);
                              currentMeta['_is_meta'] = true;
                              currentMeta['edit_history'] = updatedHistory;
                              currentMeta['last_edited_at'] = DateTime.now().toUtc().toIso8601String();
                              currentMeta['last_edited_by'] = userName;

                              final updatedItemsJson = [...editableItems, currentMeta];

                              // 3. Update Supabase
                              try {
                                await Supabase.instance.client.from('bills').update({
                                  'total_amount': computedTotal,
                                  'items_json': updatedItemsJson,
                                  'payment_method': paymentMethod,
                                  'amount_tendered': computedTotal,
                                  'change_due': 0.0,
                                }).eq('id', bill['id']);

                                // Update in-memory bill object
                                bill['total_amount'] = computedTotal;
                                bill['items_json'] = updatedItemsJson;
                                bill['payment_method'] = paymentMethod;
                                bill['amount_tendered'] = computedTotal;
                                bill['change_due'] = 0.0;

                                setBState(() => isSubmitting = false);
                                if (context.mounted) Navigator.pop(bCtx, true);
                              } catch (e) {
                                setBState(() => isSubmitting = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Failed to update bill: $e")),
                                  );
                                }
                              }
                            },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (updated == true) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Bill #$billNo successfully updated!"),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
      if (onUpdated != null) onUpdated();
      return true;
    }
    return false;
  }

  static void _promptEditItemRate(BuildContext context, Map<String, dynamic> item, StateSetter setBState) {
    final rateCtrl = TextEditingController(text: item['rate']?.toString() ?? '0');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Edit Rate: ${item['itemName'] ?? item['item'] ?? 'Item'}"),
        content: TextField(
          controller: rateCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: "Price / Rate (₹)", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final newRate = double.tryParse(rateCtrl.text.trim());
              if (newRate != null && newRate >= 0) {
                setBState(() {
                  item['rate'] = newRate % 1 == 0 ? newRate.toInt().toString() : newRate.toString();
                  final qty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
                  item['price'] = (qty * newRate).round().toString();
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  static void _promptAddNewItem(BuildContext context, List<Map<String, dynamic>> items, StateSetter setBState) {
    final nameCtrl = TextEditingController();
    final rateCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: "1");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Add Item to Bill"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Item Name", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Qty", border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: rateCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Rate (₹)", border: OutlineInputBorder()))),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
              final rate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
              if (name.isNotEmpty && rate > 0) {
                setBState(() {
                  items.add({
                    'itemName': name,
                    'item': name,
                    'rawItemCode': 'OTHER-ITEM',
                    'item_code': 'OTHER-ITEM',
                    'qty': qty.toString(),
                    'rate': rate % 1 == 0 ? rate.toInt().toString() : rate.toString(),
                    'price': (qty * rate).round().toString(),
                  });
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  /// Show Full Audit Timeline History Dialog for a Bill
  static void showBillHistoryDialog(BuildContext context, {required Map<String, dynamic> bill}) {
    final billNo = (bill['bill_number'] ?? 'N/A').toString();
    final history = getEditHistory(bill);
    final isCanc = isCancelled(bill);
    final cancInfo = getCancellationInfo(bill);

    final createdAt = PdfReceiptService.parseIndianStandardTime(bill['created_at']);
    final createdDateStr =
        "${createdAt.day.toString().padLeft(2, '0')}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}";

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.history, color: Color(0xFF2563EB)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Bill #$billNo Audit History",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Initial Creation Event
                _buildTimelineTile(
                  icon: Icons.check_circle,
                  iconColor: Colors.green,
                  title: "Bill Created",
                  timeStr: createdDateStr,
                  subtitle: "Staff: ${bill['staff_name'] ?? 'Staff'} • Counter: ${bill['counter_name'] ?? 'Counter'}\nAmount: ₹${bill['total_amount']} (${bill['payment_method']})",
                ),

                // 2. Edit Events
                if (history.isNotEmpty) ...[
                  for (int i = 0; i < history.length; i++) ...[
                    const Divider(indent: 20),
                    () {
                      final e = history[i];
                      final dt = PdfReceiptService.parseIndianStandardTime(e['edited_at']);
                      final timeStr =
                          "${dt.day.toString().padLeft(2, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";

                      return _buildTimelineTile(
                        icon: Icons.edit_note,
                        iconColor: Colors.amber.shade800,
                        title: "Edit #${i + 1} by ${e['edited_by'] ?? 'Staff'}",
                        timeStr: timeStr,
                        subtitle: "Reason: \"${e['reason'] ?? 'N/A'}\"\nTotal Changed: ₹${e['old_total']} → ₹${e['new_total']}\nItems: ${e['old_items_count']} → ${e['new_items_count']}",
                      );
                    }(),
                  ],
                ],

                // 3. Cancellation Event
                if (isCanc) ...[
                  const Divider(indent: 20),
                  () {
                    DateTime cDt = createdAt;
                    if (cancInfo != null && cancInfo['cancelled_at'] != null) {
                      cDt = PdfReceiptService.parseIndianStandardTime(cancInfo['cancelled_at']);
                    }
                    final timeStr =
                        "${cDt.day.toString().padLeft(2, '0')}-${cDt.month.toString().padLeft(2, '0')}-${cDt.year} ${cDt.hour.toString().padLeft(2, '0')}:${cDt.minute.toString().padLeft(2, '0')}";

                    return _buildTimelineTile(
                      icon: Icons.cancel,
                      iconColor: Colors.red,
                      title: "Bill Cancelled / Voided",
                      timeStr: timeStr,
                      subtitle: "Cancelled by: ${cancInfo?['cancelled_by'] ?? 'Staff'}\nReason: \"${cancInfo?['cancellation_reason'] ?? 'Customer cancellation'}\"\nInventory stock restored.",
                    );
                  }(),
                ],

                if (history.isEmpty && !isCanc) ...[
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      "No edits made. Bill is in original state.",
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
        ],
      ),
    );
  }

  static Widget _buildTimelineTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String timeStr,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: iconColor.withValues(alpha: 0.12),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                  Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.black45)),
                ],
              ),
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }
}
