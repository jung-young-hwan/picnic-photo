"""화면 캡처용 예시 사진을 만든다 (CI 시뮬레이터 전용).

picsum.photos 의 무료 사진을 받고, 흐린 사본·비슷한 사본·영수증 이미지를 덧붙인다.
사용법: python3 tools/make_demo_photos.py <출력 폴더>
"""
import io
import sys
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)


def fetch(seed: int) -> Image.Image:
    url = f"https://picsum.photos/seed/picnic{seed}/1200/900"
    with urllib.request.urlopen(url, timeout=30) as response:
        return Image.open(io.BytesIO(response.read())).convert("RGB")


count = 0
for seed in range(1, 25):
    try:
        image = fetch(seed)
    except Exception as error:  # 네트워크 실패는 건너뛴다
        print("skip", seed, error)
        continue
    image.save(out / f"photo_{seed:02d}.jpg", quality=90)
    count += 1
    if seed % 4 == 0:
        image.filter(ImageFilter.GaussianBlur(9)).save(out / f"photo_{seed:02d}_blur.jpg", quality=90)
    if seed % 3 == 0:
        w, h = image.size
        image.crop((12, 9, w - 12, h - 9)).resize((w, h)).save(out / f"photo_{seed:02d}_dup.jpg", quality=88)

font = ImageFont.load_default(size=44)
for n in range(3):
    receipt = Image.new("RGB", (900, 1400), (250, 250, 246))
    draw = ImageDraw.Draw(receipt)
    lines = ["PICNIC CAFE", "", "Americano      4,500", "Cafe Latte     5,000",
             "Cheesecake     6,800", "", f"TOTAL         {16300 + n * 1000:,}", "", "THANK YOU", "2026-10-20 14:32"]
    for i, line in enumerate(lines):
        draw.text((80, 90 + i * 110), line, fill=(30, 30, 30), font=font)
    receipt.save(out / f"receipt_{n}.jpg", quality=92)

print("photos:", count, "files:", len(list(out.iterdir())))
