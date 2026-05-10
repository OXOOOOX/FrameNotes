import argparse
from pathlib import Path

from huggingface_hub import snapshot_download


def main():
    parser = argparse.ArgumentParser(description="Download a faster-whisper model into a local project cache.")
    parser.add_argument("--model", default="medium", choices=["tiny", "base", "small", "medium", "large-v3"])
    parser.add_argument("--output-root", type=Path, default=Path(".models"))
    args = parser.parse_args()

    repo_id = f"Systran/faster-whisper-{args.model}"
    output_dir = (args.output_root / f"faster-whisper-{args.model}").resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Downloading {repo_id} to {output_dir}")
    snapshot_download(
        repo_id=repo_id,
        local_dir=output_dir,
        resume_download=True,
    )

    model_bin = output_dir / "model.bin"
    if not model_bin.exists():
        raise FileNotFoundError(f"Download finished but model.bin is missing: {model_bin}")

    print(output_dir)
    print("model ready")


if __name__ == "__main__":
    main()
