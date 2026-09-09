import re

filepath = "android/app/src/main/AndroidManifest.xml"
with open(filepath, "r") as f:
    content = f.read()

perm = '<uses-permission android:name="android.permission.CAMERA" />\n    <uses-feature android:name="android.hardware.camera" android:required="false" />\n'
if "android.permission.CAMERA" not in content:
    content = content.replace("<application", perm + "\n    <application")

with open(filepath, "w") as f:
    f.write(content)
