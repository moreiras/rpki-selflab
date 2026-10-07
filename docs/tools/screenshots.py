#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
"""
Regenerates the screenshots used by the project site (docs/), in en, pt and es.

It drives the running lab through the story (./scripts/lab.sh step1-clean ...
step9-leak-off) and, at each step, photographs the panel's topology and
verdicts in the three languages, plus a few extra views (the whole panel, a
challenge, the registry panel). Images are written as WebP into
docs/img/<lang>/.

Before running:
  - the lab is up (./scripts/lab.sh up) and Preparation is done (the Krill CA
    exists, with its parent and repository): the step commands refuse to run
    otherwise;
  - pip install playwright pillow && python -m playwright install chromium

  python3 docs/tools/screenshots.py

It leaves the lab back at step1-clean.
"""
import io
import os
import subprocess
import sys
import time

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "docs", "img")
PANEL = os.environ.get("PANEL", "http://localhost:8080")
LANGS = ["en", "pt", "es"]
# guide <select> index of each story step (1. Introduction ... 8. Step 1 ...)
STEP_INDEX = {1: 7, 2: 8, 3: 9, 4: 10, 5: 11, 6: 12, 7: 13, 8: 14, 9: 15}
STEPS = [
    (1, "step1-clean", 15), (2, "step2-hijack-simple", 15), (3, "step3-rov-mark", 22),
    (4, "step4-hijack-posrov", 22), (5, "step5-aspa-mark", 25), (6, "step6-add-provider-b", 22),
    (7, "step7-leak-on", 22), (8, "step8-drop", 25), (9, "step9-leak-off", 22),
]


def save_webp(png_bytes, path, max_width=1400):
    im = Image.open(io.BytesIO(png_bytes)).convert("RGB")
    if im.width > max_width:
        im = im.resize((max_width, round(im.height * max_width / im.width)), Image.LANCZOS)
    im.save(path, "WEBP", quality=86, method=6)


def lab(cmd, settle):
    print(f"== {cmd}", flush=True)
    subprocess.run(["./scripts/lab.sh", cmd], cwd=ROOT, check=True, capture_output=True)
    time.sleep(settle)


def main():
    for lang in LANGS:
        os.makedirs(os.path.join(OUT, lang), exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        ctx = {}
        for lang in LANGS:
            c = browser.new_context(viewport={"width": 1600, "height": 900}, device_scale_factor=2)
            c.add_init_script(
                f"try{{localStorage.setItem('rpki-selflab-language','{lang}');"
                "localStorage.setItem('rpki-selflab-theme','light')}catch(e){}")
            ctx[lang] = c

        def open_panel(lang, step):
            pg = ctx[lang].new_page()
            pg.goto(PANEL)
            pg.wait_for_timeout(2500)
            pg.select_option("#guide-select", index=STEP_INDEX[step])
            pg.wait_for_timeout(1500)
            return pg

        for step, cmd, settle in STEPS:
            lab(cmd, settle)
            for lang in LANGS:
                pg = open_panel(lang, step)
                save_webp(pg.locator("#center-pane").screenshot(),
                          os.path.join(OUT, lang, f"step{step}.webp"), 1100)
                if step == 3:
                    ch = pg.locator("#guide-body .challenge").first
                    ch.scroll_into_view_if_needed()
                    pg.wait_for_timeout(400)
                    save_webp(ch.screenshot(), os.path.join(OUT, lang, "challenge.webp"), 1100)
                if step == 5:
                    save_webp(pg.screenshot(), os.path.join(OUT, lang, "panel.webp"))
                pg.close()

        for lang in LANGS:
            pg = ctx[lang].new_page()
            base = PANEL.replace("//localhost", "//registry.localhost")
            pg.goto(f"{base}/?lang={lang}")
            pg.wait_for_timeout(2500)
            save_webp(pg.screenshot(), os.path.join(OUT, lang, "registry.webp"))
            pg.close()
        browser.close()
    lab("step1-clean", 0)
    print("done:", OUT)


if __name__ == "__main__":
    sys.exit(main())
