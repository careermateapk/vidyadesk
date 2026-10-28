"""Makes the Android build sign with ci/debug.keystore (fixed SHA-1),
whatever debug key the build machine would otherwise create."""
import pathlib
import re

kts = pathlib.Path("android/app/build.gradle.kts")
groovy = pathlib.Path("android/app/build.gradle")

if kts.exists():
    block = '''
    signingConfigs {
        getByName("debug") {
            storeFile = file("../../ci/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }
'''
    path = kts
else:
    block = '''
    signingConfigs {
        debug {
            storeFile file("../../ci/debug.keystore")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
    }
'''
    path = groovy

text = path.read_text()
new, n = re.subn(r"^android\s*\{\n", "android {\n" + block, text, count=1, flags=re.M)
if n != 1:
    raise SystemExit(f"::error::Could not find the android {{ block in {path}")
path.write_text(new)
print(f"Signing key set in {path}")
