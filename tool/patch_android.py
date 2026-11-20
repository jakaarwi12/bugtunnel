#!/usr/bin/env python3
"""Menyiapkan proyek Android yang dihasilkan `flutter create` untuk BugTunnel.

Dijalankan di GitHub Actions setelah `flutter create` dan sebelum build.
Tidak memerlukan Android SDK di mesin lokal.
"""

from __future__ import annotations

import re
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android"
APP = ANDROID / "app"
ANDROID_NS = "http://schemas.android.com/apk/res/android"


def fail(message: str) -> None:
    print(f"::error::{message}")
    sys.exit(1)


def patch_gradle_kts(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    original = text

    text = text.replace("minSdk = flutter.minSdkVersion", "minSdk = 24")

    # `java` di dalam skrip Gradle menunjuk ke ekstensi Java, bukan paket,
    # sehingga `java.util.Properties` gagal dikompilasi. Impor harus di atas.
    if "import java.util.Properties" not in text:
        text = (
            "import java.io.FileInputStream\n"
            "import java.util.Properties\n\n"
            + text
        )

    if "keystorePropertiesFile" not in text:
        properties = """val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

"""
        text = text.replace("android {", properties + "android {", 1)

    if "useLegacyPackaging" not in text:
        packaging = """    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

"""
        text = text.replace("    buildTypes {", packaging + "    buildTypes {", 1)

    if "signingConfigs {" not in text:
        signing = """    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

"""
        text = text.replace("    buildTypes {", signing + "    buildTypes {", 1)

    text = re.sub(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        'signingConfig = if (keystorePropertiesFile.exists()) '
        'signingConfigs.getByName("release") else '
        'signingConfigs.getByName("debug")',
        text,
    )

    if text == original:
        print("Gradle Kotlin DSL tidak berubah (mungkin sudah dipatch).")
    else:
        path.write_text(text, encoding="utf-8")
        print("Gradle Kotlin DSL dipatch.")


def patch_gradle_groovy(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    original = text

    text = text.replace("minSdkVersion flutter.minSdkVersion", "minSdkVersion 24")

    if "keystorePropertiesFile" not in text:
        properties = """def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

"""
        text = text.replace("android {", properties + "android {", 1)

    if "useLegacyPackaging" not in text:
        packaging = """    packaging {
        jniLibs {
            useLegacyPackaging true
        }
    }

"""
        text = text.replace("    buildTypes {", packaging + "    buildTypes {", 1)

    if "signingConfigs {" not in text:
        signing = """    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            release {
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
            }
        }
    }

"""
        text = text.replace("    buildTypes {", signing + "    buildTypes {", 1)

    text = re.sub(
        r"signingConfig\s+signingConfigs\.debug",
        "signingConfig keystorePropertiesFile.exists() ? "
        "signingConfigs.release : signingConfigs.debug",
        text,
    )
    text = re.sub(
        r"signingConfig\s*=\s*signingConfigs\.getByName\(\"debug\"\)",
        "signingConfig keystorePropertiesFile.exists() ? "
        "signingConfigs.release : signingConfigs.debug",
        text,
    )

    if text == original:
        print("Gradle Groovy tidak berubah (mungkin sudah dipatch).")
    else:
        path.write_text(text, encoding="utf-8")
        print("Gradle Groovy dipatch.")


def patch_manifest(path: Path) -> None:
    ET.register_namespace("android", ANDROID_NS)
    tree = ET.parse(path)
    root = tree.getroot()

    def android(name: str) -> str:
        return f"{{{ANDROID_NS}}}{name}"

    existing = {
        permission.get(android("name"))
        for permission in root.findall("uses-permission")
    }
    wanted = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.FOREGROUND_SERVICE",
        "android.permission.FOREGROUND_SERVICE_SPECIAL_USE",
        "android.permission.POST_NOTIFICATIONS",
    ]

    application = root.find("application")
    if application is None:
        fail("AndroidManifest.xml tidak punya elemen <application>.")

    index = list(root).index(application)
    for name in wanted:
        if name in existing:
            continue
        root.insert(index, ET.Element("uses-permission", {android("name"): name}))
        index += 1

    application.set(android("label"), "BugTunnel")
    application.set(android("extractNativeLibs"), "true")
    application.set(android("usesCleartextTraffic"), "true")

    tree.write(path, encoding="utf-8", xml_declaration=True)
    print("AndroidManifest.xml dipatch.")


def copy_icons() -> None:
    source_root = ROOT / "tool" / "icon"
    if not source_root.exists():
        return
    destination_root = APP / "src" / "main" / "res"
    copied = 0
    for source in source_root.glob("mipmap-*/*.png"):
        destination = destination_root / source.parent.name / source.name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        copied += 1
    if copied:
        print(f"{copied} ikon disalin.")


def remove_generated_tests() -> None:
    for relative in ("test/widget_test.dart",):
        path = ROOT / relative
        if path.exists():
            path.unlink()
            print(f"{relative} dihapus (template tidak dipakai).")


def main() -> None:
    if not ANDROID.exists():
        fail("Folder android/ belum ada. Jalankan `flutter create` dulu.")

    kts = APP / "build.gradle.kts"
    groovy = APP / "build.gradle"
    if kts.exists():
        patch_gradle_kts(kts)
    elif groovy.exists():
        patch_gradle_groovy(groovy)
    else:
        fail("build.gradle(.kts) tidak ditemukan.")

    manifest = APP / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        fail("AndroidManifest.xml tidak ditemukan.")
    patch_manifest(manifest)
    copy_icons()
    remove_generated_tests()

    print("Patch Android selesai.")


if __name__ == "__main__":
    main()
