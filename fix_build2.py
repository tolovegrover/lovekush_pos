with open("lib/main.dart", "r") as f:
    content = f.read()

content = content.replace("  @override\n\n    if (isPreviewingBill)", "  @override\n  Widget build(BuildContext context) {\n    if (isPreviewingBill)")
content = content.replace("  @override\n\n    return Scaffold(", "  @override\n  Widget build(BuildContext context) {\n    return Scaffold(")

with open("lib/main.dart", "w") as f:
    f.write(content)
