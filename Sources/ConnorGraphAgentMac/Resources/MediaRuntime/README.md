# Connor Media Runtime Bundle

Connor treats media transcription as an app-managed consumer feature. Users must not be asked to install Python, yt-dlp, ffmpeg, WhisperKit, or baseline ASR models manually.

## Required bundled WhisperKit baseline

A consumer-grade offline baseline requires both models below to be shipped in the app-managed runtime:

- `whisperkit/models/openai_whisper-small/`
- `whisperkit/models/openai_whisper-medium/`

The default transcription model is `openai_whisper-medium`. `openai_whisper-small` is retained as the fast / lower-resource fallback.

Each bundled model directory must contain the real WhisperKit CoreML artifacts, not placeholder folders:

- `AudioEncoder.mlmodelc/`
- `MelSpectrogram.mlmodelc/`
- `TextDecoder.mlmodelc/`
- `config.json`
- `generation_config.json`

The app runtime verifier intentionally marks WhisperKit unavailable unless both `small` and `medium` are present with these required files.

## Optional high-accuracy models

Large / distilled-large models are not baseline requirements. They should be user-initiated high-accuracy downloads managed by Connor:

- `openai_whisper-large-v3-v20240930_547MB`
- `openai_whisper-large-v3-v20240930_626MB`
- `distil-whisper_distil-large-v3_594MB`

## Upstream model source

Argmax WhisperKit CoreML model repository:

- https://huggingface.co/argmaxinc/whisperkit-coreml
