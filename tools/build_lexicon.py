"""tools/lexicon_ko.txt -> Picnic/Resources/lexicon_ko.json

사용법: python tools/build_lexicon.py [vision_labels.txt]
라벨 목록 파일을 주면 빠진 라벨과 존재하지 않는 라벨을 검사한다.
"""
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
entries = []
seen = set()
for raw in (root / "tools" / "lexicon_ko.txt").read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    label, _, words = line.partition("=")
    label = label.strip()
    ko = [w.strip() for w in words.split(",") if w.strip()]
    if not ko:
        sys.exit(f"한국어 없음: {label}")
    if label in seen:
        sys.exit(f"중복 라벨: {label}")
    seen.add(label)
    entries.append({"label": label, "ko": ko})

if len(sys.argv) > 1:
    known = {l.strip() for l in Path(sys.argv[1]).read_text().splitlines() if l.strip()}
    missing = sorted(known - seen)
    unknown = sorted(seen - known)
    if missing or unknown:
        sys.exit(f"빠진 라벨 {missing}\n없는 라벨 {unknown}")

out = root / "Picnic" / "Resources" / "lexicon_ko.json"
out.write_text(json.dumps(entries, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"{len(entries)}개 항목 -> {out.relative_to(root)} ({out.stat().st_size // 1024}KB)")
