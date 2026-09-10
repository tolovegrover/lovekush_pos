import re

with open("lib/main.dart", "r") as f:
    content = f.read()

# Fix PosApp
content = content.replace(
"""  @override

    return MaterialApp(""", 
"""  @override
  Widget build(BuildContext context) {
    return MaterialApp(""")

# Fix anything else that might have it missing
content = re.sub(r'  @override\n\n    return', r'  @override\n  Widget build(BuildContext context) {\n    return', content)

with open("lib/main.dart", "w") as f:
    f.write(content)
