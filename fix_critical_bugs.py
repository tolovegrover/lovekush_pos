import re

# Fix Android Manifest
manifest_path = "android/app/src/main/AndroidManifest.xml"
with open(manifest_path, "r") as f:
    manifest = f.read()

if "android.permission.INTERNET" not in manifest:
    manifest = manifest.replace("<uses-permission android:name=\"android.permission.CAMERA\" />", 
                                "<uses-permission android:name=\"android.permission.INTERNET\" />\n    <uses-permission android:name=\"android.permission.CAMERA\" />")

with open(manifest_path, "w") as f:
    f.write(manifest)

# Fix literal newline in main.dart
main_path = "lib/main.dart"
with open(main_path, "r") as f:
    main_dart = f.read()

main_dart = main_dart.replace('LOVE KUSH\\\\nSHOPPING CENTER', 'LOVE KUSH\\nSHOPPING CENTER')
main_dart = main_dart.replace('to:\\\\n$submittedEmail', 'to:\\n$submittedEmail')

with open(main_path, "w") as f:
    f.write(main_dart)

