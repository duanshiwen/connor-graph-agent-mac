# yt-dlp Notice

Connor Browser Media Transcription is designed to use a governed yt-dlp source/runtime sidecar, not an unmanaged user PATH binary.

Planned distribution policy:

- Runtime source/version must be pinned.
- License and dependency notices must be preserved.
- Official PyInstaller binaries are not the default distribution path because bundled dependencies can change the combined licensing posture.
- Runtime self-update is disabled; updates must go through Connor runtime governance.

Forbidden runtime capabilities in Connor wrappers:

- `--update`, `-U`, `--update-to`
- `--exec`
- arbitrary `--external-downloader`
- arbitrary cookie/netrc/username/password parameters unless a future explicit per-domain credential capability is approved
- playlist batch processing without explicit user confirmation
