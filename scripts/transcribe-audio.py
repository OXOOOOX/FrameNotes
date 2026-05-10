import argparse
import json
import sys
from pathlib import Path

from faster_whisper import WhisperModel


def fmt_time(seconds):
    seconds = max(0.0, float(seconds))
    whole = int(seconds)
    millis = int(round((seconds - whole) * 1000))
    return f"{whole // 3600:02d}:{(whole % 3600) // 60:02d}:{whole % 60:02d}.{millis:03d}"


def main():
    parser = argparse.ArgumentParser(description="Transcribe audio with faster-whisper.")
    parser.add_argument("audio", type=Path)
    parser.add_argument("--model", default="medium")
    parser.add_argument("--language", default="auto", help="Language hint such as zh, en, or auto.")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--compute-type", default="int8")
    args = parser.parse_args()

    audio = args.audio.resolve()
    if not audio.exists():
        raise FileNotFoundError(audio)

    output_dir = audio.parent
    print(f"[ASR] Loading faster-whisper model: {args.model}", file=sys.stderr, flush=True)
    model = WhisperModel(args.model, device=args.device, compute_type=args.compute_type)
    transcribe_options = {
        "vad_filter": True,
        "beam_size": 5,
    }
    if args.language != "auto":
        transcribe_options["language"] = args.language

    print(f"[ASR] Starting transcription: {audio}", file=sys.stderr, flush=True)
    segments, info = model.transcribe(str(audio), **transcribe_options)

    rows = []
    text_lines = []
    srt_lines = []

    for index, segment in enumerate(segments, start=1):
        item = {
            "index": index,
            "start": segment.start,
            "end": segment.end,
            "start_text": fmt_time(segment.start),
            "end_text": fmt_time(segment.end),
            "text": segment.text.strip(),
        }
        rows.append(item)
        text_lines.append(f"[{item['start_text']} - {item['end_text']}] {item['text']}")
        srt_lines.extend([
            str(index),
            f"{fmt_time(segment.start).replace('.', ',')} --> {fmt_time(segment.end).replace('.', ',')}",
            item["text"],
            "",
        ])
        if index == 1 or index % 10 == 0:
            percent = min(100.0, (segment.end / info.duration) * 100) if info.duration else 0.0
            print(
                f"[ASR] {percent:5.1f}% {fmt_time(segment.end)} segments={index}",
                file=sys.stderr,
                flush=True,
            )

    payload = {
        "audio": str(audio),
        "model": args.model,
        "language": info.language,
        "requested_language": args.language,
        "language_probability": info.language_probability,
        "duration": info.duration,
        "segments": rows,
    }

    (output_dir / "transcript.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    (output_dir / "transcript.txt").write_text("\n".join(text_lines) + "\n", encoding="utf-8")
    (output_dir / "transcript.srt").write_text("\n".join(srt_lines), encoding="utf-8")

    print("[ASR] 100.0% transcription complete", file=sys.stderr, flush=True)
    print(output_dir / "transcript.txt")
    print(output_dir / "transcript.json")
    print(f"segments={len(rows)} language={info.language} prob={info.language_probability:.3f}")


if __name__ == "__main__":
    main()
