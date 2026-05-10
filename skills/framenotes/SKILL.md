---
name: framenotes
description: Turn online or local teaching videos into editable visual note packages. Use when Codex is given a video URL or video file and asked to download, transcribe, summarize, create notes, create a tutorial, extract screenshots, review screenshot quality, run ASR, or export editable DOCX/PDF deliverables from video content.
---

# FrameNotes

Use this skill to run the FrameNotes workflow: video input -> local media -> keyframes -> agent screenshot review -> ASR -> structured note -> DOCX/PDF package.

## Locate The Project

Prefer an existing FrameNotes repo when present. If the repo location is unknown, find a folder containing `scripts/process-video-url.ps1` and use that as the working directory.

Generated media and process artifacts belong under `media/` and `analysis/`. Do not ask the user to approve every stage; print concise progress and artifact paths while running.

## Core Command

For a URL, run the full pipeline:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\process-video-url.ps1 "<video-url>" -Language auto -AsrModel auto -AsrDevice auto
```

The pipeline should:

1. download/import the video
2. extract scene-change frames
3. build the multimodal frame package
4. prepare the agent frame review package with nearby dense candidate frames
5. extract audio
6. run faster-whisper ASR
7. write `pipeline.json`

Use `-AsrModel auto -AsrDevice auto` unless the user explicitly requests a model/device. The project should prefer CUDA only when CUDA ASR is already usable; if an NVIDIA GPU is present but CUDA is not ready, recommend the CPU first run and show the optional CUDA setup path.

## Screenshot Review

After the pipeline creates `frame_review.json` and `frame_review_prompt.md`, inspect the selected screenshots and candidates as an agent with multimodal image understanding. Do not create a separate vision API integration for this step.

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

## Note Quality

Start the note with a decision block:

- recommended reading score, 1-5 stars
- content type
- suggested action: skip, read summary, read notes, or watch original video
- estimated reading time
- whether the original video is still worth watching

For operation/tutorial videos, produce a usable tutorial, not just a summary. Each step should include goal, timestamp, screenshot reference, action, expected result, and common mistakes/checks.

For concept explainers, prefer a chapter timeline, core ideas, comparisons, and screenshot evidence. Do not force a step-by-step tutorial when the video is not procedural.

## Deliverables

For user-facing packages, use title-based filenames:

- `<safe-title>.note.docx`: editable main deliverable
- `<safe-title>.note.pdf`: read-only preview/export
- `<safe-title>.source.md`: optional source Markdown
- `<safe-title>.pipeline.json`: optional processing trace

Keep working files such as `final_tutorial.md` internal. Do not call the public output `final`.

Export DOCX with:

```powershell
$name = powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\get-safe-title.ps1 -Text "<video title>"
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\export-tutorial-docx.ps1 -Markdown "<final_tutorial.md>" -NamePrefix "$name.note"
```

When producing DOCX/PDF, use the Documents skill if available and render/verify the document before delivery. If LibreOffice is unavailable on Windows, Microsoft Word COM plus PDF-to-PNG rendering is acceptable for visual QA.

## Git And File Safety

Track only code and documentation. Downloaded videos, generated frames, ASR output, dense candidates, DOCX/PDF deliverables, and process files should remain under ignored directories such as `media/` and `analysis/`.

Do not batch-delete files or directories. On this machine, never use recursive deletion commands. If cleanup is needed, delete only one explicit file path at a time or ask the user to clean generated artifacts manually.
