import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from faster_whisper import WhisperModel


def ffmpeg_bin(explicit):
    if explicit:
        return Path(explicit)

    local = Path.home() / "AppData/Local/Microsoft/WinGet/Packages"
    matches = list(local.glob("Gyan.FFmpeg_*/ffmpeg-*/bin/ffmpeg.exe"))
    if matches:
        return matches[0]

    return Path("ffmpeg")


def parse_time(value):
    value = value.strip()
    if re.fullmatch(r"\d+(\.\d+)?", value):
        return float(value)

    parts = value.split(":")
    if len(parts) == 2:
        minutes, seconds = parts
        return int(minutes) * 60 + float(seconds)
    if len(parts) == 3:
        hours, minutes, seconds = parts
        return int(hours) * 3600 + int(minutes) * 60 + float(seconds)

    raise ValueError(f"Invalid timestamp: {value}")


def fmt_time(seconds):
    seconds = max(0.0, float(seconds))
    whole = int(seconds)
    millis = int(round((seconds - whole) * 1000))
    return f"{whole // 3600:02d}:{(whole % 3600) // 60:02d}:{whole % 60:02d}.{millis:03d}"


def parse_ranges(values, padding):
    ranges = []
    for value in values:
        for chunk in value.split(","):
            chunk = chunk.strip()
            if not chunk:
                continue
            if "-" not in chunk:
                raise ValueError(f"Range must be start-end: {chunk}")
            start_text, end_text = chunk.split("-", 1)
            start = max(0.0, parse_time(start_text) - padding)
            end = parse_time(end_text) + padding
            if end <= start:
                raise ValueError(f"Range end must be after start: {chunk}")
            ranges.append((start, end, chunk))
    return ranges


def extract_clip(ffmpeg, audio, output, start, end):
    duration = end - start
    subprocess.run(
        [
            str(ffmpeg),
            "-hide_banner",
            "-ss",
            str(start),
            "-t",
            str(duration),
            "-i",
            str(audio),
            "-ac",
            "1",
            "-ar",
            "16000",
            "-c:a",
            "pcm_s16le",
            str(output),
        ],
        check=True,
        text=True,
    )


def main():
    parser = argparse.ArgumentParser(description="Retranscribe selected audio ranges with context padding.")
    parser.add_argument("audio", type=Path)
    parser.add_argument("--range", action="append", required=True, help="Time range such as 00:01:20-00:01:45. Can be repeated or comma-separated.")
    parser.add_argument("--padding", type=float, default=8.0)
    parser.add_argument("--model", default="medium")
    parser.add_argument("--language", default="auto")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--compute-type", default="int8")
    parser.add_argument("--ffmpeg", type=Path)
    args = parser.parse_args()

    audio = args.audio.resolve()
    if not audio.exists():
        raise FileNotFoundError(audio)

    ranges = parse_ranges(args.range, args.padding)
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    output_dir = audio.parent / f"segment_asr_{run_id}"
    output_dir.mkdir(parents=True, exist_ok=False)

    ffmpeg = ffmpeg_bin(args.ffmpeg)
    print(f"[segment-asr] Loading model: {args.model}", file=sys.stderr, flush=True)
    model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)

    transcript_rows = []
    text_lines = []
    srt_lines = []
    srt_index = 1

    for index, (start, end, requested) in enumerate(ranges, start=1):
        clip = output_dir / f"clip_{index:03d}_{fmt_time(start).replace(':', '-')}_{fmt_time(end).replace(':', '-')}.wav"
        print(f"[segment-asr] [{index}/{len(ranges)}] {requested} with padding -> {fmt_time(start)}-{fmt_time(end)}", file=sys.stderr, flush=True)
        extract_clip(ffmpeg, audio, clip, start, end)

        options = {"vad_filter": True, "beam_size": 5}
        if args.language != "auto":
            options["language"] = args.language

        segments, info = model.transcribe(str(clip), **options)
        segment_rows = []
        for segment in segments:
            absolute_start = start + segment.start
            absolute_end = start + segment.end
            row = {
                "range_index": index,
                "requested_range": requested,
                "clip": clip.name,
                "start": absolute_start,
                "end": absolute_end,
                "start_text": fmt_time(absolute_start),
                "end_text": fmt_time(absolute_end),
                "text": segment.text.strip(),
                "detected_language": info.language,
            }
            segment_rows.append(row)
            transcript_rows.append(row)
            text_lines.append(f"[{row['start_text']} - {row['end_text']}] {row['text']}")
            srt_lines.extend([
                str(srt_index),
                f"{fmt_time(absolute_start).replace('.', ',')} --> {fmt_time(absolute_end).replace('.', ',')}",
                row["text"],
                "",
            ])
            srt_index += 1

        print(f"[segment-asr] range {index} segments={len(segment_rows)} language={info.language}", file=sys.stderr, flush=True)

    payload = {
        "source_audio": str(audio),
        "model": args.model,
        "requested_language": args.language,
        "padding_seconds": args.padding,
        "ranges": [
            {"index": idx, "requested": requested, "start": start, "end": end}
            for idx, (start, end, requested) in enumerate(ranges, start=1)
        ],
        "segments": transcript_rows,
    }

    (output_dir / "segment_transcript.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    (output_dir / "segment_transcript.txt").write_text("\n".join(text_lines) + "\n", encoding="utf-8")
    (output_dir / "segment_transcript.srt").write_text("\n".join(srt_lines), encoding="utf-8")

    print(output_dir)
    print(output_dir / "segment_transcript.txt")
    print(output_dir / "segment_transcript.json")


if __name__ == "__main__":
    main()
