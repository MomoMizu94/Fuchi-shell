""" Prepare pywal colors before exporting them to the shell and terminals """
""" Some colors need adjustments before they can be applied from pywal to terminal/shell """
import copy
import json
import sys


def rgb(color):
    return tuple(int(color[i:i + 2], 16) for i in (1, 3, 5))


def shade(color, factor):
    return "#" + "".join(f"{round(channel * factor):02x}" for channel in rgb(color))


def luminance(color):
    channels = [channel / 255 for channel in rgb(color)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels]
    return sum(v * weight for v, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def light_palette(palette):
    palette = copy.deepcopy(palette)
    # Allow for the shell's inset background as well as the terminal background.
    background = shade(palette["special"]["background"], 1 / 1.12)
    for key, original in palette["colors"].items():
        if key == "color0":  # Background slot, also used by terminal UI panels.
            continue
        color = original
        for step in range(1, 101):
            if (luminance(background) + 0.05) / (luminance(color) + 0.05) >= 4.5:
                break
            color = shade(original, 1 - step / 100)
        palette["colors"][key] = color
    return palette


if __name__ == "__main__":
    from pywal import colors, image

    light = sys.argv[2] == "light"
    palette = colors.get(image.get(sys.argv[1]), light=light, sat="0.6")
    print(json.dumps(light_palette(palette) if light else palette))
