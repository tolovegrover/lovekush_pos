with open("restore.txt", "r") as f:
    restore_code = f.read()

# Remove the PosScreen part from restore text
restore_code = restore_code.replace("// ==========================================\n// POS SCREEN\n// ==========================================\nclass PosScreen extends StatefulWidget {\n", "")

with open("lib/main.dart", "r") as f:
    content = f.read()

if "class StaffManagementScreen" not in content:
    content = content.replace("// ==========================================\n// POS SCREEN\n// ==========================================\nclass PosScreen extends StatefulWidget {", restore_code + "\n// ==========================================\n// POS SCREEN\n// ==========================================\nclass PosScreen extends StatefulWidget {")

with open("lib/main.dart", "w") as f:
    f.write(content)
