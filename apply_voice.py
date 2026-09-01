#!/usr/bin/env python3
"""Voice notes: packages, permissions and platform config.

Run from the famzone-flutter repo root, then `flutter pub get`.
Idempotent, and every anchor is guarded.
"""

import io
import sys

changed = []


def read(p):
    return io.open(p, encoding='utf-8').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def patch(path, pairs, marker):
    s = read(path)

    if marker in s:
        print(f'{path}: already patched')

        return

    for old, new in pairs:
        if old not in s:
            sys.exit(f'{path}: anchor missing ->\n{old[:200]}')

        s = s.replace(old, new, 1)

    write(path, s)
    changed.append(path)
    print(f'{path}: patched')


# =============================================================== packages

patch('pubspec.yaml', [
    (
        "  url_launcher: ^6.3.2\n",
        "  url_launcher: ^6.3.2\n"
        "\n"
        "  # Voice notes.\n"
        "  #\n"
        "  # record captures and reports the input level for the live\n"
        "  # waveform; just_audio plays back with seeking and speed;\n"
        "  # audio_session is what stops iOS routing playback to the earpiece\n"
        "  # after a recording; path_provider gives the temp file a home,\n"
        "  # which record requires explicitly from v5 on.\n"
        "  record: ^7.1.1\n"
        "  just_audio: ^0.10.6\n"
        "  audio_session: ^0.2.4\n"
        "  path_provider: ^2.1.0\n",
    ),
], marker='record: ^7')


# ================================================================ android

patch('android/app/src/main/AndroidManifest.xml', [
    (
        '    <uses-permission android:name="android.permission.INTERNET"/>',
        '    <uses-permission android:name="android.permission.INTERNET"/>\n'
        '\n'
        '    <!-- Voice notes. Requested at the moment of the first recording,\n'
        '         not at launch: a microphone prompt on a safety app\'s first\n'
        '         run, before anything has explained why, is a prompt people\n'
        '         decline. -->\n'
        '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>',
    ),
], marker='RECORD_AUDIO')

patch('android/app/build.gradle.kts', [
    (
        "        minSdk = flutter.minSdkVersion",
        "        // Pinned rather than inherited: the record plugin needs 23,\n"
        "        // and 24 is where the audio encoder behaviour stops varying\n"
        "        // between manufacturers. Inheriting it means a Flutter\n"
        "        // upgrade could quietly move it under us.\n"
        "        minSdk = 24",
    ),
], marker='minSdk = 24')


# ==================================================================== ios

patch('ios/Runner/Info.plist', [
    (
        "\t<key>CADisableMinimumFrameDurationOnPhone</key>",
        "\t<!-- Shown verbatim in the system prompt. Vague wording here is a\n"
        "\t     common App Store rejection, and is also just worse for the\n"
        "\t     person deciding. -->\n"
        "\t<key>NSMicrophoneUsageDescription</key>\n"
        "\t<string>SFamily uses the microphone so you can send voice messages "
        "in your chats.</string>\n"
        "\t<key>NSCameraUsageDescription</key>\n"
        "\t<string>SFamily uses the camera so you can take photos to send in "
        "your chats and set your profile picture.</string>\n"
        "\t<key>NSPhotoLibraryUsageDescription</key>\n"
        "\t<string>SFamily needs access to your photos so you can send them in "
        "your chats and set your profile picture.</string>\n"
        "\t<key>CADisableMinimumFrameDurationOnPhone</key>",
    ),
], marker='NSMicrophoneUsageDescription')


print('\ndone: ' + (', '.join(changed) if changed else 'nothing to do'))
print('\nnext: flutter pub get')
