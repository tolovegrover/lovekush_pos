import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# Add _checkExistingLogin to initState
old_init = """  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }"""

new_init = """  @override
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
  }"""

content = content.replace(old_init, new_init)

with open("lib/main.dart", "w") as f:
    f.write(content)
