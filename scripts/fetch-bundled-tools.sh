#!/usr/bin/env bash
# Downloads (with checksum checks) and builds the universal helper tools that ship inside
# the downloadable app, into vendor/bin and vendor/licenses. Needs Xcode, cmake and ninja.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${MACTUBE_VENDOR_WORK:-$ROOT_DIR/.vendor-work}"
OUT="$ROOT_DIR/vendor/bin"; LIC="$ROOT_DIR/vendor/licenses"
mkdir -p "$WORK" "$OUT" "$LIC"; cd "$WORK"
YTDLP_VERSION=2026.10.26; YTDLP_SHA=0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa
WHISPER_VERSION=1.9.5
FF=https://ffmpeg.martin-riedl.de/download/macos
dl() { curl -fsSL --retry 3 -o "$2" "$1"; }
check() { [ "$(shasum -a 256 "$1" | awk '{print $1}')" = "$2" ] || { echo "Checksum mismatch: $1" >&2; exit 1; }; }
for pair in amd64:1789931006_9.0.2 arm64:1789931890_9.0.2; do a=${pair%%:*}; r=${pair#*:}; mkdir -p ff-$a
  for f in ffmpeg ffprobe; do
    dl "$FF/$a/$r/$f.zip" ff-$a/$f.zip; dl "$FF/$a/$r/$f.zip.sha256" ff-$a/$f.zip.sha256
    check ff-$a/$f.zip "$(awk '{print $1}' ff-$a/$f.zip.sha256)"; (cd ff-$a && ditto -x -k $f.zip .)
  done
  dl "$FF/$a/$r/versions.txt" "$LIC/ffmpeg-versions-$a.txt"
done
for f in ffmpeg ffprobe; do lipo -create ff-amd64/$f ff-arm64/$f -output "$OUT/$f"; done
dl "https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION/yt-dlp_macos" "$OUT/yt-dlp"; check "$OUT/yt-dlp" "$YTDLP_SHA"
dl "https://raw.githubusercontent.com/yt-dlp/yt-dlp/$YTDLP_VERSION/LICENSE" "$LIC/yt-dlp-LICENSE.txt"
# Deno: JavaScript runtime yt-dlp needs for YouTube.
DENO_VERSION=2.9.8
DENO_SHA_aarch64=9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e
DENO_SHA_x86_64=4b2f5edd2639b7470f034238b321d7002d8dfb4726d8558f52c17afac370eb2c
for a in aarch64 x86_64; do
  dl "https://github.com/denoland/deno/releases/download/v$DENO_VERSION/deno-$a-apple-darwin.zip" deno-$a.zip
  sha_var="DENO_SHA_$a"; check deno-$a.zip "${!sha_var}"
  rm -rf deno-$a && mkdir deno-$a && ditto -x -k deno-$a.zip deno-$a
done
lipo -create deno-aarch64/deno deno-x86_64/deno -output "$OUT/deno"
dl "https://raw.githubusercontent.com/denoland/deno/v$DENO_VERSION/LICENSE.md" "$LIC/deno-LICENSE.md"
dl "https://raw.githubusercontent.com/FFmpeg/FFmpeg/n9.0.2/COPYING.GPLv3" "$LIC/ffmpeg-COPYING.GPLv3.txt"
dl "https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v$WHISPER_VERSION.tar.gz" whisper.tar.gz
rm -rf "whisper.cpp-$WHISPER_VERSION" && tar xzf whisper.tar.gz
cp "whisper.cpp-$WHISPER_VERSION/LICENSE" "$LIC/whisper.cpp-LICENSE.txt"
# Intel slice: CPU only (AVX2 + Accelerate). Metal on Intel GPUs produced wrong transcripts.
for arch in arm64 x86_64; do
  extra=(); [ $arch = x86_64 ] && extra=(-DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON -DGGML_METAL=OFF)
  cmake -S "whisper.cpp-$WHISPER_VERSION" -B wb-$arch -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=$arch \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DBUILD_SHARED_LIBS=OFF -DGGML_NATIVE=OFF -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_OPENMP=OFF -DWHISPER_SDL2=OFF -DWHISPER_CURL=OFF \
    -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF -DWHISPER_BUILD_EXAMPLES=ON ${extra[@]+"${extra[@]}"} >/dev/null
  cmake --build wb-$arch --target whisper-cli -j 8 >/dev/null
done
lipo -create wb-arm64/bin/whisper-cli wb-x86_64/bin/whisper-cli -output "$OUT/whisper-cli"
chmod +x "$OUT"/*
for f in "$OUT"/*; do lipo -info "$f"; if otool -L "$f" | grep -qE '/usr/local|/opt/homebrew'; then echo "Non-system dependency in $f" >&2; exit 1; fi; done
