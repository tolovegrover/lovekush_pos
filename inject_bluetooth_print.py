import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# 1. Inject executeBluetoothPrint below confirmPrint
old_confirm = """  void confirmPrint() {
    setState(() {
      cart.clear();
      if (activeBills.length > 1) {
        activeBills.removeAt(currentBillIndex);
        currentBillIndex = currentBillIndex > 0 ? currentBillIndex - 1 : 0;
      }
      rawItemCode = "";
      qty = "1";
      rate = "";
      focusedField = 0;
      isPreviewingBill = false;
    });
  }"""

new_confirm = """  void confirmPrint() {
    setState(() {
      cart.clear();
      if (activeBills.length > 1) {
        activeBills.removeAt(currentBillIndex);
        currentBillIndex = currentBillIndex > 0 ? currentBillIndex - 1 : 0;
      }
      rawItemCode = "";
      qty = "1";
      rate = "";
      focusedField = 0;
      isPreviewingBill = false;
    });
  }

  void executeBluetoothPrint() async {
    if (!_printerConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please connect the printer in the Side Menu!")));
      setState(() => isPreviewingBill = true);
      return;
    }

    try {
      bool? isConnected = await bluetooth.isConnected;
      if (isConnected != true) throw Exception("Lost connection");

      ByteData bytesAsset = await rootBundle.load("assets/logo_bw.jpg");
      Uint8List imageBytes = bytesAsset.buffer.asUint8List();
      await bluetooth.printImageBytes(imageBytes);
      
      await bluetooth.printNewLine();
      await bluetooth.printCustom("LOVE KUSH", 3, 1); 
      await bluetooth.printCustom("SHOPPING CENTER", 2, 1); 
      await bluetooth.printCustom(counterName.toUpperCase(), 1, 1);
      
      await bluetooth.printNewLine();
      await bluetooth.printLeftRight("Item", "Qty x Rate", 1);
      await bluetooth.printCustom("--------------------------------", 1, 1);
      
      for (var item in cart) {
        String name = item["item"].toString();
        if (name.length > 15) name = name.substring(0, 15);
        String details = "${item["qty"]} x \u20B9${item["rate"]}";
        await bluetooth.printLeftRight(name, details, 1);
      }
      
      await bluetooth.printCustom("--------------------------------", 1, 1);
      await bluetooth.printLeftRight("TOTAL", "\u20B9${cartTotal.toStringAsFixed(2)}", 2); 
      await bluetooth.printNewLine();
      
      await bluetooth.printCustom("Thank you for shopping!", 1, 1);
      await bluetooth.printCustom("No Exchange / No Refund", 1, 1);
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.paperCut();

      confirmPrint();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bill Printed Successfully!")));
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Print Error: $e")));
      setState(() => isPreviewingBill = true);
    }
  }"""

content = content.replace(old_confirm, new_confirm)

# 2. Wire the Preview Screen button to executeBluetoothPrint
old_preview_btn = """                      onPressed: confirmPrint, 
                      child: const Text("🖨️ PRINT BILL","""

new_preview_btn = """                      onPressed: executeBluetoothPrint, 
                      child: const Text("🖨️ PRINT BILL","""

content = content.replace(old_preview_btn, new_preview_btn)

# 3. Wire the Main Screen button to executeBluetoothPrint
old_main_btn = """              onTap: () => setState(() => isPreviewingBill = true),
              child: Container("""

new_main_btn = """              onTap: executeBluetoothPrint,
              child: Container("""

content = content.replace(old_main_btn, new_main_btn)

with open("lib/main.dart", "w") as f:
    f.write(content)
