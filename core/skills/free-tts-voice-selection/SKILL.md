---
name: free-tts-voice-selection
description: "Выбор и проверка бесплатного решения для синтеза речи под конкретную машину, включая macOS на CPU. Используй, когда нужен бесплатный TTS или сравнение открытых проектов по практической применимости, а не по теоретической мощности."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [tts, voice-cloning, open-source, github, macos, cpu-only, research]
---

# Free/Open-Source TTS Voice Selection

Use this skill when the user wants a free/open-source TTS solution, asks to compare GitHub projects, or wants the “best practical” option for their machine rather than the most advanced model on paper.

## Core principle

Do not pick the flashiest model by reputation alone. First inspect the actual machine constraints, then choose the strongest option that is realistically deployable there.

On macOS arm64 with no NVIDIA GPU, prefer a lightweight local engine first. In practice, Piper is often the best default for immediate production results.

## Proven workflow

1. Inspect the machine first
- Check OS/arch, Python version, GPU availability, and ffmpeg.
- Example:
  - `uname -a`
  - `python3 --version`
  - `nvidia-smi` if available, otherwise note CPU-only
  - `ffmpeg -version | head -n 1`

2. Gather candidate projects
Common comparison set:
- OHF-Voice/piper1-gpl
- coqui-ai/TTS
- myshell-ai/OpenVoice
- ResembleAI/chatterbox
- neonbjb/tortoise-tts
- yl4579/StyleTTS2

3. Validate claims from source materials
- Read upstream README/USAGE via `curl` from GitHub raw when possible.
- Check what the project explicitly claims: multilingual, voice cloning, CPU/GPU assumptions, install method, platform notes.
- Prefer direct docs over third-party blog posts.

4. Validate installability, not just popularity
Use package metadata to measure practical cost.
- `python -m pip index versions <package>`
- `python -m pip download --no-deps <package> -d /tmp/...`
- Inspect wheel `METADATA` for `Requires-Dist`
- Attempt a minimal install in a temporary venv for the frontrunner
- Run a smoke test import and `--help` or CLI invocation

5. Make the decision based on deployment reality
Recommended decision rule:
- CPU-only / Mac / wants free + local + fast -> Piper first
- Needs voice cloning from reference audio and can tolerate more setup -> Coqui XTTS or OpenVoice
- Wants experimental higher-expressiveness stack and has more compute/headroom -> Chatterbox
- Avoid Tortoise/StyleTTS2 as first choice for quick, reliable production on constrained systems

6. Separate “voice identity” from “voice character”
If the user says “match voices to personalities,” do not promise historically exact voices. Instead map each character to:
- timbre
- pace
- authority level
- emotional color
- narration style

Example character mapping pattern:
- philosopher -> calm, deep, measured
- officer/revolutionary -> firm, energetic, sharper pacing
- dark political theorist -> low, cold, deliberate
- diplomat/jurist -> balanced, articulate, restrained
- sovereign/state theorist -> authoritative, official, declarative

## Practical conclusions from experience

### Best free practical option on macOS CPU-only
Choose Piper when all of the following are true:
- no NVIDIA GPU
- user wants a free/open-source local workflow
- user needs output soon
- cloning is optional, but distinct character voices are needed

Why Piper wins in this environment:
- lighter dependency stack
- local inference
- CPU-friendly
- fast enough for batch quiz/audio generation
- easier to verify with CLI and package install

### When not to choose Piper first
Escalate to XTTS/OpenVoice when the user explicitly needs:
- zero-shot voice cloning from a reference clip
- cross-lingual cloning
- more actor-like/persona-like differentiation than prebuilt voices can provide

## Tooling notes and pitfalls

- GitHub/API/network tooling may fail for environmental reasons. If Python urllib hits SSL certificate issues, fall back to `curl`.
- Some raw GitHub URLs can 404 because of incorrect owner casing, branch assumptions, or path mismatches. Verify repo owner and default branch before relying on raw URLs.
- In protected environments, some shell commands may be blocked by guardrails. Do not keep retrying the exact blocked command.
- Package availability on PyPI can be more reliable for fast validation than full repo installation.

## Recommended output format to the user

When reporting findings, provide:
1. Best choice now
2. Why it fits this specific machine
3. Why stronger-looking alternatives were rejected for now
4. A practical next step (e.g. generate 3–5 sample voices and choose by ear)
5. Character-to-voice-style recommendations

## Verification checklist

Before finalizing a recommendation, verify at least:
- environment constraints captured
- frontrunner package exists
- minimal install works or is plausibly installable
- import/CLI smoke test works for the chosen path
- comparison includes at least one lightweight option and one cloning-capable option

## Good final recommendation pattern

For a quiz/narration project on macOS without NVIDIA:
- Recommend Piper as the main production path
- Use 3–5 distinct voices/styles to represent different personalities
- If later needed, propose XTTS/OpenVoice as a second-phase upgrade for reference-based cloning
