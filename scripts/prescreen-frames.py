import argparse
import json
from pathlib import Path


def load_transcript(path: Path):
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    return data.get("segments", [])


def find_context(segments: list, target_seconds: float, window_segments: int = 3):
    target = float(target_seconds)
    best_idx = None
    best_dist = float("inf")
    for i, seg in enumerate(segments):
        mid = (seg["start"] + seg["end"]) / 2
        dist = abs(mid - target)
        if dist < best_dist:
            best_dist = dist
            best_idx = i

    if best_idx is None:
        return [], -1

    start_idx = max(0, best_idx - window_segments)
    end_idx = min(len(segments), best_idx + window_segments + 1)
    return segments[start_idx:end_idx], best_idx - start_idx


def build_frame_block(frame_index: int, timestamp: str, context_segments: list, center_offset: int):
    lines = []
    for i, seg in enumerate(context_segments):
        marker = " >>>" if i == center_offset else "    "
        start_text = seg.get("start_text", f"{seg['start']:.3f}")
        lines.append(f"{marker} [{start_text}] {seg['text']}")

    context_block = "\n".join(lines)

    return f"""### 帧 #{frame_index} ({timestamp})

```
{context_block}
```

回答（仅 REJECT 或 KEEP）：
"""


def main():
    parser = argparse.ArgumentParser(
        description="Generate a prescreen prompt for agent-level text LLM classification. "
                    "The agent reads the output .md file, classifies each frame as REJECT or KEEP, "
                    "and updates frame_review.json accordingly."
    )
    parser.add_argument("frame_review", type=Path, help="Path to frame_review.json")
    parser.add_argument("--transcript", type=Path, help="Path to transcript.json (auto-detected if omitted)")
    parser.add_argument("--window", type=int, default=3, help="Transcript segments on each side of frame")
    args = parser.parse_args()

    review_path = args.frame_review.resolve()
    if not review_path.exists():
        raise FileNotFoundError(review_path)

    review = json.loads(review_path.read_text(encoding="utf-8-sig"))
    analysis_dir = review_path.parent

    # Auto-detect transcript: match by stripping the analysis dir's trailing timestamp,
    # then look for a sibling audio dir whose name starts with the same base and contains _audio_
    transcript_path = args.transcript
    if not transcript_path:
        import re
        analysis_name = analysis_dir.name
        base = re.sub(r"_\d{8}T\d{6}Z(_interval)?$", "", analysis_name)
        for sibling in analysis_dir.parent.iterdir():
            if not sibling.is_dir():
                continue
            if not sibling.name.startswith(base):
                continue
            if "_audio_" not in sibling.name:
                continue
            t_json = sibling / "transcript.json"
            if t_json.exists():
                transcript_path = t_json
                break
    if not transcript_path or not transcript_path.exists():
        raise FileNotFoundError("Cannot find transcript.json. Pass --transcript explicitly.")

    segments = load_transcript(transcript_path)

    pending = [f for f in review["frames"] if f["review"]["status"] == "pending"]
    if not pending:
        print("No pending frames to screen.")
        return

    lines = [
        "# Frame Pre-Screen Task",
        "",
        "You are running in agent mode with access to `frame_review.json` and `transcript.json`.",
        "Use your text LLM to classify each pending frame below. Do not call a vision API for this step.",
        "",
        "## Rules",
        "",
        "- Read each frame's timestamp and surrounding transcript context.",
        "- `REJECT` if: silence/gap/transition, duplicate of a nearby frame, filler chat with no teaching value.",
        "- `KEEP` if: teaching step, demo, key conclusion, chapter turn — even if you're unsure, keep for visual review.",
        "- Write `REJECT` or `KEEP` on the answer line after each frame block.",
        "",
        "## Update Instructions",
        "",
        "After classification, update `frame_review.json` for each rejected frame:",
        "",
        "- Set `review.status` to `rejected`",
        '- Set `review.reason` to `"文本预筛：该时刻无明显教学价值，跳过视觉审查"`',
        "- Set all `review.checks` booleans to `false`",
        '- Add `"skip_multimodal": true` to the review object',
        "",
        "Do not modify kept frames — they stay `pending` for later multimodal review.",
        "",
        "---",
        "",
        f"Total pending frames: {len(pending)}",
        "",
    ]

    for frame in pending:
        idx = frame["index"]
        ts = frame["timestamp"]
        secs = frame["timestamp_seconds"]
        ctx_segments, center = find_context(segments, secs, args.window)
        lines.append(build_frame_block(idx, ts, ctx_segments, center))

    prompt_path = analysis_dir / "prescreen_prompt.md"
    prompt_path.write_text("\n".join(lines), encoding="utf-8")
    print(prompt_path)
    print(f"frames={len(pending)}")


if __name__ == "__main__":
    main()
