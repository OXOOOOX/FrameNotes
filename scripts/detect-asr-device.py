import json

import ctranslate2


def main():
    cuda_count = 0
    error = None
    try:
        cuda_count = ctranslate2.get_cuda_device_count()
    except Exception as exc:
        error = str(exc)

    payload = {
        "cuda_available": cuda_count > 0,
        "cuda_device_count": cuda_count,
        "recommended_device": "cuda" if cuda_count > 0 else "cpu",
        "error": error,
    }
    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()
