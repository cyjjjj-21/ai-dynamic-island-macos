#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

TEST_PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\x0cIDAT\x08\xd7c"
    b"\xf8\xff\xff?\x00\x05\xfe\x02\xfeA\xad\x1c\x1c\x00\x00\x00\x00IEND"
    b"\xaeB`\x82"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Capture a reproducible AI Island visual review bundle."
    )
    parser.add_argument("--app", default="AIIslandApp", help="App name to capture.")
    parser.add_argument(
        "--output-dir",
        help="Directory to write review artifacts into. Defaults to a temp bundle directory.",
    )
    parser.add_argument(
        "--window-name",
        help="Optional window-title substring filter when the app has multiple windows.",
    )
    parser.add_argument(
        "--window-id",
        type=int,
        help="Capture a specific window id instead of auto-selecting the app window.",
    )
    return parser.parse_args()


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def scripts_dir() -> Path:
    return repo_root() / "scripts"


def default_output_dir() -> Path:
    timestamp = dt.datetime.now().strftime("%Y-%m-%d_%H-%M-%S_%f")
    return Path(tempfile.gettempdir()) / f"aiisland-review-{timestamp}"


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def write_test_png(path: Path) -> None:
    path.write_bytes(TEST_PNG)


def run(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(cmd, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        stdout = (exc.stdout or "").strip()
        detail = stderr or stdout or "unknown command failure"
        raise SystemExit(f"command failed: {' '.join(cmd)}\n{detail}") from exc


def swift_json(script: Path, args: list[str]) -> dict:
    module_cache = Path(tempfile.gettempdir()) / "aiisland-swift-module-cache"
    ensure_dir(module_cache)
    command = ["swift", "-module-cache-path", str(module_cache), str(script), *args]
    result = run(command)
    return json.loads(result.stdout)


def discover_windows(app: str, window_name: str | None) -> dict:
    flags = ["--app", app]
    if window_name:
        flags.extend(["--window-name", window_name])
    return swift_json(scripts_dir() / "macos_window_info.swift", flags)


def discover_displays() -> dict:
    return swift_json(scripts_dir() / "macos_display_info.swift", [])


def choose_window(payload: dict, explicit_window_id: int | None) -> dict:
    windows = payload.get("windows") or []
    if explicit_window_id is not None:
        for item in windows:
            if item.get("id") == explicit_window_id:
                return item
        raise SystemExit(f"window id {explicit_window_id} not found in discovered windows")

    selected = payload.get("selected")
    if not selected:
        raise SystemExit("no matching on-screen window found for capture")
    return selected


def capture_desktop(path: Path) -> None:
    run(["screencapture", "-x", str(path)])


def crop_window_from_desktop(desktop_path: Path, output_path: Path, bounds: dict, scale: float) -> dict:
    from PIL import Image

    x = int(round(bounds["x"] * scale))
    y = int(round(bounds["y"] * scale))
    width = int(round(bounds["width"] * scale))
    height = int(round(bounds["height"] * scale))

    image = Image.open(desktop_path)
    cropped = image.crop((x, y, x + width, y + height))
    cropped.save(output_path)

    return {
        "x": x,
        "y": y,
        "width": width,
        "height": height,
    }


def write_metadata(path: Path, metadata: dict) -> None:
    path.write_text(json.dumps(metadata, indent=2, sort_keys=True), encoding="utf-8")


def print_paths(output_dir: Path) -> None:
    print(str(output_dir))
    print(str(output_dir / "window.png"))
    print(str(output_dir / "desktop.png"))
    print(str(output_dir / "metadata.json"))


def run_test_mode(args: argparse.Namespace, output_dir: Path) -> int:
    ensure_dir(output_dir)
    write_test_png(output_dir / "window.png")
    write_test_png(output_dir / "desktop.png")
    metadata = {
        "app": args.app,
        "capturedAt": "test-mode",
        "selectedWindow": {
            "id": 999,
            "owner": args.app,
            "name": "",
            "layer": 25,
            "bounds": {
                "x": 531,
                "y": 0,
                "width": 449,
                "height": 340,
            },
            "area": 152660,
        },
        "windows": [
            {
                "id": 999,
                "owner": args.app,
                "name": "",
                "layer": 25,
                "bounds": {
                    "x": 531,
                    "y": 0,
                    "width": 449,
                    "height": 340,
                },
                "area": 152660,
            }
        ],
    }
    write_metadata(output_dir / "metadata.json", metadata)
    print_paths(output_dir)
    return 0


def run_real_mode(args: argparse.Namespace, output_dir: Path) -> int:
    ensure_dir(output_dir)
    payload = discover_windows(args.app, args.window_name)
    selected = choose_window(payload, args.window_id)
    displays = discover_displays()
    if displays.get("count") != 1:
        raise SystemExit(
            "canonical review capture currently supports exactly one active display; "
            "use a single-display setup before relying on this artifact"
        )

    main_display = (displays.get("displays") or [None])[0]
    if not main_display:
        raise SystemExit("no active display information available")

    desktop_path = output_dir / "desktop.png"
    capture_desktop(desktop_path)
    crop_rect = crop_window_from_desktop(
        desktop_path,
        output_dir / "window.png",
        selected["bounds"],
        float(main_display["scale"]),
    )

    metadata = {
        "app": args.app,
        "capturedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "display": main_display,
        "cropRectPixels": crop_rect,
        "selectedWindow": selected,
        "windows": payload.get("windows") or [],
    }
    write_metadata(output_dir / "metadata.json", metadata)
    print_paths(output_dir)
    return 0


def main() -> int:
    args = parse_args()
    output_dir = Path(args.output_dir).expanduser() if args.output_dir else default_output_dir()

    if os.environ.get("AIISLAND_CAPTURE_TEST_MODE") == "1":
        return run_test_mode(args, output_dir)

    if sys.platform != "darwin":
        raise SystemExit("capture_review_bundle.py currently supports macOS only")

    return run_real_mode(args, output_dir)


if __name__ == "__main__":
    raise SystemExit(main())
