# MacTube Converter

Download, convert, and transcribe video on your Mac.

[![Latest release](https://img.shields.io/github/v/release/asjames18/mac-tube-converter)](https://github.com/asjames18/mac-tube-converter/releases/latest)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Universal](https://img.shields.io/badge/universal-arm64%20%2B%20x86__64-555555)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Overview

MacTube Converter is a native Swift app for downloading video or audio from links, converting local media, and transcribing to text and SRT subtitles. The work stays on your Mac. The 1.3.1 download already includes yt-dlp, Deno, ffmpeg, ffprobe, and whisper-cli, so Homebrew is not required.

## Features

- **Download** video or audio from one or more links (one per line). Choose a format and start a batch; single-video mode is on by default.
- **Convert** local files by drag-and-drop or Choose Files. Pick a format and, where supported, Compact, Balanced, or High quality.
- **Transcribe** local files or video URLs to plain text and optional timestamped SRT subtitles. Choose a model in the Transcribe tab, including Automatic (balanced Small English), Accuracy (Large v3 Turbo), and Faster (Base English).
- **Everything included:** yt-dlp 2026.10.26, Deno 2.9.8 (the JavaScript runtime YouTube downloads need), ffmpeg/ffprobe 9.0.2, and whisper-cli (whisper.cpp 1.9.5) ship inside the app. The app prefers these built-in tools and falls back to Homebrew copies only if the bundled ones are missing.
- **First-run speech model:** one prompt offers to download whisper.cpp's Small English model (`ggml-small.en-q5_1.bin`, 190 MB, one time). The file is checked against its SHA-256 and saved to `~/Library/Application Support/MacTubeConverter/Models`. Downloading and converting work without it; you can also start the download later from Tools & transcription > Download Model…
- Transcription uses the GPU (Metal) on Apple Silicon and the CPU on Intel Macs. Models run locally. Singing, overlapping voices, and background music can still produce recognition errors.
- Session results, progress, activity logs, cancel, and numbered filenames for conversions and transcripts so existing files are not overwritten. Downloads also refuse to overwrite existing files.
- Keyboard: Command-Return starts the selected operation; Escape cancels it.

## Download

Get MacTube Converter 1.3.1 from the [latest GitHub release](https://github.com/asjames18/mac-tube-converter/releases/latest), or from the [Melanated in Tech apps page](https://melanatedintech.com/apps).

- [MacTubeConverter-1.3.1-macOS.dmg](https://github.com/asjames18/mac-tube-converter/releases/download/v1.3.1/MacTubeConverter-1.3.1-macOS.dmg)
- [MacTubeConverter-1.3.1-macOS.zip](https://github.com/asjames18/mac-tube-converter/releases/download/v1.3.1/MacTubeConverter-1.3.1-macOS.zip)

Checksum files (`.sha256`) and [THIRD_PARTY_NOTICES.md](https://github.com/asjames18/mac-tube-converter/releases/download/v1.3.1/THIRD_PARTY_NOTICES.md) are attached to the same release. The app files are over 100 MB, so they are published as release assets, not as files in this repository.

## Install

The download is a universal app (Apple Silicon and Intel) with an ad-hoc signature. It is not notarized, so macOS will block it until you allow it.

1. Open the `.dmg` and drag MacTubeConverter to Applications (or unzip the `.zip` and move the app to Applications).
2. Open the app from Applications. macOS will say it can't verify the app is free of malware. Click **Done**.
3. Open **System Settings > Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to MacTubeConverter. Confirm with your password or Touch ID, then click **Open Anyway** again.
4. The app opens; after that it opens normally.

If Open Anyway does not appear, run this in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/MacTubeConverter.app
```

On first launch, if no speech model is installed, the app offers a one-time download of the Small English model described above. You can decline and still download or convert media.

## Requirements

- macOS 13 Ventura or later
- An Apple Silicon or Intel Mac (the release is a universal binary)
- No other software is required for the release download
- A Whisper model (`ggml-*.bin`) is required only for transcription. The app can download the recommended Small English model for you, or you can add a model to `~/Library/Application Support/MacTubeConverter/Models`, set `MACTUBE_MODEL_DIR`, or choose a model file in the app.

Tested on an Intel Mac.

## Usage

Use the sidebar to switch between Download, Convert, and Transcribe. Each workflow follows source, format, and destination; start and cancel stay at the bottom. Open Activity from the toolbar for process logs, or Tools & transcription from the sidebar for setup and the model download.

Paste links (one per line) to download, drop or choose files to convert, and drag a file onto Transcribe or use a video URL. When a job finishes, open or reveal the output in Finder. Incomplete files from a failed or cancelled download or conversion go to the Trash.

The app prefers its bundled tools. Tools & transcription can also show Homebrew versions and, after confirmation, run `brew upgrade yt-dlp` to update a Homebrew install. That does not replace the copy bundled inside the app.

## Privacy

Downloads, conversions, and transcriptions run on your Mac. There is no account. The only optional network download in normal use is the speech model, and only if you accept the first-run prompt or choose Download Model later. That file comes from the official whisper.cpp model distribution on Hugging Face and is checksum-verified before it is used. Optional “Update yt-dlp” through Homebrew also needs a network connection, and only if you confirm it.

## Verify the download

From Terminal, in the folder that contains the file you downloaded:

```sh
shasum -a 256 MacTubeConverter-1.3.1-macOS.dmg
shasum -a 256 MacTubeConverter-1.3.1-macOS.zip
```

The SHA-256 values should match the release and the `.sha256` files next to the downloads:

| File | SHA-256 |
| --- | --- |
| `MacTubeConverter-1.3.1-macOS.zip` | `d8a0b1520d827bc5e54bf6ab35411e986abedf7b206e416aaa3f8c1951320880` |
| `MacTubeConverter-1.3.1-macOS.dmg` | `86f1d851aa638970a621b57b495cdfdf1e22e9befa5bee41bb800bd5b57c6730` |

## Build from source

You need macOS 13 or later and a Swift 6 toolchain (this package declares `swift-tools-version: 6.0`).

```sh
./scripts/fetch-bundled-tools.sh
./scripts/build-app.sh
./scripts/package-release.sh build/MacTubeConverter.app 1.3.1
```

`fetch-bundled-tools.sh` downloads checksum-verified copies of yt-dlp, Deno, and static ffmpeg/ffprobe, and builds a static universal whisper-cli, into `vendor/` (that folder is not committed). `build-app.sh` produces a universal, ad-hoc-signed `build/MacTubeConverter.app` with those tools in `Contents/Resources/bin`. Set `UNIVERSAL=0` for a host-only build. Whisper models are not bundled in the app binary.

`./script/build_and_run.sh --verify` is available for a local build-and-launch check.

## Troubleshooting

- **macOS says the app can't be verified.** Use Open Anyway in System Settings > Privacy & Security, or the `xattr` command in [Install](#install). Right-click > Open is not a reliable workaround on current macOS.
- **Transcription asks for a model.** Accept the first-run download, use Tools & transcription > Download Model…, or place a `ggml-*.bin` file in `~/Library/Application Support/MacTubeConverter/Models`.
- **YouTube or another site fails to download.** The bundled Deno is what yt-dlp uses for YouTube's JavaScript challenges. Confirm you are running the 1.3.1 app (not an older build without Deno). If you previously relied on Homebrew, remember the app prefers its built-in tools.

## License

The app's own code is licensed under the [MIT License](LICENSE). Copyright (c) 2026 Antonio James.

Bundled tools keep their own licenses: ffmpeg is GPLv3, Deno is MIT, yt-dlp is Unlicense, and whisper.cpp is MIT. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details. Copies also ship inside the app at `Contents/Resources/Licenses`.

- yt-dlp 2026.10.26 — Unlicense (public domain)
- Deno 2.9.8 — MIT
- ffmpeg / ffprobe 9.0.2 — GPL v3. Corresponding source: https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz. Build scripts: https://git.martin-riedl.de/ffmpeg/build-script
- whisper-cli (whisper.cpp 1.9.5) — MIT
- The optional Small English speech model is downloaded separately from [whisper.cpp's model distribution](https://huggingface.co/ggerganov/whisper.cpp) (MIT; derived from OpenAI Whisper, MIT)

## Made by

[Antonio James](https://antoniojames.dev) / [Melanated in Tech](https://melanatedintech.com)
