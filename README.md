# MacTube Converter

Native macOS app for permitted video downloads, media conversion, and full-length local transcription.

## Workspace

Use the sidebar to switch between Download, Convert, and Transcribe. Each workflow follows source, format, and destination; the start/cancel controls stay visible at the bottom. Open Activity from the toolbar for process logs, or Tools & transcription from the sidebar for setup.

- **Download:** paste one or more links, one per line; choose a video or audio format and start the batch. Single-video mode is on by default.
- **Convert:** drag files into the drop area or use Choose Files to select several at once. Choose a format and, where supported, Compact, Balanced, or High quality. Completed files leave the queue; failed, cancelled, and pending files remain for retry. A failure stops the batch.
- **Results:** the current session keeps up to 30 results, with the latest eight displayed beside the workspace. Open or reveal output files directly. Download results open their destination folder.

## Features

- Download video or audio, convert local media, and transcribe local files or video URLs.
- Export plain text and optional timestamped SRT subtitles; copy the transcript or reveal results in Finder.
- Choose an accuracy/speed model directly in Transcribe. Automatic prefers quantized Small English for this Intel Mac. Large v3 Turbo is an explicit Accuracy option; Base English remains available. English-only models keep the language set to English; multilingual models support automatic detection.
- Transcription shows decoded percentage, elapsed time, audio position, and live text. Percentages advance at section boundaries; a long pause between updates does not necessarily mean the decoder stopped. Five-beam search is retained, with repeated higher-temperature fallback attempts off by default. Extra decoding retries can be enabled for another attempt at difficult passages, with a substantial time cost. Optional terminology can help with names and specialized words. Live text is marked unsaved until export finishes.
- Models run locally. Singing, overlapping voices, and background music can still produce recognition errors; model selection is not a guarantee of word accuracy.
- Remember the output folder between launches. Conversions and transcripts use numbered filenames when a destination exists; downloads do not overwrite existing files.
- Cancel running jobs, see the current processing stage, and inspect bounded activity logs. Cancel and quit stop the whole tool process tree (for example the ffmpeg that yt-dlp starts). Incomplete conversions and partial download files created by a failed or cancelled job go to the Trash. Temporary transcription audio is removed after success, failure, or cancellation.
- Download and conversion progress bars; failures show the tool's own error lines, and yt-dlp errors that usually mean an outdated yt-dlp suggest updating it.
- Tools & transcription shows installed vs latest Homebrew versions and offers Update yt-dlp (asks for confirmation, runs `brew upgrade yt-dlp`).
- Accepts MKV, WebM, Opus, FLAC and other common containers by extension. Drag a file onto Transcribe. Paste adds links to the Download list. Formats, quality, subtitle, language and decoding options are remembered.
- Command-Return starts the selected operation; Escape cancels it.

## Requirements

macOS 13 or later, `yt-dlp`, `ffmpeg`, and `whisper-cli` from `whisper-cpp`.
Tools are found in Homebrew locations or PATH. A Whisper GGML model (`ggml-*.bin`) is required for transcription.
Models are not bundled into the app. At runtime they are read, in order, from `MACTUBE_MODEL_DIR`, `~/Library/Application Support/MacTubeConverter/Models`, and the workspace's sibling `~/Documents/Mac Apps/Models`.
You can also select a model file directly in the app.

## Build and run

```sh
./script/build_and_run.sh --verify
```

The script builds `build/MacTubeConverter.app`, launches it, and checks the process. It also supports `--debug`, `--logs`, and `--telemetry`. To build without launching, use `./scripts/build-app.sh` (bundle id `com.asjames18.MacTubeConverter`, ad-hoc signed; an icon is included if `Resources/AppIcon.icns` exists). To install into /Applications, run `./scripts/install.sh`; an existing copy is moved to the Trash first.

## Tests

```sh
swift test
MACTUBE_INTEGRATION_TESTS=1 swift test --filter WorkflowTests
```

The integration test uses macOS speech synthesis to generate sample audio, converts it through the app model, and verifies text and SRT output using the installed local tools. It does not download remote videos.

## Transcription diagnostics

The September 13 reproduction used a 364.5-second recording. The original CPU decoder was still working while its last reported progress remained at 7%; the live log later reached 16%. The app previously left progress and partial text inside the activity log. It now parses ordered complete UTF-8 lines and presents those updates in the workspace, including a message during long decoding intervals.

On the first 35 seconds of that recording, Base English took 42.4 seconds with the default decoder and 69.8 seconds with Flash Attention disabled. Small English Q5 took 37.4 seconds; Large v3 Turbo Q5 took 139.3 seconds. A full Turbo trial was stopped after about six minutes had decoded only the first 76 seconds, so Turbo was not selected as the default. These are single-run measurements on this Intel i7 Mac, not general performance or accuracy scores. The default attention setting is retained.

Models come from the [official whisper.cpp model distribution](https://huggingface.co/ggerganov/whisper.cpp/tree/main). Download integrity was checked against upstream hashes. Optional reproduction tests use `MACTUBE_REPRO_AUDIO`, `MACTUBE_REPRO_MODEL`, and `MACTUBE_REPRO_OUTPUT`; the output directory retains the transcript, subtitles, progress log, and decoder log for inspection.

The single-pass 65-second reproduction completed, and the full recording progressed to 32% (about 118 seconds decoded) with live text. That background full-recording test was intentionally interrupted when the user began the same recording in the updated app, to avoid CPU contention. Full six-minute export was not confirmed in that test. Model discovery is cached and runs off the main actor; known model files are checked without enumerating the app's launch directory.
