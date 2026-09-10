import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# 1. Imports
imports = """import 'package:app_links/app_links.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';
import 'dart:async';"""
content = content.replace("import 'package:app_links/app_links.dart';\nimport 'dart:async';", imports)

# 2. Add Bluetooth variables to _PosScreenState
old_vars = """  int focusedField = 0; 
  String counterName = "Basement Counter";"""

new_vars = """  int focusedField = 0; 
  String counterName = "Basement Counter";
  
  // Printer Setup
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _printerConnected = false;"""

content = content.replace(old_vars, new_vars)

# 3. Add initBluetooth to initState
old_init = """  void initState() {
    super.initState();
    _loadCounterName();
  }"""

new_init = """  void initState() {
    super.initState();
    _loadCounterName();
    _initBluetooth();
  }

  void _initBluetooth() async {
    try {
      List<BluetoothDevice> devices = await bluetooth.getBluetooths ?? [];
      setState(() => _devices = devices);
    } catch (e) {
      print("Bluetooth Error: $e");
    }
    
    bluetooth.onStateChanged().listen((state) {
      switch (state) {
        case BlueThermalPrinter.CONNECTED:
          setState(() => _printerConnected = true);
          break;
        case BlueThermalPrinter.DISCONNECTED:
        case BlueThermalPrinter.DISCONNECT_REQUESTED:
        case BlueThermalPrinter.STATE_OFF:
        case BlueThermalPrinter.ERROR:
          setState(() => _printerConnected = false);
          break;
        default:
          break;
      }
    });
  }

  void _showPrinterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("Connect Receipt Printer"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_devices.isEmpty) const Text("No paired Bluetooth devices found. Please pair your printer in Android Settings first."),
                if (_devices.isNotEmpty) DropdownButton<BluetoothDevice>(
                  hint: const Text("Select Printer"),
                  value: _selectedDevice,
                  isExpanded: true,
                  items: _devices.map((device) => DropdownMenuItem(
                    value: device,
                    child: Text(device.name ?? "Unknown Device"),
                  )).toList(),
                  onChanged: (device) {
                    setDialogState(() => _selectedDevice = device);
                    setState(() => _selectedDevice = device);
                  },
                ),
                const SizedBox(height: 16),
                if (_printerConnected) const Text("🟢 Connected", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                if (!_printerConnected && _selectedDevice != null) const Text("🔴 Disconnected", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE")),
              if (!_printerConnected) ElevatedButton(
                onPressed: _selectedDevice == null ? null : () async {
                  try {
                    await bluetooth.connect(_selectedDevice!);
                    setDialogState(() {});
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to connect: $e")));
                  }
                },
                child: const Text("CONNECT"),
              ),
              if (_printerConnected) ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  await bluetooth.disconnect();
                  setDialogState(() {});
                },
                child: const Text("DISCONNECT", style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        }
      ),
    );
  }"""

content = content.replace(old_init, new_init)

# 4. Add Printer Setup to Drawer
old_drawer = """            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Generate QR Labels'),"""

new_drawer = """            ListTile(
              leading: Icon(Icons.print, color: _printerConnected ? Colors.green : Colors.black54),
              title: Text(_printerConnected ? 'Printer Connected' : 'Connect Printer'),
              onTap: () {
                Navigator.pop(context);
                _showPrinterDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Generate QR Labels'),"""

content = content.replace(old_drawer, new_drawer)

# 5. Inject a real Print function that uses the thermal printer!
# Replace the empty generateAndPrintBill() with the real one
old_print = """  void generateAndPrintBill() {
    setState(() {
      isPreviewingBill = true;
    });
  }"""

new_print = """  void generateAndPrintBill() async {
    if (!_printerConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please connect the printer first!")));
      setState(() => isPreviewingBill = true);
      return;
    }

    try {
      bool? isConnected = await bluetooth.isConnected;
      if (isConnected != true) throw Exception("Lost connection");

      // Print Logo (Load from assets)
      ByteData bytesAsset = await rootBundle.load("assets/logo_bw.jpg");
      Uint8List imageBytes = bytesAsset.buffer.asUint8List();
      await bluetooth.printImageBytes(imageBytes);
      
      await bluetooth.printNewLine();
      await bluetooth.printCustom("LOVE KUSH", 3, 1); // Size 3, Center
      await bluetooth.printCustom("SHOPPING CENTER", 2, 1); // Size 2, Center
      await bluetooth.printCustom(counterName.toUpperCase(), 1, 1);
      
      await bluetooth.printNewLine();
      await bluetooth.printLeftRight("Item", "Qty x Rate", 1);
      await bluetooth.printCustom("--------------------------------", 1, 1);
      
      for (var item in currentCart) {
        String name = item["item"].toString();
        if (name.length > 15) name = name.substring(0, 15); // limit length
        String details = "${item["qty"]} x \u20B9${item["rate"]}";
        await bluetooth.printLeftRight(name, details, 1);
      }
      
      await bluetooth.printCustom("--------------------------------", 1, 1);
      await bluetooth.printLeftRight("TOTAL", "\u20B9$cartTotal", 2); // Size 2, Bold
      await bluetooth.printNewLine();
      
      await bluetooth.printCustom("Thank you for shopping!", 1, 1);
      await bluetooth.printCustom("No Exchange / No Refund", 1, 1);
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.paperCut();

      // Clear cart and go back
      setState(() {
        currentCart.clear();
        calculateTotal();
        focusedField = 0;
        isPreviewingBill = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bill Printed Successfully!")));
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Print Error: $e")));
      setState(() => isPreviewingBill = true);
    }
  }"""

content = content.replace(old_print, new_print)

with open("lib/main.dart", "w") as f:
    f.write(content)
