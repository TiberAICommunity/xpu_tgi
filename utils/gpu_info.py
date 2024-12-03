#!/usr/bin/env python3

import sys
import glob
import os


def get_render_devices():
    """Get available render devices from /dev/dri/"""
    render_devices = glob.glob("/dev/dri/renderD*")
    return sorted([int(dev.split("renderD")[1]) for dev in render_devices])


def get_gpu_info():
    """Get GPU information based on render devices"""
    render_numbers = get_render_devices()
    if not render_numbers:
        return 0, []
    gpu_numbers = [render - 128 for render in render_numbers]
    return len(gpu_numbers), gpu_numbers


def main():
    if len(sys.argv) != 2:
        print("Usage: gpu_info.py [count|numbers]", file=sys.stderr)
        sys.exit(1)

    count, numbers = get_gpu_info()

    if sys.argv[1] == "count":
        print(count)
    elif sys.argv[1] == "numbers":
        print(",".join(map(str, numbers)))
    else:
        print(f"Unknown command: {sys.argv[1]}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
