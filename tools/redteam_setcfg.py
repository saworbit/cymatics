#!/usr/bin/env python3
"""Write (or clear) user://settings.cfg for the red-team probes.

  python tools/redteam_setcfg.py "ui_scale=nan"          # one key per arg
  python tools/redteam_setcfg.py --clear                 # delete the file
"""
import os
import pathlib
import shutil
import sys

APP = "That's a Paddlin'"
d = pathlib.Path(os.environ["APPDATA"]) / "Godot" / "app_userdata" / APP
cfg = d / "settings.cfg"
d.mkdir(parents=True, exist_ok=True)
if cfg.is_dir():
    shutil.rmtree(cfg)
elif cfg.exists():
    cfg.unlink()

args = sys.argv[1:]
if args and args[0] != "--clear":
    cfg.write_text("[settings]\n" + "\n".join(args) + "\n", encoding="utf-8")
print(f"wrote {cfg}: {cfg.read_text() if cfg.exists() else '<deleted>'!r}")
