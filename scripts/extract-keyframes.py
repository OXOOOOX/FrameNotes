import argparse
import json
import math
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path


def run(command):
    return subprocess.run(command, text=True, capture_output=True, check=True)


def ffmpeg_bin(explicit):
    if explicit:
        return Path(explicit)

    local = Path.home() / "AppData/Local/Microsoft/WinGet/Packages"
    matches = list(local.glob("Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe"))
    if matches:
        return matches[0]

    return Path("ffmpeg")


def ffprobe_bin(ffmpeg):
    if ffmpeg.name.lower() == "ffmpeg.exe":
        return ffmpeg.with_name("ffprobe.exe")
    return Path("ffprobe")


def probe(video, ffprobe):
    result = run([
        str(ffprobe),
        "-v", "error",
        "-show_entries", "format=duration:stream=index,codec_type,width,height",
        "-of", "json",
        str(video),
    ])
    return json.loads(result.stdout)


def timestamp(seconds):
    seconds = max(0.0, float(seconds))
    whole = int(seconds)
    return f"{whole // 3600:02d}-{(whole % 3600) // 60:02d}-{whole % 60:02d}"


def extract_scene_frames(video, output_dir, ffmpeg, threshold, max_width):
    frame_pattern = output_dir / "frames" / "frame_%05d.jpg"
    scale_part = f",scale='min({max_width},iw)':-2" if max_width > 0 else ""
    vf = f"select='gt(scene,{threshold})',showinfo" + scale_part
    command = [
        str(ffmpeg),
        "-hide_banner",
        "-i", str(video),
        "-vf", vf,
        "-vsync", "vfr",
        "-q:v", "3",
        str(frame_pattern),
    ]
    process = subprocess.run(command, text=True, capture_output=True)
    if process.returncode != 0:
        raise RuntimeError(process.stderr)

    times = []
    for line in process.stderr.splitlines():
        match = re.search(r"pts_time:([0-9.]+)", line)
        if match:
            times.append(float(match.group(1)))
    return times


def extract_interval_frames(video, output_dir, ffmpeg, interval, max_width):
    frame_pattern = output_dir / "frames" / "frame_%05d.jpg"
    scale_part = f",scale='min({max_width},iw)':-2" if max_width > 0 else ""
    vf = f"fps=1/{interval}" + scale_part
    run([
        str(ffmpeg),
        "-hide_banner",
        "-i", str(video),
        "-vf", vf,
        "-q:v", "3",
        str(frame_pattern),
    ])


def make_contact_sheet(output_dir, ffmpeg, columns):
    frames = sorted((output_dir / "frames").glob("frame_*.jpg"))
    if not frames:
        return None

    rows = math.ceil(len(frames) / columns)
    contact = output_dir / "contact.jpg"
    run([
        str(ffmpeg),
        "-hide_banner",
        "-framerate", "1",
        "-i", str(output_dir / "frames" / "frame_%05d.jpg"),
        "-frames:v", "1",
        "-vf", f"scale=320:-2,tile={columns}x{rows}",
        "-q:v", "3",
        str(contact),
    ])
    return contact


def main():
    parser = argparse.ArgumentParser(description="Extract keyframes and metadata from a teaching video.")
    parser.add_argument("video", type=Path)
    parser.add_argument("--output-root", type=Path, default=Path("analysis"))
    parser.add_argument("--scene-threshold", type=float, default=0.18)
    parser.add_argument("--fallback-interval", type=int, default=20)
    parser.add_argument("--max-width", type=int, default=0, help="Max width for extracted frames. 0 = keep original resolution.")
    parser.add_argument("--contact-columns", type=int, default=5)
    parser.add_argument("--ffmpeg", type=Path)
    args = parser.parse_args()

    video = args.video.resolve()
    if not video.exists():
        raise FileNotFoundError(video)

    ffmpeg = ffmpeg_bin(args.ffmpeg)
    ffprobe = ffprobe_bin(ffmpeg)

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    stem = re.sub(r"[^\w.-]+", "_", video.stem, flags=re.UNICODE).strip("_")[:80]
    output_dir = (args.output_root / f"{stem}_{run_id}").resolve()
    frames_dir = output_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    metadata = probe(video, ffprobe)
    times = extract_scene_frames(video, output_dir, ffmpeg, args.scene_threshold, args.max_width)
    method = "scene"

    frames = sorted(frames_dir.glob("frame_*.jpg"))
    if len(frames) < 3:
        method = "interval"
        output_dir = (args.output_root / f"{stem}_{run_id}_interval").resolve()
        frames_dir = output_dir / "frames"
        frames_dir.mkdir(parents=True, exist_ok=True)
        extract_interval_frames(video, output_dir, ffmpeg, args.fallback_interval, args.max_width)
        frames = sorted(frames_dir.glob("frame_*.jpg"))
        times = [index * args.fallback_interval for index in range(len(frames))]

    frame_manifest = []
    for index, frame in enumerate(frames, start=1):
        seconds = times[index - 1] if index <= len(times) else None
        frame_manifest.append({
            "index": index,
            "timestamp_seconds": seconds,
            "timestamp": timestamp(seconds) if seconds is not None else None,
            "path": str(frame.relative_to(output_dir)).replace("\\", "/"),
        })

    contact = make_contact_sheet(output_dir, ffmpeg, args.contact_columns)

    manifest = {
        "source_video": str(video),
        "created_at": run_id,
        "method": method,
        "scene_threshold": args.scene_threshold,
        "fallback_interval_seconds": args.fallback_interval,
        "metadata": metadata,
        "contact_sheet": contact.name if contact else None,
        "frames": frame_manifest,
    }

    (output_dir / "frames.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output_dir)
    print(f"frames={len(frames)} method={method}")


if __name__ == "__main__":
    main()
