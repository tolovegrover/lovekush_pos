import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart' as bw;
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
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'firebase_options.dart';
import 'cosmetics_catalog.dart';
import 'pdf_receipt_service.dart';
import 'vedic_time_service.dart';
import 'vedic_clock_screen.dart';
import 'settings_screen.dart';
import 'package:printing/printing.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); } catch (e) { print(e); }
  try {
    await Supabase.initialize(
      url: 'https://hzseglqgnjxmkzrecizn.supabase.co',
      anonKey: 'sb_publishable_y6Rb83ANnxVRaEItiKf5kg_MjqHNo6w',
    );
  } catch (e) { print("Supabase Init Error: $e"); }

  runApp(const PosApp());
}

// ==========================================
// MOCK DATABASE (For DartPad Prototype)
// ==========================================
final List<String> adminEmails = [
  "tolovegrover@gmail.com",
  "sanjeetagrover@gmail.com",
  "mrsnishagrover@gmail.com"
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
  final TextEditingController _passwordController = TextEditingController();
  bool isLoginMode = true;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  void _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    
    if (isLoggedIn && mounted) {
      String name = prefs.getString('userName') ?? "Staff";
      String emailOrPhone = prefs.getString('userEmail') ?? "";
      bool isAdmin = prefs.getBool('isAdmin') ?? false;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PosScreen(userName: name, userEmail: emailOrPhone, isAdmin: isAdmin)));
    }
  }

  void _completeLogin(String name, String emailOrPhone, bool isAdmin) async {
    setState(() => isLoading = true);
    try {
      final emailLower = emailOrPhone.toLowerCase();
      bool finalIsAdmin = adminEmails.contains(emailLower);
      bool isApproved = finalIsAdmin;
      
      final data = await Supabase.instance.client.from('staff_users').select().eq('email', emailLower);
      
      if (data.isEmpty) {
        await Supabase.instance.client.from('staff_users').insert({
          'email': emailLower,
          'name': name,
          'is_approved': finalIsAdmin,
          'is_admin': finalIsAdmin
        });
      } else {
        isApproved = data[0]['is_approved'] == true;
        if (data[0]['is_admin'] == true) finalIsAdmin = true;
      }
      
      if (!isApproved) {
        try { await FirebaseAuth.instance.signOut(); } catch(e){}
        if (mounted) {
          showDialog(
            context: context, 
            builder: (_) => AlertDialog(
              title: const Text("Approval Pending 🕒"),
              content: const Text("Your account has been created, but you must wait for the shop owner to approve your access."),
              actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text("OK"))]
            )
          );
        }
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('userName', name);
      await prefs.setString('userEmail', emailLower);
      await prefs.setBool('isAdmin', finalIsAdmin);

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PosScreen(userName: name, userEmail: emailLower, isAdmin: finalIsAdmin)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("DB Error: $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return; 

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;
      
      if (user != null && user.email != null) {
        _completeLogin(user.displayName ?? user.email!.split('@')[0], user.email!, adminEmails.contains(user.email!.toLowerCase()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Google Sign-In Failed: $e")));
    }
  }

  Future<void> _submitEmailPassword() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();
    
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter email and password")));
      return;
    }
    
    setState(() => isLoading = true);
    
    try {
      UserCredential userCredential;
      if (isLoginMode) {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      } else {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      }
      
      final user = userCredential.user;
      if (user != null && user.email != null) {
        _completeLogin(user.displayName ?? email.split('@')[0], user.email!, adminEmails.contains(user.email!.toLowerCase()));
      }
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? "Authentication failed")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 40),
            title: const Text('Exit App?'),
            content: const Text('Are you sure you want to close the Love Kush POS app?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('STAY')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () => SystemNavigator.pop(), 
                child: const Text('EXIT')
              ),
            ]
          )
        );
        if (shouldExit == true) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF111827),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)]),
                    child: ClipOval(child: Image.asset('assets/logo_bw.jpg', width: 100, height: 100, fit: BoxFit.cover)),
                  ),
                  const SizedBox(height: 24),
                  const Text("LOVE KUSH SHOPPING CENTER", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  const Text("STAFF LOGIN", style: TextStyle(color: Colors.blueAccent, letterSpacing: 2, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 40),
                  
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      children: [
                        Align(alignment: Alignment.centerLeft, child: Text(isLoginMode ? "Email Address" : "Create Account (Email)", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54))),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.email, color: Colors.blueAccent),
                            hintText: "staff@example.com",
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock, color: Colors.blueAccent),
                            hintText: "Password",
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            onPressed: isLoading ? null : _submitEmailPassword,
                            child: isLoading 
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                              : Text(isLoginMode ? "SIGN IN" : "REGISTER", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => isLoginMode = !isLoginMode),
                          child: Text(isLoginMode ? "Create a new account" : "Already have an account? Sign In", style: const TextStyle(color: Colors.black54)),
                        ),
                        const SizedBox(height: 8),
                        
                        Row(
                          children: const [
                            Expanded(child: Divider(color: Colors.black26)),
                            Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("OR", style: TextStyle(color: Colors.black54, fontWeight: FontWeight.bold))),
                            Expanded(child: Divider(color: Colors.black26)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.black12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                            icon: Image.network("https://upload.wikimedia.org/wikipedia/commons/thumb/c/c1/Google_%22G%22_logo.svg/120px-Google_%22G%22_logo.svg.png", width: 24),
                            label: const Text("Continue with Google", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                            onPressed: isLoading ? null : () async {
                              setState(() => isLoading = true);
                              await _signInWithGoogle();
                              if (mounted) setState(() => isLoading = false);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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
  bool isLoading = true;
  List<dynamic> users = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  void _fetchUsers() async {
    try {
      final data = await Supabase.instance.client.from('staff_users').select().order('created_at', ascending: false);
      setState(() {
        users = data;
        isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching users: $e")));
      setState(() => isLoading = false);
    }
  }

  void _toggleApproval(String email, bool currentStatus) async {
    try {
      await Supabase.instance.client.from('staff_users').update({'is_approved': !currentStatus}).eq('email', email);
      _fetchUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _deleteUser(String email) async {
    try {
      await Supabase.instance.client.from('staff_users').delete().eq('email', email);
      _fetchUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  String _getSellerCode(String email) {
    final clean = email.trim().toLowerCase();
    if (clean == "tolovegrover@gmail.com") return "01";
    if (clean == "sanjeetagrover@gmail.com") return "02";
    if (clean == "mrsnishagrover@gmail.com") return "03";
    int id = (clean.hashCode.abs() % 3) + 4;
    return id.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Staff Access", style: TextStyle(color: Colors.white)), 
        backgroundColor: const Color(0xFF111827), 
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh list",
            onPressed: _fetchUsers,
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : users.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text("No Staff Registered Yet", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                          "When staff members register or log in, they will appear here awaiting your approval.\n\nMake sure the 'staff_users' table has been created in your Supabase SQL editor!",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                          onPressed: _fetchUsers,
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          label: const Text("Refresh List", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    bool isApproved = user['is_approved'] == true;
                    bool isAdmin = user['is_admin'] == true;
                    String sCode = _getSellerCode(user['email'] ?? '');
                    
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isAdmin ? Colors.purple : (isApproved ? Colors.green : Colors.orange),
                          child: Icon(isAdmin ? Icons.admin_panel_settings : Icons.person, color: Colors.white),
                        ),
                        title: Text(user['name'] ?? 'Staff', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${user['email']}\nSeller ID: $sCode • ${isApproved ? 'Approved' : 'Pending Approval'}"),
                        isThreeLine: true,
                        trailing: isAdmin 
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Text("ADMIN", style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 12)),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: isApproved,
                                    activeColor: Colors.green,
                                    onChanged: (val) => _toggleApproval(user['email'], isApproved),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                                    onPressed: () => _deleteUser(user['email']),
                                  )
                                ],
                              ),
                      ),
                    );
                  },
                ),
    );
  }
}

// ==========================================
// PRELOADED COSMETICS & ACCESSORIES DATABASE
// ==========================================
// Master cosmetics catalog (506 items) is loaded from cosmetics_catalog.dart
// ==========================================

// ==========================================
// ITEM NAME SANITIZER & DISPLAY FORMATTER
// ==========================================
// Ensures bills, receipts, and previews:
// 1. Never display "Unassigned Product" or "Barcode 890..."
// 2. Never duplicate the barcode number twice (e.g. in parentheses)
// 3. Never display or print "General Item" - if name is unknown, cleanly display the raw barcode number!
String cleanItemName(String? name, {String? barcode}) {
  final cleanBarcode = (barcode ?? '').trim();
  if (name == null || name.trim().isEmpty) {
    return cleanBarcode;
  }
  String cleaned = name.trim();
  if (cleaned.contains("\n")) {
    cleaned = cleaned.split("\n")[0].trim();
  }
  // Strip trailing bracketed barcode matching the barcode parameter if provided
  if (cleanBarcode.isNotEmpty) {
    cleaned = cleaned.replaceAll("($cleanBarcode)", "").trim();
  }
  // Strip bracketed long barcode or numeric ID (5+ digits)
  cleaned = cleaned.replaceAll(RegExp(r'\s*\([0-9]{5,}\)$'), '').trim();
  // Strip bracketed shelf format like (01-03-C-134) or (01-03-C)
  cleaned = cleaned.replaceAll(RegExp(r'\s*\([0-9]{2}-[0-9]{2}-[A-Za-z](-[0-9]+)?\)$'), '').trim();
  // Strip general trailing bracketed raw codes if they resemble barcodes/itemcodes (5+ alphanumeric chars)
  cleaned = cleaned.replaceAll(RegExp(r'\s*\([0-9A-Za-z-]{5,}\)$'), '').trim();

  // If it is a generic placeholder or "General Item", return the barcode number directly!
  final lower = cleaned.toLowerCase();
  if (cleaned.isEmpty ||
      lower == "general item" ||
      lower.startsWith("general item") ||
      lower.startsWith("unassigned") ||
      lower.startsWith("new scanned product") ||
      lower.startsWith("barcode ") ||
      lower == "barcode" ||
      RegExp(r'^item\s+[0-9A-Za-z-]+$', caseSensitive: false).hasMatch(cleaned)) {
    return cleanBarcode.isNotEmpty
        ? cleanBarcode
        : (cleaned.isNotEmpty && !lower.contains("general item") && !lower.contains("unassigned") ? cleaned : (cleanBarcode.isNotEmpty ? cleanBarcode : ""));
  }
  return cleaned;
}

// ==========================================
// SHELF CODE BREAKDOWN & AUTO-DASH FORMATTER
// ==========================================
class ShelfCodeBreakdown {
  final String shelfLocation; // e.g. "01-03-C"
  final String itemNumber;    // e.g. "134" or ""
  final String fullCode;      // e.g. "01-03-C-134" or "01-03-C"
  final bool isShelfOnly;

  ShelfCodeBreakdown({
    required this.shelfLocation,
    required this.itemNumber,
    required this.fullCode,
    required this.isShelfOnly,
  });

  static ShelfCodeBreakdown parse(String input) {
    String clean = input.replaceAll(' ', '').trim().toUpperCase();
    if (clean.isEmpty) {
      return ShelfCodeBreakdown(shelfLocation: "", itemNumber: "", fullCode: "", isShelfOnly: true);
    }

    if (clean.contains('-')) {
      final parts = clean.split('-');
      if (parts.length >= 4) {
        String shelf = "${parts[0]}-${parts[1]}-${parts[2]}";
        String item = parts.sublist(3).join('-');
        return ShelfCodeBreakdown(
          shelfLocation: shelf,
          itemNumber: item,
          fullCode: clean,
          isShelfOnly: item.isEmpty,
        );
      } else if (parts.length == 3) {
        String shelf = "${parts[0]}-${parts[1]}-${parts[2]}";
        return ShelfCodeBreakdown(
          shelfLocation: shelf,
          itemNumber: "",
          fullCode: shelf,
          isShelfOnly: true,
        );
      } else {
        return ShelfCodeBreakdown(
          shelfLocation: clean,
          itemNumber: "",
          fullCode: clean,
          isShelfOnly: true,
        );
      }
    }

    // Format raw digits
    String f = '';
    for (int i = 0; i < clean.length; i++) {
      if (i == 2 || i == 4 || i == 5) f += '-';
      if (i == 4) {
        int? d = int.tryParse(clean[i]);
        f += (d != null && d >= 1 && d <= 9) ? String.fromCharCode(64 + d) : clean[i];
      } else {
        f += clean[i];
      }
    }

    final parts = f.split('-');
    if (parts.length >= 4) {
      String shelf = "${parts[0]}-${parts[1]}-${parts[2]}";
      String item = parts.sublist(3).join('-');
      return ShelfCodeBreakdown(
        shelfLocation: shelf,
        itemNumber: item,
        fullCode: f,
        isShelfOnly: item.isEmpty,
      );
    } else if (parts.length == 3) {
      return ShelfCodeBreakdown(
        shelfLocation: f,
        itemNumber: "",
        fullCode: f,
        isShelfOnly: true,
      );
    } else {
      return ShelfCodeBreakdown(
        shelfLocation: f,
        itemNumber: "",
        fullCode: f,
        isShelfOnly: true,
      );
    }
  }
}

class ShelfCodeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length < oldValue.text.length) {
      return newValue;
    }

    String raw = newValue.text.replaceAll('-', '').replaceAll(' ', '').trim().toUpperCase();
    if (raw.isEmpty) return newValue;

    String formatted = '';
    for (int i = 0; i < raw.length; i++) {
      if (i == 2) formatted += '-';
      if (i == 4) formatted += '-';
      if (i == 5) formatted += '-';

      if (i == 4) {
        int? d = int.tryParse(raw[i]);
        if (d != null && d >= 1 && d <= 9) {
          formatted += String.fromCharCode(64 + d);
        } else {
          formatted += raw[i];
        }
      } else {
        formatted += raw[i];
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// ==========================================
// MULTI-API ONLINE BARCODE RESOLVER
// (Queries Open Beauty Facts, Open Food Facts, UPCitemdb, and Indian Retail registries)
// ==========================================
Future<List<Map<String, dynamic>>> resolveBarcodeOnlineMulti(String barcode) async {
  final clean = barcode.replaceAll(RegExp(r'[^0-9]'), '').trim();
  if (clean.length < 8) return [];

  final List<Map<String, dynamic>> results = [];
  final Set<String> seenNames = {};

  void addResult(String name, String brand, double price, String category, String source) {
    String cName = cleanItemName(name, barcode: clean);
    if (cName.isNotEmpty && cName != clean && !seenNames.contains(cName.toLowerCase())) {
      seenNames.add(cName.toLowerCase());
      results.add({
        'name': cName,
        'brand': brand,
        'price': price,
        'category': category.isNotEmpty ? category : 'Cosmetics',
        'source': source,
      });
    }
  }

  // 1. UPCitemdb lookup (covers Indian FMCG / Cosmetics)
  Future<void> queryUpcItemDb() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2800);
      final uri = Uri.parse("https://api.upcitemdb.com/prod/trial/lookup?upc=$clean");
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'LoveKushPOS/1.0 (Retail Scanner; Retail; India)');
      final resp = await req.close().timeout(const Duration(milliseconds: 2800));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = json.decode(body);
        if (data is Map && data['items'] is List) {
          for (var it in data['items']) {
            String title = (it['title'] ?? '').toString().trim();
            String brand = (it['brand'] ?? '').toString().trim();
            // CRITICAL FIX: UPCitemdb lowest_recorded_price is in US DOLLARS (e.g. $10.08)!
            // NEVER use foreign currency prices as Indian INR MRP! Always set price = 0.0
            // so the cashier can type the genuine Indian MRP from the product box.
            if (title.isNotEmpty) {
              addResult(title, brand, 0.0, 'Cosmetics', 'UPC Database');
            }
          }
        }
      } else if (resp.statusCode == 429 || resp.statusCode != 200) {
        // Fallback to web page scraper if trial API limit is reached
        final webUri = Uri.parse("https://www.upcitemdb.com/upc/$clean");
        final webReq = await client.getUrl(webUri);
        webReq.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
        final webResp = await webReq.close().timeout(const Duration(milliseconds: 2800));
        if (webResp.statusCode == 200) {
          final webHtml = await webResp.transform(utf8.decoder).join();
          final titleMatch = RegExp(r'<title>(.*?)(?:\s*\|\s*upcitemdb\.com)?</title>', caseSensitive: false).firstMatch(webHtml);
          if (titleMatch != null) {
            String title = titleMatch.group(1)!.replaceAll('| upcitemdb.com', '').trim();
            title = title.replaceAll(RegExp(r'^(?:EAN|UPC)\s+[0-9]+\s*-\s*', caseSensitive: false), '').trim();
            if (title.isNotEmpty && !title.toLowerCase().contains("not found") && !title.toLowerCase().contains("search") && title != clean) {
              addResult(title, '', 0.0, 'Cosmetics', 'UPC Database');
            }
          }
        }
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  // 2. Open Facts Endpoints (Open Beauty, Open Food, Open Products, Open Pet Food)
  final openFactsEndpoints = [
    ("https://world.openbeautyfacts.org/api/v2/product/$clean.json", "Open Beauty Facts"),
    ("https://world.openbeautyfacts.org/api/v0/product/$clean.json", "Open Beauty Facts"),
    ("https://in.openfoodfacts.org/api/v2/product/$clean.json", "Open Food Facts India"),
    ("https://world.openfoodfacts.org/api/v2/product/$clean.json", "Open Food Facts"),
    ("https://world.openproductsfacts.org/api/v2/product/$clean.json", "Open Products Facts"),
    ("https://world.openpetfoodfacts.org/api/v2/product/$clean.json", "Open Pet Food Facts"),
  ];

  Future<void> queryOpenFacts(String url, String source) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2400);
      final uri = Uri.parse(url);
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'LoveKushPOS/1.0 (Retail Scanner; Retail; India; contact: lovekush@retail.in)');
      final resp = await req.close().timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final data = json.decode(body);
        if (data is Map && (data['status'] == 1 || data['status'] == 'success') && data['product'] != null) {
          final prod = data['product'];
          String name = (prod['product_name'] ?? prod['product_name_en'] ?? prod['generic_name'] ?? '').toString().trim();
          String brand = (prod['brands'] ?? '').toString().trim();
          String cat = (prod['categories'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            if (brand.isNotEmpty && !name.toLowerCase().contains(brand.toLowerCase())) {
              name = "$brand $name";
            }
            addResult(name, brand, 0.0, cat, source);
          }
        }
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  // 3. DuckDuckGo Retail Slug Extractor (BigBasket, Blinkit, Nykaa, Amazon India)
  Future<void> queryRetailWebSearch() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 3000);
      final uri = Uri.parse("https://html.duckduckgo.com/html/?q=$clean");
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/119.0');
      final resp = await req.close().timeout(const Duration(milliseconds: 3000));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final reg = RegExp(r'uddg=([^&]+)');
        final matches = reg.allMatches(body);
        for (var m in matches) {
          final rawUrl = Uri.decodeComponent(m.group(1)!);
          if (rawUrl.contains("bigbasket.com/pd/") ||
              rawUrl.contains("blinkit.com/prn/") ||
              rawUrl.contains("nykaa.com/") ||
              rawUrl.contains("amazon.in/")) {
            final slugMatch = RegExp(r'/([^/]+)/?$').firstMatch(rawUrl.split('?')[0]);
            if (slugMatch != null) {
              String slug = slugMatch.group(1)!.replaceAll('-', ' ').replaceAll(RegExp(r'^[0-9]+\s*'), '').trim();
              if (slug.isNotEmpty && slug.length > 3) {
                final words = slug.split(' ').map((w) => w.isNotEmpty ? "${w[0].toUpperCase()}${w.substring(1)}" : "").join(' ');
                addResult(words, '', 0.0, 'Cosmetics', 'Retail Online Registry');
              }
            }
          }
        }
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  // 4. Barcode-List.com lookup (Database of barcodes and goods conformity)
  Future<void> queryBarcodeList() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2800);
      final uri = Uri.parse("https://barcode-list.com/barcode/EN/Search.htm?barcode=$clean");
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      final resp = await req.close().timeout(const Duration(milliseconds: 2800));
      if (resp.statusCode == 200) {
        final html = await resp.transform(utf8.decoder).join();

        // 1) Match pageTitle: <h1 class="pageTitle" ...>PRODUCT NAME - Barcode: 123456</h2>
        final titleMatch = RegExp(r'<h1[^>]*class="pageTitle"[^>]*>\s*(.*?)\s*-\s*Barcode:\s*[0-9]+', caseSensitive: false).firstMatch(html);
        if (titleMatch != null) {
          String title = titleMatch.group(1)!.trim();
          if (title.isNotEmpty && !title.toLowerCase().startsWith("search for") && title != clean) {
            addResult(title, '', 0.0, 'Cosmetics', 'Barcode-List');
          }
        }

        // 2) Match randomBarcodes table rows
        final tableMatch = RegExp(r'<table[^>]*class="randomBarcodes"[^>]*>(.*?)</table>', caseSensitive: false, dotAll: true).firstMatch(html);
        if (tableMatch != null) {
          final tableContent = tableMatch.group(1)!;
          final rowMatches = RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true).allMatches(tableContent);
          for (var row in rowMatches) {
            final tdMatches = RegExp(r'<td[^>]*>(.*?)</td>', caseSensitive: false, dotAll: true).allMatches(row.group(1)!).toList();
            if (tdMatches.length >= 3) {
              String prodName = tdMatches[2].group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
              if (prodName.isNotEmpty && prodName != clean && !prodName.toLowerCase().startsWith("search for")) {
                addResult(prodName, '', 0.0, 'Cosmetics', 'Barcode-List');
              }
            }
          }
        }
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  // 5. Go-UPC.com lookup (Comprehensive Indian barcode database)
  Future<void> queryGoUpc() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2800);
      final uri = Uri.parse("https://go-upc.com/search?q=$clean");
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
      final resp = await req.close().timeout(const Duration(milliseconds: 2800));
      if (resp.statusCode == 200) {
        final html = await resp.transform(utf8.decoder).join();
        final nameMatch = RegExp(r'<h1[^>]*class="product-name"[^>]*>(.*?)</h1>', caseSensitive: false, dotAll: true).firstMatch(html);
        if (nameMatch != null) {
          String rawName = nameMatch.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
          rawName = rawName
              .replaceAll('&amp;', '&')
              .replaceAll('&#39;', "'")
              .replaceAll('&quot;', '"')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>');

          // Extract brand if available
          String brand = '';
          final brandMatch = RegExp(r'<td[^>]*class="metadata-label"[^>]*>Brand</td>\s*<td[^>]*>(.*?)</td>', caseSensitive: false, dotAll: true).firstMatch(html);
          if (brandMatch != null) {
            brand = brandMatch.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
            brand = brand.replaceAll('&amp;', '&').replaceAll('&#39;', "'").replaceAll('&quot;', '"');
          }

          // Extract category if available
          String category = 'Cosmetics';
          final catMatch = RegExp(r'<td[^>]*class="metadata-label"[^>]*>Category</td>\s*<td[^>]*>(.*?)</td>', caseSensitive: false, dotAll: true).firstMatch(html);
          if (catMatch != null) {
            category = catMatch.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
            category = category.replaceAll('&amp;', '&').replaceAll('&#39;', "'").replaceAll('&quot;', '"');
          }

          if (rawName.isNotEmpty && rawName != clean && !rawName.toLowerCase().contains("not found")) {
            addResult(rawName, brand, 0.0, category, 'Go-UPC');
          }
        }
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  // 6. GS1 India DataKart Verified GTIN API (Official National Indian Barcode Registry)
  Future<void> queryGs1DataKart() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 2800);
      final uri = Uri.parse("https://dk-app.org/verified_gtin");
      final req = await client.postUrl(uri);
      final gtin14 = clean.padLeft(14, '0');
      const token =
          'DeVFjnh2K1GydCinuhQt3PrM235h7iLTnozqRxk4KYbnM4kmB8Zs1SfV6UNNwUByw4gRsbdmIv6CSDhc2V5tj/LfVICX/IuhR66ylCKfNOyOBmGO5/IOTo2NpmxamjgbliATP8P/lQLewdk8oRyga/evjp5t51QvbviSk6pErxWHu9x0NgAZY2wpVjdeuX452KnS33YHjE6GJIaPLsJVkR1Gje9djegdpgVg/CmyseJqqKoNQb0SRAie2QGvzLmc/oFcTyeFinOYpeYYdTLq6ZEy8RhgpiyPhWtgtpini00=';
      req.headers.set('Authorization', 'Bearer $token');
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
      req.add(utf8.encode(json.encode([gtin14])));
      final resp = await req.close().timeout(const Duration(milliseconds: 2800));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final list = json.decode(body);
        if (list is List && list.isNotEmpty) {
          final first = list.first;
          if (first is Map) {
            String brand = '';
            if (first['brandName'] is List && (first['brandName'] as List).isNotEmpty) {
              brand = (first['brandName'][0]['value'] ?? '').toString().trim();
            }
            String desc = '';
            if (first['productDescription'] is List && (first['productDescription'] as List).isNotEmpty) {
              desc = (first['productDescription'][0]['value'] ?? '').toString().trim();
            }
            if (desc.isNotEmpty && desc != clean) {
              // Clean redundant duplicate suffixes if present
              String cleanDesc = desc;
              if (brand.isNotEmpty && !cleanDesc.toLowerCase().contains(brand.toLowerCase())) {
                cleanDesc = "$brand $cleanDesc";
              }
              addResult(cleanDesc, brand, 0.0, 'Cosmetics', 'GS1 DataKart India');
            }
          }
        }
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
  }

  await Future.wait([
    queryUpcItemDb(),
    ...openFactsEndpoints.map((e) => queryOpenFacts(e.$1, e.$2)),
    queryRetailWebSearch(),
    queryBarcodeList(),
    queryGoUpc(),
    queryGs1DataKart(),
  ]).timeout(const Duration(milliseconds: 3200), onTimeout: () => []);

  return results;
}

