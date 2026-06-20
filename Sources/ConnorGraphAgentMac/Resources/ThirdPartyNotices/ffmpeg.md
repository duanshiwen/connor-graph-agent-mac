# FFmpeg Notice

Connor Browser Media Transcription may use FFmpeg as a governed sidecar executable for audio probing, normalization, conversion, and chunking.

Distribution policy:

- Only LGPL-compatible builds are allowed by default.
- Builds must not enable GPL or nonfree components unless the entire product licensing strategy is explicitly revisited.
- Configure flags, version, checksum, source offer/source link, and license text must be recorded in the runtime manifest and application notices.
- FFmpeg is invoked as an external executable sidecar; it is not linked into Connor application code.
