import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); } catch (e) { print(e); }

  runApp(const PosApp());
}

// ==========================================
// MOCK DATABASE (For DartPad Prototype)
// ==========================================
final List<String> adminEmails = [
  "tolovegrover@gmail.com",
  "sanjeetagrover@gmail.com",
  "nishaankit60@gmail.com"
];
List<String> allowedStaffEmails = ["staff@demo.com"];

class PosApp extends StatelessWidget {
  const PosApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Love Kush Shopping Center',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(0xFFF9FAFB), 
        fontFamily: 'Roboto',
      ),
      home: const LoginScreen(), 
    );
  }
}

// ==========================================
// LOGIN SCREEN (Real Firebase Magic Link Auth)
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool isPhoneMode = false;
  String _verificationId = "";
  final TextEditingController _otpController = TextEditingController();
  
  final Map<String, Map<String, dynamic>> phoneAuth = {
    "8800452769": {"name": "Love Kush", "email": "tolovegrover@gmail.com", "isAdmin": true},
    "8130550842": {"name": "Sanjeeta", "email": "sanjeetagrover@gmail.com", "isAdmin": true},
    "9716839756": {"name": "Ved Prakash", "email": "vedprakash@demo.com", "isAdmin": true},
    "9205809074": {"name": "Nisha", "email": "nishaankit60@gmail.com", "isAdmin": true},
  };
  final TextEditingController _nameController = TextEditingController();
  
  bool isLinkSent = false;
  String submittedEmail = "";
  bool isAdmin = false;
  
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
    _initDeepLinks();
  }

  void _checkExistingLogin() async {
    final prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    if (isLoggedIn && mounted) {
      String userName = prefs.getString('userName') ?? "Staff";
      String userEmail = prefs.getString('userEmail') ?? "";
      bool isAdmin = prefs.getBool('isAdmin') ?? false;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PosScreen(userName: userName, userEmail: userEmail, isAdmin: isAdmin)));
    }
  }
  
  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  void _initDeepLinks() async {
    _appLinks = AppLinks();
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri.toString());
    });
  }

  void _handleDeepLink(String link) async {
    if (FirebaseAuth.instance.isSignInWithEmailLink(link)) {
      final prefs = await SharedPreferences.getInstance();
      String email = prefs.getString('saved_email') ?? submittedEmail;
      
      if (email.isEmpty) return;
      
      try {
        await FirebaseAuth.instance.signInWithEmailLink(email: email, emailLink: link);
        // Check Admin Status
        if (adminEmails.contains(email)) isAdmin = true;
        else if (allowedStaffEmails.contains(email)) isAdmin = false;
        
        _promptForName(email);
      } catch (e) {
        debugPrint("Error signing in with email link: $e");
      }
    }
  }

  void _verifyPhoneNumber() async {
    String phone = _emailController.text.trim();
    if (phone.length == 10 && !phone.startsWith('+')) {
      phone = '+91$phone'; // Default to India if no code
    }

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          _completeLogin("Staff (Phone)", phone, false);
        },
        verificationFailed: (FirebaseAuthException e) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? "Phone Verification Failed")));
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() => _verificationId = verificationId);
          _showOtpDialog(phone);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showOtpDialog(String phone) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text("Enter SMS OTP"),
        content: TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "6-digit OTP"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.black54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () async {
              try {
                PhoneAuthCredential credential = PhoneAuthProvider.credential(
                  verificationId: _verificationId,
                  smsCode: _otpController.text.trim(),
                );
                await FirebaseAuth.instance.signInWithCredential(credential);
                if (mounted) Navigator.pop(context);
                _completeLogin("Staff (Phone)", phone, false);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP")));
              }
            },
            child: const Text("VERIFY", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      )
    );
  }

  void _completeLogin(String name, String emailOrPhone, bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userName', name);
    await prefs.setString('userEmail', emailOrPhone);
    await prefs.setBool('isAdmin', isAdmin);
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PosScreen(userName: name, userEmail: emailOrPhone, isAdmin: isAdmin)));
    }
  }

  void _sendEmailLink() async {
    if (isPhoneMode) {
      _verifyPhoneNumber();
      return;
    }
    String input = _emailController.text.trim().toLowerCase();
    
    // Instant Phone Login Bypass
    if (phoneAuth.containsKey(input)) {
      final user = phoneAuth[input]!;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userName', user["name"]);
      await prefs.setString('userEmail', user["email"]);
      await prefs.setBool('isAdmin', user["isAdmin"]);
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PosScreen(userName: user["name"], userEmail: user["email"], isAdmin: user["isAdmin"])));
      }
      return;
    }

    String email = input;
    if (email.isEmpty || !email.contains("@")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid email.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent)
      );
      return;
    }

    if (!adminEmails.contains(email) && !allowedStaffEmails.contains(email)) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Access Denied", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          content: Text("The email '$email' is not authorized. Ask an Admin to add you."),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("OK"))],
        )
      );
      return;
    }

    // REAL FIREBASE AUTH!
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_email', email);
      
      var acs = ActionCodeSettings(
        url: 'https://love-kush-pos.firebaseapp.com/',
        handleCodeInApp: true,
        androidPackageName: 'com.lovekush.lovekush_pos',
        androidInstallApp: false,
        androidMinimumVersion: '23'
      );
      
      await FirebaseAuth.instance.sendSignInLinkToEmail(
        email: email, 
        actionCodeSettings: acs
      );

      setState(() {
        submittedEmail = email;
        isLinkSent = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Firebase Error: $e"), 
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 10),
      ));
    }
  }

  void _promptForName(String email) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Account Setup", style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Email verified securely! Please enter your name for the billing receipts."),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Your Full Name",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)), 
              onPressed: () async {
                if (_nameController.text.trim().isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('isLoggedIn', true);
                  await prefs.setString('userName', _nameController.text.trim());
                  await prefs.setString('userEmail', email);
                  await prefs.setBool('isAdmin', isAdmin);
                  
                  if (!mounted) return;
                  Navigator.pop(context); 
                  Navigator.pushReplacement(
                    context, 
                    MaterialPageRoute(
                      builder: (context) => PosScreen(
                        userName: _nameController.text.trim(),
                        userEmail: email,
                        isAdmin: isAdmin,
                      )
                    )
                  );
                }
              },
              child: const Text("Enter POS System", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: const Color(0xFFEFF6FF), shape: BoxShape.circle),
                child: const Icon(Icons.storefront, size: 80, color: Color(0xFF3B82F6)),
              ),
              const SizedBox(height: 24),
              const Text("लव कुश शॉपिङ्ग सेण्टर", textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2, height: 1.2)),
              const SizedBox(height: 8),
              const Text("Secure Staff Portal", style: TextStyle(fontSize: 16, color: Colors.black54)),
              const SizedBox(height: 40),
              
              if (!isLinkSent) ...[
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: "Email or Phone Number", prefixIcon: const Icon(Icons.email_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: _sendEmailLink,
                    child: const Text("Send Magic Link", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
              ] else ...[
                const Icon(Icons.mark_email_read, size: 80, color: Color(0xFF10B981)), 
                const SizedBox(height: 16),
                const Text("Check your email!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text("We sent a real secure login link to:\n$submittedEmail", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.black54, height: 1.5)),
                const SizedBox(height: 40),
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text("Waiting for you to click the link in your email app...", style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => setState(() => isLinkSent = false),
                  child: const Text("Use a different email", style: TextStyle(color: Colors.grey)),
                )
              ]
            ],
          ),
        ),
      ),
    );
  }
}

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({Key? key}) : super(key: key);

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  final TextEditingController _newStaffController = TextEditingController();

  void _addStaff() {
    String newEmail = _newStaffController.text.trim().toLowerCase();
    if (newEmail.isEmpty || !newEmail.contains("@")) return;

    if (allowedStaffEmails.contains(newEmail) || adminEmails.contains(newEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User already has access.")));
      return;
    }

    setState(() {
      allowedStaffEmails.add(newEmail);
      _newStaffController.clear();
    });
  }

  void _revokeAccess(String email) {
    setState(() {
      allowedStaffEmails.remove(email);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MANAGE STAFF", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          // ADD NEW STAFF BAR
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newStaffController,
                    decoration: InputDecoration(
                      labelText: "New Staff Email",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onPressed: _addStaff,
                  child: const Text("AUTHORIZE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          
          // LIST OF ALLOWED STAFF
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text("ADMINISTRATORS (Cannot be removed here)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                ...adminEmails.map((email) => Card(
                  color: Colors.blue.shade50,
                  child: ListTile(
                    leading: const Icon(Icons.admin_panel_settings, color: Colors.blue),
                    title: Text(email, style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: const Text("ADMIN", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  ),
                )).toList(),
                
                const SizedBox(height: 24),
                const Text("AUTHORIZED STAFF", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                
                if (allowedStaffEmails.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text("No staff members authorized yet.", style: TextStyle(fontStyle: FontStyle.italic)),
                  ),
                  
                ...allowedStaffEmails.map((email) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.person, color: Colors.black54),
                    title: Text(email),
                    trailing: IconButton(
                      icon: const Icon(Icons.person_remove, color: Colors.red),
                      onPressed: () {
                        // Confirm deletion
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("Revoke Access?"),
                            content: Text("Are you sure you want to kick $email out of the system?"),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _revokeAccess(email);
                                },
                                child: const Text("Revoke Access", style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          )
                        );
                      },
                    ),
                  ),
                )).toList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


// ==========================================
// POS SCREEN
// ==========================================
class PosScreen extends StatefulWidget {
  final String userName;
  final String userEmail;
  final bool isAdmin;
  
  const PosScreen({Key? key, required this.userName, required this.userEmail, required this.isAdmin}) : super(key: key);

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  Map<String, double> cloudInventory = {};
  
  void _syncInventoryFromCloud() async {
    try {
      final data = await Supabase.instance.client.from('inventory').select();
      setState(() {
        for (var item in data) {
          cloudInventory[item['item_code'].toString()] = (item['price'] as num).toDouble();
        }
      });
    } catch (e) {
      print("Inventory Sync Error: $e");
    }
  }

  List<List<Map<String, dynamic>>> activeBills = [[]];
  int currentBillIndex = 0;
  List<Map<String, dynamic>> get cart => activeBills[currentBillIndex];
  String rawItemCode = ""; 
  String qty = "1"; 
  String rate = ""; 
  int focusedField = 0; 
  String counterName = "Basement Counter";
  
  // Printer Setup
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;
  bool _printerConnected = false;

  @override
  void initState() {
    super.initState();
    _loadCounterName();
    _initBluetooth();
    _syncInventoryFromCloud();
  }

  void _initBluetooth() async {
    try {
      List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
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
  }

  void _loadCounterName() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        counterName = prefs.getString('counterName') ?? "Basement Counter";
      });
    }
  }

  void _changeCounterName() {
    TextEditingController ctrl = TextEditingController(text: counterName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Change Counter Name"),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: "Counter Name (e.g. Ground Floor)"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.black54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('counterName', ctrl.text.trim());
                setState(() => counterName = ctrl.text.trim());
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("SAVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ]
      )
    );
  }
  bool isPreviewingBill = false;
  bool isScanning = false; 

  // ... (Keeping all the POS logic identical for brevity) ...

  String get formattedItemCode {
    if (rawItemCode.isEmpty) return "";
    String result = "";
    for (int i = 0; i < rawItemCode.length; i++) {
      if (i == 1) result += " - "; 
      if (i == 3) result += " - "; 
      if (i == 4) result += " - "; 
      if (i == 3) {
        int? num = int.tryParse(rawItemCode[i]);
        if (num != null && num >= 1 && num <= 9) {
          result += String.fromCharCode(64 + num); 
        } else {
          result += rawItemCode[i];
        }
      } else {
        result += rawItemCode[i];
      }
    }
    return result;
  }

  String get totalPrice {
    if (qty.isEmpty || rate.isEmpty) return "";
    double q = double.tryParse(qty) ?? 0;
    double r = double.tryParse(rate) ?? 0;
    return (q * r).round().toString();
  }

  int get cartTotal {
    int total = 0;
    for (var item in cart) total += int.tryParse(item["price"]) ?? 0;
    return total;
  }

  void addToCart() {
    if (rawItemCode.isEmpty || rate.isEmpty) return;
    setState(() {
      cart.insert(0, {
        "qty": qty.isEmpty ? "1" : qty,
        "item": formattedItemCode,
        "rawItemCode": rawItemCode, 
        "rate": rate,
        "price": totalPrice, 
      });
      rawItemCode = "";
      qty = "1"; 
      rate = "";
      focusedField = 0; 
    });
  }

  void editCartItem(int index) {
    setState(() {
      final item = cart[index];
      rawItemCode = item["rawItemCode"];
      qty = item["qty"];
      rate = item["rate"];
      focusedField = 0; 
      cart.removeAt(index); 
    });
  }

  void removeCartItem(int index) {
    setState(() => cart.removeAt(index));
  }

  void onKeypadPress(String value) {
    setState(() {
      if (value == "ENTER") {
        if (focusedField == 0) focusedField = 1;
        else if (focusedField == 1) focusedField = 2;
        else if (focusedField == 2) addToCart();
      } 
      else if (value == "BACK") {
        if (focusedField == 2) focusedField = 1;
        else if (focusedField == 1) focusedField = 0;
      }
      else if (value == "DEL") {
        if (focusedField == 2) {
          if (rate.isNotEmpty) rate = rate.substring(0, rate.length - 1);
          else focusedField = 1; 
        } 
        else if (focusedField == 1) {
          if (qty.isNotEmpty) qty = qty.substring(0, qty.length - 1);
          else focusedField = 0; 
        } 
        else if (focusedField == 0) {
          if (rawItemCode.isNotEmpty) rawItemCode = rawItemCode.substring(0, rawItemCode.length - 1);
        }
      } 
      else {
        if (focusedField == 0 && rawItemCode.length < 8) {
          if (value != ".") rawItemCode += value;
        }
        if (focusedField == 1) {
          if (value == ".") {
            if (!qty.contains(".")) qty += value; 
          } else if (qty == "1" && value != "0" && value != "00") {
            qty = value; 
          } else {
            qty += value;
          }
        }
        if (focusedField == 2) {
          if (value == ".") {
            if (!rate.contains(".")) rate += value;
          } else {
            rate += value;
          }
        }
      }
    });
  }


  void _deleteTab(int index) {
    if (activeBills.length <= 1) {
      setState(() => activeBills[0].clear());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cleared the active bill.")));
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Customer Bill?"),
        content: Text("Are you sure you want to permanently delete Bill ${index + 1}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL", style: TextStyle(color: Colors.black54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                activeBills.removeAt(index);
                if (currentBillIndex >= activeBills.length) {
                  currentBillIndex = activeBills.length - 1;
                } else if (currentBillIndex > index) {
                  currentBillIndex--;
                }
              });
              Navigator.pop(context);
            },
            child: const Text("DELETE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ]
      )
    );
  }


  void confirmPrint() {
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
        String details = "${item["qty"]} x ₹${item["rate"]}";
        await bluetooth.printLeftRight(name, details, 1);
      }
      
      await bluetooth.printCustom("--------------------------------", 1, 1);
      await bluetooth.printLeftRight("TOTAL", "₹${cartTotal.toStringAsFixed(2)}", 2); 
      await bluetooth.printNewLine();
      
      await bluetooth.printCustom("Thank you for shopping!", 1, 1);
      await bluetooth.printCustom("No Exchange / No Refund", 1, 1);
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.paperCut();
      
      // Save to Supabase Cloud
      try {
        await Supabase.instance.client.from('bills').insert({
          'staff_name': widget.userName,
          'counter_name': counterName,
          'total_amount': cartTotal,
          'items_json': cart,
        });
      } catch (dbError) {
        print("Supabase Error: $dbError");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cloud Sync Failed: $dbError")));
      }

      confirmPrint();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bill Printed & Saved to Cloud!")));
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Print Error: $e")));
      setState(() => isPreviewingBill = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        
        if (isPreviewingBill) {
          setState(() => isPreviewingBill = false);
          return;
        }
        if (isScanning) {
          setState(() => isScanning = false);
          return;
        }
        
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Exit App?'),
            content: const Text('Are you sure you want to exit the POS?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO', style: TextStyle(color: Colors.black54))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red), 
                onPressed: () => Navigator.pop(context, true), 
                child: const Text('YES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              ),
            ],
          ),
        );
        if (shouldExit == true) SystemNavigator.pop();
      },
      child: isPreviewingBill ? buildPrintPreviewScreen() : _buildMainScaffold(),
    );
  }

  Widget _buildMainScaffold() {
    return Scaffold(
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF111827)), 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Container(
                        height: 50,
                        width: 50,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          image: DecorationImage(image: AssetImage('assets/logo_bw.jpg'), fit: BoxFit.cover),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(child: Text('लव कुश शॉपिङ्ग सेण्टर', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(widget.userName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                  Text(widget.userEmail, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            
            // ADMIN ONLY SECTION
            if (widget.isAdmin) ...[
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
                child: Text("ADMIN CONTROLS", style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ),
              ListTile(
                leading: const Icon(Icons.manage_accounts, color: Colors.black87),
                title: const Text('Manage Staff Access', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context); // close drawer
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StaffManagementScreen()));
                },
              ),
              const Divider(),
            ],
            
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.black87),
              title: const Text('New Bill (POS)', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context), 
            ),
            ListTile(
              leading: Icon(Icons.print, color: _printerConnected ? Colors.green : Colors.black87),
              title: Text(_printerConnected ? 'Printer Connected' : 'Connect Printer', style: TextStyle(fontWeight: FontWeight.bold, color: _printerConnected ? Colors.green : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _showPrinterDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.black54),
              title: const Text('Past Bills'),
              onTap: () {}, 
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text('Logout', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
                try { await FirebaseAuth.instance.signOut(); } catch(e){}
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context, 
                    MaterialPageRoute(builder: (context) => const LoginScreen()), 
                    (route) => false
                  );
                }
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        title: const Text('लव कुश शॉपिङ्ग सेण्टर', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black), 
      ),
      body: Column(
        children: [
          Container(
            height: 55,
            color: Colors.white,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: activeBills.length + 1,
              itemBuilder: (context, index) {
                if (index == activeBills.length) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: ActionChip(
                      backgroundColor: Colors.green.shade50,
                      side: BorderSide(color: Colors.green),
                      label: const Text("+ New Customer", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                      onPressed: () {
                        setState(() {
                          activeBills.add([]);
                          currentBillIndex = activeBills.length - 1;
                        });
                      }
                    ),
                  );
                }
                bool isSelected = index == currentBillIndex;
                int itemCount = activeBills[index].length;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: GestureDetector(
                    onLongPress: () => _deleteTab(index),
                    child: ChoiceChip(
                    label: Text("Bill ${index + 1} ($itemCount items)", style: TextStyle(fontWeight: FontWeight.bold)),
                    selected: isSelected,
                    showCheckmark: false,
                    onSelected: (bool selected) {
                      if (selected) setState(() => currentBillIndex = index);
                    },
                    selectedColor: Colors.black,
                    labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
                  ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            flex: 4,
            child: Material(
              color: Colors.transparent,
              child: cart.isEmpty 
                ? Center(child: Text("Welcome, ${widget.userName}!\nReady for next customer", textAlign: TextAlign.center, style: const TextStyle(color: Colors.black38, fontSize: 18, fontWeight: FontWeight.w500)))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: cart.length,
                    itemBuilder: (context, index) {
                      final item = cart[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade200),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                        ),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          clipBehavior: Clip.antiAlias, 
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            onTap: () => editCartItem(index),
                            leading: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text("${item["qty"]}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                            ),
                            title: Text(item["item"], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
                            subtitle: Text("@ ₹${item["rate"]} (Tap to edit)", style: const TextStyle(fontSize: 13, color: Colors.black38, fontWeight: FontWeight.w500)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("₹${item["price"]}", style: const TextStyle(fontSize: 22, color: Colors.black, fontWeight: FontWeight.w800)),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.black26),
                                  onPressed: () => removeCartItem(index),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            ),
          ),
          if (cart.isNotEmpty)
            GestureDetector(
              onTap: executeBluetoothPrint,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981), 
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -4))],
                ),
                child: Text(
                  "FINISH BILL ( ₹$cartTotal )  ➔",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.5),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.black12, width: 1)),
            ),
            child: Row(
              children: [
                _buildInputBox("ITEM CODE", formattedItemCode, focusedField == 0, 0, flex: 8, isCode: true),
                const SizedBox(width: 8),
                _buildInputBox("QTY", qty.isEmpty ? "—" : qty, focusedField == 1, 1, flex: 3),
                const SizedBox(width: 8),
                _buildInputBox("RATE", rate.isEmpty ? "" : "₹$rate", focusedField == 2, 2, flex: 4),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF), 
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text("TOTAL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.blueAccent)),
                        const SizedBox(height: 6),
                        Text(
                          totalPrice.isEmpty ? "—" : "₹$totalPrice",
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.black),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: isScanning 
              ? Stack(
                  children: [
                    MobileScanner(
                      onDetect: (capture) {
                        final List<Barcode> barcodes = capture.barcodes;
                        if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                          setState(() {
                            rawItemCode = barcodes.first.rawValue!.replaceAll("-", "");
                            focusedField = 1; // jump to qty
                            isScanning = false; // instantly close camera to show keypad
                          });
                        }
                      },
                    ),
                    Positioned(
                      top: 16, right: 16,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 32),
                        onPressed: () => setState(() => isScanning = false),
                      )
                    ),
                    const Positioned(
                      bottom: 24, left: 0, right: 0,
                      child: Center(
                        child: Text("Scanning...", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, backgroundColor: Colors.black54)),
                      )
                    )
                  ]
                )
              : Container(
                  color: const Color(0xFF111827), 
                  child: Column(
                    children: [
                      _buildKeypadRow([_key("1", "A"), _key("2", "B"), _key("3", "C"), _actionKey("⌫", const Color(0xFFEF4444))]), 
                      _buildKeypadRow([_key("4", "D"), _key("5", "E"), _key("6", "F"), _actionKey("◀", const Color(0xFFF59E0B))]),
                      _buildKeypadRow([_key("7", "G"), _key("8", "H"), _key("9", "I"), _key("00", "")]),
                      _buildKeypadRow([_actionKey("📷 SCAN", Colors.black, isScan: true), _key("0", ""), _key(".", ""), _actionKey("ENTER", const Color(0xFF3B82F6), isEnter: true)]),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget buildPrintPreviewScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF374151), 
      body: SafeArea(
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(16.0), child: Text("PREVIEW BILL", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2))),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Image.asset('assets/logo_bw.jpg', height: 100),
                      const SizedBox(height: 16),
                      const Text("लव कुश शॉपिङ्ग सेण्टर", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      const Text("Basement Counter", style: TextStyle(fontSize: 16, color: Colors.black54)),
                      Text("Served by: ${widget.userName}", style: const TextStyle(fontSize: 14, color: Colors.black45, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 16),
                      const Text("----------------------------------------", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ...cart.reversed.map((item) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(flex: 3, child: Text(item["item"], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                              Expanded(flex: 2, child: Text("${item["qty"]} x ${item["rate"]}", style: const TextStyle(fontSize: 14, color: Colors.black54), textAlign: TextAlign.center)),
                              Expanded(flex: 2, child: Text("₹${item["price"]}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), textAlign: TextAlign.right)),
                            ],
                          ),
                        );
                      }).toList(),
                      const SizedBox(height: 16),
                      const Text("----------------------------------------", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("GRAND TOTAL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          Text("₹$cartTotal", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 40),
                      const Text("Thank you for shopping!", style: TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), side: const BorderSide(color: Colors.black, width: 2)),
                      onPressed: () => setState(() => isPreviewingBill = false), 
                      child: const Text("◀ EDIT BILL", style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), padding: const EdgeInsets.symmetric(vertical: 20)),
                      onPressed: executeBluetoothPrint, 
                      child: const Text("🖨️ PRINT BILL", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBox(String label, String value, bool isFocused, int fieldIndex, {required int flex, bool isCode = false}) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: () => setState(() => focusedField = fieldIndex),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          decoration: BoxDecoration(
            color: isFocused ? Colors.black : Colors.white,
            border: Border.all(color: isFocused ? Colors.black : Colors.black26, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: isFocused ? Colors.white70 : Colors.black45)),
              const SizedBox(height: 6),
              Text(value.isEmpty ? (isCode ? "—" : "") : value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: isFocused ? Colors.white : Colors.black), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypadRow(List<Widget> keys) {
    return Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: keys));
  }

  Widget _key(String number, String letter) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onKeypadPress(number),
          splashColor: Colors.white24,
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.white.withOpacity(0.05), width: 0.5)),
            child: Stack(
              children: [
                Center(child: Text(number, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w300, color: Colors.white))),
                if (letter.isNotEmpty) Positioned(top: 12, right: 16, child: Text(letter, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.3)))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionKey(String action, Color color, {int flex = 1, bool isEnter = false, bool isScan = false}) {
    return Expanded(
      flex: flex,
      child: Material(
        color: color,
        child: InkWell(
          onTap: () {
            if (isScan) {
              setState(() => isScanning = true);
            } else {
              onKeypadPress(isEnter ? "ENTER" : (action.contains("⌫") ? "DEL" : "BACK"));
            }
          },
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: Colors.black26, width: 0.5)),
            child: Center(child: Text(action, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 1.2))),
          ),
        ),
      ),
    );
  }
}


