---
name: elevenlabs-gs
description: "Превращает пронумерованный русский текст квиза в голосовые файлы (mp3, wav, ogg) через ElevenLabs. Используй, когда нужно озвучить текстовые блоки."
version: 1.0.0
author: local
license: MIT
metadata:
  hermes:
    tags: [TTS, ElevenLabs, Voice Message, Russian]
prerequisites:
  env_vars: [ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID]
---

# ElevenLabs to GS

Use this skill to transform text blocks into ready voice-message files (`mp3`, `wav`, or `ogg`).

## Required Inputs

1. Source text file path.
2. Output directory path.
3. Voice ID (`--voice-id` or `ELEVENLABS_VOICE_ID`).

## Command

```bash
python3 ~/.hermes/bin/elevenlabs_to_gs.py \
  --input "<TEXT_FILE>" \
  --out-dir "<OUTPUT_DIR>" \
  --format mp3
```

For Telegram-style voice notes:

```bash
python3 ~/.hermes/bin/elevenlabs_to_gs.py \
  --input "<TEXT_FILE>" \
  --out-dir "<OUTPUT_DIR>" \
  --format ogg
```

## Validation Workflow

1. Run dry-run parse first:
   `python3 ~/.hermes/bin/elevenlabs_to_gs.py -i "<TEXT_FILE>" -o "<OUTPUT_DIR>" --dry-run`
2. Confirm segment count and `manifest.json`.
3. Run real synthesis.
4. Confirm output files exist and have non-zero sizes.
5. Return:
   - absolute output directory
   - generated files list
   - path to `manifest.json`

## Security and Stability Rules

1. Never print API keys.
2. Keep keys only in `~/.hermes/.env`.
3. If missing key/voice id, fail with explicit action message.
4. Do not overwrite unrelated files outside output directory.
