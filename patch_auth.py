import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# Make sure we have the required imports
imports = """import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'firebase_options.dart';
"""

content = re.sub(r"import 'package:flutter/material.dart';[\s\S]*?void main\(\)", imports + "\nvoid main()", content)


new_login_screen = """// ==========================================
// LOGIN SCREEN (Real Firebase Magic Link Auth)
// ==========================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  
  bool isLinkSent = false;
  String submittedEmail = "";
  bool isAdmin = false;
  
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
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

  void _sendEmailLink() async {
    String email = _emailController.text.trim().toLowerCase();
    
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
      debugPrint("Firebase Link Error: $e");
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
              onPressed: () {
                if (_nameController.text.trim().isNotEmpty) {
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
              const Text("LOVE KUSH\\nSHOPPING CENTER", textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 2, height: 1.2)),
              const SizedBox(height: 8),
              const Text("Secure Staff Portal", style: TextStyle(fontSize: 16, color: Colors.black54)),
              const SizedBox(height: 40),
              
              if (!isLinkSent) ...[
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: "Email Address", prefixIcon: const Icon(Icons.email_outlined), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
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
                Text("We sent a real secure login link to:\\n$submittedEmail", textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.black54, height: 1.5)),
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
"""

content = re.sub(r"// ==+[\s]*// LOGIN SCREEN \(With Access Control\)[\s]*// ==+[\s]*class LoginScreen.*?class PosScreen", new_login_screen + "\n// ==========================================\n// POS SCREEN\n// ==========================================\nclass PosScreen", content, flags=re.DOTALL)

with open("lib/main.dart", "w") as f:
    f.write(content)
