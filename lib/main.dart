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
import 'firebase_options.dart';
import 'cosmetics_catalog.dart';

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
                  const Text("लव कुश शॉपिङ्ग सेण्टर", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.2)),
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

Future<Map<String, String>?> fetchOpenBeautyFacts(String barcode) async {
  final endpoints = [
    "https://world.openbeautyfacts.org/api/v0/product/$barcode.json",
    "https://world.openfoodfacts.org/api/v0/product/$barcode.json",
    "https://world.openproductsfacts.org/api/v0/product/$barcode.json",
  ];

  for (final url in endpoints) {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 3);
      final uri = Uri.parse(url);
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'LoveKushPOS/1.0 (Retail Scanner)');
      final response = await request.close().timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final data = json.decode(body);
        if (data is Map && data['status'] == 1 && data['product'] != null) {
          final prod = data['product'];
          String name = (prod['product_name'] ?? prod['product_name_en'] ?? '').toString().trim();
          String brand = (prod['brands'] ?? '').toString().trim();
          String category = (prod['categories'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            if (brand.isNotEmpty && !name.toLowerCase().contains(brand.toLowerCase())) {
              name = "$brand $name";
            }
            return {'name': name, 'brand': brand, 'category': category};
          }
        }
      }
    } catch (_) {}
  }
  return null;
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

  // Scanned items waiting for shelf assignment (never lost!)
  static List<Map<String, dynamic>> pendingScannedItems = [];

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

      // Remove from pending scanned queue since it is now assigned and saved to shop stock!
      setState(() {
        pendingScannedItems.removeWhere((p) =>
          (p['barcode'] ?? '') == (companyBarcode ?? '') || (p['barcode'] ?? '') == code
        );
      });

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

      // Check local cosmeticDatabase
      for (var c in cosmeticDatabase) {
        if ((c['barcode'] ?? '').toString().toUpperCase() == clean.toUpperCase()) {
          masterMatch = {
            'name': c['name'],
            'price': c['price'],
            'category': c['category'],
            'brand': c['brand'] ?? '',
          };
          break;
        }
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

      // Check Open Beauty Facts if 8+ digit commercial barcode
      final digitsOnly = clean.replaceAll(RegExp(r'[^0-9]'), '');
      if (masterMatch == null && clean.length >= 8 && digitsOnly.length == clean.length) {
        final obf = await fetchOpenBeautyFacts(clean);
        if (obf != null && obf['name'] != null && obf['name']!.isNotEmpty) {
          masterMatch = {
            'name': obf['name'],
            'price': 0.0,
            'category': obf['category'] ?? 'Cosmetics',
            'brand': obf['brand'] ?? '',
          };
        }
      }

      // 3. Recognized in Master Catalog / Backup OR New Item:
      // Record in pending queue so it NEVER goes empty or gets lost!
      if (masterMatch != null) {
        if (!pendingScannedItems.any((p) => (p['barcode'] ?? '') == clean)) {
          setState(() {
            pendingScannedItems.insert(0, {
              'barcode': clean,
              'name': masterMatch!['name'],
              'brand': masterMatch['brand'] ?? '',
              'price': masterMatch['price'] ?? 0.0,
              'category': masterMatch['category'] ?? 'Cosmetics',
            });
          });
        }
        if (mounted) {
          _showRecognizedMasterProductDialog(clean, masterMatch);
        }
      } else {
        // Unrecognized barcode: record in pending & prompt to add
        if (!pendingScannedItems.any((p) => (p['barcode'] ?? '') == clean)) {
          setState(() {
            pendingScannedItems.insert(0, {
              'barcode': clean,
              'name': 'New Scanned Product ($clean)',
              'brand': '',
              'price': 0.0,
              'category': 'Cosmetics',
            });
          });
        }
        if (mounted) {
          if (clean.length >= 8 && digitsOnly.length == clean.length) {
            _showAddEditDialog(null, null, null, null, clean);
          } else {
            _showAddEditDialog(null, clean);
          }
        }
      }
    }
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
      String shelf = existing['shelf_location'] ?? '';
      String num = existing['item_number'] ?? '';
      if (shelf.isNotEmpty) {
        initialShelfCode = num.isNotEmpty ? "$shelf-$num" : shelf;
      } else {
        initialShelfCode = existing['item_code'] ?? '';
      }
    } else if (prefilledCode != null && prefilledCode.isNotEmpty) {
      initialShelfCode = prefilledCode;
    } else {
      initialShelfCode = "${_lastRack.padLeft(2, '0')}-${_lastCol.padLeft(2, '0')}-${_lastRow.toUpperCase()}-${_lastItemNum + 1}";
    }

    final companyBarcodeCtrl = TextEditingController(text: initialCompanyBarcode);
    final shelfCodeCtrl = TextEditingController(text: initialShelfCode);
    final nameCtrl = TextEditingController(text: isEdit ? (existing['item_name'] ?? '') : (prefilledName ?? ''));
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
                              tooltip: "Fetch Name from Open Beauty Facts",
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
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Fetched: ${obf['name']}")));
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No match on Open Beauty Facts. Enter name manually.")));
                                  }
                                });
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent, size: 20),
                            tooltip: "Scan Box Barcode",
                            onPressed: () async {
                              final scanned = await Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
                              if (scanned != null && scanned is String && scanned.isNotEmpty) {
                                setDialogState(() => companyBarcodeCtrl.text = scanned.trim());
                                // Attempt auto-fetch name
                                setDialogState(() => isFetchingObf = true);
                                final obf = await fetchOpenBeautyFacts(scanned.trim());
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
                        tooltip: "Scan Shelf Sticker",
                        onPressed: () async {
                          final scanned = await Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
                          if (scanned != null && scanned is String && scanned.isNotEmpty) {
                            setDialogState(() => shelfCodeCtrl.text = scanned.trim().toUpperCase());
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
    final filtered = items.where((it) {
      final q = searchQuery.toLowerCase();
      final code = (it['item_code'] ?? '').toString().toLowerCase();
      final name = (it['item_name'] ?? '').toString().toLowerCase();
      return code.contains(q) || name.contains(q);
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
          if (pendingScannedItems.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFF59E0B)),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.12),
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
                      const Icon(Icons.pending_actions, color: Color(0xFFD97706), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "${pendingScannedItems.length} Scanned Item${pendingScannedItems.length > 1 ? 's' : ''} Ready to Assign Shelf",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E)),
                        ),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                        onPressed: () => setState(() => pendingScannedItems.clear()),
                        child: const Text("Clear All", style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Tap any item to assign its shelf number and save to shop stock:",
                    style: TextStyle(fontSize: 11, color: Color(0xFFB45309)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: pendingScannedItems.map((p) {
                      return ActionChip(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        avatar: const Icon(Icons.add_location_alt, size: 14, color: Color(0xFFD97706)),
                        label: Text(
                          "${p['name']} (₹${(p['price'] as num?)?.toInt() ?? 0})",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF92400E)),
                        ),
                        onPressed: () {
                          _showAddEditDialog(
                            null,
                            null,
                            p['name'],
                            (p['price'] as num?)?.toDouble() ?? 0.0,
                            p['barcode'],
                          );
                        },
                      );
                    }).toList(),
                  ),
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

                          String displayLoc = shelfLoc.isNotEmpty
                              ? (itemNum.isNotEmpty ? "$shelfLoc-$itemNum" : "$shelfLoc (Shelf Only)")
                              : code;

                          return Card(
                            elevation: 1.5,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () {
                                if (widget.selectMode) {
                                  Navigator.pop(context, item);
                                } else {
                                  _showAddEditDialog(item);
                                }
                              },
                              leading: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  displayLoc.length >= 2 ? displayLoc.substring(0, 2) : "##",
                                  style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.blueAccent, fontSize: 16),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(name.isNotEmpty ? name : "Unnamed Item", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text("📍 Shelf: $displayLoc", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo, fontSize: 12)),
                                  if (companyBar.isNotEmpty)
                                    Text("🏭 Barcode: $companyBar", style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey.shade700, fontSize: 11)),
                                  if (category.isNotEmpty && category != "General")
                                    Text("🏷️ Category: $category", style: TextStyle(fontWeight: FontWeight.w500, color: Colors.grey.shade600, fontSize: 11)),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text("₹${price.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.green)),
                                      if (mrp > price)
                                        Text("MRP ₹${mrp.toStringAsFixed(0)}", style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 10)),
                                    ],
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.print, size: 20, color: Colors.green),
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
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20, color: Colors.blueAccent),
                                    onPressed: () => _showAddEditDialog(item),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                                    onPressed: () => _deleteItem(code),
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
            };
          }
        });
      }
    } catch (e) {
      print("Inventory Sync Error: $e");
    }
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
      double p = (item['price'] as num?)?.toDouble() ?? 0.0;
      if (p > 0) {
        rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
      }
      focusedField = 1; // Advance directly to QTY
    });
  }

  void _showConflictSelectionSheet(List<Map<String, dynamic>> matches, String query) {
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
                      child: Icon(Icons.touch_app, color: Colors.amber.shade900, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Select Product (${matches.length} on Shelf)",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            "Shelf / Code: $query",
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
                const SizedBox(height: 8),
                const Text(
                  "Multiple items share this location. Tap to select:",
                  style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: matches.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (c, idx) {
                      final it = matches[idx];
                      final name = it['item_name'] ?? 'Unnamed Product';
                      final price = (it['price'] as num?)?.toDouble() ?? 0.0;
                      final shelf = it['shelf_location'] ?? '';
                      final itemNum = it['item_number'] ?? '';
                      final barcode = it['company_barcode'] ?? '';
                      final mrp = (it['mrp'] as num?)?.toDouble() ?? 0.0;

                      return InkWell(
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyResolvedItem(it);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Selected: $name (₹${price % 1 == 0 ? price.toInt() : price})"),
                              duration: const Duration(milliseconds: 1500),
                              backgroundColor: const Color(0xFF10B981),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text(
                                    itemNum.isNotEmpty ? itemNum : "${idx + 1}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Color(0xFF047857),
                                    ),
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
                                    const SizedBox(height: 3),
                                    Row(
                                      children: [
                                        if (shelf.isNotEmpty)
                                          Text("📍 $shelf", style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                                        if (shelf.isNotEmpty && barcode.isNotEmpty)
                                          Text(" • ", style: TextStyle(color: Colors.grey.shade400)),
                                        if (barcode.isNotEmpty)
                                          Text("🏷️ $barcode", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                        if (mrp > price) ...[
                                          Text(" • ", style: TextStyle(color: Colors.grey.shade400)),
                                          Text("MRP ₹${mrp % 1 == 0 ? mrp.toInt() : mrp}",
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500, decoration: TextDecoration.lineThrough)),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "₹${price % 1 == 0 ? price.toInt() : price}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
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

  void addToCart() {
    if (rawItemCode.isEmpty || rate.isEmpty) return;
    final match = _lookupItem(rawItemCode);
    String itemName = match != null ? (match['item_name'] ?? '') : '';
    if (itemName.isEmpty) {
      // Check backup database so cart item name is NEVER blank!
      for (var c in cosmeticDatabase) {
        if ((c['barcode'] ?? '').toString().toUpperCase() == rawItemCode.toUpperCase()) {
          itemName = c['name'] ?? '';
          break;
        }
      }
    }
    String displayTitle = itemName.isNotEmpty ? "$itemName\n$formattedItemCode" : formattedItemCode;

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
        if (focusedField == 0) {
          final matches = _lookupAllMatches(rawItemCode);
          if (matches.length == 1) {
            _applyResolvedItem(matches.first);
            return;
          } else if (matches.length > 1) {
            _showConflictSelectionSheet(matches, rawItemCode);
            return;
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
            final matches = _lookupAllMatches(rawItemCode);
            if (matches.length == 1) {
              double p = (matches.first['price'] as num?)?.toDouble() ?? 0.0;
              if (p > 0) {
                rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
              }
            } else {
              rate = "";
            }
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
            final matches = _lookupAllMatches(rawItemCode);
            if (matches.length == 1) {
              double p = (matches.first['price'] as num?)?.toDouble() ?? 0.0;
              if (p > 0) {
                rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
              }
            } else {
              rate = "";
            }
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

  void _saveAndPrintBill() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    
    String billNumber = "";
    try {
      final data = await Supabase.instance.client.from('bills').select('id').gte('created_at', startOfDay);
      int count = data.length + 1;
      
      String dateStr = "${now.day.toString().padLeft(2, '0')}${now.month.toString().padLeft(2, '0')}${now.year.toString().substring(2)}";
      String sellerCode = _getSellerCode(widget.userEmail);
      billNumber = "$dateStr$sellerCode${count.toString().padLeft(4, '0')}";
    } catch (e) {
      billNumber = "${now.millisecondsSinceEpoch}";
    }

    double finalChangeDue = 0.0;
    if (paymentMethod == 'Cash') {
      finalChangeDue = (double.tryParse(amountTendered) ?? 0.0) - cartTotal;
    } else if (paymentMethod == 'Hybrid') {
      finalChangeDue = ((double.tryParse(amountTendered) ?? 0.0) + (double.tryParse(onlineAmount) ?? 0.0)) - cartTotal;
    }

    // 1. Save to Supabase
    try {
      await Supabase.instance.client.from('bills').insert({
        'bill_number': billNumber,
        'staff_name': widget.userName,
        'counter_name': counterName,
        'total_amount': cartTotal,
        'items_json': cart,
        'payment_method': paymentMethod,
        'amount_tendered': double.tryParse(amountTendered) ?? 0.0,
        'change_due': finalChangeDue,
      });
    } catch (dbError) {
      print("Supabase Error: $dbError");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cloud Sync Failed: $dbError")));
      return; 
    }

    // 2. Try Printing if connected
    if (_printerConnected) {
      try {
        bool? isConnected = await bluetooth.isConnected;
        if (isConnected == true) {
          ByteData bytesAsset = await rootBundle.load("assets/logo_bw.jpg");
          Uint8List imageBytes = bytesAsset.buffer.asUint8List();
          await bluetooth.printImageBytes(imageBytes);
          
          await bluetooth.printNewLine();
          await bluetooth.printCustom("LOVE KUSH", 3, 1); 
          await bluetooth.printCustom("SHOPPING CENTER", 2, 1); 
          await bluetooth.printCustom(counterName.toUpperCase(), 1, 1);
          await bluetooth.printCustom("BILL NO: $billNumber", 1, 1);
          try { await bluetooth.printQRcode(billNumber, 200, 200, 1); } catch(e){}
          
          await bluetooth.printNewLine();
          await bluetooth.printLeftRight("Item", "Qty x Rate", 1);
          await bluetooth.printCustom("--------------------------------", 1, 1);
          
          for (var item in cart) {
            String name = (item["itemName"] != null && item["itemName"].toString().isNotEmpty)
                ? item["itemName"].toString()
                : item["item"].toString();
            if (name.contains("\n")) name = name.split("\n")[0];
            if (name.length > 15) name = name.substring(0, 15);
            String details = "${item["qty"]} x ₹${item["rate"]}";
            await bluetooth.printLeftRight(name, details, 1);
          }
          
          await bluetooth.printCustom("--------------------------------", 1, 1);
          await bluetooth.printLeftRight("TOTAL", "₹${cartTotal.toStringAsFixed(2)}", 2); 
          await bluetooth.printNewLine();
          
          await bluetooth.printLeftRight("PAYMENT", paymentMethod.toUpperCase(), 1);
          if (paymentMethod == "Cash" && double.tryParse(amountTendered) != null) {
            double tendered = double.tryParse(amountTendered)!;
            await bluetooth.printLeftRight("Tendered:", "Rs${tendered.toStringAsFixed(2)}", 1);
            await bluetooth.printLeftRight("Change:", "Rs${(tendered - cartTotal).toStringAsFixed(2)}", 1);
          } else if (paymentMethod == "Hybrid") {
            await bluetooth.printLeftRight("Cash:", "Rs${amountTendered}", 1);
            await bluetooth.printLeftRight("Online:", "Rs${onlineAmount}", 1);
            if (finalChangeDue > 0) {
              await bluetooth.printLeftRight("Change:", "Rs${finalChangeDue.toStringAsFixed(2)}", 1);
            }
          }
          await bluetooth.printNewLine();

          await bluetooth.printCustom("Thank you for shopping!", 1, 1);
          await bluetooth.printCustom("No Exchange / No Refund", 1, 1);
          await bluetooth.printNewLine();
          await bluetooth.printNewLine();
          await bluetooth.paperCut();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bill Saved & Printed!")));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Printer lost connection. Bill Saved to Cloud Only.")));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Printer Error: $e. Bill Saved to Cloud Only.")));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bill Saved to Cloud Only")));
    }

    // 3. Clear Cart
    confirmPrint();
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
                leading: const Icon(Icons.dashboard, color: Colors.blueAccent),
                title: const Text('Admin Dashboard (Past Bills)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
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
            ListTile(
              leading: const Icon(Icons.price_change_outlined, color: Colors.blueAccent),
              title: const Text('Item Codes & Rates', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              subtitle: const Text('Lookup, edit, and map item rates'),
              onTap: () {
                Navigator.pop(context);
                _openItemCatalog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2, color: Colors.indigo),
              title: const Text('Print Barcode Labels', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
              subtitle: const Text('3 Print Sizes: Large, Medium, Compact'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const BarcodeLabelPrinterScreen()));
              },
            ),
            ListTile(
              leading: Icon(Icons.print, color: _printerConnected ? Colors.green : Colors.black87),
              title: Text(_printerConnected ? 'Printer Connected' : 'Connect Printer', style: TextStyle(fontWeight: FontWeight.bold, color: _printerConnected ? Colors.green : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _showPrinterDialog();
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
        title: const Text('लव कुश शॉपिङ्ग सेण्टर', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black), 
        actions: [
          IconButton(
            tooltip: "Item Codes & Rates",
            icon: const Icon(Icons.menu_book, color: Colors.blueAccent),
            onPressed: _openItemCatalog,
          ),
        ],
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
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: ActionChip(
                          backgroundColor: Colors.green.shade50,
                          side: const BorderSide(color: Colors.green),
                          label: const Text("+ New Customer", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          onPressed: () {
                            setState(() {
                              activeBills.add([]);
                              currentBillIndex = activeBills.length - 1;
                            });
                          }
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: ActionChip(
                          avatar: const Icon(Icons.menu_book, size: 16, color: Colors.blueAccent),
                          backgroundColor: Colors.blue.shade50,
                          side: const BorderSide(color: Colors.blueAccent),
                          label: const Text("Codes & Rates", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                          onPressed: _openItemCatalog,
                        ),
                      ),
                    ],
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.black12, width: 1)),
            ),
            child: Row(
              children: [
                () {
                  final matches = _lookupAllMatches(rawItemCode);
                  String? codeSubtext;
                  Color? subColor;
                  VoidCallback? onConflictTap;

                  if (matches.length == 1) {
                    codeSubtext = "${matches.first['item_name']} (₹${matches.first['price']})";
                    subColor = focusedField == 0 ? Colors.greenAccent : Colors.green.shade700;
                  } else if (matches.length > 1) {
                    codeSubtext = "⚠️ ${matches.length} items (Tap to pick)";
                    subColor = focusedField == 0 ? Colors.amberAccent : Colors.amber.shade800;
                    onConflictTap = () => _showConflictSelectionSheet(matches, rawItemCode);
                  } else if (rawItemCode.isNotEmpty) {
                    for (var c in cosmeticDatabase) {
                      if ((c['barcode'] ?? '').toString().toUpperCase() == rawItemCode.toUpperCase()) {
                        codeSubtext = "✨ ${c['name']} (MRP ₹${c['price']}) • From Backup";
                        subColor = focusedField == 0 ? Colors.cyanAccent : Colors.teal.shade700;
                        break;
                      }
                    }
                  }
                  return _buildInputBox(
                    "ITEM CODE",
                    formattedItemCode,
                    focusedField == 0,
                    0,
                    flex: 8,
                    isCode: true,
                    subtext: codeSubtext,
                    subtextColor: subColor,
                    onCustomTap: onConflictTap,
                  );
                }(),
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
                          final scannedVal = barcodes.first.rawValue!;
                          final parsedRaw = _parseToRaw(scannedVal);
                          setState(() {
                            rawItemCode = parsedRaw;
                            isScanning = false; // instantly close camera to show keypad
                          });
                          final matches = _lookupAllMatches(parsedRaw);
                          if (matches.length == 1) {
                            _applyResolvedItem(matches.first);
                          } else if (matches.length > 1) {
                            _showConflictSelectionSheet(matches, parsedRaw);
                          } else {
                            // Check Master Reference Database / Backup
                            bool foundInMaster = false;
                            for (var c in cosmeticDatabase) {
                              if ((c['barcode'] ?? '').toString().toUpperCase() == parsedRaw.toUpperCase()) {
                                setState(() {
                                  double p = (c['price'] as num?)?.toDouble() ?? 0.0;
                                  if (p > 0) rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
                                  focusedField = 1;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Backup Recognized: ${c['name']} (MRP ₹$rate)"),
                                    duration: const Duration(seconds: 3),
                                    backgroundColor: Colors.teal,
                                    action: SnackBarAction(
                                      label: "ASSIGN SHELF",
                                      textColor: Colors.amberAccent,
                                      onPressed: () => _openItemCatalog(),
                                    ),
                                  ),
                                );
                                foundInMaster = true;
                              }
                            }
                            if (!foundInMaster) {
                              setState(() {
                                focusedField = 2; // jump to rate
                              });
                            }
                          }
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
    double changeDue = 0;
    if (paymentMethod == 'Cash' && double.tryParse(amountTendered) != null) {
      changeDue = double.parse(amountTendered) - cartTotal;
    } else if (paymentMethod == 'Hybrid') {
      double cash = double.tryParse(amountTendered) ?? 0.0;
      double online = double.tryParse(onlineAmount) ?? 0.0;
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
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 16),
                            if (paymentMethod == "Cash") ...[
                              TextField(
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: "Cash Given (₹)", prefixIcon: Icon(Icons.money), border: OutlineInputBorder()),
                                onChanged: (val) => setState(() => amountTendered = val),
                              ),
                              const SizedBox(height: 12),
                              Text("Change Due: ₹${changeDue.toStringAsFixed(2)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: changeDue >= 0 ? Colors.green : Colors.red)),
                            ],
                            if (paymentMethod == "Hybrid") ...[
                              Row(
                                children: [
                                  Expanded(child: TextField(keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Cash (₹)", border: OutlineInputBorder()), onChanged: (val) => setState(() => amountTendered = val))),
                                  const SizedBox(width: 10),
                                  Expanded(child: TextField(keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Online (₹)", border: OutlineInputBorder()), onChanged: (val) => setState(() => onlineAmount = val))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text("Change Due: ₹${changeDue.toStringAsFixed(2)}", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: changeDue >= 0 ? Colors.green : Colors.red)),
                            ]
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text("RECEIPT PREVIEW", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                      const Divider(thickness: 2),
                      
                      // 2. RECEIPT PREVIEW
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
                    ],
                  ),
                ),
              ),
            ),
            
            // ACTION BUTTONS
            Container(
              padding: const EdgeInsets.all(24),
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
                      onPressed: _saveAndPrintBill, 
                      child: Text(_printerConnected ? "🖨️ SAVE & PRINT" : "☁️ SAVE BILL", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    ),
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
  int _selectedFormat = 1;
  // 'qr' or 'barcode'
  String _codeType = 'qr';

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
        // 3. SMALLEST PRINT (Just barcode, smallest print)
        await bluetooth.printQRcode(code, 120, 120, 1);
        String label = price.isNotEmpty ? "$code  Rs $price" : code;
        await bluetooth.printCustom(label, 0, 1);
        await bluetooth.printNewLine();
        await bluetooth.paperCut();
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
                    label: const Text("Big (Full Info)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    selected: _selectedFormat == 0,
                    selectedColor: Colors.blueAccent,
                    labelStyle: TextStyle(color: _selectedFormat == 0 ? Colors.white : Colors.black87),
                    onSelected: (val) => setState(() => _selectedFormat = 0),
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
                    label: const Text("Small (Barcode Only)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    selected: _selectedFormat == 2,
                    selectedColor: Colors.orange,
                    labelStyle: TextStyle(color: _selectedFormat == 2 ? Colors.white : Colors.black87),
                    onSelected: (val) => setState(() => _selectedFormat = 2),
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
                  label: const Text("2D QR Code"),
                  selected: _codeType == 'qr',
                  onSelected: (_) => setState(() => _codeType = 'qr'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("1D Barcode (Code128)"),
                  selected: _codeType == 'barcode',
                  onSelected: (_) => setState(() => _codeType = 'barcode'),
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
  double collection = 0.0;
  List<dynamic> pastBills = [];
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  
  String currentFilter = "Today";
  DateTime? customStart;
  DateTime? customEnd;

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  void _fetchDashboardData() async {
    setState(() => isLoading = true);
    try {
      final now = DateTime.now();
      String startISO = "";
      String endISO = "";

      if (currentFilter == "Today") {
        startISO = DateTime(now.year, now.month, now.day).toIso8601String();
        endISO = DateTime(now.year, now.month, now.day, 23, 59, 59).toIso8601String();
      } else if (currentFilter == "This Month") {
        startISO = DateTime(now.year, now.month, 1).toIso8601String();
        endISO = DateTime(now.year, now.month + 1, 0, 23, 59, 59).toIso8601String();
      } else if (currentFilter == "Custom" && customStart != null && customEnd != null) {
        startISO = customStart!.toIso8601String();
        endISO = DateTime(customEnd!.year, customEnd!.month, customEnd!.day, 23, 59, 59).toIso8601String();
      }

      final data = await Supabase.instance.client
          .from('bills')
          .select()
          .gte('created_at', startISO)
          .lte('created_at', endISO)
          .order('created_at', ascending: false);

      double total = 0;
      for (var row in data) {
        total += (row['total_amount'] as num).toDouble();
      }

      setState(() {
        collection = total;
        pastBills = data;
        isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error fetching data: $e")));
      setState(() => isLoading = false);
    }
  }


  void _reprintBill(Map<String, dynamic> bill) async {
    bool? isConnected = await bluetooth.isConnected;
    if (isConnected != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please connect printer first!")));
      return;
    }
    
    try {
      final items = bill['items_json'] as List<dynamic>;
      String bNo = bill['bill_number'] ?? "N/A";
      String counterName = bill['counter_name'].toString();
      double total = (bill['total_amount'] as num).toDouble();
      
      ByteData bytesAsset = await rootBundle.load("assets/logo_bw.jpg");
      Uint8List imageBytes = bytesAsset.buffer.asUint8List();
      await bluetooth.printImageBytes(imageBytes);
      
      await bluetooth.printNewLine();
      await bluetooth.printCustom("LOVE KUSH", 3, 1); 
      await bluetooth.printCustom("SHOPPING CENTER", 2, 1); 
      await bluetooth.printCustom(counterName.toUpperCase(), 1, 1);
      
      if (bNo != "N/A") {
        await bluetooth.printCustom("BILL NO: $bNo", 1, 1);
        try { await bluetooth.printQRcode(bNo, 200, 200, 1); } catch(e){}
      }
      
      await bluetooth.printNewLine();
      await bluetooth.printLeftRight("Item", "Qty x Rate", 1);
      await bluetooth.printCustom("--------------------------------", 1, 1);
      
      for (var item in items) {
        String name = item['item'].toString();
        if (name.length > 15) name = name.substring(0, 15);
        String details = "${item['qty']} x ₹${item['rate']}";
        await bluetooth.printLeftRight(name, details, 1);
      }
      
      await bluetooth.printCustom("--------------------------------", 1, 1);
      await bluetooth.printLeftRight("TOTAL", "₹${total.toStringAsFixed(2)}", 2); 
      await bluetooth.printNewLine();
      
      
      String pMethod = bill['payment_method']?.toString() ?? "Cash";
      double pTendered = double.tryParse(bill['amount_tendered']?.toString() ?? "0") ?? 0.0;
      await bluetooth.printLeftRight("PAYMENT", pMethod.toUpperCase(), 1);
      if (pMethod == "Cash" && pTendered > 0) {
        await bluetooth.printLeftRight("Tendered:", "Rs${pTendered.toStringAsFixed(2)}", 1);
        await bluetooth.printLeftRight("Change:", "Rs${(pTendered - total).toStringAsFixed(2)}", 1);
      }
      await bluetooth.printNewLine();

      await bluetooth.printCustom("Thank you for shopping!", 1, 1);
      await bluetooth.printCustom("No Exchange / No Refund", 1, 1);
      await bluetooth.printCustom("*** DUPLICATE COPY ***", 1, 1);
      await bluetooth.printNewLine();
      await bluetooth.printNewLine();
      await bluetooth.paperCut();
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bill Reprinted!")));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Print Error: $e")));
    }
  }

  void _showBillPreview(Map<String, dynamic> bill) {
    showDialog(
      context: context,
      builder: (context) {
        final items = bill['items_json'] as List<dynamic>;
        String bNo = bill['bill_number'] ?? "N/A";
        
        return AlertDialog(
          contentPadding: const EdgeInsets.all(16),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("LOVE KUSH", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  const Text("SHOPPING CENTER", style: TextStyle(fontSize: 16)),
                  Text(bill['counter_name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  if (bNo != "N/A") ...[
                    bw.BarcodeWidget(barcode: bw.Barcode.code128(), data: bNo, width: 200, height: 60, drawText: false),
                    const SizedBox(height: 4),
                    Text("BILL NO: $bNo", style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text("Item", style: TextStyle(fontWeight: FontWeight.bold)), Text("Qty x Rate", style: TextStyle(fontWeight: FontWeight.bold))]),
                  const Divider(color: Colors.black, thickness: 1),
                  ...items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(item['item'].toString(), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text("${item['qty']} x ₹${item['rate']}"),
                        ],
                      ),
                    );
                  }).toList(),
                  const Divider(color: Colors.black, thickness: 1),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("TOTAL", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)), Text("₹${bill['total_amount']}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18))]),
                  const SizedBox(height: 10),
                  Text("Staff: ${bill['staff_name']}", style: const TextStyle(color: Colors.black54)),
                  Text("Date: ${DateTime.parse(bill['created_at']).toLocal().toString().split('.')[0]}", style: const TextStyle(color: Colors.black54)),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton.icon(
              icon: const Icon(Icons.print, color: Colors.white),
              label: const Text("REPRINT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
              onPressed: () {
                Navigator.pop(context);
                _reprintBill(bill);
              },
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CLOSE"))
          ],
        );
      }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Dashboard", style: TextStyle(color: Colors.white)), 
        backgroundColor: const Color(0xFF111827), 
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: Colors.blueAccent.withOpacity(0.1),
            child: Column(
              children: [
                Text("${currentFilter.toUpperCase()} COLLECTION", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Text("₹${collection.toStringAsFixed(2)}", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.blueAccent)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Align(alignment: Alignment.centerLeft, child: Text("${currentFilter.toUpperCase()} BILLS", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ),
          if (isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: ListView.builder(
                itemCount: pastBills.length,
                itemBuilder: (context, index) {
                  final bill = pastBills[index];
                  String bNo = bill['bill_number'] ?? "N/A";
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.black12, child: const Icon(Icons.receipt, color: Colors.black)),
                    title: Text("₹${bill['total_amount']}  (No: $bNo)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text("Staff: ${bill['staff_name']} • Counter: ${bill['counter_name']}"),
                    trailing: Text(DateTime.parse(bill['created_at']).toLocal().toString().split('.')[0].substring(11), style: const TextStyle(color: Colors.black54)),
                    onTap: () => _showBillPreview(bill),
                  );
                },
              ),
            )
        ],
      ),
    );
  }
}
