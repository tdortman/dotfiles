# Applies one declarative full-display layout per invocation. Reads the
# baked config (argv 1), takes a layout name or cycle (default).
# Plans over a single kscreen-doctor snapshot; all GPU
# ownership and DDC bus checks run before any mutation, and the final
# state is re-probed as postcondition.
import glob
import json
import math
import os
import subprocess
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    CONFIG = json.load(config_file)
ARGS = sys.argv[2:]
LAYOUTS = CONFIG["layouts"]
MANAGED = CONFIG["managed"]
LOGIN = CONFIG["login"]
DDC_ENABLE = CONFIG["ddcEnable"]
MODES = ["cycle"] + [layout["name"] for layout in LAYOUTS]


class PrepareError(Exception):
    pass


class DimensionsError(PrepareError):
    pass


class RequiredDisconnected(PrepareError):
    def __init__(self, output):
        super().__init__(output)
        self.output = output


def fail(message):
    print("display-layout: " + message, file=sys.stderr)
    sys.exit(1)


def usage():
    lines = [
        "Usage: display-layout [" + "|".join(MODES) + "]",
        "",
        "Apply the declarative output layout with kscreen-doctor.",
    ]
    for layout in LAYOUTS:
        parts = []
        for output in layout["outputs"]:
            label = output["output"]
            if output["primary"]:
                label += " primary"
            parts.append(label)
        lines.append("  " + layout["name"] + "   " + ", ".join(parts))
    lines += [
        "  cycle  switch to the next layout using the live state (default)",
        "",
        "Cycle compares the full live state against every layout in order with wraparound and falls back to "
        + LOGIN
        + " when nothing matches. When several layouts match, the first configured match wins.",
        "Connected outputs form a left-to-right row with a shared bottom edge; explicit positions override automatic placement. All listed outputs are required: a disconnected output fails the layout before any change.",
        "Managed outputs ("
        + (", ".join(MANAGED) if MANAGED else "none")
        + ") absent from the selected layout are disabled when present; unknown external connectors are left alone.",
        "Existing mode, refresh rate, and HDR settings are preserved; scale is preserved unless the layout sets it.",
    ]
    return "\n".join(lines) + "\n"


def kscreen_snapshot():
    try:
        proc = subprocess.run(
            ["kscreen-doctor", "-j"], capture_output=True, text=True, check=False
        )
    except OSError as error:
        fail("kscreen-doctor -j failed (" + str(error) + "), cannot read output state.")
    if proc.returncode != 0:
        detail = proc.stderr.strip()
        if detail:
            fail("kscreen-doctor -j failed, cannot read output state: " + detail)
        fail("kscreen-doctor -j failed, cannot read output state.")
    try:
        snapshot = json.loads(proc.stdout)
    except ValueError:
        fail("failed to parse kscreen-doctor output.")
    if not isinstance(snapshot, dict) or not isinstance(snapshot.get("outputs"), list):
        fail("failed to parse kscreen-doctor output: missing outputs list.")
    return snapshot


def by_name(snapshot):
    return {output.get("name"): output for output in snapshot["outputs"]}


def logical_size(entry, scale=None):
    if scale is None:
        scale = entry.get("scale")
    if isinstance(scale, bool) or not isinstance(scale, (int, float)) or scale <= 0:
        raise DimensionsError("invalid scale for " + str(entry.get("name")))
    size = entry.get("size") or {}
    width = size.get("width", 0) or 0
    height = size.get("height", 0) or 0
    if width <= 0 or height <= 0:
        current = str(entry.get("currentModeId"))
        for mode in entry.get("modes") or []:
            if str(mode.get("id")) == current:
                mode_size = mode.get("size") or {}
                width = mode_size.get("width", 0) or 0
                height = mode_size.get("height", 0) or 0
                break
    if width <= 0 or height <= 0:
        raise DimensionsError("missing dimensions for " + str(entry.get("name")))
    return (math.ceil(width / scale), math.ceil(height / scale))


def prepare(layout, live):
    connected = []
    for output in layout["outputs"]:
        entry = live.get(output["output"])
        if entry is None or entry.get("connected") is not True:
            raise RequiredDisconnected(output["output"])
        connected.append((output, logical_size(entry, output.get("scale"))))
    max_height = max(height for (_, (_, height)) in connected)
    primaries = [
        index for index, (output, _) in enumerate(connected) if output.get("primary")
    ]
    if len(primaries) != 1:
        fail("layout '" + layout["name"] + "' must select exactly one primary output.")
    priority_of = {primaries[0]: 1}
    others = [index for index in range(len(connected)) if index != primaries[0]]
    for rank, index in enumerate(others, start=2):
        priority_of[index] = rank
    selected = []
    x = 0
    for index, (output, (width, height)) in enumerate(connected):
        # Automatic x accumulates logical widths of all preceding
        # connected outputs; automatic y bottom-aligns against the
        # tallest connected output.
        if output["position"] is not None:
            pos_x = output["position"]["x"]
            pos_y = output["position"]["y"]
        else:
            pos_x = x
            pos_y = max_height - height
        selected.append(
            {
                "output": output["output"],
                "gpu": output["gpu"],
                "priority": priority_of[index],
                "x": pos_x,
                "y": pos_y,
                "input": output["input"],
                "ddcGpu": output["ddcGpu"],
                "ddcOutput": output["ddcOutput"],
                "scale": output.get("scale"),
            }
        )
        x += width
    return selected


