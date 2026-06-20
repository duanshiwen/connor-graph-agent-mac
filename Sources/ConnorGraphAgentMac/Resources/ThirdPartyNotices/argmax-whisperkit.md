# Argmax OSS / WhisperKit Notice

Connor Browser Media Transcription is designed for local-first speech-to-text using governed Apple Silicon transcription runtimes such as WhisperKit, and optionally speaker diarization runtimes such as SpeakerKit.

Distribution policy:

- SDK version, license, and source must be recorded.
- Model version, checksum, source, and license must be recorded separately from SDK notices.
- Larger models should be managed through explicit model download/materialization settings rather than silently bundled.
- Transcription output must remain session-owned and local by default.
