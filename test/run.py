"""Headless check of Robo Grid on vanilla."""
import json, shutil, subprocess, sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT))
from factorio_paths import PATHS  # noqa: E402
from factorio_paths import run_dir  # noqa: E402
RUN = run_dir(Path(__file__).resolve().parent / "run")
MODS = RUN / "rg-mods"
shutil.rmtree(MODS, ignore_errors=True)
MODS.mkdir(parents=True)
shutil.copytree(HERE.parent, MODS / "robo-grid", ignore=shutil.ignore_patterns("test"))
TEST = sys.argv[1] if len(sys.argv) > 1 else "rg-test"
shutil.copytree(HERE / TEST, MODS / TEST)
names = ["base", "elevated-rails", "quality", "space-age", "robo-grid", TEST]
(MODS / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
out = RUN / "script-output" / (TEST + ".txt")
out.unlink(missing_ok=True)
save = RUN / "rg-test.zip"
save.unlink(missing_ok=True)
common = [str(PATHS["factorio_exe"]), "--config", str(RUN / "config.ini"), "--mod-directory", str(MODS)]
for args in (["--create", str(save)], ["--benchmark", str(save), "--benchmark-ticks", "18010", "--disable-audio"]):
    p = subprocess.run(common + args, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode or "non-recoverable" in p.stdout or "Error" in p.stdout:
        print(p.stdout[-3000:]); sys.exit(1)
print(out.read_text() if out.exists() else "no result")