Future<Map<String, String>?> fetchOpenBeautyFacts(String barcode) async {
  final list = await resolveBarcodeOnlineMulti(barcode);
  if (list.isNotEmpty) {
    final first = list.first;
    return {
      'name': first['name']?.toString() ?? '',
      'brand': first['brand']?.toString() ?? '',
      'category': first['category']?.toString() ?? 'Cosmetics',
      'price': (first['price']?.toString() ?? '0.0'),
    };
  }
  return null;
}

// ==========================================
// DUAL-STOCK / MULTI-RATE RETIREMENT & PERSISTENCE
// ==========================================
List<double> extractDualRates(Map<String, dynamic> item) {
  final Set<double> rates = {};
  double primary = (item['price'] as num?)?.toDouble() ?? 0.0;
  if (primary > 0) rates.add(primary);

  if (item['dual_rates'] is List) {
    for (var r in (item['dual_rates'] as List)) {
      double d = (r as num).toDouble();
      if (d > 0) rates.add(d);
    }
  }

  final desc = item['description']?.toString() ?? '';
  if (desc.startsWith('{') && desc.contains('dual_rates')) {
    try {
      final parsed = json.decode(desc);
      if (parsed is Map && parsed['dual_rates'] is List) {
        for (var r in (parsed['dual_rates'] as List)) {
          double d = (r as num).toDouble();
          if (d > 0) rates.add(d);
        }
      }
    } catch (_) {}
  }

  final list = rates.toList();
  list.sort();
  return list;
}

// ==========================================
// AUTO-INGESTION INTO SUPABASE
// ==========================================
Future<void> autoIngestProductToDatabase({
  required String barcode,
  required String name,
  String brand = '',
  String category = 'Cosmetics',
  double price = 0.0,
  List<double>? dualRates,
}) async {
  final clean = barcode.trim();
  if (clean.isEmpty) return;
  final cleanName = cleanItemName(name, barcode: clean).isNotEmpty
      ? cleanItemName(name, barcode: clean)
      : '';

  // CRITICAL FIX: NEVER save uncatalogued raw barcodes or price 0 items into inventory!
  if (cleanName.isEmpty || cleanName == clean || price <= 0) {
    return;
  }

  try {
    Map<String, dynamic> payload = {
      'item_code': clean,
      'item_name': cleanName,
      'company_barcode': clean,
      'price': price,
      'mrp': price,
      'stock_qty': 10,
      'shelf_location': 'PENDING',
      'category': category.isNotEmpty ? category : 'Cosmetics',
      'is_online': true,
    };
    if (dualRates != null && dualRates.length > 1) {
      payload['description'] = json.encode({'dual_rates': dualRates});
    }

    await Supabase.instance.client.from('inventory').upsert(payload, onConflict: 'item_code');
  } catch (_) {
    try {
      await Supabase.instance.client.from('inventory').upsert({
        'item_code': clean,
        'item_name': cleanName,
        'price': price,
      });
    } catch (_) {}
  }
}

Future<void> updateCatalogItemDualRates({
  required String itemCode,
  required double primaryPrice,
  required List<double> dualRates,
}) async {
  try {
    Map<String, dynamic> descObj = {};
    if (dualRates.length > 1) {
      descObj['dual_rates'] = dualRates;
    }
    final jsonDesc = dualRates.length > 1 ? json.encode(descObj) : null;

    await Supabase.instance.client.from('inventory').update({
      'price': primaryPrice,
      'description': jsonDesc,
    }).eq('item_code', itemCode);
  } catch (e) {
    debugPrint("Error updating catalog dual rates: $e");
  }
}

// ==========================================
// UNASSIGNED / PENDING SCANNED ITEMS MANAGER
// (Scanned during sales or stocktake, saved to review & assign later)
// ==========================================
class PendingItemsManager {
  static List<Map<String, dynamic>> items = [];

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('pending_scanned_items');
      if (str != null && str.isNotEmpty) {
        final decoded = json.decode(str);
        if (decoded is List) {
          items = List<Map<String, dynamic>>.from(decoded).map((item) {
            final m = Map<String, dynamic>.from(item);
            m['name'] = cleanItemName(m['name']?.toString(), barcode: m['barcode']?.toString());
            return m;
          }).toList();
        }
      }
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_scanned_items', json.encode(items));
    } catch (_) {}
  }

  static void addPending({
    required String barcode,
    required String name,
    double price = 0.0,
    String brand = '',
    String category = 'Cosmetics',
  }) {
    final clean = barcode.trim();
    if (clean.isEmpty) return;
    String cleanName = cleanItemName(name, barcode: clean);
    if (cleanName.isEmpty) cleanName = clean;
    final index = items.indexWhere((p) => (p['barcode'] ?? '').toString().trim().toUpperCase() == clean.toUpperCase());
    final entry = {
      'barcode': clean,
      'name': cleanName,
      'brand': brand,
      'price': price,
      'category': category,
      'scanned_at': DateTime.now().toIso8601String(),
    };
    if (index >= 0) {
      if (cleanName.isNotEmpty &&
          cleanName != clean &&
          !cleanName.toLowerCase().startsWith("unassigned") &&
          !cleanName.toLowerCase().startsWith("barcode") &&
          !cleanName.toLowerCase().startsWith("item ") &&
          !cleanName.toLowerCase().startsWith("general item")) {
        items[index]['name'] = cleanName;
      }
      if (price > 0) {
        items[index]['price'] = price;
      }
      if (brand.isNotEmpty) {
        items[index]['brand'] = brand;
      }
    } else {
      items.insert(0, entry);
    }
    save();
  }

  static Map<String, dynamic>? find(String barcode) {
    final clean = barcode.trim();
    if (clean.isEmpty) return null;
    final index = items.indexWhere((p) => (p['barcode'] ?? '').toString().trim().toUpperCase() == clean.toUpperCase());
    return index >= 0 ? items[index] : null;
  }

  static void remove(String barcode) {
    if (barcode.trim().isEmpty) return;
    items.removeWhere((p) => (p['barcode'] ?? '').toString().trim().toUpperCase() == barcode.trim().toUpperCase());
    save();
  }

  static void clear() {
    items.clear();
    save();
  }
}

// ==========================================
// PENDING RATE CHANGES MANAGER
// (Rates manually adjusted during sales; review & approve in Item Catalog)
// ==========================================
class PendingRateChangesManager {
  static List<Map<String, dynamic>> items = [];

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString('pending_rate_changes');
      if (str != null && str.isNotEmpty) {
        final decoded = json.decode(str);
        if (decoded is List) {
          items = List<Map<String, dynamic>>.from(decoded);
        }
      }
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_rate_changes', json.encode(items));
    } catch (_) {}
  }

  static void addRateChange({
    required String itemCode,
    required String barcode,
    required String itemName,
    required double oldRate,
    required double newRate,
  }) {
    if (itemCode.isEmpty || (oldRate - newRate).abs() < 0.01) return;
    final cleanCode = itemCode.trim().toUpperCase();
    final index = items.indexWhere((p) => (p['item_code'] ?? '').toString().trim().toUpperCase() == cleanCode);
    final entry = {
      'item_code': itemCode.trim(),
      'barcode': barcode.trim(),
      'item_name': itemName.trim(),
      'old_rate': oldRate,
      'new_rate': newRate,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (index >= 0) {
      items[index] = entry;
    } else {
      items.insert(0, entry);
    }
    save();
  }

  static void remove(String itemCode) {
    if (itemCode.trim().isEmpty) return;
    items.removeWhere((p) => (p['item_code'] ?? '').toString().trim().toUpperCase() == itemCode.trim().toUpperCase());
    save();
  }

  static void clear() {
    items.clear();
    save();
  }
}

// ==========================================
// ITEM CODES & RATES (INVENTORY MAPPING)
// ==========================================
class ItemCatalogScreen extends StatefulWidget {
  final bool selectMode;
  const ItemCatalogScreen({Key? key, this.selectMode = false}) : super(key: key);

  @override
  State<ItemCatalogScreen> createState() => _ItemCatalogScreenState();
}

class _ItemCatalogScreenState extends State<ItemCatalogScreen> {
  bool isLoading = true;
  List<Map<String, dynamic>> items = [];
  String searchQuery = "";
  String stockFilter = "all"; // 'all', 'low', 'out'


  // Last used code components for rapid sequential shelf entry
  static String _lastRack = "01";
  static String _lastCol = "03";
  static String _lastRow = "C";
  static int _lastItemNum = 134;

