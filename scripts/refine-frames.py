import argparse
import json
import subprocess
from pathlib import Path


def ffmpeg_bin(explicit):
    if explicit:
        return Path(explicit)

    local = Path.home() / "AppData/Local/Microsoft/WinGet/Packages"
    matches = list(local.glob("Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe"))
    if matches:
        return matches[0]

    return Path("ffmpeg")


def timestamp(seconds):
    seconds = max(0.0, float(seconds))
    whole = int(seconds)
    return f"{whole // 3600:02d}-{(whole % 3600) // 60:02d}-{whole % 60:02d}"


def extract_dense_frames(ffmpeg, video, output_dir, center, window, fps, max_width):
    start = max(0.0, center - window)
    duration = window * 2
    folder = output_dir / f"around_{timestamp(center)}"
    folder.mkdir(parents=True, exist_ok=True)
    pattern = folder / "dense_%04d.jpg"

    vf = f"fps={fps},scale='min({max_width},iw)':-2"
    subprocess.run(
        [
            str(ffmpeg),
            "-v",
            "error",
            "-hide_banner",
            "-ss",
            str(start),
            "-t",
            str(duration),
            "-i",
            str(video),
            "-vf",
            vf,
            "-q:v",
            "3",
            str(pattern),
        ],
        check=True,
        text=True,
    )
    return folder


def rel(path, base):
    return str(path.relative_to(base)).replace("\\", "/")


def image_ref(path):
    return path.resolve().as_posix()


def main():
    parser = argparse.ArgumentParser(description="Prepare selected frames for multimodal review and optional dense fallback extraction.")
    parser.add_argument("selected_frames_json", type=Path)
    parser.add_argument("--extract-dense", action="store_true")
    parser.add_argument("--window", type=float, default=4.0)
    parser.add_argument("--fps", type=float, default=1.0)
    parser.add_argument("--max-width", type=int, default=1280)
    parser.add_argument("--ffmpeg", type=Path)
    args = parser.parse_args()

    selected_path = args.selected_frames_json.resolve()
    selected = json.loads(selected_path.read_text(encoding="utf-8-sig"))
    analysis_dir = selected_path.parent
    video = Path(selected["source_video"])
    ffmpeg = ffmpeg_bin(args.ffmpeg)

    review_items = []
    dense_root = analysis_dir / "dense_candidates"

    for frame in selected["frames"]:
        item = {
            "index": frame["index"],
            "timestamp": frame["timestamp"],
            "timestamp_seconds": frame["timestamp_seconds"],
            "frame_path": frame["path"],
            "frame_absolute_path": image_ref(analysis_dir / frame["path"]),
            "review": {
                "status": "pending",
                "checks": {
                    "is_clear": None,
                    "is_step_relevant": None,
                    "has_obstruction": None,
                    "needs_replacement": None,
                    "needs_annotation": None,
                },
                "reason": "",
                "replacement_candidates": [],
                "annotation_suggestions": [],
            },
        }

        if args.extract_dense and frame.get("timestamp_seconds") is not None:
            folder = extract_dense_frames(
                ffmpeg,
                video,
                dense_root,
                float(frame["timestamp_seconds"]),
                args.window,
                args.fps,
                args.max_width,
            )
            item["review"]["replacement_candidates"] = [
                {
                    "path": rel(path, analysis_dir),
                    "absolute_path": image_ref(path),
                }
                for path in sorted(folder.glob("*.jpg"))
            ]

        review_items.append(item)

    prompt_lines = [
        "# Agent Frame Review Task",
        "",
        "You are running in agent mode with local filesystem access and multimodal image understanding.",
        "Do not call a standalone vision API. Inspect the image paths in `frame_review.json` directly, then update that JSON in place.",
        "",
        "Goal: decide whether each selected screenshot is good enough for a tutorial note. If it is not, choose a nearby dense candidate. If needed, add annotation suggestions that a later document builder can render.",
        "",
        "For each frame, check:",
        "",
        "- clarity: text or hardware details are readable enough",
        "- step relevance: it shows an action, setting, connection, command, or expected result",
        "- coverage: the important UI or hardware region is visible",
        "- obstruction: no severe blur, occlusion, black screen, transition frame, or irrelevant presenter shot",
        "- replacement: if unsuitable, compare nearby `replacement_candidates` and choose the best one",
        "- annotation: if the screenshot is usable but needs guidance, add boxes, arrows, or labels",
        "",
        "Update rules:",
        "",
        "- Set `review.status` to `accepted`, `replace`, `annotate`, or `reject`.",
        "- Fill all boolean `review.checks` values.",
        "- Write a short `review.reason` in Chinese.",
        "- If replacing, set `review.selected_replacement` to the chosen candidate path.",
        "- If annotating, append objects to `review.annotation_suggestions` with `type`, `target`, `label`, and optional normalized `box` `[x, y, width, height]` values from 0 to 1.",
        "- Keep paths relative to the analysis directory when writing replacements.",
        "",
        "Output: modify `frame_review.json` only. Do not rewrite generated screenshots.",
    ]

    payload = {
        "source_video": selected["source_video"],
        "analysis_dir": selected["analysis_dir"],
        "dense_extracted": args.extract_dense,
        "dense_window_seconds": args.window,
        "dense_fps": args.fps,
        "frames": review_items,
    }

    (analysis_dir / "frame_review.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    (analysis_dir / "frame_review_prompt.md").write_text("\n".join(prompt_lines) + "\n", encoding="utf-8")

    print(analysis_dir / "frame_review.json")
    print(analysis_dir / "frame_review_prompt.md")
    if args.extract_dense:
        print(dense_root)


if __name__ == "__main__":
    main()
