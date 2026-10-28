import json
import math
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys


def wallpaper_images():
    try:
        result = subprocess.run(["awww", "query"], capture_output=True, text=True)
    except FileNotFoundError as error:
        print(f"Lock wallpaper unavailable: {error}", file=sys.stderr)
        return {}
    if result.returncode:
        print(f"Lock wallpaper unavailable: {result.stderr.strip()}", file=sys.stderr)
        return {}
    images = {}
    marker = "currently displaying: image: "
    for line in result.stdout.splitlines():
        if marker not in line:
            continue
        description, image = line.split(marker, 1)
        monitor = description.lstrip(": ").split(":", 1)[0].strip()
        if re.fullmatch(r"[A-Za-z0-9_.-]+", monitor) and Path(image).is_file():
            images[monitor] = image
    if not images:
        print("No active wallpaper image; locking with a solid background", file=sys.stderr)
    return images


def background(monitor, image):
    path = f"    path = {image}\n" if image is not None else ""
    return (
        "background {\n"
        f"    monitor = {monitor}\n"
        f"{path}"
        "    color = rgb(111827)\n"
        "    blur_passes = 3\n"
        "    blur_size = 8\n"
        "    brightness = 0.85\n"
        "}\n"
    )


def physical_size(output):
    mode = output.get("current_mode") or {}
    width, height = mode.get("width", 0), mode.get("height", 0)
    if width > 0 and height > 0:
        if output.get("transform") in {"90", "270", "flipped-90", "flipped-270"}:
            width, height = height, width
        return width, height
    scale = output.get("scale", 1)
    return (
        round(output["rect"]["width"] * scale),
        round(output["rect"]["height"] * scale),
    )


def fitted_wallpapers(outputs, images, runtime):
    sources = {}
    for index, image in enumerate(dict.fromkeys(images.values())):
        link = runtime / f"wallpaper-source-{index}"
        temporary = runtime / f".wallpaper-source-{index}-{os.getpid()}"
        temporary.symlink_to(Path(image).resolve())
        temporary.replace(link)
        sources[image] = link

    geometries = {}
    output_keys = {}
    for output in outputs:
        image = images.get(output["name"])
        if image is None:
            continue
        width, height = physical_size(output)
        divisor = math.gcd(width, height)
        key = (image, width // divisor, height // divisor)
        output_keys[output["name"]] = key
        if key not in geometries or width > geometries[key][0]:
            geometries[key] = (width, height)

    colors = {}
    fitted = {}
    for index, (key, (width, height)) in enumerate(geometries.items()):
        image = key[0]
        if image not in colors:
            colors[image] = subprocess.check_output(
                [
                    "magick", str(sources[image]), "-colorspace", "sRGB",
                    "-alpha", "off", "-depth", "8", "-format", "%[hex:p{0,0}]", "info:",
                ],
                text=True,
            ).strip()
        target = runtime / f"wallpaper-fit-{index}.png"
        temporary = runtime / f".wallpaper-fit-{index}-{os.getpid()}.png"
        geometry = f"{width}x{height}"
        subprocess.run(
            [
                "magick", str(sources[image]), "-colorspace", "sRGB",
                "-resize", geometry, "-background", f"#{colors[image]}",
                "-alpha", "remove", "-alpha", "off", "-gravity", "center",
                "-extent", geometry, "-depth", "8", str(temporary),
            ],
            check=True,
        )
        temporary.replace(target)
        fitted[key] = target

    paths = {monitor: fitted[key] for monitor, key in output_keys.items()}
    # A generic background also covers outputs connected after preparation.
    paths[""] = next(iter(paths.values()), next(iter(sources.values()), None))
    return paths


def main():
    renderer, base_config, runtime_directory = sys.argv[1:]
    runtime = Path(runtime_directory)
    runtime.mkdir(parents=True, exist_ok=True)
    outputs = json.loads(subprocess.check_output(["swaymsg", "-t", "get_outputs"], text=True))
    outputs = [
        output for output in outputs
        if output.get("active") and output["rect"]["width"] > 0 and output["rect"]["height"] > 0
    ]
    paths = fitted_wallpapers(outputs, wallpaper_images(), runtime)
    default_image = paths.pop("")
    configuration = Path(base_config).read_text()
    configuration += "\n" + background("", default_image)
    for monitor, image in paths.items():
        if image != default_image:
            configuration += background(monitor, image)
    # One bar per output, rendered at its logical width.
    bars = {}
    targets = [(output["name"], output["rect"]["width"], output.get("scale", 1)) for output in outputs]
    for monitor, width, scale in targets or [("", 1440, 1)]:
        key = (width, math.ceil(scale))
        if key not in bars:
            bar_image = runtime / f"bar-{len(bars)}.png"
            command = [renderer, str(width), str(bar_image), str(key[1])]
            subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
            bars[key] = (bar_image, command)
        bar_image, command = bars[key]
        configuration += (
            "image {\n"
            f"    monitor = {monitor}\n"
            f"    path = {bar_image}\n"
            "    size = 30\n"
            "    rounding = 0\n"
            "    border_size = 0\n"
            "    position = 0, 0\n"
            "    halign = right\n"
            "    valign = top\n"
            "    reload_time = 10\n"
            f"    reload_cmd = {shlex.join(command)}\n"
            "}\n"
        )
    temporary = runtime / ".hyprlock.conf"
    temporary.write_text(configuration)
    temporary.replace(runtime / "hyprlock.conf")


if __name__ == "__main__":
    main()
