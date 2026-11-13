# Third-party software bundled with MacTube Converter

The downloadable app includes these unmodified command-line tools in
`MacTubeConverter.app/Contents/Resources/bin`. They run as separate programs; their
licenses are in `Contents/Resources/Licenses`.

| Tool | Version | Source of the binary | License |
|---|---|---|---|
| yt-dlp | 2026.10.26 | Official `yt-dlp_macos` release asset, https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26 (universal) | Unlicense (public domain) |
| deno | 2.9.8 | Official release binaries deno-aarch64-apple-darwin.zip and deno-x86_64-apple-darwin.zip, https://github.com/denoland/deno/releases/tag/v2.9.8 (checksums verified, joined with `lipo`); used by yt-dlp as its JavaScript runtime for YouTube | MIT |
| ffmpeg, ffprobe | 9.0.2 | Static builds by Martin Riedl, https://ffmpeg.martin-riedl.de (arm64 and x86_64 release builds, joined with `lipo`) | GPL v3 (built with --enable-gpl --enable-version3) |
| whisper-cli | whisper.cpp 1.9.5 | Built from https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.5.tar.gz (static; arm64 slice uses Metal, x86_64 slice uses the CPU with AVX2) | MIT |

## FFmpeg source code (GPL)

FFmpeg is free software under the GNU General Public License v3. The corresponding source
code is available at https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz, and the build scripts
used for these static binaries (including the versions of every bundled library, listed in
`Licenses/ffmpeg-versions-*.txt`) are at https://git.martin-riedl.de/ffmpeg/build-script.
A copy of the source can also be requested from the publisher of this app.

## Whisper speech model

The model is not bundled. On first use the app offers to download whisper.cpp's
`ggml-small.en-q5_1.bin` (190 MB, MIT, derived from OpenAI Whisper, MIT) from
https://huggingface.co/ggerganov/whisper.cpp and verifies its SHA-256 before use.
