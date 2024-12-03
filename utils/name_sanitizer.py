#!/usr/bin/env python3

import re
import sys
import os


def sanitize_name(name):
    """
    Sanitize model name for use as service/container name.
    Returns a tuple of (service_name, route_prefix)
    """
    # Get GPU number from environment
    gpu_num = os.environ.get("GPU_NUM", "0")

    # Basic sanitization
    name = name.lower()
    name = re.sub(r"[^a-z0-9-]", "_", name)
    name = re.sub(r"_+", "_", name)
    name = name.strip("_")

    # Create unique service name with GPU number
    service_name = f"tgi_{name}_gpu{gpu_num}_{hex(abs(hash(name + gpu_num)))[-6:]}"
    route_prefix = f"/{name}/generate"

    return f"{service_name}\n{route_prefix}"


def main():
    if len(sys.argv) != 2:
        print("Usage: ./name_sanitizer.py <name>", file=sys.stderr)
        sys.exit(1)

    print(sanitize_name(sys.argv[1]))


if __name__ == "__main__":
    main()
