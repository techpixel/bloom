#!/usr/bin/env python3
"""Show Bloom's prompts on cue from a Mac during a live demo.

Bloom must be open on the phone, on the same Wi-Fi as this Mac. The phone is
found over Bonjour; pass --host to skip that.

    scripts/bloom-remote.py sighting Ishan
    scripts/bloom-remote.py sighting Ishan --place "Hicks Library, West Lafayette" --when "Today at 2:40 PM"
    scripts/bloom-remote.py reflect Manitej --activity Lunch --place "Purdue Memorial Union"
    scripts/bloom-remote.py name --visits 4
    scripts/bloom-remote.py notify --title "Ishan is nearby" --body "You’re both near Hicks Library." --delay 10
    scripts/bloom-remote.py reset

  sighting  "Did you meet with <friend>?" appears in Home's Recent.
  reflect   A new hangout with <friend>; Recent asks how it felt.
  name      "You’ve been here 3 times… Name this new location?" on the hangout open on the phone.
  notify    A notification on the phone, like a push; --delay lets you lock it first.
  reset     Puts Home back the way it started.
  friends   Lists the friends the phone knows (real names on Celeste).
"""
import argparse
import json
import re
import subprocess
import sys
import urllib.request

SERVICE = "_bloom-demo._tcp"


def find_phone(timeout: float = 6.0) -> str:
    """Resolve Bloom's Bonjour service to host:port with dns-sd."""
    try:
        out = subprocess.run(
            ["dns-sd", "-L", "Bloom", SERVICE, "local."],
            capture_output=True, text=True, timeout=timeout,
        ).stdout
    except subprocess.TimeoutExpired as finished:
        out = finished.stdout.decode() if isinstance(finished.stdout, bytes) else (finished.stdout or "")
    match = re.search(r"can be reached at (\S+?)\.?:(\d+)", out)
    if not match:
        sys.exit("Couldn't find Bloom on the network. Is it open on the phone, on the same Wi-Fi? "
                 "Or pass --host <phone IP>.")
    return f"{match.group(1)}:{match.group(2)}"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("kind", choices=["sighting", "reflect", "reset", "name", "friends", "notify"])
    parser.add_argument("friend", nargs="?", help="a friend's first or full name")
    parser.add_argument("--place", help='e.g. "Vienna Cafe, Lafayette"')
    parser.add_argument("--when", help='sighting only, e.g. "Today at 6:13 PM" (default: "Just now")')
    parser.add_argument("--activity", help='reflect only, e.g. "Lunch" (default: "Coffee")')
    parser.add_argument("--length", help='reflect only, e.g. "2 hours" (default: "1 hour")')
    parser.add_argument("--visits", type=int, help="name only: times you've been there this month (default: 3)")
    parser.add_argument("--title", help="notify only: the notification's title")
    parser.add_argument("--body", help="notify only: its message")
    parser.add_argument("--delay", type=float, help="notify only: seconds to wait before it shows (default: 0)")
    parser.add_argument("--host", help="the phone's address, as IP or IP:port (default: found over Bonjour)")
    args = parser.parse_args()

    if args.kind not in ("reset", "name", "friends", "notify") and not args.friend:
        parser.error(f"{args.kind} needs a friend's name")

    host = args.host or find_phone()
    if ":" not in host:
        host += ":7777"

    body = {"kind": args.kind}
    for key in ("friend", "place", "when", "activity", "length", "visits", "title", "body", "delay"):
        value = getattr(args, key)
        if value:
            body[key] = value

    request = urllib.request.Request(
        f"http://{host}/", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            print(response.read().decode().strip() or "ok")
    except urllib.error.HTTPError as error:
        sys.exit(f"Bloom said no: {error.read().decode().strip()}")
    except OSError as error:
        sys.exit(f"Couldn't reach Bloom at {host}: {error}")


if __name__ == "__main__":
    main()
