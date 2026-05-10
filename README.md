# FrameNotes

FrameNotes is a teaching-video ingestion and analysis project. The first step is downloading or importing videos into a stable local media layout.

## One-Command Pipeline

In the formal workflow, the user provides a video URL and the pipeline runs every step automatically. It prints stage progress and artifact paths while it works, so the user can inspect intermediate outputs without approving each step.

```powershell
.\scripts\process-video-url.ps1 "https://www.bilibili.com/video/BVxxxx" -Language auto -AsrModel auto -AsrDevice auto
```

Pipeline stages:

1. Download video
2. Extract scene-change keyframes
3. Build multimodal frame package
4. Prepare agent frame review package with nearby dense candidate frames
5. Extract audio
6. Run ASR transcription

Downloaded media and generated process files stay under `media/` and `analysis/`; both folders are ignored by Git.

Each full pipeline run writes `pipeline.json` in the analysis folder. It records the URL, selected video, audio directory, transcript, stage durations, and intermediate artifact paths.

Use `-AsrModel auto -AsrDevice auto` in the normal product flow. The pipeline will inspect the local machine, explain the tradeoff, choose a model, and prefer CUDA only when CUDA ASR is already usable in the Python environment.

## ASR Model Recommendation

Before transcription, tell the user what the ASR model choice means:

```powershell
$video = Get-ChildItem -Path media -Filter *.mp4 -Recurse -File | Select-Object -First 1 -ExpandProperty FullName
.\scripts\recommend-asr-model.ps1 -Video $video -Purpose final
```

Current CPU defaults:

| Model | First download | Recommended memory | Best for |
| --- | --- | --- | --- |
| `small` | ~0.5 GB | 2-3 GB available | Fast preview, rough notes, low-memory machines |
| `medium` | ~1.5 GB | 5-6 GB available | Formal notes, better English terminology, mixed-language ASR |

On this machine, `small` is appropriate for quick previews and `medium` is recommended for final notes.

## GPU ASR

GPU transcription is worth considering only when an NVIDIA GPU is available. CUDA setup downloads extra runtime packages and can take longer than the first useful CPU run.

Runtime policy:

- If CUDA ASR is already installed and available, use CUDA first.
- If CUDA is not available but an NVIDIA GPU is detected, recommend CPU for the first run and show the optional CUDA setup path.
- If no NVIDIA GPU is detected, recommend CPU.

Check recommendation:

```powershell
.\scripts\recommend-asr-model.ps1 -Purpose final
.\scripts\detect-asr-device.ps1
```

If the machine has an NVIDIA GPU and the user explicitly wants GPU ASR:

```powershell
.\scripts\setup-cuda-asr.ps1 -Model medium
```

Then run transcription with CUDA:

```powershell
.\scripts\transcribe-audio.ps1 -Audio <audio.wav> -Model medium -Language auto -Device cuda
```

For AMD or Intel graphics on Windows, CPU transcription is recommended for new users.

## Video Download

