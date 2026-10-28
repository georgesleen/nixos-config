"""Render the shared Waybar status pills at logical-pixel resolution."""

import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile

import cairo
import gi

gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Pango, PangoCairo


def color(value, alpha=1.0):
    """Decode palette hex colors, including an optional alpha byte."""
    digits = value.removeprefix("#")
    if len(digits) in (3, 4):
        digits = "".join(digit * 2 for digit in digits)
    if len(digits) not in (6, 8):
        raise ValueError(f"Invalid palette color: {value}")
    channels = tuple(int(digits[index:index + 2], 16) / 255 for index in (0, 2, 4))
    opacity = int(digits[6:8], 16) / 255 if len(digits) == 8 else 1.0
    return (*channels, opacity * float(alpha))


def rounded_rectangle(context, left, top, width, height, radius):
    radius = min(radius, width / 2, height / 2)
    context.new_sub_path()
    for center_x, center_y, start in (
        (left + width - radius, top + radius, -math.pi / 2),
        (left + width - radius, top + height - radius, 0),
        (left + radius, top + height - radius, math.pi / 2),
        (left + radius, top + radius, math.pi),
    ):
        context.arc(center_x, center_y, radius, start, start + math.pi / 2)
    context.close_path()


def module_color(name, palette):
    key = {
        "network": "network",
        "custom/audio": "audio",
        "custom/memory": "memory",
        "power-profiles-daemon": "power",
    }.get(name, "fg")
    return color(palette[key])


def render(style, modules, width, density=1.0):
    height = style["height"]
    surface = cairo.ImageSurface(
        cairo.FORMAT_ARGB32, math.ceil(width * density), math.ceil(height * density)
    )
    surface.set_device_scale(density, density)
    context = cairo.Context(surface)
    palette = style["palette"]
    context.set_source_rgba(*color(palette["bg"], palette["bgAlpha"]))
    context.paint()

    font = Pango.FontDescription()
    font.set_family(", ".join(style["fontFamilies"]))
    # GTK CSS px are absolute device-independent pixels, not Pango points.
    font.set_absolute_size(style["fontSize"] * Pango.SCALE)
    layouts = []
    for module in modules:
        layout = PangoCairo.create_layout(context)
        layout.set_font_description(font)
        layout.set_single_paragraph_mode(True)
        layout.set_markup(module["text"], -1)
        ink, logical = layout.get_pixel_extents()
        left = min(ink.x, logical.x)
        top = min(ink.y, logical.y)
        right = max(ink.x + ink.width, logical.x + logical.width)
        bottom = max(ink.y + ink.height, logical.y + logical.height)
        layouts.append((module, layout, left, top, right - left, bottom - top))

    margin = style["marginHorizontal"]
    padding = style["paddingHorizontal"]
    spacing = style["spacing"]
    total_width = sum(item[4] + 2 * (margin + padding) for item in layouts)
    total_width += spacing * max(0, len(layouts) - 1)
    if not total_width:
        return surface

    # Small outputs keep the entire group, with uniform scaling only on overflow.
    scale = min(1.0, width / total_width)
    pill_height = height - 2 * style["marginVertical"]
    tallest = max(item[5] for item in layouts)
    scale = min(scale, pill_height / tallest) if tallest else scale
    context.translate(width - total_width * scale, (height - height * scale) / 2)
    context.scale(scale, scale)
    left = 0
    for module, layout, text_left, text_top, text_width, text_height in layouts:
        pill_width = text_width + 2 * padding
        rounded_rectangle(
            context,
            left + margin,
            style["marginVertical"],
            pill_width,
            pill_height,
            style["radius"],
        )
        context.set_source_rgba(*color(palette["pill"], palette["pillAlpha"]))
        context.fill()
        context.set_source_rgba(*module_color(module["name"], palette))
        context.move_to(
            left + margin + padding - text_left,
            (height - text_height) / 2 - text_top,
        )
        PangoCairo.show_layout(context, layout)
        left += pill_width + 2 * margin + spacing
    return surface


def main():
    style_path, stats_command, width_text, output_path, *density_argument = sys.argv[1:]
    width = int(width_text)
    density = float(density_argument[0]) if density_argument else 1.0
    if width <= 0 or not math.isfinite(density) or density <= 0:
        raise ValueError("Output width and density must be positive")
    style = json.loads(Path(style_path).read_text())
    modules = json.loads(subprocess.check_output([stats_command], text=True))
    surface = render(style, modules, width, density)
    destination = Path(output_path).absolute()
    descriptor, temporary_path = tempfile.mkstemp(
        prefix=f".{destination.name}.", suffix=".png", dir=destination.parent
    )
    try:
        with os.fdopen(descriptor, "wb") as output:
            surface.write_to_png(output)
        os.replace(temporary_path, destination)
    finally:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)
    print(destination)


if __name__ == "__main__":
    main()
