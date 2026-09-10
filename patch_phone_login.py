import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# 1. Add phone users map to _LoginScreenState
old_class_start = """class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();"""

new_class_start = """class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  
  final Map<String, Map<String, dynamic>> phoneAuth = {
    "8800452769": {"name": "Love Kush", "email": "tolovegrover@gmail.com", "isAdmin": true},
    "8130550842": {"name": "Sanjeeta", "email": "sanjeetagrover@gmail.com", "isAdmin": true},
    "9716839756": {"name": "Ved Prakash", "email": "vedprakash@demo.com", "isAdmin": true},
    "9205809074": {"name": "Nisha", "email": "nishaankit60@gmail.com", "isAdmin": true},
  };"""

content = content.replace(old_class_start, new_class_start)

# 2. Update _sendEmailLink to handle phone instant login
old_send_link = """  void _sendEmailLink() async {
    String email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains("@")) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid email address")));
      return;
    }"""

new_send_link = """  void _sendEmailLink() async {
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid email or authorized phone number")));
      return;
    }"""

content = content.replace(old_send_link, new_send_link)

# 3. Update UI text
content = content.replace('labelText: "Email Address",', 'labelText: "Email or Phone Number",')
content = content.replace('keyboardType: TextInputType.emailAddress,', 'keyboardType: TextInputType.emailAddress,')

with open("lib/main.dart", "w") as f:
    f.write(content)
