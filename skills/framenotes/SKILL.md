---
name: framenotes
description: Turn online or local teaching videos into editable visual note packages. Use when Codex is given a video URL or video file and asked to download, transcribe, summarize, create notes, create a tutorial, extract screenshots, review screenshot quality, run ASR, or export editable DOCX/PDF deliverables from video content.
version: "2026-05-11.3"
---

# FrameNotes

Use this skill to run the FrameNotes workflow: video input -> local media -> keyframes -> agent screenshot review -> ASR -> structured note -> DOCX/PDF package.

## Locate The Project

Prefer an existing FrameNotes repo when present. If the repo location is unknown, find a folder containing `scripts/process-video-url.ps1` and use that as the working directory.

Generated media and process artifacts belong under `media/` and `analysis/`. Do not ask the user to approve every stage; print concise progress and artifact paths while running.

## Environment Setup

**Windows (native):** Use `powershell -NoProfile -ExecutionPolicy Bypass`.

**WSL / Linux:** PowerShell is not available. Use `powershell.exe` (Windows host executable) for all `.ps1` scripts. If a command fails with "command not found: powershell", retry with `powershell.exe`.

**Python dependencies:** The project requires a venv at `.venv/` with packages listed in `requirements.txt`. If packages are missing, install them silently:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
```

Individual scripts (e.g. `export-tutorial-docx.ps1`) auto-install their own missing dependencies.

## BiliBili Login

For BiliBili URLs, a cookies.txt at the repo root unlocks 720p/1080p. Without it, downloads cap at 480p — screenshots suffer noticeably.

When starting a BiliBili video: if `cookies.txt` already exists in the repo root, proceed silently. If not, recommend the user export one:

1. Install the browser extension **Get cookies.txt LOCALLY** (Chrome/Edge)
2. Visit bilibili.com and log in
3. Click the extension icon → Export → save as `cookies.txt` in the repo root

If the user declines, say "no problem" and proceed with guest mode — the pipeline handles both paths. Never pressure the user.

`scripts/download-video.ps1` auto-detects `cookies.txt` at the repo root; no extra flags needed.

## Core Command

For a URL, run the full pipeline (use `powershell.exe` on WSL/Linux):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\process-video-url.ps1 "<video-url>" -Language auto -AsrModel auto -AsrDevice auto
```

The pipeline should:

1. download/import the video (max 1080p)
2. extract scene-change frames at original resolution
3. build the multimodal frame package
4. prepare the agent frame review package with nearby dense candidate frames
5. generate downsampled preview frames (`preview_frames/`) for agent review
6. extract audio
7. run faster-whisper ASR
8. text pre-screen frames: use transcript context to mark obvious rejects (skip multimodal for those)
9. write `pipeline.json`

Use `-AsrModel auto -AsrDevice auto` unless the user explicitly requests a model/device. The project should prefer CUDA only when CUDA ASR is already usable; if an NVIDIA GPU is present but CUDA is not ready, recommend the CPU first run and show the optional CUDA setup path.

**Skip flags** for re-runs and debugging:

- `-SkipDownload`: use the most recent MP4 in `media/` instead of re-downloading
- `-SkipAsr`: use the most recent `transcript.json` in `analysis/` instead of re-extracting audio and re-running ASR

## Screenshot Review

After the pipeline creates `frame_review.json` and `frame_review_prompt.md`, inspect the selected screenshots and candidates as an agent with multimodal image understanding. Use `preview_frames/` (downsampled to 720p) when the original `frames/` are too large for the multimodal viewer. Do not create a separate vision API integration for this step.

**Vision degradation strategy:** If the current model does not support image input (pure text model, or vision API returns 400 errors), do NOT attempt browser_navigate to local file paths. Instead:

1. Read `frame_review.json` and `transcript.json`
2. For each pending frame, check the timestamp against the transcript
3. Accept frames at clear content boundaries (heading mentions, topic shifts, new chapter)
4. Reject frames in silent/gap transitions or pure filler segments
5. Write the results directly into `frame_review.json` (status, reason, checks)
6. Report: "Model does not support vision — reviewed N frames by transcript alignment, accepted X, rejected Y"

Do not waste time trying multiple vision approaches when the model is text-only. One 400 error is enough signal.

For each selected screenshot:

- decide whether it is clear, step-relevant, unobstructed, and useful evidence
- if unsuitable, compare nearby `replacement_candidates` and choose a better frame
- if useful but ambiguous, add annotation suggestions
- write updates into `frame_review.json`

Use these statuses:

- `accepted`: screenshot is good as-is
- `replace`: use `review.selected_replacement`
- `annotate`: keep image and add `review.annotation_suggestions`
- `reject`: no image should be used for that step

Annotation suggestions should be simple objects with `type`, `target`, `label`, and optional normalized `box` `[x, y, width, height]` values from 0 to 1.

## ASR Policy

Use `medium` for final notes when the machine has enough memory; use `small` for quick previews or low-memory machines. Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\recommend-asr-model.ps1 -Purpose final
```

Explain model tradeoffs when relevant:

- `small`: about 0.5 GB initial download, roughly 2-3 GB available memory, faster rough notes
- `medium`: about 1.5 GB initial download, roughly 5-6 GB available memory, better final notes and mixed terminology

Use `-Language auto` for mixed-language content unless the user asks to force a language.

When only a few sections need repair, do not rerun full-video ASR. Use targeted segment ASR:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\transcribe-segments.ps1 -Audio "<audio.wav>" -Range "00:01:20-00:01:45" -Padding 8 -Model medium -Language auto
```