// ==========================================
// INVENTORY QR LABEL PRINTER
// ==========================================
class InventoryQrScreen extends StatefulWidget {
  const InventoryQrScreen({Key? key}) : super(key: key);
  @override
  State<InventoryQrScreen> createState() => _InventoryQrScreenState();
}

class _InventoryQrScreenState extends State<InventoryQrScreen> {
  final TextEditingController _floorCtrl = TextEditingController(text: "1");
  final TextEditingController _rackCtrl = TextEditingController(text: "01");
  final TextEditingController _shelfCtrl = TextEditingController(text: "A");
  final TextEditingController _itemCtrl = TextEditingController(text: "1");
  
  String get locationCode => "${_floorCtrl.text}-${_rackCtrl.text}-${_shelfCtrl.text}-${_itemCtrl.text}".toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Item QR Generator"), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text("Enter Location Code Parts", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextField(controller: _floorCtrl, decoration: const InputDecoration(labelText: "Floor"), onChanged: (_) => setState((){}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _rackCtrl, decoration: const InputDecoration(labelText: "Rack"), onChanged: (_) => setState((){}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _shelfCtrl, decoration: const InputDecoration(labelText: "Shelf"), onChanged: (_) => setState((){}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _itemCtrl, decoration: const InputDecoration(labelText: "Item"), onChanged: (_) => setState((){}))),
              ],
            ),
            const SizedBox(height: 40),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12, width: 2),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]
              ),
              child: Column(
                children: [
                  Text("Item Location", style: const TextStyle(fontSize: 16, color: Colors.black54)),
                  Text(locationCode, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 24),
                  QrImageView(
                    data: locationCode,
                    version: QrVersions.auto,
                    size: 200.0,
                    backgroundColor: Colors.white,
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity, height: 56,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.print),
                label: const Text("PRINT QR LABEL", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sending to Bluetooth/USB Printer...")));
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}


// ==========================================
// QR CAMERA SCANNER SCREEN
// ==========================================
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({Key? key}) : super(key: key);
  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan QR Label"), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: MobileScanner(
        controller: controller,
        onDetect: (BarcodeCapture capture) {
          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            final String code = barcodes.first.rawValue!;
            controller.stop();
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);
  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool isLoading = true;
  double todaysCollection = 0.0;
  List<dynamic> pastBills = [];

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  void _fetchDashboardData() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();

      // Fetch today's bills
      final data = await Supabase.instance.client
          .from('bills')
          .select()
          .gte('created_at', startOfDay)
          .order('created_at', ascending: false);

      double total = 0;
      for (var row in data) {
        total += (row['total_amount'] as num).toDouble();
      }

      setState(() {
        todaysCollection = total;
        pastBills = data;
        isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching data: $e")));
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Dashboard", style: TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF111827), iconTheme: const IconThemeData(color: Colors.white)),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  color: Colors.blueAccent.withOpacity(0.1),
                  child: Column(
                    children: [
                      const Text("TODAY'S COLLECTION", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      Text("₹${todaysCollection.toStringAsFixed(2)}", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Align(alignment: Alignment.centerLeft, child: Text("TODAY'S BILLS", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: pastBills.length,
                    itemBuilder: (context, index) {
                      final bill = pastBills[index];
                      return ListTile(
                        leading: CircleAvatar(backgroundColor: Colors.black12, child: const Icon(Icons.receipt, color: Colors.black)),
                        title: Text("₹${bill['total_amount']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        subtitle: Text("Staff: ${bill['staff_name']} • Counter: ${bill['counter_name']}"),
                        trailing: Text(DateTime.parse(bill['created_at']).toLocal().toString().split('.')[0].substring(11), style: const TextStyle(color: Colors.black54)),
                      );
                    },
                  ),
                )
              ],
            ),
    );
  }
}
