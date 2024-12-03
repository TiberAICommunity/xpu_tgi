#!/usr/bin/env python3

import socket
import sys

def is_port_available(port):
    """Check if a port is available."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        try:
            s.bind(('localhost', port))
            return True
        except socket.error:
            return False

def find_available_port(start_port=8000):
    """Find first available port starting from start_port."""
    port = start_port
    while port < 65536:  # Maximum port number
        if is_port_available(port):
            return port
        port += 1
    return None

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ['check', 'find']:
        print(f"Usage: {sys.argv[0]} {{check|find}}")
        print("  check: Check if port 8000 is available")
        print("  find:  Find first available port starting from 8000")
        sys.exit(1)

    command = sys.argv[1]
    if command == 'check':
        if is_port_available(8000):
            print("available")
            sys.exit(0)
        else:
            print("in-use")
            sys.exit(1)
    elif command == 'find':
        port = find_available_port()
        if port:
            print(port)
            sys.exit(0)
        else:
            print("No available ports found", file=sys.stderr)
            sys.exit(1)

if __name__ == '__main__':
    main() 