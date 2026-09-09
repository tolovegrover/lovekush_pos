import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# 1. Update main()
old_main = """void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); } catch (e) { print(e); }
  runApp(const PosApp());
}"""

new_main = """void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); } catch (e) { print(e); }
  
  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
  final String userName = prefs.getString('userName') ?? 'Admin';
  final String userEmail = prefs.getString('userEmail') ?? '';
  final bool isAdmin = prefs.getBool('isAdmin') ?? false;

  runApp(PosApp(
    isLoggedIn: isLoggedIn,
    userName: userName,
    userEmail: userEmail,
    isAdmin: isAdmin,
  ));
}"""
content = content.replace(old_main, new_main)

# 2. Update PosApp
old_posapp = """class PosApp extends StatelessWidget {
  const PosApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Love Kush POS',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF3F4F6), 
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF111827)),
        fontFamily: 'Roboto', 
      ),
      home: const LoginScreen(),
    );
  }
}"""

new_posapp = """class PosApp extends StatelessWidget {
  final bool isLoggedIn;
  final String userName;
  final String userEmail;
  final bool isAdmin;

  const PosApp({Key? key, required this.isLoggedIn, required this.userName, required this.userEmail, required this.isAdmin}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Love Kush POS',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF3F4F6), 
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF111827)),
        fontFamily: 'Roboto', 
      ),
      home: isLoggedIn 
          ? PosScreen(userName: userName, userEmail: userEmail, isAdmin: isAdmin) 
          : const LoginScreen(),
    );
  }
}"""
content = content.replace(old_posapp, new_posapp)

# 3. Update _promptForName logic
old_prompt = """              onPressed: () {
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
              },"""

new_prompt = """              onPressed: () async {
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
              },"""
content = content.replace(old_prompt, new_prompt)

# 4. Update Logout Button
old_logout = """              onTap: () {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              },"""

new_logout = """              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('isLoggedIn', false);
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              },"""
content = content.replace(old_logout, new_logout)

with open("lib/main.dart", "w") as f:
    f.write(content)

