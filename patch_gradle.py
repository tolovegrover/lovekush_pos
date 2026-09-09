import re

filepath = "android/app/build.gradle.kts"
with open(filepath, "r") as f:
    content = f.read()

keystore_config = """
    signingConfigs {
        create("release") {
            storeFile = file("upload-keystore.jks")
            storePassword = "lovekush123"
            keyAlias = "upload"
            keyPassword = "lovekush123"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
"""

content = re.sub(r"buildTypes\s*\{[\s\S]*?\}[\s\S]*?\}", keystore_config.strip(), content)

with open(filepath, "w") as f:
    f.write(content)