## Agent Conduct

Core rules for how you present work to the user:

**Do NOT expose internal operations.** The user should never see raw `read_file`, `patch`, `grep`, `bash`, or other tool call details. When you need to fix a bug or inspect code mid-session, do it quietly. Tell the user the result ("fixed, re-running export" / "已修复，重新导出中"), not the process.

**Handle missing dependencies silently.** If a script fails with `ModuleNotFoundError`, install the missing package in `.venv/` and retry automatically. Only inform the user if the fix requires their action (e.g., "need to install system package X").

**Pre-check before running.** Before starting the pipeline, quickly verify:
- `powershell.exe` works (WSL: use `powershell.exe`, not `powershell`)
- `.venv/Scripts/python.exe` exists
- `requirements.txt` packages are installed (spot-check `python -c "import docx"`)

**Progress beats silence.** For pipelines expected to run >2 minutes, relay `[STAGE]` markers to the user so they know progress is happening. Never leave the user staring at a blank chat for 38 minutes.

## Note Quality

Start the note with a decision block:

- recommended reading score, 1-5 stars
- content type
- suggested action: skip, read summary, read notes, or watch original video
- estimated reading time
- whether the original video is still worth watching

For operation/tutorial videos, produce a usable tutorial, not just a summary. Each step must include goal, timestamp, action, expected result, and common mistakes/checks.

**Every accepted (or replaced) frame from `frame_review.json` MUST appear in the tutorial as a markdown image on its own line using the exact relative path from the tutorial to the frame file:**

```
![](frames/frame_00001.jpg)
```

- Place the image line immediately after the step heading, before the bullet points.
- Each step that has a screenshot gets at least one matching `![](frames/frame_XXXXX.jpg)` line — do not merely write the frame name in text.
- If a step has multiple accepted frames, include each on its own line.
- The image paths are relative: the tutorial lives in the analysis directory, so `frames/` is a subdirectory there.

For concept explainers, prefer a chapter timeline, core ideas, comparisons, and screenshot evidence (still using `![](frames/frame_XXXXX.jpg)` on its own line for each relevant frame). Do not force a step-by-step tutorial when the video is not procedural.

**Long videos (>20 min):** Rich, multi-topic videos should not be crammed into a single compressed note. Split into parts:

- `final_tutorial.md` — complete timeline, all chapters, key screenshots (overview)
- `part2-deep-dive.md` — detailed analysis of specific topics, data points, techniques worth adopting

Each part exports independently to DOCX/PDF. Let the agent judge whether the video content density warrants splitting; do not compress just to fit a token budget.

## Pipeline Output

The pipeline produces technical output (GPU names, model sizes, ASR progress percentages, probability scores). Do NOT forward this raw output to the user. Instead, watch for `[STAGE]` markers and relay concise one-line summaries:

```
[STAGE] 1/6 Downloading video → relay "Downloading video..."
[STAGE] 2/6 Extracting keyframes → relay "Extracting keyframes..."
[STAGE] 3/6 Building multimodal package → relay "Building frame package..."
[STAGE] 4/6 Frame review package → relay "Preparing frames for review..."
[STAGE] 5/6 Extracting audio → relay "Extracting audio..."
[STAGE] 6/6 ASR → relay "Transcribing audio..." + update from [ASR] lines
```

For long videos (>10 min), ASR dominates runtime. Watch for `[ASR]` progress lines (e.g. `[ASR]  45.2% 00:14:03`) and relay "Transcribing: ~45%" every few minutes. Do NOT relay every single progress line — summarize at meaningful intervals.

When the pipeline finishes, summarize:

```
Download done (49s), keyframes extracted (24 frames), ASR done (zh, 20 segments), pre-screen done (18 kept, 6 rejected)
```

**Failure visibility:** If a stage fails and the pipeline exits non-zero, tell the user which stage failed and what the error was. Do not hide failures behind vague "something went wrong" messages.

Only surface warnings or errors that need user action. The raw output is available in `pipeline.json` if needed.

## Deliverables

For user-facing packages, use title-based filenames:

- `<safe-title>.note.docx`: editable main deliverable
- `<safe-title>.note.pdf`: read-only preview/export
- `<safe-title>.source.md`: optional source Markdown
- `<safe-title>.pipeline.json`: optional processing trace

Keep working files such as `final_tutorial.md` internal. Do not call the public output `final`.

Export DOCX with:

```powershell
$name = powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\get-safe-title.ps1 -Text "<video title>"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-tutorial-docx.ps1 -Markdown "<final_tutorial.md>" -NamePrefix "$name.note"
```

Export PDF from the resulting DOCX:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-tutorial-pdf.ps1 -Docx "<path-to-.docx>"
```

This tries `docx2pdf` first, then falls back to Word COM. Install `docx2pdf` with `.\.venv\Scripts\pip.exe install docx2pdf` if needed.

When producing DOCX/PDF, use the Documents skill if available and render/verify the document before delivery. If LibreOffice is unavailable on Windows, Microsoft Word COM plus PDF-to-PNG rendering is acceptable for visual QA.

## Git And File Safety

Track only code and documentation. Downloaded videos, generated frames, ASR output, dense candidates, DOCX/PDF deliverables, and process files should remain under ignored directories such as `media/` and `analysis/`.

Do not batch-delete files or directories. On this machine, never use recursive deletion commands. If cleanup is needed, delete only one explicit file path at a time or ask the user to clean generated artifacts manually.
