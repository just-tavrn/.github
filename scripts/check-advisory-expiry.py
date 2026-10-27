#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# Expiry of temporary RustSec exceptions, run by rust-advisories.yml for each deny.toml: an [advisories] ignore entry
# whose reason says "expires YYYY-MM-DD" fails once that date (UTC) is past; so does a date that is no valid
# YYYY-MM-DD. Entries without "expires" are not checked. Errors are GitHub annotations (::error file=...::). Run:
# scripts/check-advisory-expiry.py [--today YYYY-MM-DD] deny.toml...
import argparse
import datetime
import re
import sys
import tomllib

EXPIRES = re.compile(r"\bexpires\b[\s:]*([^\s;,)]*)", re.IGNORECASE)
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")


def problems(path, today):
    """Yields one message per expired or malformed expiry of the ignore entries in the deny.toml at path."""
    try:
        with open(path, "rb") as f:
            config = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        yield f"cannot read {path}: {e}"
        return
    ignore = config.get("advisories", {}).get("ignore", [])
    for entry in ignore:
        # A plain string is an id without a reason, so without an expiry.
        if not isinstance(entry, dict):
            continue
        advisory = entry.get("id", "?")
        for match in EXPIRES.finditer(str(entry.get("reason", ""))):
            text = match.group(1).rstrip(".")
            try:
                if not DATE.fullmatch(text):
                    raise ValueError
                expires = datetime.date.fromisoformat(text)
            except ValueError:
                yield f"{path}: {advisory}: malformed expiry date '{text}' (expected 'expires YYYY-MM-DD')"
                continue
            if expires < today:
                yield f"{path}: the exception for {advisory} expired on {expires.isoformat()}; fix the advisory or renew the exception (reviewed)"
            else:
                print(f"{path}: {advisory} excepted until {expires.isoformat()}")


def main():
    parser = argparse.ArgumentParser(description="Fail on expired RustSec exceptions in deny.toml files.")
    parser.add_argument("--today", type=datetime.date.fromisoformat, help="date to compare with (default: today, UTC)")
    parser.add_argument("files", nargs="+", metavar="deny.toml")
    args = parser.parse_args()
    today = args.today or datetime.datetime.now(datetime.timezone.utc).date()
    failed = 0
    for path in args.files:
        for message in problems(path, today):
            print(f"::error file={path}::{message}")
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
