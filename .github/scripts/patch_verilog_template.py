"""Point the HUD verilog template at this fork and register mac_rne_sat."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

REPO_URL = "https://github.com/KanimozhiMarikani/takehome-mac-rne-sat.git"
CACHE_BUST = os.environ.get("GITHUB_RUN_ID", "local12")

MAC_SPEC = '''
PROBLEM_REGISTRY.append(
    ProblemSpec(
        id="mac_rne_sat",
        description="""Implement the module `mac_rne_sat` in sources/mac_rne_sat.sv according to
docs/spec.md.

Requirements:
- Synthesizable SystemVerilog, compatible with Icarus Verilog (-g2012).
- No SystemVerilog Assertions (SVA).
- Keep the module name, port names, directions, and widths exactly as in
  the provided skeleton.
- You may write and run your own tests, but grading is performed by a
  hidden testbench that checks cycle-exact behavior against docs/spec.md.

Deliverable: the completed sources/mac_rne_sat.sv. Do not modify any other
file.
""",
        difficulty="hard",
        base="mac_rne_sat_baseline",
        test="mac_rne_sat_test",
        golden="mac_rne_sat_golden",
        test_files=["tests/test_mac_rne_sat.py"],
    )
)
'''


def patch_dockerfile(root: Path) -> None:
    path = root / "Dockerfile"
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"^ARG REPO_URL=.*$", f"ARG REPO_URL={REPO_URL}", text, flags=re.M)
    if re.search(r"^ENV random=", text, flags=re.M):
        text = re.sub(r"^ENV random=.*$", f"ENV random=random{CACHE_BUST}", text, flags=re.M)
    else:
        text = text.replace(
            f"ARG REPO_URL={REPO_URL}",
            f"ARG REPO_URL={REPO_URL}\nENV random=random{CACHE_BUST}",
            1,
        )
    path.write_text(text, encoding="utf-8")
    print(f"Dockerfile REPO_URL={REPO_URL} random=random{CACHE_BUST}")


def patch_basic_py(root: Path) -> None:
    path = root / "src" / "hud_controller" / "problems" / "basic.py"
    text = path.read_text(encoding="utf-8")
    if 'id="mac_rne_sat"' in text:
        print("basic.py already has mac_rne_sat")
        return
    path.write_text(text.rstrip() + "\n" + MAC_SPEC + "\n", encoding="utf-8")
    print("appended mac_rne_sat ProblemSpec to basic.py")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_verilog_template.py <template-dir>", file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    patch_dockerfile(root)
    patch_basic_py(root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