def state_matches(selected, live):
    for item in selected:
        entry = live.get(item["output"])
        if (
            entry is None
            or entry.get("connected") is not True
            or entry.get("enabled") is not True
        ):
            return False
        if entry.get("priority") != item["priority"]:
            return False
        if (entry.get("pos") or {}) != {"x": item["x"], "y": item["y"]}:
            return False
        if item["scale"] is not None and entry.get("scale") != item["scale"]:
            return False
    wanted = {item["output"] for item in selected}
    for connector in MANAGED:
        if connector in wanted:
            continue
        entry = live.get(connector)
        if entry is not None and entry.get("enabled") is True:
            return False
    return True


def cycle_target(live):
    current = None
    for index, layout in enumerate(LAYOUTS):
        try:
            selected = prepare(layout, live)
        except PrepareError:
            continue
        if state_matches(selected, live):
            current = index
            break
    if current is None:
        return LOGIN
    return LAYOUTS[(current + 1) % len(LAYOUTS)]["name"]


def sysfs_matches(pattern):
    return [path for path in glob.glob(pattern) if os.path.exists(path)]


def check_ownership(selected):
    for item in selected:
        found = sysfs_matches(
            "/sys/bus/pci/devices/" + item["gpu"] + "/drm/card*/card*-" + item["output"]
        )
        if len(found) != 1:
            fail(
                "expected exactly one DRM device for output '"
                + item["output"]
                + "' on GPU '"
                + item["gpu"]
                + "', found "
                + str(len(found))
                + "."
            )


def resolve_ddc_bus(gpu, connector):
    found = sysfs_matches(
        "/sys/bus/pci/devices/" + gpu + "/drm/card*/card*-" + connector + "/ddc"
    )
    if len(found) != 1:
        fail(
            "expected exactly one DDC device for connector '"
            + connector
            + "' on GPU '"
            + gpu
            + "', found "
            + str(len(found))
            + "."
        )
    try:
        link = os.readlink(found[0])
    except OSError:
        fail("cannot resolve DDC bus for connector '" + connector + "'.")
    bus = os.path.basename(link)
    bus = bus.removeprefix("i2c-")
    if not bus or any(char not in "0123456789" for char in bus):
        fail(
            "unexpected DDC bus link '" + link + "' for connector '" + connector + "'."
        )
    return bus


def apply_ddc(selected):
    jobs = []
    for item in selected:
        if item["input"] is None:
            continue
        jobs.append(
            (
                item["output"],
                resolve_ddc_bus(item["ddcGpu"], item["ddcOutput"]),
                item["input"],
            )
        )
    for output, bus, value in jobs:
        proc = subprocess.run(
            ["ddcutil", "--bus", bus, "setvcp", "60", f"0x{value:02x}"], check=False
        )
        if proc.returncode != 0:
            fail(
                "ddcutil failed to select input '"
                + str(value)
                + "' for output '"
                + output
                + "' (see ddcutil output)."
            )


def apply_layout(layout, live):
    try:
        selected = prepare(layout, live)
    except RequiredDisconnected as missing:
        fail(
            "required output '"
            + missing.output
            + "' not connected, cannot apply "
            + layout["name"]
            + " layout. See 'kscreen-doctor -o'."
        )
    except DimensionsError as error:
        fail(
            "cannot determine scaled output dimensions for bottom alignment ("
            + str(error)
            + ")."
        )
    check_ownership(selected)
    if DDC_ENABLE:
        apply_ddc(selected)
    args = []
    for item in selected:
        args += [
            "output." + item["output"] + ".enable",
            "output."
            + item["output"]
            + ".position."
            + str(item["x"])
            + ","
            + str(item["y"]),
            "output." + item["output"] + ".priority." + str(item["priority"]),
        ]
        if item["scale"] is not None:
            args += ["output." + item["output"] + ".scale." + str(item["scale"])]
    wanted = {item["output"] for item in selected}
    for connector in MANAGED:
        if connector not in wanted and connector in live:
            args += ["output." + connector + ".disable"]
    proc = subprocess.run(["kscreen-doctor"] + args, check=False)
    if proc.returncode != 0:
        fail(
            "kscreen-doctor failed to apply the requested layout (see kscreen-doctor output)."
        )
    # kscreen-doctor can succeed while KWin rejects the change. Compare
    # the original plan: re-preparing here could silently accept a
    # target output disappearing mid-apply.
    if not state_matches(selected, by_name(kscreen_snapshot())):
        fail(
            "compositor did not apply the requested layout; check that this display session is active."
        )


def main():
    if len(ARGS) > 1:
        print("display-layout: expected at most one argument", file=sys.stderr)
        print(usage(), file=sys.stderr, end="")
        return 2
    mode = ARGS[0] if ARGS else "cycle"
    if mode in ("-h", "--help", "help"):
        print(usage(), end="")
        return 0
    if mode not in MODES:
        print(
            "display-layout: unknown layout '"
            + mode
            + "' (expected "
            + "|".join(MODES)
            + ")",
            file=sys.stderr,
        )
        print(usage(), file=sys.stderr, end="")
        return 2
    live = by_name(kscreen_snapshot())
    if mode == "cycle":
        mode = cycle_target(live)
    apply_layout(next(layout for layout in LAYOUTS if layout["name"] == mode), live)
    return 0


sys.exit(main())
