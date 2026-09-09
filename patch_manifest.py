import re

filepath = "android/app/src/main/AndroidManifest.xml"
with open(filepath, "r") as f:
    content = f.read()

intent_filter = """
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="https" android:host="love-kush-pos.firebaseapp.com" />
                <data android:scheme="http" android:host="love-kush-pos.firebaseapp.com" />
            </intent-filter>
"""

# Insert inside the <activity> tag, right after the main intent-filter
if "love-kush-pos.firebaseapp.com" not in content:
    content = content.replace("</intent-filter>", "</intent-filter>" + intent_filter, 1)

with open(filepath, "w") as f:
    f.write(content)