Install the downloader in a project-local Python environment:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -U yt-dlp
```

Download a public video:

```powershell
.\scripts\download-video.ps1 "https://www.bilibili.com/video/BVxxxx"
```

Download using browser login cookies when the source requires your existing login:

```powershell
.\scripts\download-video.ps1 "https://www.bilibili.com/video/BVxxxx" -CookiesFromBrowser edge
```

Downloaded files are written under `media/`, with sidecar metadata such as `*.info.json`, subtitles, and thumbnails when available.
The downloader is configured with `--no-overwrites` and `--keep-video` so existing files and merge inputs are preserved.

Only download videos you have permission to access and use.

## Keyframe Extraction

Extract scene-change keyframes from a downloaded video:

```powershell
$video = Get-ChildItem -Path media -Filter *.mp4 -Recurse -File | Select-Object -First 1 -ExpandProperty FullName
.\scripts\extract-keyframes.ps1 -Video $video
```

Each run writes a new folder under `analysis/` containing:

- `frames/`: extracted keyframe images
- `frames.json`: source metadata, frame paths, and timestamps
- `contact.jpg`: visual overview sheet

## Multimodal Package

Create a model-ready prompt and selected frame manifest:

```powershell
$framesJson = Get-ChildItem -Path analysis -Filter frames.json -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
.\scripts\build-multimodal-package.ps1 -FramesJson $framesJson -MaxFrames 24
```

This writes `multimodal_prompt.md` and `selected_frames.json` into the same analysis folder.

## Frame Review And Dense Fallback

Selected screenshots should be reviewed before becoming final tutorial evidence. In the agent workflow this is not a standalone API call. The pipeline prepares local image paths, nearby dense candidates, and a strict JSON update format; the configured agent inspects those images with multimodal capability and updates `frame_review.json`.

Prepare a review manifest:

```powershell
$selected = Get-ChildItem -Path analysis -Filter selected_frames.json -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
.\scripts\refine-frames.ps1 -SelectedFramesJson $selected
```

When a selected screenshot is not suitable, extract denser nearby candidates:

```powershell
.\scripts\refine-frames.ps1 -SelectedFramesJson $selected -ExtractDense -Window 4 -Fps 1
```

This writes `frame_review.json`, `frame_review_prompt.md`, and optionally `dense_candidates/`.

Agent behavior:

- inspect `frame_absolute_path` for every selected screenshot
- if the screenshot is unclear or weak, compare `replacement_candidates`
- set `review.status` to `accepted`, `replace`, `annotate`, or `reject`
- when replacing, set `review.selected_replacement`
- when annotation helps, add `review.annotation_suggestions`
- keep all generated media local under `analysis/`

## Audio Extraction

Extract mono 16 kHz WAV audio for transcription:

```powershell
$video = Get-ChildItem -Path media -Filter *.mp4 -Recurse -File | Select-Object -First 1 -ExpandProperty FullName
.\scripts\extract-audio.ps1 -Video $video
```

This writes `audio.wav` and `audio.json` under `analysis/`. Processing outputs stay local and are ignored by Git.

## Transcription

Transcribe extracted audio with `faster-whisper`:

```powershell
.\.venv\Scripts\python.exe -m pip install -U faster-whisper
.\scripts\download-whisper-model.ps1 -Model medium
$audio = Get-ChildItem -Path analysis -Filter audio.wav -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
.\scripts\transcribe-audio.ps1 -Audio $audio -Model .\.models\faster-whisper-medium -Language auto
```

This writes `transcript.txt`, `transcript.srt`, and `transcript.json` beside the audio file.

Use `-Language auto` for mixed Chinese/English videos. Use `-Language zh` or `-Language en` when the video's language is known and you want to force the model.

## Targeted ASR Reruns

Do not rerun full-video ASR when only a few sections are suspicious. Retranscribe just the questionable ranges with a small amount of surrounding context:

```powershell
$audio = "C:\path\to\audio.wav"
.\scripts\transcribe-segments.ps1 -Audio $audio -Range "00:01:20-00:01:45","00:03:10-00:03:35" -Padding 8 -Model medium -Language auto
```

This writes `segment_transcript.txt`, `segment_transcript.srt`, and `segment_transcript.json` under a new `segment_asr_*` folder beside the audio. Use this for low-confidence or language-misdetected fragments, then patch the final notes from the segment output.

## Note Format

Generated notes should start with a reading decision block:

- Recommended reading score: 1-5 stars
- Content type
- Suggested action: skip, read summary, read notes, or watch original video
- Estimated reading time
- Whether the original video is still worth watching

For operation/tutorial videos, turn the extracted screenshots into a usable step-by-step tutorial. Each step should include:

- Goal
- Timestamp
- Screenshot/frame reference
- Action to perform
- Expected result
- Common mistakes or checks

For concept explainer videos, prefer chapter timelines, concept summaries, comparisons, and frame evidence instead of forcing a screenshot tutorial.

## Final Deliverables

For user-facing tutorial packages, produce:

- `<safe-title>.note.docx`: editable main deliverable for Word/WPS/LibreOffice
- `<safe-title>.note.pdf`: read-only preview/export for users who do not need editing
- `final_tutorial.md`: internal source file
- `pipeline.json`: internal processing trace

Export DOCX from the final Markdown:

```powershell
$name = .\scripts\get-safe-title.ps1 -Text "如何为树莓派 CM5 EMMC版本 烧录系统"
.\scripts\export-tutorial-docx.ps1 -Markdown "analysis\...\final_tutorial.md" -NamePrefix "$name.note"
```

Recommended public filenames:

- `<safe-title>.note.docx`
- `<safe-title>.note.pdf`
- `<safe-title>.source.md`
- `<safe-title>.pipeline.json`

Keep `final_tutorial.*` as internal working names only.

## Publishing And Codex Skill

FrameNotes code and the Codex skill are published together but serve different roles:

- project code under `scripts/` implements downloading, keyframes, ASR, frame review package generation, and exports
- `skills/framenotes/` is the Codex workflow layer that tells an agent how to use the project
- generated videos, screenshots, transcripts, DOCX/PDF files, and process manifests stay under ignored folders such as `media/` and `analysis/`

Install the bundled skill into the local Codex skills directory:

```powershell
.\scripts\install-codex-skill.ps1
```

If `CODEX_HOME` is set, the installer uses `$env:CODEX_HOME\skills\framenotes`. Otherwise it installs to `$HOME\.codex\skills\framenotes`.

After installation, use the skill in Codex:

```text
Use $framenotes to turn this video link into an editable note package: <url>
```

The skill should remain a thin workflow guide. Keep implementation changes in the project scripts so the code can be tested, versioned, and reviewed normally.