  @override
  void initState() {
    super.initState();
    _loadLastUsedCode();
    _fetchInventory();
    PendingItemsManager.load().then((_) {
      if (mounted) setState(() {});
    });
    PendingRateChangesManager.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _loadLastUsedCode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _lastRack = prefs.getString('last_rack') ?? "01";
      _lastCol = prefs.getString('last_col') ?? "03";
      _lastRow = prefs.getString('last_row') ?? "C";
      _lastItemNum = prefs.getInt('last_item_num') ?? 134;
    });
  }

  void _fetchInventory() async {
    setState(() => isLoading = true);
    try {
      final data = await Supabase.instance.client.from('inventory').select().order('item_code');
      setState(() {
        items = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching items: $e")));
        setState(() => isLoading = false);
      }
    }
  }

  void _saveOrUpdateItem({
    required String code,
    required String name,
    required double price,
    String? companyBarcode,
    String? shelfLocation,
    String? itemNumber,
    String? category,
    double? mrp,
    int? stockQty,
    bool isOnline = true,
  }) async {
    try {
      final Map<String, dynamic> fullData = {
        'item_code': code,
        'item_name': name,
        'price': price,
        'company_barcode': companyBarcode ?? '',
        'shelf_location': shelfLocation ?? '',
        'item_number': itemNumber ?? '',
        'category': category ?? 'Cosmetics',
        'mrp': mrp ?? price,
        'stock_qty': stockQty ?? 10,
        'is_online': isOnline,
      };

      try {
        await Supabase.instance.client.from('inventory').upsert(fullData);
      } catch (_) {
        // Fallback if schema migration hasn't been run yet
        await Supabase.instance.client.from('inventory').upsert({
          'item_code': code,
          'item_name': name,
          'price': price,
        });
      }

      // Update last used components
      if (shelfLocation != null && shelfLocation.contains('-')) {
        final parts = shelfLocation.split('-');
        if (parts.isNotEmpty) _lastRack = parts[0];
        if (parts.length > 1) _lastCol = parts[1];
        if (parts.length > 2) _lastRow = parts[2];
      } else {
        final parts = code.split('-');
        if (parts.isNotEmpty) _lastRack = parts[0];
        if (parts.length > 1) _lastCol = parts[1];
        if (parts.length > 2) _lastRow = parts[2];
      }
      if (itemNumber != null && itemNumber.isNotEmpty) {
        final numPart = int.tryParse(itemNumber);
        if (numPart != null) _lastItemNum = numPart;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_rack', _lastRack);
      await prefs.setString('last_col', _lastCol);
      await prefs.setString('last_row', _lastRow);
      await prefs.setInt('last_item_num', _lastItemNum);

      // If an item was previously saved with shelf PENDING under its barcode as item_code,
      // and is now being assigned a proper shelf code (code != companyBarcode), delete the temporary pending record.
      if (companyBarcode != null && companyBarcode.isNotEmpty && companyBarcode != code) {
        try {
          await Supabase.instance.client.from('inventory').delete().eq('item_code', companyBarcode);
        } catch (_) {}
      }

      // Also upsert into master_catalog if name is provided and company barcode is present
      if (companyBarcode != null && companyBarcode.isNotEmpty && name.isNotEmpty && name != companyBarcode) {
        try {
          await Supabase.instance.client.from('master_catalog').upsert({
            'barcode': companyBarcode,
            'product_name': name,
            'category': category ?? 'Cosmetics',
            'mrp': mrp ?? price,
          }, onConflict: 'barcode');
        } catch (_) {}
      }

      // Remove from pending scanned queue since it is now assigned and saved to shop stock!
      PendingItemsManager.remove(companyBarcode ?? '');
      PendingItemsManager.remove(code);
      setState(() {});

      _fetchInventory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Saved: $code ($name)"),
            action: SnackBarAction(
              label: "PRINT LABEL",
              textColor: Colors.amberAccent,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BarcodeLabelPrinterScreen(
                      initialCode: code,
                      initialName: name,
                      initialPrice: price,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save Error: $e")));
      }
    }
  }

  void _deleteItem(String code) async {
    try {
      await Supabase.instance.client.from('inventory').delete().eq('item_code', code);
      _fetchInventory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Item deleted")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete Error: $e")));
      }
    }
  }

  void _updateStock(String code, int newQty) async {
    if (newQty < 0) newQty = 0;
    setState(() {
      final idx = items.indexWhere((it) => it['item_code'] == code);
      if (idx != -1) {
        items[idx]['stock_qty'] = newQty;
      }
    });
    try {
      await Supabase.instance.client
          .from('inventory')
          .update({'stock_qty': newQty})
          .eq('item_code', code);
    } catch (_) {}
  }

  Future<void> _retireOldRateInCatalog(Map<String, dynamic> item, double oldRateToRemove, double newPrimaryRate) async {
    final itemCode = item['item_code']?.toString() ?? '';
    if (itemCode.isEmpty) return;

    Map<String, dynamic> descObj = {};
    final curDesc = item['description']?.toString() ?? '';
    if (curDesc.startsWith('{')) {
      try { descObj = json.decode(curDesc); } catch (_) {}
    } else if (curDesc.isNotEmpty) {
      descObj['notes'] = curDesc;
    }

    List<double> currentDual = extractDualRates(item);
    currentDual.removeWhere((r) => (r - oldRateToRemove).abs() < 0.01);
    if (!currentDual.contains(newPrimaryRate)) {
      currentDual.add(newPrimaryRate);
    }
    final remainingDual = currentDual.length <= 1 ? <double>[] : currentDual;
    descObj['dual_rates'] = remainingDual;
    final jsonDesc = json.encode(descObj);

    try {
      await Supabase.instance.client.from('inventory').update({
        'price': newPrimaryRate,
        'description': jsonDesc,
      }).eq('item_code', itemCode);

      setState(() {
        item['price'] = newPrimaryRate;
        item['description'] = jsonDesc;
        item['dual_rates'] = remainingDual;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ Retired ₹${oldRateToRemove % 1 == 0 ? oldRateToRemove.toInt() : oldRateToRemove}! Sole rate is now ₹${newPrimaryRate % 1 == 0 ? newPrimaryRate.toInt() : newPrimaryRate}."),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error updating rate: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showQuickStockDialog(Map<String, dynamic> item) {
    final code = item['item_code']?.toString() ?? '';
    final name = item['item_name']?.toString() ?? 'Item';
    final currentQty = (item['stock_qty'] as num?)?.toInt() ?? 0;
    final ctrl = TextEditingController(text: currentQty.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.inventory_2, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("📍 Shelf / Code: $code", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo, fontSize: 13)),
            const SizedBox(height: 4),
            Text("Current Stock: $currentQty pcs", style: const TextStyle(color: Colors.black54, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Total Stock Quantity (pcs)",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
            ),
            const SizedBox(height: 12),
            const Text("Quick Add to Stock:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text("+1 pc"),
                  backgroundColor: Colors.blue.shade50,
                  onPressed: () {
                    final val = (int.tryParse(ctrl.text) ?? currentQty) + 1;
                    ctrl.text = val.toString();
                  },
                ),
                ActionChip(
                  label: const Text("+5 pcs"),
                  backgroundColor: Colors.blue.shade50,
                  onPressed: () {
                    final val = (int.tryParse(ctrl.text) ?? currentQty) + 5;
                    ctrl.text = val.toString();
                  },
                ),
                ActionChip(
                  label: const Text("+10 pcs"),
                  backgroundColor: Colors.blue.shade50,
                  onPressed: () {
                    final val = (int.tryParse(ctrl.text) ?? currentQty) + 10;
                    ctrl.text = val.toString();
                  },
                ),
                ActionChip(
                  label: const Text("+25 (Carton)"),
                  backgroundColor: Colors.amber.shade50,
                  onPressed: () {
                    final val = (int.tryParse(ctrl.text) ?? currentQty) + 25;
                    ctrl.text = val.toString();
                  },
                ),
                ActionChip(
                  label: const Text("+50 (Box)"),
                  backgroundColor: Colors.green.shade50,
                  onPressed: () {
                    final val = (int.tryParse(ctrl.text) ?? currentQty) + 50;
                    ctrl.text = val.toString();
                  },
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newQty = int.tryParse(ctrl.text.trim()) ?? currentQty;
              Navigator.pop(ctx);
              _updateStock(code, newQty);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Updated stock for $name: $newQty pcs")),
                );
              }
            },
            child: const Text("SAVE STOCK"),
          ),
        ],
      ),
    );
  }

  // Fast Barcode Scanning with Master Catalog Recognition
  void _scanBarcodeToEditOrAdd() async {
    final scannedCode = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );
    if (scannedCode != null && scannedCode is String && scannedCode.isNotEmpty) {
      final clean = scannedCode.trim();

      // 1. First check active shop inventory for matches
      final List<Map<String, dynamic>> shopMatches = [];
      final cleanUp = clean.toUpperCase();
      final cleanNoDash = cleanUp.replaceAll('-', '').replaceAll(' ', '');

      for (var it in items) {
        final itCode = (it['item_code'] ?? '').toString().toUpperCase();
        final itBar = (it['company_barcode'] ?? '').toString().toUpperCase();
        final itShelf = (it['shelf_location'] ?? '').toString().toUpperCase();
        final itItemNum = (it['item_number'] ?? '').toString().toUpperCase();
        final itFullShelf = itItemNum.isNotEmpty ? '$itShelf-$itItemNum' : itShelf;

        if (itCode == cleanUp ||
            itBar == cleanUp ||
            itShelf == cleanUp ||
            itFullShelf == cleanUp ||
            itCode.replaceAll('-', '') == cleanNoDash ||
            itFullShelf.replaceAll('-', '') == cleanNoDash ||
            itShelf.replaceAll('-', '') == cleanNoDash) {
          shopMatches.add(it);
        }
      }

      if (shopMatches.length == 1) {
        _showAddEditDialog(shopMatches.first);
        return;
      } else if (shopMatches.length > 1) {
        _showCatalogConflictSheet(clean, shopMatches);
        return;
      }

      // 2. NOT in shop inventory! Check Master Reference Catalog:
      Map<String, dynamic>? masterMatch;

      // Check local master cosmetics catalog (Instant O(1) hash map lookup)
      final c = findCosmeticByBarcode(clean);
      if (c != null) {
        masterMatch = {
          'name': c['name'],
          'price': c['price'],
          'category': c['category'],
          'brand': c['brand'] ?? '',
        };
      }

      // Check Supabase master_catalog if not found locally
      if (masterMatch == null) {
        try {
          final res = await Supabase.instance.client
              .from('master_catalog')
              .select()
              .eq('barcode', clean)
              .maybeSingle();
          if (res != null) {
            masterMatch = {
              'name': res['product_name'],
              'price': (res['mrp'] as num?)?.toDouble() ?? 0.0,
              'category': res['category'] ?? 'Cosmetics',
              'brand': res['brand'] ?? '',
            };
          }
        } catch (_) {}
      }

      // Check Multi-API online resolver if 8+ digit commercial barcode
      final digitsOnly = clean.replaceAll(RegExp(r'[^0-9]'), '');
      if (masterMatch == null && clean.length >= 8 && digitsOnly.length == clean.length) {
        final onlineResults = await resolveBarcodeOnlineMulti(clean);
        if (onlineResults.length == 1) {
          masterMatch = onlineResults.first;
        } else if (onlineResults.length > 1) {
          if (mounted) {
            _showOnlineConflictDialogInCatalog(clean, onlineResults);
            return;
          }
        }
      }

      // 3. Recognized in Master Catalog / Online OR New Item:
      if (masterMatch != null) {
        PendingItemsManager.addPending(
          barcode: clean,
          name: masterMatch['name'] ?? '',
          brand: masterMatch['brand'] ?? '',
          price: (masterMatch['price'] as num?)?.toDouble() ?? 0.0,
          category: masterMatch['category'] ?? 'Cosmetics',
        );
        double mPrice = (masterMatch['price'] as num?)?.toDouble() ?? 0.0;
        if (mPrice > 0) {
          autoIngestProductToDatabase(
            barcode: clean,
            name: masterMatch['name'] ?? '',
            brand: masterMatch['brand'] ?? '',
            price: mPrice,
            category: masterMatch['category'] ?? 'Cosmetics',
          );
        }
        setState(() {});
        if (mounted) {
          _showRecognizedMasterProductDialog(clean, masterMatch);
        }
      } else {
        // Unrecognized barcode: Do NOT auto-save price 0!
        PendingItemsManager.addPending(
          barcode: clean,
          name: clean,
          brand: '',
          price: 0.0,
          category: 'General',
        );
        setState(() {});
        if (mounted) {
          if (clean.length >= 8 && digitsOnly.length == clean.length) {
            _showAddEditDialog(null, null, clean, null, clean);
          } else {
            _showAddEditDialog(null, clean, clean);
          }
        }
      }
    }
  }

  void _showOnlineConflictDialogInCatalog(String barcode, List<Map<String, dynamic>> results) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Icon(Icons.travel_explore, color: Colors.blue.shade900, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Select Matching Product", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text("Barcode: $barcode", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 12),
                const Text("Multiple possible options found online. Tap to assign to shelf:", style: TextStyle(fontSize: 13, color: Colors.black87)),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, idx) {
                      final prod = results[idx];
                      final name = prod['name'] ?? '';
                      final price = (prod['price'] as num?)?.toDouble() ?? 0.0;
                      final source = prod['source'] ?? 'Online';

                      return ListTile(
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text("Source: $source", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        trailing: price > 0
                            ? Text("₹${price % 1 == 0 ? price.toInt() : price}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF10B981)))
                            : const Text("Enter Rate", style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _showRecognizedMasterProductDialog(barcode, prod);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCatalogConflictSheet(String query, List<Map<String, dynamic>> matches) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.shelves, color: Colors.amber.shade900, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${matches.length} Products at Shelf",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "Location / Code: $query",
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  "Tap a product to edit its details:",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: matches.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, idx) {
                      final it = matches[idx];
                      final name = it['item_name'] ?? 'Unnamed Item';
                      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                      final shelf = it['shelf_location'] ?? '';
                      final itemNum = it['item_number'] ?? '';
                      final barcode = it['company_barcode'] ?? '';
                      final cat = it['category'] ?? '';

                      return InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _showAddEditDialog(it);
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFF6366F1).withOpacity(0.1),
                                child: Text(
                                  itemNum.isNotEmpty ? itemNum : "${idx + 1}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF6366F1),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        if (shelf.isNotEmpty)
                                          Text("📍 Shelf: $shelf", style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                        if (barcode.isNotEmpty)
                                          Text("🏷️ $barcode", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                        if (cat.isNotEmpty)
                                          Text("• $cat", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green.shade200),
                                ),
                                child: Text(
                                  "₹${price % 1 == 0 ? price.toInt() : price}",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green.shade800),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right, color: Colors.grey),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAddEditDialog(null, query);
                  },
                  icon: const Icon(Icons.add),
                  label: Text("Add Another Product to $query"),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRecognizedMasterProductDialog(String barcode, Map<String, dynamic> prod) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.auto_awesome, color: Colors.amber, size: 24),
            SizedBox(width: 8),
            Expanded(child: Text("Product Recognized!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(prod['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 4),
                  if ((prod['brand'] ?? '').toString().isNotEmpty)
                    Text("Brand: ${prod['brand']}", style: const TextStyle(color: Colors.black54, fontSize: 13)),
                  Text("Barcode: $barcode", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  if ((prod['price'] ?? 0.0) > 0)
                    Text("Catalog MRP: ₹${prod['price']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "⚠️ This product is in the Master Reference Database, but is NOT in your shop inventory yet.",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(height: 6),
            const Text(
              "Would you like to assign a shelf location, set your shop selling rate, and add it to your inventory?",
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Kept in Pending List: ${prod['name']}"),
                  backgroundColor: const Color(0xFFD97706),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text("KEEP IN PENDING", style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_location_alt, size: 16),
            label: const Text("+ ASSIGN SHELF & SAVE"),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _showAddEditDialog(
                null,
                null,
                prod['name'],
                (prod['price'] as num?)?.toDouble() ?? 0.0,
                barcode,
              );
            },
          ),
        ],
      ),
    );
  }

  // Cosmetics Database Dialog (Browse & 1-tap Use / Sync Master Catalog)
  void _showCosmeticsCatalogDialog() {
    String filterCategory = "All";
    String search = "";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final cats = ["All", "Eyes", "Lips", "Face", "Nails", "Skincare", "Hair", "Bangles", "Jewelry", "Accessories"];
          final filteredCosmetics = cosmeticDatabase.where((c) {
            final matchCat = filterCategory == "All" || c["category"] == filterCategory;
            final matchSearch = search.isEmpty || c["name"].toString().toLowerCase().contains(search.toLowerCase());
            return matchCat && matchSearch;
          }).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.pinkAccent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text("Master Reference Database", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Search cosmetics, kajal, bangles...",
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) => setModalState(() => search = val.trim()),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: cats.map((cat) => Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: ChoiceChip(
                          label: Text(cat, style: const TextStyle(fontSize: 12)),
                          selected: filterCategory == cat,
                          selectedColor: Colors.pinkAccent.withOpacity(0.2),
                          onSelected: (sel) {
                            if (sel) setModalState(() => filterCategory = cat);
                          },
                        ),
                      )).toList(),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredCosmetics.length,
                      itemBuilder: (context, i) {
                        final it = filteredCosmetics[i];
                        final hasBarcode = (it["barcode"] ?? '').toString().isNotEmpty;
                        return ListTile(
                          dense: true,
                          title: Text(it["name"], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("${it["category"]} • MRP ₹${it["price"]}${hasBarcode ? ' • 🏭 ${it["barcode"]}' : ''}"),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.pinkAccent,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showAddEditDialog(
                                null,
                                null,
                                it["name"] as String,
                                (it["price"] as num).toDouble(),
                                it["barcode"] as String?,
                              );
                            },
                            child: const Text("USE", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("CLOSE"),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_sync, size: 16),
                label: const Text("SYNC TO MASTER CATALOG"),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF111827), foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(ctx);
                  _syncToMasterCatalog();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _syncToMasterCatalog() async {
    setState(() => isLoading = true);
    try {
      int synced = 0;
      for (var item in cosmeticDatabase) {
        final bar = (item['barcode'] ?? item['name']).toString();
        try {
          await Supabase.instance.client.from('master_catalog').upsert({
            'barcode': bar,
            'product_name': item['name'],
            'brand': item['brand'] ?? 'Generic',
            'category': item['category'] ?? 'Cosmetics',
            'mrp': item['price'],
          });
          synced++;
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Master Reference Catalog updated ($synced products). None were added to your shop inventory."),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Sync Error: $e")));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showAddEditDialog([
    Map<String, dynamic>? existing,
    String? prefilledCode,
    String? prefilledName,
    double? prefilledPrice,
    String? prefilledCompanyBarcode,
  ]) {
    final bool isEdit = existing != null;

    String initialCompanyBarcode = isEdit
        ? (existing['company_barcode'] ?? '')
        : (prefilledCompanyBarcode ?? '');

    String initialShelfCode = "";
    if (isEdit) {
      String shelf = (existing['shelf_location'] ?? '').toString();
      String num = (existing['item_number'] ?? '').toString();
      if (shelf.isNotEmpty && shelf.toUpperCase() != 'PENDING') {
        initialShelfCode = num.isNotEmpty ? "$shelf-$num" : shelf;
      } else {
        // Item was pending shelf assignment: auto-suggest next available sequential shelf code!
        initialShelfCode = "${_lastRack.padLeft(2, '0')}-${_lastCol.padLeft(2, '0')}-${_lastRow.toUpperCase()}-${_lastItemNum + 1}";
        if (initialCompanyBarcode.isEmpty && (existing['item_code'] ?? '').toString().length >= 8) {
          initialCompanyBarcode = (existing['item_code'] ?? '').toString();
        }
      }
    } else if (prefilledCode != null && prefilledCode.isNotEmpty && !prefilledCode.toUpperCase().startsWith('890') && prefilledCode.toUpperCase() != 'PENDING') {
      initialShelfCode = prefilledCode;
    } else {
      initialShelfCode = "${_lastRack.padLeft(2, '0')}-${_lastCol.padLeft(2, '0')}-${_lastRow.toUpperCase()}-${_lastItemNum + 1}";
      if (prefilledCode != null && prefilledCode.isNotEmpty && (prefilledCode.length >= 8 || prefilledCode.startsWith('890')) && initialCompanyBarcode.isEmpty) {
        initialCompanyBarcode = prefilledCode;
      }
    }

    String initialName = isEdit ? (existing['item_name'] ?? '') : (prefilledName ?? '');
    // If name is equal to raw barcode or placeholder, clear it so user can easily enter product name
    if (initialName == initialCompanyBarcode ||
        initialName == initialShelfCode ||
        initialName.toLowerCase() == "general item" ||
        initialName.toLowerCase().startsWith("unassigned") ||
        initialName.toLowerCase().startsWith("barcode ")) {
      initialName = "";
    }

    final companyBarcodeCtrl = TextEditingController(text: initialCompanyBarcode);
    final shelfCodeCtrl = TextEditingController(text: initialShelfCode);
    final nameCtrl = TextEditingController(text: initialName);
    final priceCtrl = TextEditingController(
      text: isEdit
          ? (existing['price']?.toString() ?? '')
          : (prefilledPrice != null ? (prefilledPrice % 1 == 0 ? prefilledPrice.toInt().toString() : prefilledPrice.toString()) : ''),
    );
    final mrpCtrl = TextEditingController(
      text: isEdit
          ? (existing['mrp']?.toString() ?? existing['price']?.toString() ?? '')
          : (prefilledPrice != null ? (prefilledPrice % 1 == 0 ? prefilledPrice.toInt().toString() : prefilledPrice.toString()) : ''),
    );
    final stockCtrl = TextEditingController(
      text: isEdit ? (existing['stock_qty']?.toString() ?? '10') : '10',
    );
    String selectedCategory = isEdit ? (existing['category'] ?? 'Cosmetics') : 'Cosmetics';
    bool isOnline = isEdit ? (existing['is_online'] ?? true) : true;
    bool isFetchingObf = false;

    List<Map<String, dynamic>> suggestions = [];

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final breakdown = ShelfCodeBreakdown.parse(shelfCodeCtrl.text);

          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEdit ? "Edit Item & Rate" : "Add Item (Dual Barcodes)",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blueAccent),
                  ),
                  child: const Text("Retail + Online", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. COMPANY BARCODE (Optional / Commercial EAN-13)
                  TextField(
                    controller: companyBarcodeCtrl,
                    decoration: InputDecoration(
                      labelText: "Company Barcode (Optional)",
                      hintText: "e.g. 8901030732585 (from box)",
                      helperText: "Leave blank for unbranded items (bangles/loose)",
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isFetchingObf)
                            const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.cloud_download, color: Colors.teal, size: 20),
                              tooltip: "Fetch Name from Open Facts Cloud (<2s)",
                              onPressed: () async {
                                final bar = companyBarcodeCtrl.text.trim();
                                if (bar.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter barcode first to fetch details")));
                                  return;
                                }
                                setDialogState(() => isFetchingObf = true);
                                final obf = await fetchOpenBeautyFacts(bar);
                                setDialogState(() {
                                  isFetchingObf = false;
                                  if (obf != null && obf['name'] != null && obf['name']!.isNotEmpty) {
                                    nameCtrl.text = obf['name']!;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cloud Fetched: ${obf['name']}")));
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No match in Open Facts Cloud (<2s). Enter name manually.")));
                                  }
                                });
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent, size: 20),
                            tooltip: "Scan Box Barcode",
                            onPressed: () async {
                              final scanned = await Navigator.push(
                                ctx,
                                MaterialPageRoute(
                                  builder: (_) => const QRScannerScreen(title: "Scan Product Barcode"),
                                ),
                              );
                              if (scanned != null && scanned is String && scanned.isNotEmpty) {
                                final clean = scanned.trim();
                                setDialogState(() => companyBarcodeCtrl.text = clean);
                                // Attempt auto-fetch name
                                setDialogState(() => isFetchingObf = true);
                                final obf = await fetchOpenBeautyFacts(clean);
                                setDialogState(() {
                                  isFetchingObf = false;
                                  if (obf != null && obf['name'] != null && obf['name']!.isNotEmpty) {
                                    nameCtrl.text = obf['name']!;
                                  }
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 2. UNIFIED SHELF LOCATION & ITEM CODE (Automatic dashes!)
                  TextField(
                    controller: shelfCodeCtrl,
                    inputFormatters: [ShelfCodeInputFormatter()],
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: "Shelf Location & Item Code",
                      hintText: "e.g. 01-03-C-134 or 01-03-C",
                      helperText: "Format: Rack(01)-Col(03)-Row(C)-Item#(134)",
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code, color: Colors.indigo),
                        tooltip: "Scan Shelf Sticker (Barcode or QR)",
                        onPressed: () async {
                          final scanned = await Navigator.push(
                            ctx,
                            MaterialPageRoute(
                              builder: (_) => const QRScannerScreen(title: "Scan Shelf Barcode or QR"),
                            ),
                          );
                          if (scanned != null && scanned is String && scanned.isNotEmpty) {
                            final clean = scanned.trim();
                            final digitsOnly = clean.replaceAll(RegExp(r'[^0-9]'), '');
                            if (clean.length >= 8 && digitsOnly.length == clean.length) {
                              setDialogState(() => companyBarcodeCtrl.text = clean);
                              setDialogState(() => isFetchingObf = true);
                              final obf = await fetchOpenBeautyFacts(clean);
                              setDialogState(() {
                                isFetchingObf = false;
                                if (obf != null && obf['name'] != null && obf['name']!.isNotEmpty && nameCtrl.text.isEmpty) {
                                  nameCtrl.text = obf['name']!;
                                }
                              });
                            } else {
                              final parsed = ShelfCodeBreakdown.parse(clean);
                              setDialogState(() {
                                shelfCodeCtrl.text = parsed.fullCode.isNotEmpty
                                    ? parsed.fullCode
                                    : clean.toUpperCase();
                              });
                            }
                          }
                        },
                      ),
                    ),
                  ),

                  // Live Breakdown Banner (Shelf Location vs Item #)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: breakdown.itemNumber.isNotEmpty ? Colors.green.shade50 : Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: breakdown.itemNumber.isNotEmpty ? Colors.green.shade300 : Colors.blue.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          breakdown.itemNumber.isNotEmpty ? Icons.shelves : Icons.inventory_2,
                          size: 16,
                          color: breakdown.itemNumber.isNotEmpty ? Colors.green.shade800 : Colors.blue.shade800,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            breakdown.itemNumber.isNotEmpty
                                ? "📍 Shelf: ${breakdown.shelfLocation}  |  🏷️ Item #: ${breakdown.itemNumber}"
                                : "📍 Shelf: ${breakdown.shelfLocation.isNotEmpty ? breakdown.shelfLocation : 'N/A'}  |  📦 Shelf Only (Item # Blank)",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: breakdown.itemNumber.isNotEmpty ? Colors.green.shade900 : Colors.blue.shade900,
                            ),
                          ),
                        ),
                        if (breakdown.itemNumber.isNotEmpty)
                          InkWell(
                            onTap: () {
                              setDialogState(() {
                                shelfCodeCtrl.text = breakdown.shelfLocation;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              child: const Text("Clear #", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black87)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 3. ITEM NAME (with cosmetic autocomplete chips)
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: "Item Name",
                      hintText: "Type product name (e.g. Lakme, Kajal...)",
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      setDialogState(() {
                        if (val.trim().length >= 2) {
                          suggestions = cosmeticDatabase
                              .where((c) => c["name"].toString().toLowerCase().contains(val.toLowerCase()))
                              .take(3)
                              .toList();
                        } else {
                          suggestions = [];
                        }
                      });
                    },
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: suggestions.map((s) => ActionChip(
                        backgroundColor: Colors.pink.shade50,
                        side: const BorderSide(color: Colors.pinkAccent),
                        avatar: const Icon(Icons.auto_awesome, size: 14, color: Colors.pinkAccent),
                        label: Text("${s['name']} (₹${s['price']})", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
                        onPressed: () {
                          setDialogState(() {
                            nameCtrl.text = s['name'];
                            double p = (s['price'] as num).toDouble();
                            priceCtrl.text = p % 1 == 0 ? p.toInt().toString() : p.toString();
                            mrpCtrl.text = priceCtrl.text;
                            selectedCategory = s['category'] ?? selectedCategory;
                            suggestions = [];
                          });
                        },
                      )).toList(),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // 4. PRICING: Selling Price & MRP
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: "Selling Price (₹)",
                            prefixText: "₹ ",
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            if (mrpCtrl.text.isEmpty) mrpCtrl.text = v;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: mrpCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: "MRP Price (₹)",
                            prefixText: "₹ ",
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 5. E-COMMERCE & ONLINE STORE SETTINGS
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Online Store & Inventory Details", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                value: selectedCategory,
                                isDense: true,
                                decoration: const InputDecoration(labelText: "Category", border: OutlineInputBorder(), isDense: true),
                                items: ["Cosmetics", "Eyes", "Lips", "Face", "Nails", "Skincare", "Hair", "Bangles", "Jewelry", "Accessories", "General"]
                                    .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13))))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setDialogState(() => selectedCategory = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: stockCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: "Stock Qty", isDense: true, border: OutlineInputBorder()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Sell on Online Shop", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Switch(
                              value: isOnline,
                              activeColor: Colors.blueAccent,
                              onChanged: (v) => setDialogState(() => isOnline = v),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text("CANCEL", style: TextStyle(color: Colors.black54)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                onPressed: () {
                  final bd = ShelfCodeBreakdown.parse(shelfCodeCtrl.text);
                  final companyBar = companyBarcodeCtrl.text.trim();
                  final name = nameCtrl.text.trim();
                  final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                  final mrp = double.tryParse(mrpCtrl.text.trim()) ?? price;
                  final stock = int.tryParse(stockCtrl.text.trim()) ?? 10;

                  if (name.isEmpty || price <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please fill Item Name and valid Rate")),
                    );
                    return;
                  }

                  // Determine primary code:
                  String primaryCode;
                  if (bd.itemNumber.isNotEmpty) {
                    primaryCode = bd.fullCode;
                  } else if (companyBar.isNotEmpty) {
                    primaryCode = companyBar;
                  } else if (bd.shelfLocation.isNotEmpty) {
                    primaryCode = bd.shelfLocation;
                  } else {
                    primaryCode = "${_lastRack}-${_lastCol}-${_lastRow}-${_lastItemNum + 1}";
                  }

                  Navigator.pop(dialogCtx);
                  _saveOrUpdateItem(
                    code: primaryCode,
                    name: name,
                    price: price,
                    companyBarcode: companyBar,
                    shelfLocation: bd.shelfLocation,
                    itemNumber: bd.itemNumber,
                    category: selectedCategory,
                    mrp: mrp,
                    stockQty: stock,
                    isOnline: isOnline,
                  );
                },
                child: Text(isEdit ? "UPDATE RATE" : "SAVE TO CLOUD", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingShelfItems = items.where((it) {
      final shelf = (it['shelf_location'] ?? '').toString().trim().toUpperCase();
      return shelf == 'PENDING' || shelf.isEmpty;
    }).toList();
    final lowStockItems = items.where((it) {
      final qty = (it['stock_qty'] as num?)?.toInt() ?? 0;
      return qty > 0 && qty <= 5;
    }).toList();
    final outOfStockItems = items.where((it) {
      final qty = (it['stock_qty'] as num?)?.toInt() ?? 0;
      return qty <= 0;
    }).toList();
    final dualRateItems = items.where((it) {
      return extractDualRates(it).length > 1;
    }).toList();

    final filtered = items.where((it) {
      final q = searchQuery.toLowerCase();
      final code = (it['item_code'] ?? '').toString().toLowerCase();
      final name = (it['item_name'] ?? '').toString().toLowerCase();
      final bar = (it['company_barcode'] ?? '').toString().toLowerCase();
      final matchesQuery = code.contains(q) || name.contains(q) || bar.contains(q);
      if (!matchesQuery) return false;

      final qty = (it['stock_qty'] as num?)?.toInt() ?? 0;
      if (stockFilter == "pending") {
        final shelf = (it['shelf_location'] ?? '').toString().trim().toUpperCase();
        return shelf == 'PENDING' || shelf.isEmpty;
      }
      if (stockFilter == "dual_rates") {
        return extractDualRates(it).length > 1;
      }
      if (stockFilter == "low") return qty > 0 && qty <= 5;
      if (stockFilter == "out") return qty <= 0;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectMode ? "Select Item for Bill" : "Item Codes & Rates", style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF111827),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: "Scan Barcode to Edit/Add",
            onPressed: _scanBarcodeToEditOrAdd,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: Colors.pinkAccent),
            tooltip: "Cosmetics Catalog",
            onPressed: _showCosmeticsCatalogDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "Refresh from cloud",
            onPressed: _fetchInventory,
          )
        ],
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: "fab_cosmetics",
            backgroundColor: Colors.pinkAccent,
            icon: const Icon(Icons.auto_awesome, color: Colors.white),
            label: const Text("Cosmetics", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: _showCosmeticsCatalogDialog,
          ),
          const SizedBox(width: 10),
          FloatingActionButton.extended(
            heroTag: "fab_add_code",
            backgroundColor: const Color(0xFF3B82F6),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text("Add Code", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => _showAddEditDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search by code (e.g. 01-03) or item name...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => searchQuery = ""),
                      ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                      tooltip: "Scan Barcode to Find/Edit",
                      onPressed: _scanBarcodeToEditOrAdd,
                    ),
                  ],
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
              onChanged: (val) => setState(() => searchQuery = val),
            ),
          ),
          // Stock Filters (All, Low Stock <=5, Out of Stock = 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text("All (${items.length})"),
                    selected: stockFilter == "all",
                    selectedColor: Colors.blueAccent,
                    labelStyle: TextStyle(color: stockFilter == "all" ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                    onSelected: (_) => setState(() => stockFilter = "all"),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text("⏳ Pending Shelf (${pendingShelfItems.length})"),
                    selected: stockFilter == "pending",
                    selectedColor: Colors.purple.shade700,
                    labelStyle: TextStyle(color: stockFilter == "pending" ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                    onSelected: (_) => setState(() => stockFilter = "pending"),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text("⚠️ Low Stock (${lowStockItems.length})"),
                    selected: stockFilter == "low",
                    selectedColor: Colors.amber.shade700,
                    labelStyle: TextStyle(color: stockFilter == "low" ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                    onSelected: (_) => setState(() => stockFilter = "low"),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text("🚫 Out of Stock (${outOfStockItems.length})"),
                    selected: stockFilter == "out",
                    selectedColor: Colors.redAccent,
                    labelStyle: TextStyle(color: stockFilter == "out" ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                    onSelected: (_) => setState(() => stockFilter = "out"),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text("🏷️ Dual Rates (${dualRateItems.length})"),
                    selected: stockFilter == "dual_rates",
                    selectedColor: Colors.purple.shade800,
                    labelStyle: TextStyle(color: stockFilter == "dual_rates" ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
                    onSelected: (_) => setState(() => stockFilter = "dual_rates"),
                  ),
                ],
              ),
            ),
          ),
          if (PendingRateChangesManager.items.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                border: Border.all(color: const Color(0xFF10B981)),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.price_change_outlined, color: Color(0xFF059669), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${PendingRateChangesManager.items.length} Rate Change${PendingRateChangesManager.items.length > 1 ? 's' : ''} to Approve",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF065F46)),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                        onPressed: () => setState(() => PendingRateChangesManager.clear()),
                        child: const Text("Clear All", style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Rates modified during sales. Approve catalog update or enable dual stock:",
                    style: TextStyle(fontSize: 11, color: Color(0xFF047857)),
                  ),
                  const SizedBox(height: 8),
                  ...PendingRateChangesManager.items.map((rc) {
                    final itemCode = (rc['item_code'] ?? '').toString();
                    final itemName = (rc['item_name'] ?? itemCode).toString();
                    final oldRate = (rc['old_rate'] as num?)?.toDouble() ?? 0.0;
                    final newRate = (rc['new_rate'] as num?)?.toDouble() ?? 0.0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                Text(
                                  "Catalog: ₹${oldRate % 1 == 0 ? oldRate.toInt() : oldRate} ➔ Billed: ₹${newRate % 1 == 0 ? newRate.toInt() : newRate}",
                                  style: const TextStyle(fontSize: 11, color: Color(0xFFBE185D), fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          Wrap(
                            spacing: 4,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () async {
                                  await updateCatalogItemDualRates(
                                    itemCode: itemCode,
                                    primaryPrice: newRate,
                                    dualRates: [],
                                  );
                                  setState(() {
                                    PendingRateChangesManager.remove(itemCode);
                                    _fetchInventory();
                                  });
                                },
                                child: Text("Approve ₹${newRate % 1 == 0 ? newRate.toInt() : newRate}", style: const TextStyle(fontSize: 11)),
                              ),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange.shade900,
                                  side: BorderSide(color: Colors.orange.shade400),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () async {
                                  await updateCatalogItemDualRates(
                                    itemCode: itemCode,
                                    primaryPrice: newRate,
                                    dualRates: [oldRate, newRate],
                                  );
                                  setState(() {
                                    PendingRateChangesManager.remove(itemCode);
                                    _fetchInventory();
                                  });
                                },
                                child: const Text("Dual Stock", style: TextStyle(fontSize: 11)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  setState(() => PendingRateChangesManager.remove(itemCode));
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(searchQuery.isEmpty ? "No Items Mapped Yet" : "No matching items found", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              const Text("Tap '+ Add Code' or 'Cosmetics' to map shelf codes to products and rates.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final code = item['item_code']?.toString() ?? '';
                          final name = item['item_name']?.toString() ?? '';
                          final price = (item['price'] as num?)?.toDouble() ?? 0.0;
                          final mrp = (item['mrp'] as num?)?.toDouble() ?? price;
                          final companyBar = (item['company_barcode'] ?? '').toString();
                          final shelfLoc = (item['shelf_location'] ?? '').toString();
                          final itemNum = (item['item_number'] ?? '').toString();
                          final isOnline = item['is_online'] == true;
                          final category = (item['category'] ?? '').toString();
                          final stockQty = (item['stock_qty'] as num?)?.toInt() ?? 10;

                          final isPending = shelfLoc.toUpperCase() == 'PENDING' || shelfLoc.isEmpty;
                          String displayLoc = isPending
                              ? "Pending Shelf"
                              : (shelfLoc.isNotEmpty
                                  ? (itemNum.isNotEmpty ? "$shelfLoc-$itemNum" : "$shelfLoc (Shelf Only)")
                                  : code);

                          return Card(
                            elevation: 1.5,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isPending ? Colors.amber.shade100 : Colors.blueAccent.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          isPending ? "⏳" : (displayLoc.length >= 2 ? displayLoc.substring(0, 2) : "##"),
                                          style: TextStyle(fontWeight: FontWeight.w900, color: isPending ? Colors.deepOrange : Colors.blueAccent, fontSize: 16),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    name.isNotEmpty ? name : "Unnamed Item",
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                  ),
                                                ),
                                                if (isOnline)
                                                  Container(
                                                    margin: const EdgeInsets.only(left: 4),
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.green.shade300)),
                                                    child: const Text("ONLINE", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green)),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              isPending ? "⏳ Status: Pending Shelf Assignment" : "📍 Shelf: $displayLoc",
                                              style: TextStyle(fontWeight: FontWeight.w600, color: isPending ? Colors.deepOrange.shade800 : Colors.indigo, fontSize: 12),
                                            ),
                                            if (isPending)
                                              Container(
                                                margin: const EdgeInsets.only(top: 4, bottom: 2),
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.shade50,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: Colors.amber.shade400),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: const [
                                                    Icon(Icons.hourglass_top, size: 12, color: Color(0xFFD97706)),
                                                    SizedBox(width: 4),
                                                    Text("Tap edit (✏️) to assign shelf code & finalize", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF92400E))),
                                                  ],
                                                ),
                                              ),
                                            if (companyBar.isNotEmpty)
                                              Text("🏭 Barcode: $companyBar", style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey.shade700, fontSize: 11)),
                                            if (category.isNotEmpty && category != "General")
                                              Text("🏷️ Category: $category", style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey.shade600, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text("₹${price.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.green)),
                                          if (mrp > price)
                                            Text("MRP ₹${mrp.toStringAsFixed(0)}", style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 10)),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.print, size: 18, color: Colors.green),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                tooltip: "Print Label",
                                                onPressed: () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => BarcodeLabelPrinterScreen(
                                                        initialCode: code,
                                                        initialName: name,
                                                        initialPrice: price,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(Icons.edit, size: 18, color: Colors.blueAccent),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: () => _showAddEditDialog(item),
                                              ),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: () => _deleteItem(code),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),

                                  // Dual-Rate Batch Banner & Retirement Actions
                                  if (extractDualRates(item).length > 1) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFAF5FF),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFC084FC)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.style, size: 14, color: Color(0xFF7E22CE)),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  "🏷️ Dual Stock Rates: ${extractDualRates(item).map((r) => '₹${r % 1 == 0 ? r.toInt() : r}').join(' & ')}",
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF6B21A8)),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: extractDualRates(item).map((rate) {
                                              final isPrimary = (rate - price).abs() < 0.01;
                                              return ActionChip(
                                                avatar: isPrimary
                                                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                                                    : const Icon(Icons.close, size: 13, color: Colors.red),
                                                label: Text(
                                                  isPrimary
                                                      ? "Primary: ₹${rate % 1 == 0 ? rate.toInt() : rate}"
                                                      : "Old Stock Finished? Clear ₹${rate % 1 == 0 ? rate.toInt() : rate}",
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: isPrimary ? Colors.white : Colors.red.shade900,
                                                  ),
                                                ),
                                                backgroundColor: isPrimary ? const Color(0xFF7E22CE) : Colors.red.shade50,
                                                side: BorderSide(color: isPrimary ? const Color(0xFF7E22CE) : Colors.red.shade200),
                                                onPressed: isPrimary
                                                    ? null
                                                    : () => _retireOldRateInCatalog(item, rate, price),
                                              );
                                            }).toList(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],

                                  // Quick Interactive Stock Adjustment Bar
                                  Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        InkWell(
                                          onTap: () => _showQuickStockDialog(item),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: stockQty <= 0
                                                  ? Colors.red.shade50
                                                  : (stockQty <= 5 ? Colors.amber.shade50 : Colors.green.shade50),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: stockQty <= 0
                                                    ? Colors.red.shade400
                                                    : (stockQty <= 5 ? Colors.amber.shade600 : Colors.green.shade600),
                                              ),
                                            ),
                                            child: Text(
                                              "Stock: $stockQty pcs ✏️",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                                color: stockQty <= 0
                                                    ? Colors.red.shade800
                                                    : (stockQty <= 5 ? Colors.amber.shade900 : Colors.green.shade900),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.redAccent),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: "-1 pc",
                                          onPressed: () => _updateStock(code, (stockQty - 1).clamp(0, 99999)),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, size: 18, color: Colors.green),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          tooltip: "+1 pc",
                                          onPressed: () => _updateStock(code, stockQty + 1),
                                        ),
                                        const SizedBox(width: 8),
                                        ActionChip(
                                          label: const Text("+5", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: Colors.blue.shade50,
                                          side: BorderSide(color: Colors.blue.shade200),
                                          onPressed: () => _updateStock(code, stockQty + 5),
                                        ),
                                        const SizedBox(width: 4),
                                        ActionChip(
                                          label: const Text("+10", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                          backgroundColor: Colors.blue.shade50,
                                          side: BorderSide(color: Colors.blue.shade200),
                                          onPressed: () => _updateStock(code, stockQty + 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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
  Map<String, Map<String, dynamic>> cloudInventory = {};
  
  void _syncInventoryFromCloud() async {
    try {
      final data = await Supabase.instance.client.from('inventory').select();
      if (mounted) {
        setState(() {
          cloudInventory.clear();
          for (var item in data) {
            String code = item['item_code'].toString();
            final dual = extractDualRates(item);
            cloudInventory[code] = {
              'item_code': code,
              'item_name': item['item_name']?.toString() ?? '',
              'price': (item['price'] as num?)?.toDouble() ?? 0.0,
              'company_barcode': item['company_barcode']?.toString() ?? '',
              'shelf_location': item['shelf_location']?.toString() ?? '',
              'item_number': item['item_number']?.toString() ?? '',
              'category': item['category']?.toString() ?? '',
              'mrp': (item['mrp'] as num?)?.toDouble() ?? 0.0,
              'stock_qty': (item['stock_qty'] as num?)?.toInt() ?? 10,
              'is_online': item['is_online'] == true,
              'description': item['description']?.toString() ?? '',
              'dual_rates': dual,
            };
          }
        });
      }
    } catch (e) {
      print("Inventory Sync Error: $e");
    }
  }

  Future<void> updateItemDualRates({
    required String itemCode,
    required double primaryPrice,
    required List<double> dualRates,
  }) async {
    try {
      Map<String, dynamic> descObj = {};
      if (cloudInventory.containsKey(itemCode)) {
        final curDesc = cloudInventory[itemCode]?['description']?.toString() ?? '';
        if (curDesc.startsWith('{')) {
          try { descObj = json.decode(curDesc); } catch (_) {}
        } else if (curDesc.isNotEmpty) {
          descObj['notes'] = curDesc;
        }
      }
      descObj['dual_rates'] = dualRates;
      final jsonDesc = json.encode(descObj);

      await Supabase.instance.client.from('inventory').update({
        'price': primaryPrice,
        'description': jsonDesc,
      }).eq('item_code', itemCode);

      if (mounted) {
        setState(() {
          if (cloudInventory.containsKey(itemCode)) {
            cloudInventory[itemCode]!['price'] = primaryPrice;
            cloudInventory[itemCode]!['description'] = jsonDesc;
            cloudInventory[itemCode]!['dual_rates'] = dualRates;
          }
        });
      }
    } catch (e) {
      debugPrint("Error updating dual rates: $e");
    }
  }

  Future<void> retireOldRate({
    required String itemCode,
    required double oldRateToRemove,
    required double newPrimaryRate,
  }) async {
    final item = cloudInventory[itemCode];
    if (item == null) return;
    final currentDual = List<double>.from(item['dual_rates'] ?? []);
    currentDual.removeWhere((r) => (r - oldRateToRemove).abs() < 0.01);
    if (!currentDual.contains(newPrimaryRate)) {
      currentDual.add(newPrimaryRate);
    }
    await updateItemDualRates(
      itemCode: itemCode,
      primaryPrice: newPrimaryRate,
      dualRates: currentDual.length <= 1 ? [] : currentDual,
    );
  }

  String _canonicalCode(String s) {
    String clean = s.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    String digitsOnly = clean.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length >= 8 && digitsOnly.length == clean.length) {
      return clean; // Pure numeric commercial barcode - preserve exactly!
    }
    if (clean.length >= 5) {
      int? d = int.tryParse(clean[4]);
      if (d != null && d >= 1 && d <= 9) {
        clean = clean.substring(0, 4) + String.fromCharCode(64 + d) + clean.substring(5);
      }
    }
    return clean;
  }

  List<Map<String, dynamic>> _lookupAllMatches(String query) {
    if (query.isEmpty) return [];
    String cleanRaw = query.replaceAll(' ', '').trim().toUpperCase();
    String cleanNoDash = cleanRaw.replaceAll('-', '');
    final List<Map<String, dynamic>> matches = [];
    final Set<String> seenCodes = {};

    void addMatch(Map<String, dynamic> it) {
      String c = (it['item_code'] ?? '').toString();
      if (c.isNotEmpty && !seenCodes.contains(c)) {
        seenCodes.add(c);
        matches.add(it);
      }
    }

    // 1. Direct match on company_barcode (exact)
    for (var it in cloudInventory.values) {
      String cb = (it['company_barcode'] ?? '').toString().trim().toUpperCase();
      if (cb.isNotEmpty && (cb == cleanRaw || cb == cleanNoDash)) addMatch(it);
    }

    // 2. Direct match on item_code (exact)
    for (var it in cloudInventory.values) {
      String code = (it['item_code'] ?? '').toString().trim().toUpperCase();
      if (code == cleanRaw || code.replaceAll('-', '') == cleanNoDash) addMatch(it);
    }

    // 3. Match on shelf location + item number (e.g. 01-03-C-134) or shelf location (01-03-C)
    for (var it in cloudInventory.values) {
      String shelf = (it['shelf_location'] ?? '').toString().trim().toUpperCase();
      String itemNum = (it['item_number'] ?? '').toString().trim().toUpperCase();
      String fullShelf = itemNum.isNotEmpty ? "$shelf-$itemNum" : shelf;
      if (fullShelf.isNotEmpty && (fullShelf == cleanRaw || fullShelf.replaceAll('-', '') == cleanNoDash)) {
        addMatch(it);
      } else if (shelf.isNotEmpty && (shelf == cleanRaw || shelf.replaceAll('-', '') == cleanNoDash)) {
        addMatch(it);
      }
    }

    // 4. Canonical match
    String qCanon = _canonicalCode(query);
    if (qCanon.isNotEmpty) {
      for (var it in cloudInventory.values) {
        String code = (it['item_code'] ?? '').toString();
        if (_canonicalCode(code) == qCanon) addMatch(it);
        String shelf = (it['shelf_location'] ?? '').toString();
        String itemNum = (it['item_number'] ?? '').toString();
        String fullShelf = itemNum.isNotEmpty ? "$shelf-$itemNum" : shelf;
        if (_canonicalCode(fullShelf) == qCanon || _canonicalCode(shelf) == qCanon) addMatch(it);
      }
    }

    // 5. Match against formattedItemCode
    String fCanon = _canonicalCode(formattedItemCode);
    if (fCanon.isNotEmpty && fCanon != qCanon) {
      for (var it in cloudInventory.values) {
        if (_canonicalCode(it['item_code']?.toString() ?? '') == fCanon) addMatch(it);
        String shelf = (it['shelf_location'] ?? '').toString();
        String itemNum = (it['item_number'] ?? '').toString();
        String fullShelf = itemNum.isNotEmpty ? "$shelf-$itemNum" : shelf;
        if (_canonicalCode(fullShelf) == fCanon || _canonicalCode(shelf) == fCanon) addMatch(it);
      }
    }

    return matches;
  }

  Map<String, dynamic>? _lookupItem(String query) {
    final matches = _lookupAllMatches(query);
    if (matches.isNotEmpty) return matches.first;
    return null;
  }

  void _applyResolvedItem(Map<String, dynamic> item) {
    setState(() {
      String code = (item['item_code'] ?? '').toString();
      rawItemCode = _parseToRaw(code);
      activeItemName = (item['item_name'] ?? '').toString();
      activeItemSub = "📍 Shelf: ${item['shelf_location'] ?? ''}";
      activeConflicts = [];
      activeOnlineSuggestions = [];
      double p = (item['price'] as num?)?.toDouble() ?? 0.0;
      if (p > 0) {
        rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
      }
      focusedField = 1; // Advance directly to QTY
    });
  }

  void _applyResolvedItemWithPrice(Map<String, dynamic> item, double chosenPrice) {
    setState(() {
      String code = (item['item_code'] ?? '').toString();
      rawItemCode = _parseToRaw(code);
      activeItemName = (item['item_name'] ?? '').toString();
      activeItemSub = "📍 Shelf: ${item['shelf_location'] ?? ''}";
      activeConflicts = [];
      activeOnlineSuggestions = [];
      rate = chosenPrice % 1 == 0 ? chosenPrice.toInt().toString() : chosenPrice.toString();
      focusedField = 1; // Advance directly to QTY
    });
  }

  void _resolveScannedBarcode(String code) {
    if (code.isEmpty) {
      setState(() {
        activeItemName = "";
        activeItemSub = "";
        activeConflicts = [];
        activeOnlineSuggestions = [];
      });
      return;
    }

    final clean = code.trim();
    final matches = _lookupAllMatches(clean);

    if (matches.length == 1) {
      final item = matches.first;
      final dualRates = extractDualRates(item);
      if (dualRates.length > 1) {
        _showDualRateSelectionSheet(item, dualRates);
        return;
      }
      _applyResolvedItem(item);
      return;
    } else if (matches.length > 1) {
      // Multiple items on shelf (Name conflict): Show small options popup
      setState(() {
        activeConflicts = matches;
        activeOnlineSuggestions = [];
      });
      _showConflictSelectionSheet(matches, clean);
      return;
    }

    // 2. Check local master cosmetics catalog (Instant O(1) hash map lookup)
    final c = findCosmeticByBarcode(clean);
    if (c != null) {
      final cName = (c['name'] ?? '').toString();
      double p = (c['price'] as num?)?.toDouble() ?? 0.0;
      setState(() {
        rawItemCode = clean;
        activeItemName = cName;
        activeItemSub = "💄 Cosmetics Catalog (${c['category'] ?? 'Beauty'})";
        activeConflicts = [];
        activeOnlineSuggestions = [];
        if (p > 0) {
          rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
        }
        focusedField = 1; // Advance to QTY
      });
      PendingItemsManager.addPending(
        barcode: clean,
        name: cName,
        price: p,
        brand: (c['brand'] ?? '').toString(),
        category: (c['category'] ?? 'Cosmetics').toString(),
      );
      autoIngestProductToDatabase(
        barcode: clean,
        name: cName,
        brand: (c['brand'] ?? '').toString(),
        category: (c['category'] ?? 'Cosmetics').toString(),
        price: p,
      );
      return;
    }

    // 3. Multi-API Online Search across Open Facts, UPCitemdb & Retail Registries
    final digitsOnly = clean.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length >= 8 && digitsOnly.length == clean.length) {
      setState(() {
        rawItemCode = clean;
        activeItemName = clean;
        activeItemSub = "🔍 Searching Indian product registries (<3s)...";
        activeOnlineSuggestions = [];
        activeConflicts = [];
        focusedField = 2; // Allow typing rate while searching
      });

      resolveBarcodeOnlineMulti(clean).then((results) {
        if (!mounted) return;
        if (results.isEmpty) {
          // Uncategorized barcode: Quiet fallback, NO BLOCKING POPUP!
          setState(() {
            if (rawItemCode == clean) {
              activeItemName = clean;
              activeItemSub = "📦 Uncategorized Barcode";
              activeOnlineSuggestions = [];
              activeConflicts = [];
              focusedField = 2; // Move directly to rate so cashier can type and proceed
            }
          });
          PendingItemsManager.addPending(
            barcode: clean,
            name: clean,
            price: double.tryParse(rate) ?? 0.0,
          );
        } else if (results.length == 1) {
          // Single match: No conflict! Apply directly
          final prod = results.first;
          _applySuggestion(clean, prod);
        } else {
          // Multiple options found online: Show conflict picker and retain suggestions!
          setState(() {
            if (rawItemCode == clean) {
              activeOnlineSuggestions = results;
              activeConflicts = results.map((r) => {
                'item_name': r['name'] ?? '',
                'price': (r['price'] as num?)?.toDouble() ?? 0.0,
                'source': r['source'] ?? 'Online',
                'brand': r['brand'] ?? '',
                'category': r['category'] ?? 'Cosmetics',
              }).toList();
              activeItemSub = "💡 ${results.length} Suggestions (Tap to choose)";
            }
          });
          _showOnlineConflictSelectionSheet(clean, results);
        }
      });
      return;
    }

    // 4. Short / uncataloged code - Quiet fallback, NO BLOCKING POPUP!
    setState(() {
      rawItemCode = clean;
      activeItemName = clean;
      activeItemSub = "📦 Uncategorized";
      activeOnlineSuggestions = [];
      activeConflicts = [];
      focusedField = 2;
    });
    PendingItemsManager.addPending(
      barcode: clean,
      name: clean,
      price: double.tryParse(rate) ?? 0.0,
    );
  }

  void _applySuggestion(String barcode, Map<String, dynamic> prod) {
    final officialName = prod['name']?.toString() ?? (prod['item_name']?.toString() ?? barcode);
    final officialBrand = prod['brand']?.toString() ?? '';
    final officialCategory = prod['category']?.toString() ?? 'Cosmetics';
    final officialPrice = (prod['price'] as num?)?.toDouble() ?? 0.0;
    final source = prod['source']?.toString() ?? 'Online';

    setState(() {
      rawItemCode = barcode;
      activeItemName = officialName;
      activeItemSub = "🌐 $source";
      activeOnlineSuggestions = [prod];
      if (officialPrice > 0 && rate.isEmpty) {
        rate = officialPrice % 1 == 0 ? officialPrice.toInt().toString() : officialPrice.toString();
        focusedField = 1; // Advance to QTY
      } else if (rate.isEmpty) {
        focusedField = 2; // Cashier types rate
      }
      for (var i = 0; i < cart.length; i++) {
        final cRaw = (cart[i]['rawItemCode'] ?? '').toString();
        final cName = (cart[i]['itemName'] ?? '').toString();
        if (cRaw == barcode && (cName.isEmpty || cName == barcode || cName == "General Item")) {
          cart[i]['itemName'] = officialName;
          cart[i]['item'] = "$officialName\n$barcode";
          if (officialPrice > 0) {
            cart[i]['price'] = officialPrice;
            cart[i]['total'] = officialPrice * ((cart[i]['qty'] as num?)?.toInt() ?? 1);
          }
        }
      }
    });

    double finalP = double.tryParse(rate) ?? officialPrice;
    PendingItemsManager.addPending(
      barcode: barcode,
      name: officialName,
      price: finalP,
      brand: officialBrand,
      category: officialCategory,
    );
    if (finalP > 0) {
      autoIngestProductToDatabase(
        barcode: barcode,
        name: officialName,
        brand: officialBrand,
        category: officialCategory,
        price: finalP,
      );
    }
  }

  void _showDualRateSelectionSheet(Map<String, dynamic> item, List<double> dualRates) {
    final itemName = (item['item_name'] ?? 'Product').toString();
    final itemCode = (item['item_code'] ?? '').toString();
    final oldRate = dualRates.first;
    final newRate = dualRates.last;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          title: Row(
            children: [
              const Icon(Icons.sell_outlined, color: Color(0xFFD97706), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("Select batch price printed on pack:", style: TextStyle(fontSize: 12.5, color: Colors.black87)),
              const SizedBox(height: 12),
              Row(
                children: dualRates.map((r) {
                  final isOld = (r == oldRate && dualRates.length > 1);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isOld ? Colors.grey.shade100 : const Color(0xFF10B981),
                          foregroundColor: isOld ? Colors.black87 : Colors.white,
                          side: BorderSide(color: isOld ? Colors.grey.shade400 : const Color(0xFF059669), width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _applyResolvedItemWithPrice(item, r);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("₹${r % 1 == 0 ? r.toInt() : r}", style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                            Text(isOld ? "Old Batch" : "New Batch", style: TextStyle(fontSize: 11, color: isOld ? Colors.black54 : Colors.white70)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await retireOldRate(
                      itemCode: itemCode,
                      oldRateToRemove: oldRate,
                      newPrimaryRate: newRate,
                    );
                    _applyResolvedItemWithPrice(item, newRate);
                  },
                  child: Text(
                    "Old ₹${oldRate % 1 == 0 ? oldRate.toInt() : oldRate} finished? Keep ₹${newRate % 1 == 0 ? newRate.toInt() : newRate} only",
                    style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showOnlineConflictSelectionSheet(String barcode, List<Map<String, dynamic>> results) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          title: Row(
            children: [
              const Icon(Icons.travel_explore, color: Color(0xFF2563EB), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Select Matching Name",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (c, idx) {
                final prod = results[idx];
                final name = prod['name'] ?? '';
                final price = (prod['price'] as num?)?.toDouble() ?? 0.0;
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  trailing: price > 0
                      ? Text("₹${price % 1 == 0 ? price.toInt() : price}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF10B981)))
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _applySuggestion(barcode, prod);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showMasterCatalogSearchDialog(String barcode) {
    String searchTxt = "";
    List<Map<String, dynamic>> searchList = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  left: 16,
                  right: 16,
                  top: 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.75,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.pink.shade100, borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.auto_stories, color: Color(0xFFBE185D), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Find & Bind Product", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text("Barcode: $barcode", style: const TextStyle(color: Colors.black54, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: "Type name (e.g. lakme 9, ponds, ayur)...",
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        ),
                        onChanged: (val) {
                          setSheetState(() {
                            searchTxt = val;
                            searchList = searchCosmeticsByName(val, limit: 15);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: searchList.isEmpty
                            ? Center(
                                child: Text(
                                  searchTxt.isEmpty ? "Type brand or product name to search" : "No matching items found",
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              )
                            : ListView.separated(
                                itemCount: searchList.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (c, idx) {
                                  final it = searchList[idx];
                                  final name = it['name'] ?? '';
                                  final p = (it['price'] as num?)?.toDouble() ?? 0.0;
                                  final cat = it['category'] ?? '';

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    subtitle: Text(cat, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    trailing: Text("₹${p % 1 == 0 ? p.toInt() : p}",
                                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF10B981))),
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      setState(() {
                                        rawItemCode = barcode;
                                        activeItemName = name;
                                        activeItemSub = "💄 Catalog Bound ($cat)";
                                        if (p > 0) {
                                          rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
                                          focusedField = 1; // Move to QTY
                                        } else {
                                          focusedField = 2; // Move to RATE
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showConflictSelectionSheet(List<Map<String, dynamic>> matches, String query) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          title: Row(
            children: [
              const Icon(Icons.touch_app, color: Color(0xFFD97706), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Select Product ($query)",
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: matches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (c, idx) {
                final it = matches[idx];
                final name = it['item_name'] ?? 'Product';
                final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                final shelf = (it['shelf_location'] ?? '').toString();
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  subtitle: shelf.isNotEmpty ? Text("Shelf: $shelf", style: TextStyle(fontSize: 11, color: Colors.grey.shade600)) : null,
                  trailing: price > 0
                      ? Text("₹${price % 1 == 0 ? price.toInt() : price}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF10B981)))
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _applyResolvedItem(it);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _openItemCatalog() async {
    final selected = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ItemCatalogScreen(selectMode: true)),
    );
    if (selected != null && selected is Map<String, dynamic>) {
      setState(() {
        String code = selected['item_code']?.toString() ?? '';
        rawItemCode = _parseToRaw(code);
        double p = (selected['price'] as num?)?.toDouble() ?? 0.0;
        rate = p > 0 ? (p % 1 == 0 ? p.toInt().toString() : p.toString()) : '';
        focusedField = 1; // Jump to QTY
      });
    }
    _syncInventoryFromCloud();
  }

  String _parseToRaw(String code) {
    String clean = code.replaceAll("-", "").replaceAll(" ", "").trim().toUpperCase();
    String digitsOnly = clean.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.length >= 8 && digitsOnly.length == clean.length) {
      return clean; // Pure numeric commercial barcode - preserve exactly!
    }
    if (clean.length >= 5) {
      String rowChar = clean[4];
      int codeUnit = rowChar.codeUnitAt(0);
      if (codeUnit >= 65 && codeUnit <= 90) {
        int num = codeUnit - 64;
        clean = clean.substring(0, 4) + num.toString() + clean.substring(5);
      }
    }
    return clean;
  }

  List<List<Map<String, dynamic>>> activeBills = [[]];
  int currentBillIndex = 0;
  List<Map<String, dynamic>> get cart => activeBills[currentBillIndex];
  String rawItemCode = ""; 
  String qty = "1"; 
  String rate = ""; 
  int focusedField = 0; 
  String paymentMethod = "Cash";
  String amountTendered = "";
  String onlineAmount = "";
  String counterName = "";
  
  final TextEditingController _cashTenderedController = TextEditingController();
  final TextEditingController _hybridCashController = TextEditingController();
  final TextEditingController _hybridOnlineController = TextEditingController();

  String activeItemName = ""; 
  String activeItemSub = "";
  List<Map<String, dynamic>> activeConflicts = [];
  List<Map<String, dynamic>> activeOnlineSuggestions = [];

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
    PendingItemsManager.load().then((_) {
      if (mounted) setState(() {});
    });
    PendingRateChangesManager.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cashTenderedController.dispose();
    _hybridCashController.dispose();
    _hybridOnlineController.dispose();
    super.dispose();
  }

  void _initBluetooth() async {
    try {
      List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
      setState(() => _devices = devices);

      final prefs = await SharedPreferences.getInstance();
      final savedMac = prefs.getString('saved_printer_mac');
      if (savedMac != null && savedMac.isNotEmpty) {
        final matches = devices.where((d) => d.address == savedMac);
        if (matches.isNotEmpty) {
          final match = matches.first;
          setState(() => _selectedDevice = match);
          bool? isConn = await bluetooth.isConnected;
          if (isConn == true) {
            setState(() => _printerConnected = true);
          } else {
            try {
              await bluetooth.connect(match);
            } catch (_) {}
          }
        }
      } else if (devices.isNotEmpty && _selectedDevice == null) {
        setState(() => _selectedDevice = devices.first);
      }
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Type: ESC/POS Thermal Printer (80mm / 58mm)",
                  style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
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
                if (_printerConnected)
                  Text("🟢 Connected: ${_selectedDevice?.name ?? 'Thermal Printer'}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                if (!_printerConnected && _selectedDevice != null)
                  Text("🔴 Disconnected: ${_selectedDevice?.name}", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE")),
              if (!_printerConnected) ElevatedButton(
                onPressed: _selectedDevice == null ? null : () async {
                  try {
                    await bluetooth.connect(_selectedDevice!);
                    final prefs = await SharedPreferences.getInstance();
                    if (_selectedDevice?.address != null) {
                      await prefs.setString('saved_printer_mac', _selectedDevice!.address!);
                      await prefs.setString('saved_printer_name', _selectedDevice!.name ?? "Thermal Printer");
                    }
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
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('saved_printer_mac');
                  await prefs.remove('saved_printer_name');
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
        final saved = prefs.getString('counterName') ?? "";
        counterName = saved.toLowerCase().contains("basement") ? "" : saved;
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
  Map<String, dynamic>? _lastCompletedBill;

  // ... (Keeping all the POS logic identical for brevity) ...

  String get formattedItemCode {
    if (rawItemCode.isEmpty) return "";
    String digitsOnly = rawItemCode.replaceAll(RegExp(r'[^0-9]'), '');
    if (rawItemCode.length >= 8 && digitsOnly.length == rawItemCode.length) {
      return rawItemCode; // Pure numeric commercial barcode - preserve as-is!
    }
    String result = "";
    for (int i = 0; i < rawItemCode.length; i++) {
      if (i == 2) result += " - "; // After Rack (2 digits: 0, 1)
      if (i == 4) result += " - "; // After Column (2 digits: 2, 3)
      if (i == 5) result += " - "; // After Row (1 letter: 4)
      
      if (i == 4) {
        int? num = int.tryParse(rawItemCode[i]);
        if (num != null && num >= 1 && num <= 9) {
          result += String.fromCharCode(64 + num); // 1=A, 2=B, 3=C...
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

  void _updateLiveItemPreview(String code) {
    if (code.isEmpty) {
      activeItemName = "";
      activeItemSub = "";
      activeConflicts = [];
      rate = "";
      return;
    }
    final matches = _lookupAllMatches(code);
    if (matches.length == 1) {
      activeItemName = (matches.first['item_name'] ?? '').toString();
      activeItemSub = "📍 Shelf: ${matches.first['shelf_location'] ?? ''}";
      activeConflicts = [];
      double p = (matches.first['price'] as num?)?.toDouble() ?? 0.0;
      if (p > 0) rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
    } else if (matches.length > 1) {
      activeItemName = (matches.first['item_name'] ?? '').toString();
      activeItemSub = "⚠️ ${matches.length} items at this shelf";
      activeConflicts = matches;
      double p = (matches.first['price'] as num?)?.toDouble() ?? 0.0;
      if (p > 0) rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
    } else {
      final c = findCosmeticByBarcode(code);
      if (c != null) {
        activeItemName = (c['name'] ?? '').toString();
        activeItemSub = "✨ Backup Catalog (Not shelved yet)";
        activeConflicts = [];
        double p = (c['price'] as num?)?.toDouble() ?? 0.0;
        if (p > 0) rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
        return;
      }
      final pending = PendingItemsManager.find(code);
      if (pending != null &&
          (pending['name'] ?? '').toString().isNotEmpty &&
          !(pending['name'] ?? '').toString().startsWith("Barcode ") &&
          !(pending['name'] ?? '').toString().startsWith("Unassigned") &&
          !(pending['name'] ?? '').toString().startsWith("Item ")) {
        activeItemName = pending['name'].toString();
        activeItemSub = "✨ Pending Queue (Not shelved yet)";
        activeConflicts = [];
        double p = (pending['price'] as num?)?.toDouble() ?? 0.0;
        if (p > 0) rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
        return;
      }
      activeItemName = "";
      activeItemSub = "";
      activeConflicts = [];
      rate = "";
    }
  }

  void _promptRenameActiveItem() {
    if (rawItemCode.isEmpty) return;
    final textController = TextEditingController(
      text: (activeItemName == rawItemCode ||
              activeItemName == "General Item" ||
              activeItemName.startsWith("Barcode ") ||
              activeItemName.startsWith("Unassigned") ||
              activeItemName.startsWith("Item "))
          ? ""
          : activeItemName,
    );
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.edit_note, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text("Name Scanned Product", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Barcode: $rawItemCode", style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: "Product Name",
                hintText: "e.g. Ponds Cold Cream 55ml",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = textController.text.trim();
              if (newName.isNotEmpty) {
                setState(() {
                  activeItemName = newName;
                  activeItemSub = "✏️ Custom Named & Auto-Saved";
                });
                PendingItemsManager.addPending(
                  barcode: rawItemCode,
                  name: newName,
                  price: double.tryParse(rate) ?? 0.0,
                );
                autoIngestProductToDatabase(
                  barcode: rawItemCode,
                  name: newName,
                  price: double.tryParse(rate) ?? 0.0,
                );
              }
              Navigator.pop(dialogCtx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void addToCart() {
    if (rawItemCode.isEmpty || rate.isEmpty) return;
    String itemName = activeItemName;
    if (itemName.isEmpty ||
        itemName == rawItemCode ||
        itemName == "General Item" ||
        itemName.startsWith("Barcode ") ||
        itemName.startsWith("Unassigned") ||
        itemName.startsWith("Item ")) {
      final match = _lookupItem(rawItemCode);
      if (match != null && (match['item_name'] ?? '').toString().isNotEmpty) {
        itemName = (match['item_name'] ?? '').toString();
      }
      if (itemName.isEmpty ||
          itemName == rawItemCode ||
          itemName == "General Item" ||
          itemName.startsWith("Barcode ") ||
          itemName.startsWith("Unassigned") ||
          itemName.startsWith("Item ")) {
        final c = findCosmeticByBarcode(rawItemCode);
        if (c != null) {
          itemName = (c['name'] ?? '').toString();
        }
      }
      if (itemName.isEmpty ||
          itemName == rawItemCode ||
          itemName == "General Item" ||
          itemName.startsWith("Barcode ") ||
          itemName.startsWith("Unassigned") ||
          itemName.startsWith("Item ")) {
        final pending = PendingItemsManager.find(rawItemCode);
        if (pending != null &&
            (pending['name'] ?? '').toString().isNotEmpty &&
            !(pending['name'] ?? '').toString().startsWith("Barcode ") &&
            !(pending['name'] ?? '').toString().startsWith("Unassigned") &&
            !(pending['name'] ?? '').toString().startsWith("Item ") &&
            (pending['name'] ?? '').toString() != "General Item" &&
            (pending['name'] ?? '').toString() != rawItemCode) {
          itemName = pending['name'].toString();
        }
      }
    }

    itemName = cleanItemName(itemName, barcode: formattedItemCode);
    if (itemName.isEmpty || itemName.toLowerCase().startsWith("unassigned") || itemName == "General Item") {
      itemName = rawItemCode.isNotEmpty ? rawItemCode : "Item";
    }

    // Save/update pending item with user-entered rate if not yet in inventory
    double parsedRate = double.tryParse(rate) ?? 0.0;
    if (parsedRate > 0) {
      final match = _lookupItem(rawItemCode);
      if (match == null) {
        PendingItemsManager.addPending(
          barcode: rawItemCode,
          name: itemName,
          price: parsedRate,
        );
        autoIngestProductToDatabase(
          barcode: rawItemCode,
          name: itemName,
          price: parsedRate,
        );
      } else {
        // Item exists in inventory! Check if cashier changed the rate from catalog price:
        final catPrice = (match['price'] as num?)?.toDouble() ?? 0.0;
        final existingDual = extractDualRates(match);
        if (catPrice > 0 && (catPrice - parsedRate).abs() >= 0.01 && !existingDual.contains(parsedRate)) {
          PendingRateChangesManager.addRateChange(
            itemCode: (match['item_code'] ?? rawItemCode).toString(),
            barcode: (match['company_barcode'] ?? rawItemCode).toString(),
            itemName: itemName,
            oldRate: catPrice,
            newRate: parsedRate,
          );
        }
      }
    }

    String displayTitle = formattedItemCode.isNotEmpty && formattedItemCode != itemName
        ? "$itemName\n$formattedItemCode"
        : itemName;

    setState(() {
      cart.insert(0, {
        "qty": qty.isEmpty ? "1" : qty,
        "item": displayTitle,
        "itemName": itemName,
        "rawItemCode": rawItemCode, 
        "rate": rate,
        "price": totalPrice, 
      });
      rawItemCode = "";
      qty = "1"; 
      rate = "";
      activeItemName = "";
      activeItemSub = "";
      activeConflicts = [];
      activeOnlineSuggestions = [];
      focusedField = 0; 
    });
  }

  void editCartItem(int index) {
    setState(() {
      final item = cart[index];
      rawItemCode = item["rawItemCode"];
      qty = item["qty"];
      rate = item["rate"];
      activeItemName = item["itemName"] ?? "";
      activeItemSub = "";
      activeConflicts = [];
      activeOnlineSuggestions = [];
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
        if (focusedField == 0) {
          if (rawItemCode.isNotEmpty) {
            _resolveScannedBarcode(rawItemCode);
          } else {
            focusedField = 1;
          }
        }
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
          if (rawItemCode.isNotEmpty) {
            rawItemCode = rawItemCode.substring(0, rawItemCode.length - 1);
            _updateLiveItemPreview(rawItemCode);
          }
        }
      } 
      else if (value == "+/-") {
        if (focusedField == 1) {
          if (qty.startsWith("-")) qty = qty.substring(1);
          else qty = "-" + qty;
        } else if (focusedField == 2) {
          if (rate.startsWith("-")) rate = rate.substring(1);
          else rate = "-" + rate;
        }
      }
      else {
        if (focusedField == 0) {
          if (value != ".") {
            rawItemCode += value;
            _updateLiveItemPreview(rawItemCode);
          }
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
      amountTendered = "";
      onlineAmount = "";
      _cashTenderedController.clear();
      _hybridCashController.clear();
      _hybridOnlineController.clear();
      paymentMethod = "Cash";
      focusedField = 0;
      isPreviewingBill = false;
    });
  }

  String _getSellerCode(String email) {
    final clean = email.trim().toLowerCase();
    if (clean == "tolovegrover@gmail.com") return "01";
    if (clean == "sanjeetagrover@gmail.com") return "02";
    if (clean == "mrsnishagrover@gmail.com") return "03";
    int id = (clean.hashCode.abs() % 3) + 4; // 04, 05, 06
    return id.toString().padLeft(2, '0');
  }

  Future<Map<String, dynamic>?> _saveBillRecord() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toUtc().toIso8601String();
    
    String billNumber = "";
    try {
      final data = await Supabase.instance.client
          .from('bills')
          .select('id')
          .gte('created_at', startOfDay)
          .lte('created_at', endOfDay);
      int count = data.length + 1;
      
      String dateStr = "${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year.toString().substring(2)}";
      String sellerCode = _getSellerCode(widget.userEmail);
      billNumber = "$dateStr$sellerCode${count.toString().padLeft(4, '0')}";
    } catch (e) {
      billNumber = "${now.millisecondsSinceEpoch}";
    }

    double finalChangeDue = 0.0;
    double paidMoney = 0.0;
    String dbPaymentMethod = paymentMethod;

    if (paymentMethod == 'Cash') {
      double entered = double.tryParse(amountTendered) ?? 0.0;
      paidMoney = entered > 0 ? entered : cartTotal.toDouble();
      finalChangeDue = paidMoney >= cartTotal ? (paidMoney - cartTotal) : 0.0;
    } else if (paymentMethod == 'Online') {
      paidMoney = cartTotal.toDouble();
      finalChangeDue = 0.0;
    } else if (paymentMethod == 'Hybrid') {
      double cashPart = double.tryParse(amountTendered) ?? 0.0;
      double onlinePart = double.tryParse(onlineAmount) ?? 0.0;
      paidMoney = cashPart + onlinePart;
      finalChangeDue = paidMoney >= cartTotal ? (paidMoney - cartTotal) : 0.0;
      dbPaymentMethod = "Hybrid (Cash ₹${cashPart % 1 == 0 ? cashPart.toInt() : cashPart}, Online ₹${onlinePart % 1 == 0 ? onlinePart.toInt() : onlinePart})";
    }

    // Ensure every item in cart has its best possible resolved name
    for (var item in cart) {
      String rawCode = (item["rawItemCode"] ?? "").toString();
      String currentName = (item["itemName"] ?? "").toString();
      if (rawCode.isNotEmpty &&
          (currentName.isEmpty ||
           currentName == rawCode ||
           currentName == "General Item" ||
           currentName.startsWith("Barcode ") ||
           currentName.startsWith("Item ") ||
           currentName.startsWith("Unassigned"))) {
        final c = findCosmeticByBarcode(rawCode);
        if (c != null) {
          item["itemName"] = (c['name'] ?? '').toString();
        } else {
          final p = PendingItemsManager.find(rawCode);
          if (p != null &&
              (p['name'] ?? '').toString().isNotEmpty &&
              !(p['name'] ?? '').toString().startsWith("Barcode ") &&
              !(p['name'] ?? '').toString().startsWith("Item ") &&
              !(p['name'] ?? '').toString().startsWith("Unassigned") &&
              p['name'].toString() != "General Item" &&
              p['name'].toString() != rawCode) {
            item["itemName"] = p['name'].toString();
          }
        }
      }
      item["itemName"] = cleanItemName(item["itemName"]?.toString(), barcode: rawCode);
      if (item["itemName"] == null || item["itemName"].toString().isEmpty || item["itemName"].toString() == "General Item") {
        item["itemName"] = rawCode;
      }
      if (rawCode.isNotEmpty && rawCode != item["itemName"]) {
        item["item"] = "${item["itemName"]}\n$rawCode";
      } else {
        item["item"] = item["itemName"];
      }
    }

    // 1. Save to Supabase
    final savedBillRecord = {
      'bill_number': billNumber,
      'staff_name': widget.userName,
      'counter_name': counterName,
      'total_amount': cartTotal,
      'items_json': List<Map<String, dynamic>>.from(cart.map((e) => Map<String, dynamic>.from(e))),
      'payment_method': dbPaymentMethod,
      'amount_tendered': paidMoney,
      'change_due': finalChangeDue,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await Supabase.instance.client.from('bills').insert(savedBillRecord);
      _lastCompletedBill = savedBillRecord;
      return savedBillRecord;
    } catch (dbError) {
      print("Supabase Error: $dbError");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cloud Sync Failed: $dbError")));
      }
      return null; 
    }
  }

  /// Save bill and directly share via WhatsApp (Bypass thermal paper print)
  void _saveAndShareWhatsApp({ReceiptLanguage initialLanguage = ReceiptLanguage.hindi}) async {
    final savedBillRecord = await _saveBillRecord();
    if (savedBillRecord == null) return;

    // Reset checkout / cart state so next customer can be billed immediately
    confirmPrint();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                initialLanguage == ReceiptLanguage.hindi 
                    ? "Bill saved! Sending Hindi bill on WhatsApp..." 
                    : "Bill saved! Opening WhatsApp for English bill...",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
        backgroundColor: const Color(0xFF166534),
      ),
    );

    // Open WhatsApp dialog with the chosen language preselected
    PdfReceiptService.showWhatsAppPdfDialog(
      context: context,
      bill: savedBillRecord,
      initialLanguage: initialLanguage,
    );
  }

  /// Save bill and print Hindi thermal receipt
  void _saveAndPrintBillHindi() async {
    final savedBillRecord = await _saveBillRecord();
    if (savedBillRecord == null) return;

    if (_printerConnected) {
      try {
        bool? isConnected = await bluetooth.isConnected;
        if (isConnected == true) {
          await printHindiThermalBill(bluetooth: bluetooth, bill: savedBillRecord);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text("Hindi Thermal Bill Printed!"),
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: "WHATSAPP",
                  textColor: const Color(0xFF25D366),
                  onPressed: () => PdfReceiptService.showWhatsAppPdfDialog(
                    context: context,
                    bill: savedBillRecord,
                    initialLanguage: ReceiptLanguage.hindi,
                  ),
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Printer lost connection. Bill Saved to Cloud Only.")));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Printer Error: $e. Bill Saved to Cloud Only.")));
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Bill Saved! (Printer not connected)"),
            action: SnackBarAction(
              label: "WHATSAPP",
              textColor: const Color(0xFF25D366),
              onPressed: () => PdfReceiptService.showWhatsAppPdfDialog(
                context: context,
                bill: savedBillRecord,
                initialLanguage: ReceiptLanguage.hindi,
              ),
            ),
          ),
        );
      }
    }

    confirmPrint();
  }

  void _saveAndPrintBill() async {
    final savedBillRecord = await _saveBillRecord();
    if (savedBillRecord == null) return;

    final billNumber = (savedBillRecord['bill_number'] ?? "").toString();
    final paidMoney = (savedBillRecord['amount_tendered'] as num?)?.toDouble() ?? 0.0;
    final finalChangeDue = (savedBillRecord['change_due'] as num?)?.toDouble() ?? 0.0;
    final dbPaymentMethod = (savedBillRecord['payment_method'] ?? paymentMethod).toString();

    // 2. Try Printing if connected
    if (_printerConnected) {
      try {
        bool? isConnected = await bluetooth.isConnected;
        if (isConnected == true) {
          ByteData bytesAsset = await rootBundle.load("assets/logo_bw.jpg");
          Uint8List imageBytes = bytesAsset.buffer.asUint8List();
          await bluetooth.printImageBytes(imageBytes);

          // Top Sanskrit Bhagwan Namaste with Satiya (Always on top)
          try {
            final activeMantra = PdfReceiptService.resolveActiveInvocation(PdfReceiptService.currentInvocation);
            final mantraBytes = await generateMantraBannerBytes(activeMantra);
            if (mantraBytes != null) {
              await bluetooth.printImageBytes(mantraBytes);
            }
          } catch (_) {}
          
          await bluetooth.printNewLine();
          await bluetooth.printCustom("LOVE KUSH", 3, 1); 
          await bluetooth.printCustom("SHOPPING CENTER", 2, 1); 
          if (counterName.isNotEmpty && !counterName.toLowerCase().contains("basement")) {
            await bluetooth.printCustom(counterName.toUpperCase(), 1, 1);
          }
          await bluetooth.printCustom("BILL NO: $billNumber", 1, 1);
          try {
            final barcodeBytes = await generateBarcodeImageBytes(billNumber, width: 340, height: 60);
            if (barcodeBytes != null) {
              await bluetooth.printImageBytes(barcodeBytes);
            } else {
              await bluetooth.printQRcode(billNumber, 200, 200, 1);
            }
          } catch (_) {
            try { await bluetooth.printQRcode(billNumber, 200, 200, 1); } catch (_) {}
          }
          
          await bluetooth.printNewLine();
          await bluetooth.printLeftRight("Item", "Qty x Rate", 1);
          await bluetooth.printCustom("--------------------------------", 1, 1);
          
          final billItems = savedBillRecord['items_json'] as List<dynamic>;
          for (var item in billItems) {
            String name = cleanItemName(
              (item["itemName"] != null && item["itemName"].toString().isNotEmpty)
                  ? item["itemName"].toString()
                  : item["item"].toString(),
              barcode: item["rawItemCode"]?.toString(),
            );
            if (name.length > 20) name = name.substring(0, 20);
            String details = "${item["qty"]} x ₹${item["rate"]}";
            await bluetooth.printLeftRight(name, details, 1);
          }
          
          await bluetooth.printCustom("--------------------------------", 1, 1);
          await bluetooth.printLeftRight("TOTAL", "₹${cartTotal.toStringAsFixed(2)}", 2); 
          await bluetooth.printNewLine();
          
          await bluetooth.printLeftRight("PAYMENT", paymentMethod.toUpperCase(), 1);
          if (paymentMethod == "Cash") {
            await bluetooth.printLeftRight("Paid Cash:", "Rs${paidMoney.toStringAsFixed(2)}", 1);
            if (finalChangeDue > 0) {
              await bluetooth.printLeftRight("Change Returned:", "Rs${finalChangeDue.toStringAsFixed(2)}", 1);
            }
          } else if (paymentMethod == "Online") {
            await bluetooth.printLeftRight("Online Paid:", "Rs${cartTotal.toStringAsFixed(2)}", 1);
          } else if (paymentMethod == "Hybrid") {
            double cash = double.tryParse(amountTendered) ?? 0.0;
            double online = double.tryParse(onlineAmount) ?? 0.0;
            await bluetooth.printLeftRight("Cash Paid:", "Rs${cash.toStringAsFixed(2)}", 1);
            await bluetooth.printLeftRight("Online Paid:", "Rs${online.toStringAsFixed(2)}", 1);
            if (finalChangeDue > 0) {
              await bluetooth.printLeftRight("Change Returned:", "Rs${finalChangeDue.toStringAsFixed(2)}", 1);
            }
          }
          await bluetooth.printNewLine();

          await bluetooth.printCustom("Thank you for shopping! Visit again!", 0, 1);
          await bluetooth.printNewLine();
          await bluetooth.printNewLine();
          await bluetooth.paperCut();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Text("Bill Saved & Printed!"),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.amberAccent, size: 16),
                      label: const Text("PDF", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        PdfReceiptService.openPdfPreviewDialog(
                          context: context,
                          bill: savedBillRecord,
                          onThermalPrint: (lang) => executeReprintThermalBill(
                            context: context,
                            bluetooth: bluetooth,
                            bill: savedBillRecord,
                            language: lang,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      icon: const Icon(Icons.share, color: Color(0xFF25D366), size: 16),
                      label: const Text("WHATSAPP", style: TextStyle(color: Color(0xFF25D366), fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        PdfReceiptService.showWhatsAppPdfDialog(context: context, bill: savedBillRecord);
                      },
                    ),
                  ],
                ),
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: "THERMAL",
                  textColor: Colors.white,
                  onPressed: () => _openReprintPreview(savedBillRecord),
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Printer lost connection. Bill Saved to Cloud Only.")));
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Printer Error: $e. Bill Saved to Cloud Only.")));
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Text("Bill Saved!"),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.amberAccent, size: 16),
                  label: const Text("PDF", style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    PdfReceiptService.openPdfPreviewDialog(
                      context: context,
                      bill: savedBillRecord,
                      onThermalPrint: (lang) => executeReprintThermalBill(
                        context: context,
                        bluetooth: bluetooth,
                        bill: savedBillRecord,
                        language: lang,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: const Icon(Icons.share, color: Color(0xFF25D366), size: 16),
                  label: const Text("WHATSAPP", style: TextStyle(color: Color(0xFF25D366), fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    PdfReceiptService.showWhatsAppPdfDialog(context: context, bill: savedBillRecord);
                  },
                ),
              ],
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: "THERMAL",
              textColor: Colors.white,
              onPressed: () => _openReprintPreview(savedBillRecord),
            ),
          ),
        );
      }
    }

    // 3. Clear Cart
    confirmPrint();
  }

  void _reprintBill(Map<String, dynamic> bill, {ReceiptLanguage language = ReceiptLanguage.english}) {
    executeReprintThermalBill(context: context, bluetooth: bluetooth, bill: bill, language: language);
  }

  void _openReprintPreview(Map<String, dynamic> bill) {
    showReceiptPreviewDialog(
      context: context,
      bill: bill,
      onPrint: () => _reprintBill(bill),
      onPrintWithLanguage: (lang) => _reprintBill(bill, language: lang),
    );
  }

  Future<void> _openReprintLastBillPreview() async {
    if (_lastCompletedBill != null) {
      _openReprintPreview(_lastCompletedBill!);
      return;
    }
    try {
      final res = await Supabase.instance.client
          .from('bills')
          .select()
          .order('created_at', ascending: false)
          .limit(1);
      if (res.isNotEmpty) {
        _lastCompletedBill = Map<String, dynamic>.from(res.first);
        if (mounted) {
          _openReprintPreview(_lastCompletedBill!);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("No previous bills found to reprint.")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching last bill: $e")),
        );
      }
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
                      const Expanded(child: Text('LOVE KUSH SHOPPING CENTER', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5))),
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
                leading: const Icon(Icons.dashboard_customize_outlined, color: Colors.blueAccent),
                title: const Text('Admin Dashboard & Past Bills', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                subtitle: const Text('Sales reports, cash flow, festive trends & past bills'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.manage_accounts, color: Colors.black87),
                title: const Text('Manage Staff Access', style: TextStyle(fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffManagementScreen()));
                },
              ),
              const Divider(),
            ],
            
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.black87),
              title: const Text('New Bill (POS)', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context), 
            ),
            if (!widget.isAdmin)
              ListTile(
                leading: const Icon(Icons.history, color: Colors.black87),
                title: const Text('Past Bills & Reprint', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Browse sales & reprint receipts'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminDashboardScreen()));
                },
              ),
            ListTile(
              leading: Icon(Icons.print, color: _printerConnected ? Colors.green : Colors.black87),
              title: Text(
                _printerConnected
                    ? 'Printer: ${_selectedDevice?.name ?? "Connected"}'
                    : (_selectedDevice != null ? 'Connect ${_selectedDevice!.name}' : 'Connect Receipt Printer'),
                style: TextStyle(fontWeight: FontWeight.bold, color: _printerConnected ? Colors.green : Colors.black87),
              ),
              subtitle: Text(
                _printerConnected ? "🟢 ESC/POS Thermal Printer (Connected)" : "🔴 Bluetooth 80mm/58mm Thermal",
                style: TextStyle(fontSize: 11, color: _printerConnected ? const Color(0xFF047857) : Colors.black54),
              ),
              onTap: () {
                Navigator.pop(context);
                _showPrinterDialog();
              },
            ),

            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: Colors.black87),
              title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Store profile, printer & receipt preferences'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              },
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
        title: const Text('LOVE KUSH SHOPPING CENTER', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black), 
        actions: [
          IconButton(
            tooltip: "Reprint Last Bill (Preview First)",
            icon: const Icon(Icons.print_outlined, color: Colors.black87),
            onPressed: _openReprintLastBillPreview,
          ),
        ],
      ),
      body: Column(
        children: [
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
              onTap: () => setState(() => isPreviewingBill = true),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.black12, width: 1)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Prominent Live Product Banner (Name appears on scan - NO popups during sale!)
                if (activeItemName.isNotEmpty) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: activeConflicts.isNotEmpty
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: activeConflicts.isNotEmpty
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF10B981),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: _promptRenameActiveItem,
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            children: [
                              Icon(
                                activeConflicts.isNotEmpty
                                    ? Icons.shelves
                                    : Icons.check_circle_outline,
                                size: 16,
                                color: activeConflicts.isNotEmpty
                                    ? const Color(0xFFB45309)
                                    : const Color(0xFF059669),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  activeItemName,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: activeConflicts.isNotEmpty
                                        ? const Color(0xFF78350F)
                                        : const Color(0xFF065F46),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.blueGrey),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: "Tap to rename this item",
                                onPressed: _promptRenameActiveItem,
                              ),
                              if (activeItemSub.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: activeConflicts.isNotEmpty
                                        ? const Color(0xFFFDE68A)
                                        : const Color(0xFFA7F3D0),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    activeItemSub,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: activeConflicts.isNotEmpty
                                          ? const Color(0xFF92400E)
                                          : const Color(0xFF065F46),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Inline choice chips for suggestions & conflicts - NEVER LOST ON BACK!
                        if (activeConflicts.length > 1 || activeOnlineSuggestions.length > 1) ...[
                          const SizedBox(height: 6),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                if (activeOnlineSuggestions.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6.0),
                                    child: ActionChip(
                                      avatar: const Icon(Icons.travel_explore, size: 14, color: Colors.blueAccent),
                                      backgroundColor: Colors.blue.shade50,
                                      side: BorderSide(color: Colors.blue.shade300),
                                      label: Text(
                                        "All Suggestions (${activeOnlineSuggestions.length})",
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                                      ),
                                      onPressed: () => _showOnlineConflictSelectionSheet(rawItemCode, activeOnlineSuggestions),
                                    ),
                                  ),
                                ...activeConflicts.map((c) {
                                  final isSelected = activeItemName == c['item_name'];
                                  double p = (c['price'] as num?)?.toDouble() ?? 0.0;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 6.0),
                                    child: ChoiceChip(
                                      label: Text(
                                        p > 0 ? "${c['item_name']} (₹${p % 1 == 0 ? p.toInt() : p})" : "${c['item_name']}",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: isSelected ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      selected: isSelected,
                                      selectedColor: const Color(0xFFD97706),
                                      onSelected: (_) {
                                        _applySuggestion(rawItemCode, {
                                          'name': c['item_name'],
                                          'price': p,
                                          'brand': c['brand'] ?? '',
                                          'category': c['category'] ?? 'Cosmetics',
                                          'source': c['source'] ?? 'Online',
                                        });
                                      },
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                Row(
                  children: [
                    _buildInputBox(
                      "ITEM CODE",
                      formattedItemCode,
                      focusedField == 0,
                      0,
                      flex: 8,
                      isCode: true,
                    ),
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
                          final scannedVal = barcodes.first.rawValue!;
                          final parsedRaw = _parseToRaw(scannedVal);
                          HapticFeedback.mediumImpact();
                          setState(() {
                            rawItemCode = parsedRaw;
                            isScanning = false; // instantly close camera to show keypad
                          });
                          _resolveScannedBarcode(parsedRaw);
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
                      _buildKeypadRow([_key("7", "G"), _key("8", "H"), _key("9", "I"), _key("+/-", "RTN")]),
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
    double paidMoney = 0;
    double changeDue = 0;
    if (paymentMethod == 'Cash') {
      double entered = double.tryParse(amountTendered) ?? 0.0;
      paidMoney = entered > 0 ? entered : cartTotal.toDouble();
      changeDue = entered > 0 ? (entered - cartTotal) : 0.0;
    } else if (paymentMethod == 'Online') {
      paidMoney = cartTotal.toDouble();
      changeDue = 0.0;
    } else if (paymentMethod == 'Hybrid') {
      double cash = double.tryParse(amountTendered) ?? 0.0;
      double online = double.tryParse(onlineAmount) ?? 0.0;
      paidMoney = cash + online;
      changeDue = (cash + online) - cartTotal;
    }
    
    return Scaffold(
      backgroundColor: const Color(0xFF374151), 
      body: SafeArea(
        child: Column(
          children: [
            const Padding(padding: EdgeInsets.all(16.0), child: Text("CHECKOUT", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2))),
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
                      // 1. PAYMENT OPTIONS
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            const Text("PAYMENT METHOD", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent, letterSpacing: 1.5)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: ["Cash", "Online", "Hybrid"].map((method) {
                                return ChoiceChip(
                                  label: Text(method, style: TextStyle(color: paymentMethod == method ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                                  selectedColor: Colors.blueAccent,
                                  selected: paymentMethod == method,
                                  onSelected: (bool selected) {
                                    setState(() {
                                      paymentMethod = method;
                                      amountTendered = "";
                                      onlineAmount = "";
                                      _cashTenderedController.clear();
                                      _hybridCashController.clear();
                                      _hybridOnlineController.clear();
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            if (paymentMethod == "Cash") ...[
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    ActionChip(
                                      avatar: const Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
                                      label: Text("Exact ₹$cartTotal", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      backgroundColor: amountTendered == cartTotal.toString() ? const Color(0xFFD1FAE5) : null,
                                      onPressed: () {
                                        setState(() {
                                          amountTendered = cartTotal.toString();
                                          _cashTenderedController.text = amountTendered;
                                        });
                                      },
                                    ),
                                    const SizedBox(width: 8),
                                    ...[50, 100, 200, 500, 1000, 2000]
                                        .where((amt) => amt > cartTotal)
                                        .take(3)
                                        .map((amt) => Padding(
                                              padding: const EdgeInsets.only(right: 8.0),
                                              child: ActionChip(
                                                avatar: const Icon(Icons.payments_outlined, size: 16, color: Colors.blueAccent),
                                                label: Text("₹$amt", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                                backgroundColor: amountTendered == amt.toString() ? const Color(0xFFDBEAFE) : null,
                                                onPressed: () {
                                                  setState(() {
                                                    amountTendered = amt.toString();
                                                    _cashTenderedController.text = amountTendered;
                                                  });
                                                },
                                              ),
                                            )),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _cashTenderedController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: "Cash Given by Customer (₹)",
                                  hintText: "Enter note given (e.g. 500) or leave for exact",
                                  prefixIcon: const Icon(Icons.money),
                                  border: const OutlineInputBorder(),
                                  suffixIcon: amountTendered.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () {
                                            setState(() {
                                              amountTendered = "";
                                              _cashTenderedController.clear();
                                            });
                                          },
                                        )
                                      : null,
                                ),
                                onChanged: (val) => setState(() => amountTendered = val),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: changeDue >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: changeDue >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      changeDue >= 0 ? "💰 CHANGE TO RETURN:" : "⚠️ REMAINING DUE:",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: changeDue >= 0 ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                                      ),
                                    ),
                                    Text(
                                      "₹${changeDue.abs().toStringAsFixed(2)}",
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: changeDue >= 0 ? const Color(0xFF047857) : const Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (paymentMethod == "Hybrid") ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _hybridCashController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: "Cash (₹)", border: OutlineInputBorder()),
                                      onChanged: (val) => setState(() => amountTendered = val),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: _hybridOnlineController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: "Online (₹)", border: OutlineInputBorder()),
                                      onChanged: (val) => setState(() => onlineAmount = val),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: changeDue >= 0 ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: changeDue >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      changeDue >= 0 ? "💰 CHANGE TO RETURN:" : "⚠️ REMAINING DUE:",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: changeDue >= 0 ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                                      ),
                                    ),
                                    Text(
                                      "₹${changeDue.abs().toStringAsFixed(2)}",
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: changeDue >= 0 ? const Color(0xFF047857) : const Color(0xFFDC2626),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text("RECEIPT PREVIEW", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                      const Divider(thickness: 2),
                      
                      // 2. RECEIPT PREVIEW
                      const SizedBox(height: 16),
                      const Text("LOVE KUSH SHOPPING CENTER", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text("Served by: ${widget.userName}", style: const TextStyle(fontSize: 14, color: Colors.black45, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 16),
                      const Text("----------------------------------------", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ...cart.reversed.map((item) {
                        String name = cleanItemName(
                          (item["itemName"] != null && item["itemName"].toString().isNotEmpty)
                              ? item["itemName"].toString()
                              : item["item"].toString(),
                          barcode: item["rawItemCode"]?.toString(),
                        );
                        String rawCode = (item["rawItemCode"] ?? "").toString();
                        String previewTitle = rawCode.isNotEmpty && rawCode != name
                            ? "$name\n$rawCode"
                            : name;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(flex: 3, child: Text(previewTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                              Expanded(flex: 2, child: Text("${item["qty"]} x ${item["rate"]}", style: const TextStyle(fontSize: 14, color: Colors.black54), textAlign: TextAlign.center)),
                              Expanded(flex: 2, child: Text("₹${item["price"]}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), textAlign: TextAlign.right)),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      const Text("----------------------------------------", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("TOTAL", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                          Text("₹${cartTotal.toStringAsFixed(2)}", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text("----------------------------------------", style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("PAYMENT METHOD", style: TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w600)),
                          Text(paymentMethod.toUpperCase(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("PAID MONEY", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          Text("₹${paidMoney.toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                        ],
                      ),
                      if (changeDue > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("CHANGE RETURNED", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                            Text("₹${changeDue.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF047857))),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            
            // ACTION BUTTONS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // WhatsApp Direct Options (Instead of printing)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0FDF4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF86EFAC), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.share, size: 16, color: Color(0xFF166534)),
                            SizedBox(width: 6),
                            Text(
                              "WHATSAPP BILL (INSTEAD OF PRINTING)",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF166534),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Text("🇮🇳", style: TextStyle(fontSize: 16)),
                                label: const Text(
                                  "Hindi Bill",
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF15803D),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 2,
                                ),
                                onPressed: () => _saveAndShareWhatsApp(initialLanguage: ReceiptLanguage.hindi),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Text("🇬🇧", style: TextStyle(fontSize: 16)),
                                label: const Text(
                                  "English Bill",
                                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E40AF),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 2,
                                ),
                                onPressed: () => _saveAndShareWhatsApp(initialLanguage: ReceiptLanguage.english),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Secondary / Paper Print Actions: EDIT and PRINT
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Colors.black87, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => setState(() => isPreviewingBill = false), 
                          child: const Text("◀ EDIT BILL", style: TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w900)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: Tooltip(
                          message: "Tap to print English bill, long-press for Hindi",
                          child: ElevatedButton.icon(
                            icon: Icon(_printerConnected ? Icons.print : Icons.cloud_upload, color: Colors.white, size: 20),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF374151),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 2,
                            ),
                            onPressed: _saveAndPrintBill,
                            onLongPress: () {
                              if (_printerConnected) {
                                _saveAndPrintBillHindi();
                              }
                            },
                            label: Text(
                              _printerConnected ? "🖨️ SAVE & PRINT" : "☁️ SAVE BILL", 
                              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildInputBox(
    String label,
    String value,
    bool isFocused,
    int fieldIndex, {
    required int flex,
    bool isCode = false,
    String? subtext,
    Color? subtextColor,
    VoidCallback? onCustomTap,
  }) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: () {
          if (onCustomTap != null) {
            onCustomTap();
          } else {
            setState(() => focusedField = fieldIndex);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            color: isFocused ? Colors.black : Colors.white,
            border: Border.all(color: isFocused ? Colors.black : Colors.black26, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: isFocused ? Colors.white70 : Colors.black45)),
              const SizedBox(height: 4),
              Text(value.isEmpty ? (isCode ? "—" : "") : value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: isFocused ? Colors.white : Colors.black), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtext != null && subtext.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtext,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: subtextColor ?? (isFocused ? Colors.greenAccent : Colors.green.shade700),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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
// BARCODE & QR LABEL PRINTER (3 SIZES)
// ==========================================
class BarcodeLabelPrinterScreen extends StatefulWidget {
  final String? initialCode;
  final String? initialName;
  final double? initialPrice;

  const BarcodeLabelPrinterScreen({
    Key? key,
    this.initialCode,
    this.initialName,
    this.initialPrice,
  }) : super(key: key);

  @override
  State<BarcodeLabelPrinterScreen> createState() => _BarcodeLabelPrinterScreenState();
}

class _BarcodeLabelPrinterScreenState extends State<BarcodeLabelPrinterScreen> {
  late TextEditingController _rackCtrl;
  late TextEditingController _colCtrl;
  late TextEditingController _rowCtrl;
  late TextEditingController _itemCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _priceCtrl;

  // 0: Big Print (Detailed), 1: Medium (Standard), 2: Smallest (Barcode Only)
  int _selectedFormat = 2; // Default to Smallest (1D Barcode Shelf Label)
  // 'barcode' (1D) or 'qr' (2D)
  String _codeType = 'barcode'; // Default to 1D Barcode!

  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  bool _printerConnected = false;
  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedDevice;

  @override
  void initState() {
    super.initState();
    String r = "01", c = "03", row = "C", item = "134";
    if (widget.initialCode != null && widget.initialCode!.contains('-')) {
      final parts = widget.initialCode!.split('-');
      if (parts.isNotEmpty) r = parts[0];
      if (parts.length > 1) c = parts[1];
      if (parts.length > 2) row = parts[2];
      if (parts.length > 3) item = parts[3];
    }
    _rackCtrl = TextEditingController(text: r);
    _colCtrl = TextEditingController(text: c);
    _rowCtrl = TextEditingController(text: row);
    _itemCtrl = TextEditingController(text: item);
    _nameCtrl = TextEditingController(text: widget.initialName ?? "Cosmetic Item");
    _priceCtrl = TextEditingController(
      text: widget.initialPrice != null && widget.initialPrice! > 0
          ? (widget.initialPrice! % 1 == 0 ? widget.initialPrice!.toInt().toString() : widget.initialPrice!.toString())
          : "250",
    );
    _checkPrinter();
  }

  void _checkPrinter() async {
    try {
      bool? connected = await bluetooth.isConnected;
      List<BluetoothDevice> bonded = await bluetooth.getBondedDevices();
      setState(() {
        _printerConnected = connected == true;
        _devices = bonded;
      });
    } catch (_) {}
  }

  void _showPrinterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Select Bluetooth Printer"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_devices.isEmpty)
                const Text("No paired devices found. Please pair your thermal printer in Android Bluetooth settings first."),
              if (_devices.isNotEmpty)
                DropdownButton<BluetoothDevice>(
                  hint: const Text("Choose Printer"),
                  value: _selectedDevice,
                  isExpanded: true,
                  items: _devices.map((d) => DropdownMenuItem(value: d, child: Text(d.name ?? "Device"))).toList(),
                  onChanged: (d) => setDialogState(() => _selectedDevice = d),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCEL")),
            if (_selectedDevice != null)
              ElevatedButton(
                onPressed: () async {
                  try {
                    await bluetooth.connect(_selectedDevice!);
                    setState(() => _printerConnected = true);
                    if (mounted) Navigator.pop(ctx);
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connect failed: $e")));
                  }
                },
                child: const Text("CONNECT"),
              ),
          ],
        ),
      ),
    );
  }

  String get locationCode => "${_rackCtrl.text.padLeft(2, '0')}-${_colCtrl.text.padLeft(2, '0')}-${_rowCtrl.text.toUpperCase()}-${_itemCtrl.text}".toUpperCase();

  void _printLabel() async {
    try {
      bool? isConnected = await bluetooth.isConnected;
      if (isConnected != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Printer not connected. Please connect printer.")),
          );
        }
        return;
      }

      String code = locationCode;
      String name = _nameCtrl.text.trim();
      String price = _priceCtrl.text.trim();

      if (_codeType == 'barcode') {
        if (_selectedFormat == 0) {
          // 1. BIG 1D BARCODE PRINT
          await bluetooth.printNewLine();
          await bluetooth.printCustom("LOVE KUSH SHOPPING", 2, 1);
          await bluetooth.printCustom("--------------------------------", 1, 1);
          if (name.isNotEmpty) {
            await bluetooth.printCustom(name.toUpperCase(), 2, 1);
          }
          final barcodeBytes = await generateBarcodeImageBytes(code, width: 340, height: 60);
          if (barcodeBytes != null) {
            await bluetooth.printImageBytes(barcodeBytes);
          }
          await bluetooth.printCustom("LOC: $code", 1, 1);
          if (price.isNotEmpty) {
            await bluetooth.printCustom("MRP: Rs $price", 2, 1);
          }
          await bluetooth.printCustom("--------------------------------", 1, 1);
          await bluetooth.printNewLine();
          await bluetooth.paperCut();
        } else if (_selectedFormat == 1) {
          // 2. MEDIUM 1D BARCODE PRINT
          await bluetooth.printNewLine();
          if (name.isNotEmpty) {
            String displayName = name.length > 20 ? name.substring(0, 20) : name;
            await bluetooth.printCustom(displayName.toUpperCase(), 1, 1);
          }
          final barcodeBytes = await generateBarcodeImageBytes(code, width: 320, height: 50);
          if (barcodeBytes != null) {
            await bluetooth.printImageBytes(barcodeBytes);
          }
          String line = price.isNotEmpty ? "$code   Rs $price" : code;
          await bluetooth.printCustom(line, 1, 1);
          await bluetooth.printNewLine();
          await bluetooth.paperCut();
        } else {
          // 3. SMALLEST 1D BARCODE (Default - Compact Shelf Label)
          final barcodeBytes = await generateBarcodeImageBytes(code, width: 300, height: 44);
          if (barcodeBytes != null) {
            await bluetooth.printImageBytes(barcodeBytes);
          }
          String label = price.isNotEmpty ? "$code  Rs $price" : code;
          await bluetooth.printCustom(label, 0, 1);
          await bluetooth.printNewLine();
          await bluetooth.paperCut();
        }
      } else {
        // 2D QR Code mode
        if (_selectedFormat == 0) {
          // 1. BIG PRINT (A lot of info, big print)
          await bluetooth.printNewLine();
          await bluetooth.printCustom("LOVE KUSH SHOPPING", 2, 1);
          await bluetooth.printCustom("--------------------------------", 1, 1);
          if (name.isNotEmpty) {
            await bluetooth.printCustom(name.toUpperCase(), 2, 1);
          }
          await bluetooth.printCustom("LOC: $code", 2, 1);
          await bluetooth.printNewLine();
          await bluetooth.printQRcode(code, 220, 220, 1);
          await bluetooth.printNewLine();
          if (price.isNotEmpty) {
            await bluetooth.printCustom("MRP: Rs $price", 3, 1);
          }
          await bluetooth.printCustom("--------------------------------", 1, 1);
          await bluetooth.printNewLine();
          await bluetooth.printNewLine();
          await bluetooth.paperCut();
        } else if (_selectedFormat == 1) {
          // 2. MEDIUM PRINT (Medium info, medium size)
          await bluetooth.printNewLine();
          if (name.isNotEmpty) {
            String displayName = name.length > 20 ? name.substring(0, 20) : name;
            await bluetooth.printCustom(displayName.toUpperCase(), 1, 1);
          }
          await bluetooth.printCustom(code, 1, 1);
          await bluetooth.printQRcode(code, 170, 170, 1);
          if (price.isNotEmpty) {
            await bluetooth.printCustom("Rs $price", 2, 1);
          }
          await bluetooth.printNewLine();
          await bluetooth.paperCut();
        } else {
          // 3. SMALLEST PRINT (Just QR, smallest print)
          await bluetooth.printQRcode(code, 120, 120, 1);
          String label = price.isNotEmpty ? "$code  Rs $price" : code;
          await bluetooth.printCustom(label, 0, 1);
          await bluetooth.printNewLine();
          await bluetooth.paperCut();
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Label Printed!")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Print Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String code = locationCode;
    String name = _nameCtrl.text.trim();
    String price = _priceCtrl.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Barcode & Label Printer", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF111827),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            icon: Icon(Icons.circle, size: 12, color: _printerConnected ? Colors.greenAccent : Colors.redAccent),
            label: Text(_printerConnected ? "Connected" : "Connect", style: const TextStyle(color: Colors.white, fontSize: 12)),
            onPressed: _showPrinterDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Format Selector: 3 Options
            const Text("1. Select Label Size & Info Level:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text("Small (1D Barcode)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    selected: _selectedFormat == 2,
                    selectedColor: Colors.orange,
                    labelStyle: TextStyle(color: _selectedFormat == 2 ? Colors.white : Colors.black87),
                    onSelected: (val) => setState(() => _selectedFormat = 2),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    label: const Text("Medium (Standard)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    selected: _selectedFormat == 1,
                    selectedColor: Colors.green,
                    labelStyle: TextStyle(color: _selectedFormat == 1 ? Colors.white : Colors.black87),
                    onSelected: (val) => setState(() => _selectedFormat = 1),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    label: const Text("Big (Full Info)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    selected: _selectedFormat == 0,
                    selectedColor: Colors.blueAccent,
                    labelStyle: TextStyle(color: _selectedFormat == 0 ? Colors.white : Colors.black87),
                    onSelected: (val) => setState(() => _selectedFormat = 0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Barcode Type Selector
            Row(
              children: [
                const Text("Code Type: ", style: TextStyle(fontWeight: FontWeight.bold)),
                ChoiceChip(
                  label: const Text("1D Barcode (Default)"),
                  selected: _codeType == 'barcode',
                  selectedColor: Colors.blueAccent,
                  labelStyle: TextStyle(color: _codeType == 'barcode' ? Colors.white : Colors.black87),
                  onSelected: (_) => setState(() => _codeType = 'barcode'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("2D QR Code"),
                  selected: _codeType == 'qr',
                  selectedColor: Colors.blueAccent,
                  labelStyle: TextStyle(color: _codeType == 'qr' ? Colors.white : Colors.black87),
                  onSelected: (_) => setState(() => _codeType = 'qr'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Location Code Breakdown
            const Text("2. Code & Product Details:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: TextField(controller: _rackCtrl, decoration: const InputDecoration(labelText: "Rack (01)", border: OutlineInputBorder(), isDense: true), onChanged: (_) => setState((){}))),
                const SizedBox(width: 6),
                Expanded(child: TextField(controller: _colCtrl, decoration: const InputDecoration(labelText: "Col (03)", border: OutlineInputBorder(), isDense: true), onChanged: (_) => setState((){}))),
                const SizedBox(width: 6),
                Expanded(child: TextField(controller: _rowCtrl, decoration: const InputDecoration(labelText: "Row (C)", border: OutlineInputBorder(), isDense: true), onChanged: (_) => setState((){}))),
                const SizedBox(width: 6),
                Expanded(child: TextField(controller: _itemCtrl, decoration: const InputDecoration(labelText: "Item (134)", border: OutlineInputBorder(), isDense: true), onChanged: (_) => setState((){}))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: "Item Name", border: OutlineInputBorder(), isDense: true),
                    onChanged: (_) => setState((){}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _priceCtrl,
                    decoration: const InputDecoration(labelText: "Price (₹)", prefixText: "₹", border: OutlineInputBorder(), isDense: true),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState((){}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Live Visual Preview
            const Text("Live Label Preview:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: _selectedFormat == 0 ? 320 : (_selectedFormat == 1 ? 260 : 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black26, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedFormat == 0) ...[
                      const Text("LOVE KUSH SHOPPING", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1.1)),
                      const Divider(thickness: 1.5, color: Colors.black54),
                      Text(name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text("LOC: $code", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.blueAccent)),
                      const SizedBox(height: 12),
                    ] else if (_selectedFormat == 1) ...[
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(code, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 8),
                    ],

                    // Code Rendering
                    if (_codeType == 'qr')
                      QrImageView(
                        data: code,
                        version: QrVersions.auto,
                        size: _selectedFormat == 0 ? 160.0 : (_selectedFormat == 1 ? 120.0 : 80.0),
                        backgroundColor: Colors.white,
                      )
                    else
                      SizedBox(
                        height: _selectedFormat == 0 ? 70 : (_selectedFormat == 1 ? 55 : 40),
                        width: double.infinity,
                        child: bw.BarcodeWidget(
                          barcode: bw.Barcode.code128(),
                          data: code,
                          drawText: false,
                        ),
                      ),
                    
                    const SizedBox(height: 6),
                    if (_selectedFormat == 0) ...[
                      Text("MRP: ₹$price", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: Colors.green)),
                      const Divider(thickness: 1.5, color: Colors.black54),
                    ] else if (_selectedFormat == 1) ...[
                      Text("₹$price", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.green)),
                    ] else ...[
                      Text("$code  ₹$price", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Print Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.print, size: 24),
                label: Text(
                  _selectedFormat == 0 ? "PRINT BIG LABEL (FULL INFO)" : (_selectedFormat == 1 ? "PRINT MEDIUM LABEL" : "PRINT COMPACT BARCODE"),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedFormat == 0 ? Colors.blueAccent : (_selectedFormat == 1 ? Colors.green : Colors.orange.shade800),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _printLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef InventoryQrScreen = BarcodeLabelPrinterScreen;


// ==========================================
// QR CAMERA SCANNER SCREEN
// ==========================================
class QRScannerScreen extends StatefulWidget {
  final String title;
  const QRScannerScreen({Key? key, this.title = "Scan Barcode / QR Label"}) : super(key: key);
  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  late final MobileScannerController controller;
  bool isDetected = false;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      formats: const [BarcodeFormat.all],
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: "Toggle Torch / Flashlight",
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            tooltip: "Switch Camera",
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: (BarcodeCapture capture) {
              if (isDetected) return;
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                final String code = barcodes.first.rawValue!.trim();
                if (code.isNotEmpty) {
                  isDetected = true;
                  HapticFeedback.mediumImpact();
                  controller.stop();
                  Navigator.pop(context, code);
                }
              }
            },
          ),
          Center(
            child: Container(
              width: 280,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: const Text("Align Barcode or QR Sticker", style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: const Text("Supports Shelf Stickers & Product Barcodes", style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<Uint8List?> generateBarcodeImageBytes(String data, {double width = 340, double height = 64}) async {
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    final barPaint = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    final barcode = bw.Barcode.code128();
    final recipe = barcode.make(data, width: width, height: height, drawText: false);
    for (var element in recipe) {
      if (element is bw.BarcodeBar && element.black) {
        canvas.drawRect(Rect.fromLTWH(element.left, element.top, element.width, element.height), barPaint);
      }
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> generateMantraBannerBytes(String text, {double width = 384, double height = 48}) async {
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), bgPaint);

    final textSpan = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(minWidth: width, maxWidth: width);
    final offset = Offset(0, (height - textPainter.height) / 2);
    textPainter.paint(canvas, offset);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

Future<void> printHindiThermalBill({
  required BlueThermalPrinter bluetooth,
  required Map<String, dynamic> bill,
}) async {
  final pdfBytes = await PdfReceiptService.generateReceiptPdf(
    bill,
    language: ReceiptLanguage.hindi,
  );
  await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
    final pngBytes = await page.toPng();
    await bluetooth.printImageBytes(pngBytes);
    break;
  }
  await bluetooth.printNewLine();
  await bluetooth.printNewLine();
  await bluetooth.paperCut();
}

Future<void> executeReprintThermalBill({
  required BuildContext context,
  required BlueThermalPrinter bluetooth,
  required Map<String, dynamic> bill,
  ReceiptLanguage language = ReceiptLanguage.english,
}) async {
  bool? isConnected = await bluetooth.isConnected;
  if (isConnected != true) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please connect printer first!")));
    }
    return;
  }

  try {
    if (language == ReceiptLanguage.hindi) {
      await printHindiThermalBill(bluetooth: bluetooth, bill: bill);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hindi Bill Printed!")));
      }
      return;
    }

    final items = bill['items_json'] is List
        ? (bill['items_json'] as List<dynamic>)
        : (bill['items_json'] is String ? (json.decode(bill['items_json']) as List<dynamic>) : []);
    String bNo = (bill['bill_number'] ?? "N/A").toString();
    String counterName = (bill['counter_name'] ?? "").toString();
    final rawTotal = bill['total_amount'];
    double total = rawTotal is num ? rawTotal.toDouble() : (double.tryParse(rawTotal?.toString() ?? '0') ?? 0.0);

    try {
      ByteData bytesAsset = await rootBundle.load("assets/logo_bw.jpg");
      Uint8List imageBytes = bytesAsset.buffer.asUint8List();
      await bluetooth.printImageBytes(imageBytes);
    } catch (_) {}

    // Top Sanskrit Bhagwan Namaste with Satiya (Always on top)
    try {
      final activeMantra = PdfReceiptService.resolveActiveInvocation(
        bill['invocation_mantra']?.toString().trim().isNotEmpty == true
            ? bill['invocation_mantra'].toString().trim()
            : PdfReceiptService.currentInvocation,
      );
      final mantraBytes = await generateMantraBannerBytes(activeMantra);
      if (mantraBytes != null) {
        await bluetooth.printImageBytes(mantraBytes);
      }
    } catch (_) {}

    await bluetooth.printNewLine();
    await bluetooth.printCustom("LOVE KUSH", 3, 1);
    await bluetooth.printCustom("SHOPPING CENTER", 2, 1);
    await bluetooth.printCustom("A-2/392, Subhash Kansal Marg,", 1, 1);
    await bluetooth.printCustom("Harsh Vihar, Delhi - 110093", 1, 1);
    if (counterName.isNotEmpty && !counterName.toLowerCase().contains("basement")) {
      await bluetooth.printCustom(counterName.toUpperCase(), 1, 1);
    }

    if (bNo != "N/A" && bNo.isNotEmpty) {
      await bluetooth.printCustom("BILL NO: $bNo", 1, 1);
      try {
        final barcodeBytes = await generateBarcodeImageBytes(bNo, width: 340, height: 60);
        if (barcodeBytes != null) {
          await bluetooth.printImageBytes(barcodeBytes);
        } else {
          await bluetooth.printQRcode(bNo, 200, 200, 1);
        }
      } catch (_) {
        try {
          await bluetooth.printQRcode(bNo, 200, 200, 1);
        } catch (_) {}
      }
    }

    await bluetooth.printNewLine();
    await bluetooth.printLeftRight("Item", "Qty x Rate", 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);

    for (var item in items) {
      String name = cleanItemName(
        (item['itemName'] != null && item['itemName'].toString().isNotEmpty)
            ? item['itemName'].toString()
            : (item['item'] ?? '').toString(),
        barcode: item['rawItemCode']?.toString(),
      );
      if (name.length > 20) name = name.substring(0, 20);
      String details = "${item['qty'] ?? 1} x Rs. ${item['rate'] ?? 0}";
      await bluetooth.printLeftRight(name, details, 1);
    }

    await bluetooth.printCustom("--------------------------------", 1, 1);
    await bluetooth.printLeftRight("TOTAL", "Rs. ${total.toStringAsFixed(2)}", 2);
    await bluetooth.printNewLine();

    String pMethod = (bill['payment_method'] ?? "Cash").toString();
    double pTendered = double.tryParse(bill['amount_tendered']?.toString() ?? "0") ?? total;
    double pChange = double.tryParse(bill['change_due']?.toString() ?? "0") ?? (pTendered > total ? (pTendered - total) : 0.0);
    await bluetooth.printLeftRight("PAYMENT", pMethod.toUpperCase(), 1);
    await bluetooth.printLeftRight("Paid Money:", "Rs. ${pTendered.toStringAsFixed(2)}", 1);
    if (pChange > 0) {
      await bluetooth.printLeftRight("Change Given:", "Rs. ${pChange.toStringAsFixed(2)}", 1);
    }
    await bluetooth.printCustom("NO RETURN, NO EXCHANGE", 1, 1);
    await bluetooth.printCustom("Thank you for shopping! Visit again!", 0, 1);
    await bluetooth.printCustom("*** DUPLICATE COPY ***", 1, 1);
    await bluetooth.printNewLine();
    await bluetooth.printNewLine();
    await bluetooth.paperCut();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Duplicate Bill Reprinted!")));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Print Error: $e")));
    }
  }
}

void showReceiptPreviewDialog({
  required BuildContext context,
  required Map<String, dynamic> bill,
  required VoidCallback onPrint,
  void Function(ReceiptLanguage language)? onPrintWithLanguage,
}) {
  final items = bill['items_json'] is List
      ? (bill['items_json'] as List<dynamic>)
      : (bill['items_json'] is String ? (json.decode(bill['items_json']) as List<dynamic>) : []);
  final String bNo = (bill['bill_number'] ?? "N/A").toString();
  final String counterName = (bill['counter_name'] ?? "").toString();
  final rawTotal = bill['total_amount'];
  final double total = rawTotal is num ? rawTotal.toDouble() : (double.tryParse(rawTotal?.toString() ?? '0') ?? 0.0);
  final String pMethod = (bill['payment_method'] ?? "Cash").toString();
  final double pTendered = double.tryParse(bill['amount_tendered']?.toString() ?? "0") ?? total;
  final double pChange = double.tryParse(bill['change_due']?.toString() ?? "0") ?? (pTendered > total ? (pTendered - total) : 0.0);
  final String staffName = (bill['staff_name'] ?? "Staff").toString();
  final DateTime billDate = PdfReceiptService.parseIndianStandardTime(bill['created_at']);
  final String formattedDate =
      "${billDate.day.toString().padLeft(2, '0')}-${billDate.month.toString().padLeft(2, '0')}-${billDate.year} ${billDate.hour.toString().padLeft(2, '0')}:${billDate.minute.toString().padLeft(2, '0')}";

  showDialog(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dialog Header bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF1F2937),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.amberAccent, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        "Receipt Preview (Duplicate)",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "PREVIEW",
                        style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable receipt body styled like thermal receipt paper
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300, width: 1),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Sanskrit Bhagwan Namaste on top always
                        Text(
                          PdfReceiptService.resolveActiveInvocation(
                            bill['invocation_mantra']?.toString().trim().isNotEmpty == true
                                ? bill['invocation_mantra'].toString().trim()
                                : PdfReceiptService.currentInvocation,
                          ),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        // Store branding
                        const Text(
                          "लव कुश शॉपिङ्ग सेण्टर",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          "LOVE KUSH SHOPPING CENTER",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87, letterSpacing: 0.8),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          "A-2/392, Subhash Kansal Marg, Harsh Vihar, Delhi - 110093",
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                        if (counterName.isNotEmpty && !counterName.toLowerCase().contains("basement")) ...[
                          const SizedBox(height: 4),
                          Text(
                            counterName.toUpperCase(),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54),
                          ),
                        ],
                        const SizedBox(height: 10),

                        // Bill Number (Text Only - Barcode is for printed physical bills only)
                        if (bNo != "N/A" && bNo.isNotEmpty) ...[
                          Text(
                            "BILL NO: $bNo",
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 4),
                        ],
                        const SizedBox(height: 10),
                        const Text(
                          "----------------------------------------",
                          style: TextStyle(color: Colors.grey, letterSpacing: 1.5),
                        ),

                        // Column headers
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text("ITEM", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text("QTY x RATE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const Text(
                          "----------------------------------------",
                          style: TextStyle(color: Colors.grey, letterSpacing: 1.5),
                        ),

                        // Items list
                        ...items.map((item) {
                          String name = cleanItemName(
                            (item['itemName'] != null && item['itemName'].toString().isNotEmpty)
                                ? item['itemName'].toString()
                                : (item['item'] ?? '').toString(),
                            barcode: item['rawItemCode']?.toString(),
                          );
                          final qty = item['qty'] ?? 1;
                          final rate = item['rate'] ?? 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "$qty x ₹$rate",
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          );
                        }).toList(),

                        const Text(
                          "----------------------------------------",
                          style: TextStyle(color: Colors.grey, letterSpacing: 1.5),
                        ),

                        // Total
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("TOTAL", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                              Text("₹${total.toStringAsFixed(2)}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                            ],
                          ),
                        ),

                        const Text(
                          "----------------------------------------",
                          style: TextStyle(color: Colors.grey, letterSpacing: 1.5),
                        ),

                        // Payment Details Box
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            children: [
                              if (pMethod.toLowerCase().contains("hybrid")) ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: const [
                                    Text("Payment Method:", style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w600)),
                                    Text("HYBRID", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepPurple)),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Split Details:", style: TextStyle(color: Colors.black54, fontSize: 12)),
                                    Text(
                                      pMethod.replaceAll(RegExp(r'hybrid\s*\(?', caseSensitive: false), '').replaceAll(')', '').trim(),
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.black87),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Payment Method:", style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w600)),
                                    Text(pMethod.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Paid Money:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text("₹${pTendered.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueAccent)),
                                ],
                              ),
                              if (pChange > 0) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Change Given:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF047857))),
                                    Text("₹${pChange.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF047857))),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Staff: $staffName", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            Text("Date: $formattedDate", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text("सधन्यवाद! पुनः पधारें! | Thank you for shopping!", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                        const SizedBox(height: 4),
                        const Text("*** DUPLICATE COPY ***", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ),
              ),
              // Footer Action Buttons
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.black54),
                      tooltip: "Close",
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF2563EB), size: 16),
                        label: const Text("📄 PDF", style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFF2563EB)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          PdfReceiptService.openPdfPreviewDialog(
                            context: context,
                            bill: bill,
                            onThermalPrint: (lang) => executeReprintThermalBill(
                              context: context,
                              bluetooth: BlueThermalPrinter.instance,
                              bill: bill,
                              language: lang,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.share, color: Colors.white, size: 16),
                        label: const Text("📲 WHATSAPP", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          PdfReceiptService.showWhatsAppPdfDialog(context: context, bill: bill);
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Tooltip(
                        message: "Tap to print English, long-press for Hindi",
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.print, color: Colors.white, size: 16),
                          label: const Text("🖨️ PRINT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            onPrint();
                          },
                          onLongPress: () {
                            Navigator.pop(dialogContext);
                            if (onPrintWithLanguage != null) {
                              onPrintWithLanguage(ReceiptLanguage.hindi);
                            } else {
                              onPrint();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({Key? key}) : super(key: key);
  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class IndianFestiveEvent {
  final String name;
  final String hindiName;
  final int approxMonth; // 1-12
  final int approxDay;
  final double demandMultiplier;
  final String focusCategories;
  final String distributorAdvice;
  final IconData icon;

  const IndianFestiveEvent({
    required this.name,
    required this.hindiName,
    required this.approxMonth,
    required this.approxDay,
    required this.demandMultiplier,
    required this.focusCategories,
    required this.distributorAdvice,
    required this.icon,
  });

  DateTime nextOccurrence(DateTime from) {
    var candidate = DateTime(from.year, approxMonth, approxDay);
    if (candidate.isBefore(DateTime(from.year, from.month, from.day))) {
      candidate = DateTime(from.year + 1, approxMonth, approxDay);
    }
    return candidate;
  }
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool isLoading = true;
  double collection = 0.0;
  double cashCollection = 0.0;
  double upiCollection = 0.0;
  int billsCount = 0;
  List<dynamic> pastBills = [];
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  
  String currentFilter = "Today";
  DateTime? customStart;
  DateTime? customEnd;

  // Master Indian Retail Festive & Season Calendar
  final List<IndianFestiveEvent> festiveCalendar = const [
    IndianFestiveEvent(
      name: "Sharad Navratri & Durga Puja",
      hindiName: "शारदीय नवरात्रि एवं दुर्गा पूजा",
      approxMonth: 9,
      approxDay: 28,
      demandMultiplier: 2.6,
      focusCategories: "Festive Makeup, Sindoor, Kajal, Compact Powder, Lipsticks, Nail Enamel",
      distributorAdvice: "Order stock 2 weeks early (by Sept 14). High footfall for cosmetics.",
      icon: Icons.celebration,
    ),
    IndianFestiveEvent(
      name: "Karwa Chauth & Ahoi Ashtami",
      hindiName: "करवा चौथ एवं अहोई अष्टमी",
      approxMonth: 10,
      approxDay: 19,
      demandMultiplier: 3.8,
      focusCategories: "Bangles, Mehendi Cones, Bridal Lipsticks, Waterproof Kajal, Facial Kits, Bindi",
      distributorAdvice: "PEAK COSMETICS RUSH! Order stock 3-4 weeks prior (by Sept 25) to prevent shortages.",
      icon: Icons.favorite,
    ),
    IndianFestiveEvent(
      name: "Dhanteras & Diwali Festival",
      hindiName: "धनतेरस एवं दीपावली महापर्व",
      approxMonth: 11,
      approxDay: 1,
      demandMultiplier: 4.5,
      focusCategories: "Gift Baskets, Luxury Perfumes, Skin Care Hampers, Creams, Premium Cosmetics",
      distributorAdvice: "Year's Biggest Turnover! Distributor orders must arrive and be shelved by Oct 15.",
      icon: Icons.auto_awesome,
    ),
    IndianFestiveEvent(
      name: "Winter Wedding Season (Lagun)",
      hindiName: "शीतकालीन विवाह सीजन (शादी-ब्याह)",
      approxMonth: 11,
      approxDay: 20,
      demandMultiplier: 3.2,
      focusCategories: "Bridal Makeup, Foundations, Concealers, Eyelashes, Hair Sprays, Artificial Jewelry",
      distributorAdvice: "Heavy continuous demand through mid-December. Keep backup cartons in basement.",
      icon: Icons.diversity_1,
    ),
    IndianFestiveEvent(
      name: "Winter Skincare Peak & New Year",
      hindiName: "सर्दियों की स्किनकेयर एवं नव वर्ष",
      approxMonth: 12,
      approxDay: 20,
      demandMultiplier: 2.5,
      focusCategories: "Pond's Cold Cream, Nivea Body Lotions, Vaseline Petroleum Jelly, Lip Balms, Glycerin",
      distributorAdvice: "Ensure bulk cases of 100ml & 200ml cold creams and moisturizing lotions are stocked.",
      icon: Icons.ac_unit,
    ),
    IndianFestiveEvent(
      name: "Spring Wedding Season (Jan-Feb)",
      hindiName: "वसंत विवाह मुहूर्त सीजन",
      approxMonth: 1,
      approxDay: 20,
      demandMultiplier: 2.8,
      focusCategories: "Party Makeup, Waterproof Mascara, Highlighters, Bangles, Deodorants, Perfumes",
      distributorAdvice: "Restock post-Diwali inventory depletion by first week of January.",
      icon: Icons.loyalty,
    ),
    IndianFestiveEvent(
      name: "Holi & Spring Care Transition",
      hindiName: "होली महापर्व एवं त्वचा सुरक्षा",
      approxMonth: 3,
      approxDay: 15,
      demandMultiplier: 2.2,
      focusCategories: "Hair Oils (Coconut/Mustard/Almond), Face Cleansers, Mild Soaps, Post-color Skin Creams",
      distributorAdvice: "Transition off heavy cold creams to light summer face washes and skin shields.",
      icon: Icons.color_lens,
    ),
    IndianFestiveEvent(
      name: "Summer Rush & Chaitra Navratri",
      hindiName: "ग्रीष्मकालीन दैनिक उत्पाद एवं चैत्र नवरात्रि",
      approxMonth: 4,
      approxDay: 10,
      demandMultiplier: 2.0,
      focusCategories: "Prickly Heat Powders (Dermicool/Nycil), Summer Talcs, Deodorants, Sunscreens SPF 30/50",
      distributorAdvice: "High summer volume. Stock cooling talc and roll-ons in front counter trays.",
      icon: Icons.wb_sunny,
    ),
    IndianFestiveEvent(
      name: "Hariyali Teej & Raksha Bandhan",
      hindiName: "हरियाली तीज एवं रक्षाबंधन",
      approxMonth: 8,
      approxDay: 10,
      demandMultiplier: 2.9,
      focusCategories: "Green Bangles, Mehendi Cones, Festive Lip Colors, Sister Gift Sets, Nail Paints",
      distributorAdvice: "Place orders by July 20. Huge crowd for mehendi and bangles 2 days prior to Teej.",
      icon: Icons.card_giftcard,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchDashboardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _fetchDashboardData() async {
    setState(() => isLoading = true);
    try {
      final now = DateTime.now();
      String startISO = "";
      String endISO = "";

      if (currentFilter == "Today") {
        startISO = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
        endISO = DateTime(now.year, now.month, now.day, 23, 59, 59, 999).toUtc().toIso8601String();
      } else if (currentFilter == "This Month") {
        startISO = DateTime(now.year, now.month, 1).toUtc().toIso8601String();
        endISO = DateTime(now.year, now.month + 1, 1).subtract(const Duration(milliseconds: 1)).toUtc().toIso8601String();
      } else if (currentFilter == "Custom" && customStart != null && customEnd != null) {
        startISO = DateTime(customStart!.year, customStart!.month, customStart!.day).toUtc().toIso8601String();
        endISO = DateTime(customEnd!.year, customEnd!.month, customEnd!.day, 23, 59, 59, 999).toUtc().toIso8601String();
      }

      final data = await Supabase.instance.client
          .from('bills')
          .select()
          .gte('created_at', startISO)
          .lte('created_at', endISO)
          .order('created_at', ascending: false);

      double total = 0;
      double cash = 0;
      double upi = 0;
      for (var row in data) {
        final rawAmt = row['total_amount'];
        double amt = rawAmt is num ? rawAmt.toDouble() : (double.tryParse(rawAmt?.toString() ?? '0') ?? 0.0);
        total += amt;
        String method = (row['payment_method'] ?? 'Cash').toString().toLowerCase();
        if (method.contains('upi') || method.contains('online') || method.contains('scanner')) {
          upi += amt;
        } else {
          cash += amt;
        }
      }

      setState(() {
        collection = total;
        cashCollection = cash;
        upiCollection = upi;
        billsCount = data.length;
        pastBills = data;
        isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching data: $e")));
        setState(() => isLoading = false);
      }
    }
  }

  void _reprintBill(Map<String, dynamic> bill, {ReceiptLanguage language = ReceiptLanguage.english}) {
    executeReprintThermalBill(context: context, bluetooth: bluetooth, bill: bill, language: language);
  }

  void _showBillPreview(Map<String, dynamic> bill) {
    showReceiptPreviewDialog(
      context: context,
      bill: bill,
      onPrint: () => _reprintBill(bill),
      onPrintWithLanguage: (lang) => _reprintBill(bill, language: lang),
    );
  }

  void _pickCustomDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        currentFilter = "Custom";
        customStart = picked.start;
        customEnd = picked.end;
      });
      _fetchDashboardData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final sortedFestivals = List<IndianFestiveEvent>.from(festiveCalendar)
      ..sort((a, b) => a.nextOccurrence(now).compareTo(b.nextOccurrence(now)));
    final nextEvent = sortedFestivals.isNotEmpty ? sortedFestivals.first : null;
    final int daysToNextEvent = nextEvent != null
        ? nextEvent.nextOccurrence(now).difference(DateTime(now.year, now.month, now.day)).inDays
        : 0;

    double avgBillValue = billsCount > 0 ? collection / billsCount : 0.0;
    double cashPercent = collection > 0 ? (cashCollection / collection) * 100 : 0.0;
    double upiPercent = collection > 0 ? (upiCollection / collection) * 100 : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin & Festive Analytics", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF111827),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amberAccent,
          labelColor: Colors.amberAccent,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(icon: Icon(Icons.analytics_outlined), text: "Sales & Cash Flow"),
            Tab(icon: Icon(Icons.celebration_outlined), text: "Festive AI Predictions"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: SALES & CASH FLOW
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    FilterChip(
                      label: const Text("Today"),
                      selected: currentFilter == "Today",
                      onSelected: (_) { setState(() => currentFilter = "Today"); _fetchDashboardData(); },
                    ),
                    FilterChip(
                      label: const Text("This Month"),
                      selected: currentFilter == "This Month",
                      onSelected: (_) { setState(() => currentFilter = "This Month"); _fetchDashboardData(); },
                    ),
                    ActionChip(
                      label: Text(currentFilter == "Custom" ? "Custom Range ✓" : "Custom Range"),
                      onPressed: _pickCustomDates,
                    ),
                  ],
                ),
              ),

              // Overview Cards
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.blue.shade50.withOpacity(0.6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${currentFilter.toUpperCase()} TOTAL COLLECTION",
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black54, letterSpacing: 1.1),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "₹${collection.toStringAsFixed(2)}",
                                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF1D4ED8)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text("BILLS: $billsCount", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                              const SizedBox(height: 2),
                              Text("Avg: ₹${avgBillValue.toStringAsFixed(0)} / bill", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Colors.black54)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Cash vs UPI Split
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
                            child: Row(
                              children: [
                                const Icon(Icons.payments_outlined, size: 16, color: Colors.green),
                                const SizedBox(width: 6),
                                Text("Cash: ₹${cashCollection.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green)),
                                const Spacer(),
                                Text("${cashPercent.toStringAsFixed(0)}%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade900)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
                            child: Row(
                              children: [
                                const Icon(Icons.qr_code_2, size: 16, color: Colors.indigo),
                                const SizedBox(width: 6),
                                Text("UPI: ₹${upiCollection.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
                                const Spacer(),
                                Text("${upiPercent.toStringAsFixed(0)}%", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.indigo.shade900)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Row(
                  children: [
                    Text("${currentFilter.toUpperCase()} BILLS", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text("$billsCount total", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),

              if (isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (pastBills.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey),
                        const SizedBox(height: 12),
                        Text("No bills generated for $currentFilter", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: pastBills.length,
                    itemBuilder: (context, index) {
                      final bill = pastBills[index];
                      String bNo = bill['bill_number'] ?? "N/A";
                      String pMethod = bill['payment_method'] ?? 'Cash';
                      bool isUpi = pMethod.toLowerCase().contains('upi') || pMethod.toLowerCase().contains('online');

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isUpi ? Colors.indigo.shade100 : Colors.green.shade100,
                          child: Icon(isUpi ? Icons.qr_code_2 : Icons.payments, color: isUpi ? Colors.indigo : Colors.green),
                        ),
                        title: Text("₹${bill['total_amount']}  (No: $bNo)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        subtitle: Text("Paid: ₹${bill['amount_tendered'] ?? bill['total_amount']} • Change: ₹${bill['change_due'] ?? 0} ($pMethod)\nStaff: ${bill['staff_name']} • Counter: ${bill['counter_name']}"),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              () {
                                final dt = PdfReceiptService.parseIndianStandardTime(bill['created_at']);
                                return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
                              }(),
                              style: const TextStyle(color: Colors.black54, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.picture_as_pdf, size: 20, color: Color(0xFF2563EB)),
                                  tooltip: "Preview PDF",
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: () => PdfReceiptService.openPdfPreviewDialog(
                                    context: context,
                                    bill: bill,
                                    onThermalPrint: (lang) => executeReprintThermalBill(
                                      context: context,
                                      bluetooth: BlueThermalPrinter.instance,
                                      bill: bill,
                                      language: lang,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                IconButton(
                                  icon: const Icon(Icons.share, size: 20, color: Color(0xFF25D366)),
                                  tooltip: "WhatsApp / PDF",
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  onPressed: () => PdfReceiptService.showWhatsAppPdfDialog(context: context, bill: bill),
                                ),
                                const SizedBox(width: 4),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.print, size: 14, color: Colors.white),
                                  label: const Text("Reprint", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => _showBillPreview(bill),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () => _showBillPreview(bill),
                      );
                    },
                  ),
                ),
            ],
          ),

          // TAB 2: FESTIVE INTELLIGENCE & 2026/2027 FORECASTS
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Next upcoming festival spotlight banner
              if (nextEvent != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF831843), Color(0xFFBE185D)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(nextEvent.icon, color: Colors.amberAccent, size: 28),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "UPCOMING FESTIVAL SPIKE • IN $daysToNextEvent DAYS",
                                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.1),
                                ),
                                Text(
                                  nextEvent.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  nextEvent.hindiName,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              children: [
                                Text("${nextEvent.demandMultiplier}x", style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w900, fontSize: 18)),
                                const Text("Surge", style: TextStyle(color: Colors.white70, fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 6),
                      Text("🎯 Key Focus Stock: ${nextEvent.focusCategories}", style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text("📦 Distributor Action: ${nextEvent.distributorAdvice}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),

              const SizedBox(height: 20),
              Row(
                children: const [
                  Icon(Icons.calendar_month, color: Colors.blueAccent, size: 20),
                  SizedBox(width: 8),
                  Text("Indian Retail Festive Season Roadmap", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "Seasonal multipliers calibrated for Indian cosmetics, bangles & personal care cycles:",
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),

              ...sortedFestivals.map((ev) {
                final days = ev.nextOccurrence(now).difference(DateTime(now.year, now.month, now.day)).inDays;
                return Card(
                  elevation: 1.5,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Colors.pink.shade50,
                              child: Icon(ev.icon, color: Colors.pink, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ev.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text(ev.hindiName, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: days <= 30 ? Colors.amber.shade100 : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                days == 0 ? "TODAY" : "In $days Days",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: days <= 30 ? Colors.amber.shade900 : Colors.blue.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text("Expected Demand: ~${ev.demandMultiplier}x Standard Turnover", style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.green)),
                        const SizedBox(height: 2),
                        Text("Top Products: ${ev.focusCategories}", style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        const SizedBox(height: 2),
                        Text("Advice: ${ev.distributorAdvice}", style: const TextStyle(fontSize: 11, color: Colors.black54)),
                      ],
                    ),
                  ),
                );
              }).toList(),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade300)),
                child: Row(
                  children: const [
                    Icon(Icons.lightbulb, color: Color(0xFFD97706)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Pro-Tip: Use the stock updater in Item Codes to restock cartons before the festive rush hits. Shelf tags can be printed in seconds using the 1D Barcode thermal printer.",
                        style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ],
      ),
    );
  }
}
