import argparse
import json
from pathlib import Path


def pick_evenly(items, limit):
    if len(items) <= limit:
        return items
    if limit <= 1:
        return [items[0]]

    last = len(items) - 1
    selected = []
    seen = set()
    for index in range(limit):
        source_index = round(index * last / (limit - 1))
        if source_index not in seen:
            selected.append(items[source_index])
            seen.add(source_index)
    return selected


def main():
    parser = argparse.ArgumentParser(description="Build a multimodal analysis prompt from extracted keyframes.")
    parser.add_argument("frames_json", type=Path)
    parser.add_argument("--max-frames", type=int, default=24)
    args = parser.parse_args()

    frames_json = args.frames_json.resolve()
    analysis_dir = frames_json.parent
    manifest = json.loads(frames_json.read_text(encoding="utf-8-sig"))
    selected = pick_evenly(manifest["frames"], args.max_frames)

    selected_payload = {
        "source_video": manifest["source_video"],
        "analysis_dir": str(analysis_dir),
        "contact_sheet": manifest.get("contact_sheet"),
        "selection_strategy": f"evenly sampled {len(selected)} of {len(manifest['frames'])} extracted keyframes",
        "frames": selected,
    }

    (analysis_dir / "selected_frames.json").write_text(
        json.dumps(selected_payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    lines = [
        "# Teaching Video Multimodal Analysis Prompt",
        "",
        "Use the contact sheet, selected keyframes, and timestamps to analyze this teaching video.",
        "",
        "## Source",
        "",
        f"- Video: `{manifest['source_video']}`",
        f"- Duration seconds: `{manifest.get('metadata', {}).get('format', {}).get('duration', 'unknown')}`",
        f"- Contact sheet: `{manifest.get('contact_sheet')}`",
        f"- Keyframe extraction method: `{manifest.get('method')}`",
        "",
        "## Selected Frames",
        "",
    ]

    for frame in selected:
        lines.append(
            f"- Frame {frame['index']:03d} at `{frame['timestamp']}`: `{frame['path']}`"
        )

    lines.extend([
        "",
        "## Analysis Tasks",
        "",
        "1. Divide the video into chapters with start and end timestamps.",
        "2. Identify the main concepts explained in each chapter.",
        "3. For each concept, cite the most relevant frame indices and timestamps.",
        "4. Note visual elements such as diagrams, code, formulas, protocol names, or UI screens.",
        "5. Produce concise study notes suitable for review.",
        "6. List open questions or unclear parts that need transcript/audio confirmation.",
        "",
        "## Output Format",
        "",
        "Return Markdown with these sections:",
        "",
        "- Chapter Timeline",
        "- Concepts",
        "- Frame Evidence",
        "- Study Notes",
        "- Follow-up Checks",
        "",
        "Keep every claim traceable to a timestamp or frame index where possible.",
    ])

    (analysis_dir / "multimodal_prompt.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(analysis_dir / "multimodal_prompt.md")
    print(analysis_dir / "selected_frames.json")
    print(f"selected={len(selected)} total={len(manifest['frames'])}")


if __name__ == "__main__":
    main()
