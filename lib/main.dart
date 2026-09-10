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
import 'firebase_options.dart';

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
const List<Map<String, dynamic>> cosmeticDatabase = [
  // Eye Makeup
  {"name": "Lakme Eyeconic Kajal Deep Black", "price": 190.0, "category": "Eyes"},
  {"name": "Maybelline Colossal Kajal 24HR", "price": 199.0, "category": "Eyes"},
  {"name": "Colorbar Just Smoky Kajal", "price": 450.0, "category": "Eyes"},
  {"name": "Elle 18 Eye Drama Kajal", "price": 100.0, "category": "Eyes"},
  {"name": "Sugar Stroke of Genius Kohl", "price": 499.0, "category": "Eyes"},
  {"name": "Lakme Insta Liquid Eyeliner Black", "price": 145.0, "category": "Eyes"},
  {"name": "Maybelline Hyper Glossy Liquid Liner", "price": 325.0, "category": "Eyes"},
  {"name": "Faces Canada Magneteyes Eyeliner", "price": 249.0, "category": "Eyes"},
  {"name": "Swiss Beauty Gel Eyeliner & Kajal", "price": 299.0, "category": "Eyes"},
  {"name": "Mars Waterproof Sketch Eyeliner", "price": 199.0, "category": "Eyes"},
  {"name": "Maybelline Hypercurl Waterproof Mascara", "price": 399.0, "category": "Eyes"},
  {"name": "Maybelline Colossal Waterproof Mascara", "price": 425.0, "category": "Eyes"},
  {"name": "Mars Fabulash Volume Mascara", "price": 249.0, "category": "Eyes"},
  {"name": "Swiss Beauty Precision Eyebrow Pencil", "price": 149.0, "category": "Eyes"},
  {"name": "Miss Claire Eyebrow Cake Powder", "price": 295.0, "category": "Eyes"},
  {"name": "Swiss Beauty 9 Colors Eyeshadow Palette", "price": 299.0, "category": "Eyes"},
  {"name": "False Eyelashes with Glue Set", "price": 150.0, "category": "Eyes"},

  // Lip Makeup
  {"name": "Lakme Forever Matte Liquid Lipstick", "price": 349.0, "category": "Lips"},
  {"name": "Maybelline Superstay Matte Ink Lipstick", "price": 699.0, "category": "Lips"},
  {"name": "Maybelline Creamy Matte Lipstick", "price": 329.0, "category": "Lips"},
  {"name": "Elle 18 Color Pops Matte Lipstick", "price": 110.0, "category": "Lips"},
  {"name": "Colorbar Velvet Matte Lipstick", "price": 350.0, "category": "Lips"},
  {"name": "Sugar Smudge Me Not Liquid Lipstick", "price": 499.0, "category": "Lips"},
  {"name": "Insight Non-Transfer Matte Lipstick", "price": 130.0, "category": "Lips"},
  {"name": "Blue Heaven Non-Transfer Lip Color", "price": 150.0, "category": "Lips"},
  {"name": "Swiss Beauty Matte Lip Crayon", "price": 249.0, "category": "Lips"},
  {"name": "Mars Matte Lip Liner Pencil", "price": 99.0, "category": "Lips"},
  {"name": "Nivea Fruity Shine Strawberry Lip Balm", "price": 199.0, "category": "Lips"},
  {"name": "Vaseline Lip Therapy Rosy Lips", "price": 120.0, "category": "Lips"},
  {"name": "Baby Lips Moisturizing Lip Balm", "price": 175.0, "category": "Lips"},

  // Face Makeup
  {"name": "Maybelline Fit Me Matte Foundation", "price": 599.0, "category": "Face"},
  {"name": "Lakme Invisible Finish Foundation", "price": 275.0, "category": "Face"},
  {"name": "Lakme 9 to 5 Complexion Care CC Cream", "price": 325.0, "category": "Face"},
  {"name": "Spinz BB Brightening Cream", "price": 95.0, "category": "Face"},
  {"name": "Ponds White Beauty BB+ Cream", "price": 140.0, "category": "Face"},
  {"name": "Garnier Skin Naturals BB Cream", "price": 175.0, "category": "Face"},
  {"name": "Maybelline Fit Me Compact Powder", "price": 249.0, "category": "Face"},
  {"name": "Lakme Sun Expert Ultra Matte Compact", "price": 299.0, "category": "Face"},
  {"name": "White Tone Face Powder 70g", "price": 110.0, "category": "Face"},
  {"name": "Swiss Beauty Liquid Concealer", "price": 229.0, "category": "Face"},
  {"name": "Insight Concealer Palette 6-in-1", "price": 199.0, "category": "Face"},
  {"name": "Lakme Absolute Blur Perfect Primer", "price": 450.0, "category": "Face"},
  {"name": "Insight 3-in-1 Long Lasting Primer", "price": 260.0, "category": "Face"},
  {"name": "Swiss Beauty Makeup Fixer Setting Spray", "price": 249.0, "category": "Face"},
  {"name": "Sugar Contour De Force Mini Blush", "price": 349.0, "category": "Face"},
  {"name": "Mars City Paradise Blusher & Highlighter", "price": 299.0, "category": "Face"},

  // Nails
  {"name": "Colorbar Luxe Nail Lacquer", "price": 250.0, "category": "Nails"},
  {"name": "Elle 18 Nail Pops", "price": 60.0, "category": "Nails"},
  {"name": "Insight Long Wear Nail Polish", "price": 75.0, "category": "Nails"},
  {"name": "Lakme True Wear Color Crush", "price": 160.0, "category": "Nails"},
  {"name": "Blue Heaven Dip Nail Polish Remover", "price": 99.0, "category": "Nails"},
  {"name": "Envy Gel Finish Nail Polish", "price": 120.0, "category": "Nails"},
  {"name": "Artificial Nails French Manicure (24 Pcs)", "price": 250.0, "category": "Nails"},

  // Skin & Hair Care
  {"name": "Himalaya Purifying Neem Face Wash 100ml", "price": 150.0, "category": "Skincare"},
  {"name": "Clean & Clear Foaming Face Wash 100ml", "price": 175.0, "category": "Skincare"},
  {"name": "Garnier Micellar Cleansing Water 125ml", "price": 225.0, "category": "Skincare"},
  {"name": "Dabur Gulabari Premium Rose Water 120ml", "price": 85.0, "category": "Skincare"},
  {"name": "Ponds Super Light Gel Moisturizer 100g", "price": 190.0, "category": "Skincare"},
  {"name": "Nivea Soft Light Moisturizing Cream 100ml", "price": 180.0, "category": "Skincare"},
  {"name": "Lakme Peach Milk Soft Cream 100g", "price": 165.0, "category": "Skincare"},
  {"name": "Lotus Herbals Safe Sun SPF 50 Sunscreen", "price": 395.0, "category": "Skincare"},
  {"name": "Biotique Bio Dandelion Ageless Serum", "price": 230.0, "category": "Skincare"},
  {"name": "Streax Hair Serum with Walnut Oil 100ml", "price": 240.0, "category": "Hair"},
  {"name": "L'Oreal Extraordinary Oil Hair Serum 100ml", "price": 549.0, "category": "Hair"},
  {"name": "Bajaj Almond Drops Hair Oil 100ml", "price": 75.0, "category": "Hair"},

  // Bangles, Jewelry & Accessories
  {"name": "Red Velvet Bangles Set (Size 2.4)", "price": 200.0, "category": "Bangles"},
  {"name": "Red Velvet Bangles Set (Size 2.6)", "price": 200.0, "category": "Bangles"},
  {"name": "Red Velvet Bangles Set (Size 2.8)", "price": 200.0, "category": "Bangles"},
  {"name": "Maroon Velvet Bangles Set (Size 2.6)", "price": 200.0, "category": "Bangles"},
  {"name": "Multicolor Glass Bangles Set (2 Dozen)", "price": 160.0, "category": "Bangles"},
  {"name": "Gold Plated Kada Bangles (Pair)", "price": 350.0, "category": "Bangles"},
  {"name": "Bridal Latkan Chuda Set", "price": 850.0, "category": "Bangles"},
  {"name": "Velvet Bindi Packet (Maroon/Red)", "price": 40.0, "category": "Accessories"},
  {"name": "Shilpa Fancy Stone Bindi Book", "price": 80.0, "category": "Accessories"},
  {"name": "Round Golden Bindi Pack", "price": 50.0, "category": "Accessories"},
  {"name": "Premium Pearl Stud Earrings", "price": 120.0, "category": "Jewelry"},
  {"name": "Kundan Jhumka Traditional Earrings", "price": 280.0, "category": "Jewelry"},
  {"name": "Oxidised Silver Boho Jhumki", "price": 150.0, "category": "Jewelry"},
  {"name": "Metal Hair Clutchers Pack of 6", "price": 99.0, "category": "Accessories"},
  {"name": "Satin Silk Scrunchies Pack of 3", "price": 80.0, "category": "Accessories"},
  {"name": "Korean Hair Pins Pack of 4", "price": 120.0, "category": "Accessories"},
  {"name": "Makeup Beauty Blender Sponge", "price": 60.0, "category": "Accessories"},
  {"name": "Professional Makeup Brush Set (7 Pcs)", "price": 299.0, "category": "Accessories"},
  {"name": "Safety Pins Golden Pack of 12", "price": 30.0, "category": "Accessories"},
];

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

  void _saveOrUpdateItem({required String code, required String name, required double price}) async {
    try {
      await Supabase.instance.client.from('inventory').upsert({
        'item_code': code,
        'item_name': name,
        'price': price,
      });

      // Update last used components
      final parts = code.split('-');
      if (parts.length >= 4) {
        _lastRack = parts[0];
        _lastCol = parts[1];
        _lastRow = parts[2];
        final numPart = int.tryParse(parts[3]);
        if (numPart != null) _lastItemNum = numPart;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_rack', _lastRack);
        await prefs.setString('last_col', _lastCol);
        await prefs.setString('last_row', _lastRow);
        await prefs.setInt('last_item_num', _lastItemNum);
      }

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

  // Fast Barcode Scanning for Editing or Adding
  void _scanBarcodeToEditOrAdd() async {
    final scannedCode = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerScreen()),
    );
    if (scannedCode != null && scannedCode is String && scannedCode.isNotEmpty) {
      final clean = scannedCode.trim();
      Map<String, dynamic>? match;
      for (var it in items) {
        if ((it['item_code'] ?? '').toString().toUpperCase() == clean.toUpperCase()) {
          match = it;
          break;
        }
      }
      if (match != null) {
        _showAddEditDialog(match);
      } else {
        _showAddEditDialog(null, clean);
      }
    }
  }

  // Cosmetics Database Dialog (Browse & 1-tap Use / Batch Import)
  void _showCosmeticsCatalogDialog() {
    String filterCategory = "All";
    String search = "";
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final categories = ["All", "Eyes", "Lips", "Face", "Nails", "Skincare", "Hair", "Bangles", "Jewelry", "Accessories"];
          final filteredList = cosmeticDatabase.where((item) {
            final matchCat = filterCategory == "All" || item["category"] == filterCategory;
            final matchSearch = search.isEmpty || item["name"].toString().toLowerCase().contains(search.toLowerCase());
            return matchCat && matchSearch;
          }).toList();

          return AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.auto_awesome, color: Colors.pinkAccent),
                SizedBox(width: 8),
                Text("Cosmetics Catalog", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: (val) => setModalState(() => search = val),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: categories.map((cat) {
                        bool sel = filterCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6.0),
                          child: ChoiceChip(
                            label: Text(cat, style: TextStyle(fontSize: 12, color: sel ? Colors.white : Colors.black87)),
                            selected: sel,
                            selectedColor: Colors.pinkAccent,
                            onSelected: (_) => setModalState(() => filterCategory = cat),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredList.length,
                      itemBuilder: (context, idx) {
                        final it = filteredList[idx];
                        return ListTile(
                          dense: true,
                          title: Text(it["name"], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("${it["category"]} • MRP ₹${it["price"]}"),
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
                icon: const Icon(Icons.cloud_upload, size: 16),
                label: const Text("IMPORT ALL (65+ ITEMS)"),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF111827), foregroundColor: Colors.white),
                onPressed: () async {
                  Navigator.pop(ctx);
                  _batchImportCosmetics();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _batchImportCosmetics() async {
    setState(() => isLoading = true);
    try {
      int imported = 0;
      int currentNum = _lastItemNum;
      for (var item in cosmeticDatabase) {
        String name = item["name"];
        double price = (item["price"] as num).toDouble();
        bool exists = items.any((it) => (it["item_name"] ?? '').toString().toLowerCase() == name.toLowerCase());
        if (!exists) {
          currentNum++;
          String code = "${_lastRack.padLeft(2, '0')}-${_lastCol.padLeft(2, '0')}-${_lastRow.toUpperCase()}-$currentNum";
          await Supabase.instance.client.from('inventory').upsert({
            'item_code': code,
            'item_name': name,
            'price': price,
          });
          imported++;
        }
      }
      _lastItemNum = currentNum;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_item_num', _lastItemNum);
      _fetchInventory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Imported $imported cosmetics into inventory!")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Import error: $e")));
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
  ]) {
    final bool isEdit = existing != null;
    
    // Components: Rack, Col, Row, Item (uses last used position if adding)
    String defaultRack = _lastRack;
    String defaultCol = _lastCol;
    String defaultRow = _lastRow;
    String defaultItem = (_lastItemNum + 1).toString();

    if (isEdit) {
      final parts = (existing['item_code'] ?? '').toString().split('-');
      if (parts.isNotEmpty) defaultRack = parts[0];
      if (parts.length > 1) defaultCol = parts[1];
      if (parts.length > 2) defaultRow = parts[2];
      if (parts.length > 3) defaultItem = parts[3];
    } else if (prefilledCode != null && prefilledCode.contains('-')) {
      final parts = prefilledCode.split('-');
      if (parts.isNotEmpty) defaultRack = parts[0];
      if (parts.length > 1) defaultCol = parts[1];
      if (parts.length > 2) defaultRow = parts[2];
      if (parts.length > 3) defaultItem = parts[3];
    }

    final rackCtrl = TextEditingController(text: defaultRack);
    final colCtrl = TextEditingController(text: defaultCol);
    final rowCtrl = TextEditingController(text: defaultRow);
    final itemCtrl = TextEditingController(text: defaultItem);
    
    String initialCode = isEdit
        ? existing['item_code']
        : (prefilledCode ?? "${defaultRack.padLeft(2, '0')}-${defaultCol.padLeft(2, '0')}-${defaultRow.toUpperCase()}-$defaultItem");

    final codeCtrl = TextEditingController(text: initialCode);
    final nameCtrl = TextEditingController(text: isEdit ? (existing['item_name'] ?? '') : (prefilledName ?? ''));
    final priceCtrl = TextEditingController(
      text: isEdit
          ? (existing['price']?.toString() ?? '')
          : (prefilledPrice != null ? (prefilledPrice % 1 == 0 ? prefilledPrice.toInt().toString() : prefilledPrice.toString()) : ''),
    );

    List<Map<String, dynamic>> suggestions = [];

    void updateGeneratedCode(void Function(void Function()) setDialogState) {
      setDialogState(() {
        codeCtrl.text = "${rackCtrl.text.padLeft(2, '0')}-${colCtrl.text.padLeft(2, '0')}-${rowCtrl.text.toUpperCase()}-${itemCtrl.text}".toUpperCase();
      });
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isEdit ? "Edit Code & Rate" : "Add Item Mapping", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              if (!isEdit)
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner, color: Colors.blueAccent),
                  tooltip: "Scan Barcode / QR",
                  onPressed: () async {
                    final scanned = await Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
                    if (scanned != null && scanned is String && scanned.isNotEmpty) {
                      setDialogState(() {
                        codeCtrl.text = scanned.trim().toUpperCase();
                        if (scanned.contains('-')) {
                          final parts = scanned.split('-');
                          if (parts.isNotEmpty) rackCtrl.text = parts[0];
                          if (parts.length > 1) colCtrl.text = parts[1];
                          if (parts.length > 2) rowCtrl.text = parts[2];
                          if (parts.length > 3) itemCtrl.text = parts[3];
                        }
                      });
                    }
                  },
                )
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isEdit) ...[
                  const Text("Location Code (Last Used Preserved):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueAccent)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rackCtrl,
                          decoration: const InputDecoration(labelText: "Rack (01)", border: OutlineInputBorder(), isDense: true),
                          onChanged: (_) => updateGeneratedCode(setDialogState),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: colCtrl,
                          decoration: const InputDecoration(labelText: "Col (03)", border: OutlineInputBorder(), isDense: true),
                          onChanged: (_) => updateGeneratedCode(setDialogState),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: rowCtrl,
                          decoration: const InputDecoration(labelText: "Row (C)", border: OutlineInputBorder(), isDense: true),
                          onChanged: (_) => updateGeneratedCode(setDialogState),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: itemCtrl,
                          decoration: const InputDecoration(labelText: "Item (134)", border: OutlineInputBorder(), isDense: true),
                          onChanged: (_) => updateGeneratedCode(setDialogState),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: codeCtrl,
                  readOnly: isEdit,
                  decoration: InputDecoration(
                    labelText: "Item Code",
                    helperText: "Format: 01(Rack)-03(Col)-C(Row)-134(Item)",
                    border: const OutlineInputBorder(),
                    filled: isEdit,
                    fillColor: isEdit ? Colors.grey.shade100 : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: "Item Name",
                    hintText: "Type name (e.g. Lakme, Kajal...)",
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
                          suggestions = [];
                        });
                      },
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: "Rate / Price (₹)",
                    prefixText: "₹ ",
                    border: OutlineInputBorder(),
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
                final code = codeCtrl.text.trim().toUpperCase();
                final name = nameCtrl.text.trim();
                final price = double.tryParse(priceCtrl.text.trim()) ?? 0.0;
                if (code.isEmpty || name.isEmpty || price <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please fill Code, Name, and valid Rate")),
                  );
                  return;
                }
                Navigator.pop(dialogCtx);
                _saveOrUpdateItem(code: code, name: name, price: price);
              },
              child: Text(isEdit ? "UPDATE RATE" : "SAVE TO CLOUD", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
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
                                  code.length >= 2 ? code.substring(0, 2) : "##",
                                  style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.blueAccent, fontSize: 16),
                                ),
                              ),
                              title: Text(name.isNotEmpty ? name : "Unnamed Item", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              subtitle: Text("Code: $code", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text("₹${price.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.green)),
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
    if (clean.length >= 5) {
      int? d = int.tryParse(clean[4]);
      if (d != null && d >= 1 && d <= 9) {
        clean = clean.substring(0, 4) + String.fromCharCode(64 + d) + clean.substring(5);
      }
    }
    return clean;
  }

  Map<String, dynamic>? _lookupItem(String query) {
    if (query.isEmpty) return null;
    String qCanon = _canonicalCode(query);
    if (qCanon.isEmpty) return null;
    for (var entry in cloudInventory.entries) {
      if (_canonicalCode(entry.key) == qCanon) return entry.value;
    }
    String fCanon = _canonicalCode(formattedItemCode);
    if (fCanon.isNotEmpty && fCanon != qCanon) {
      for (var entry in cloudInventory.entries) {
        if (_canonicalCode(entry.key) == fCanon) return entry.value;
      }
    }
    return null;
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
          final match = _lookupItem(rawItemCode);
          if (match != null) {
            double p = (match['price'] as num?)?.toDouble() ?? 0.0;
            if (p > 0 && rate.isEmpty) {
              rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
            }
          }
          focusedField = 1;
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
            final match = _lookupItem(rawItemCode);
            if (match != null) {
              double p = (match['price'] as num?)?.toDouble() ?? 0.0;
              if (p > 0) {
                rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
              }
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
            final match = _lookupItem(rawItemCode);
            if (match != null) {
              double p = (match['price'] as num?)?.toDouble() ?? 0.0;
              if (p > 0) {
                rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
              }
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
                _buildInputBox("ITEM CODE", formattedItemCode, focusedField == 0, 0, flex: 8, isCode: true, subtext: _lookupItem(rawItemCode)?['item_name']),
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
                            rawItemCode = _parseToRaw(barcodes.first.rawValue!);
                            final match = _lookupItem(rawItemCode);
                            if (match != null) {
                              double p = (match['price'] as num?)?.toDouble() ?? 0.0;
                              if (p > 0) {
                                rate = p % 1 == 0 ? p.toInt().toString() : p.toString();
                              }
                            }
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

  Widget _buildInputBox(String label, String value, bool isFocused, int fieldIndex, {required int flex, bool isCode = false, String? subtext}) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: () => setState(() => focusedField = fieldIndex),
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
                    color: isFocused ? Colors.greenAccent : Colors.green.shade700,
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
