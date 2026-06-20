# Python Runtime Notice

Connor Browser Media Transcription may materialize a governed Python runtime sidecar for yt-dlp execution.

Boundary:

- The Python runtime is not exposed as a general scripting surface.
- It is only resolved through Connor runtime wrappers such as `YTDLPRuntime`.
- Runtime checksum, version, source, and license manifest must be recorded.
- Connor must continue to work without relying on user PATH, Homebrew, pyenv, or `/usr/bin/python3`.
