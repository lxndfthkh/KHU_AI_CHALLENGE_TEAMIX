"""python -m teamix_engine INPUT --public-output FILE --internal-output FILE"""
import argparse
import json
import os
from pathlib import Path
from .engine import solve


def main():
    parser = argparse.ArgumentParser(description="TEAMIX 추천 편성안 (편성알고리즘 v3: 처음 편성·공개 후 재편성)")
    parser.add_argument("input")
    parser.add_argument("--public-output", required=True)
    parser.add_argument("--internal-output", required=True)
    args = parser.parse_args()
    if Path(args.public_output).resolve() == Path(args.internal_output).resolve():
        parser.error("공개 출력과 내부 기록은 서로 다른 파일이어야 합니다.")
    result = solve(json.loads(Path(args.input).read_text(encoding="utf-8")))
    for path, value, private in [(args.public_output, result["public"], False),
                                 (args.internal_output, result["internal"], True)]:
        dest = Path(path)
        dest.parent.mkdir(parents=True, exist_ok=True)
        if private:
            fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            os.chmod(dest, 0o600)
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                json.dump(value, f, ensure_ascii=False, indent=2, allow_nan=False)
        else:
            dest.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    print(json.dumps({"status": result["public"]["status"],
                      "public_output": args.public_output}, ensure_ascii=False))
    return 0 if result["public"]["status"] in ("OPTIMAL", "FEASIBLE") else 1

if __name__ == "__main__":
    raise SystemExit(main())
