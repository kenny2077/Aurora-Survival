#!/usr/bin/env python3
"""Scan reachable Git blobs for recognizable credentials; never print matches.

This conservative pattern scan is not proof that the repository has no secrets.
It intentionally reports only object IDs and rule names for private triage.
"""

import re
import subprocess


RULES = {
    "private-key": re.compile(rb"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
    "github-token": re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})\b"),
    "aws-access-key": re.compile(rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
}


def main():
    objects = subprocess.check_output(["git", "rev-list", "--objects", "--all"]).splitlines()
    process = subprocess.Popen(["git", "cat-file", "--batch"], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    findings = []
    checked = 0
    for entry in objects:
        oid = entry.split(b" ", 1)[0]
        process.stdin.write(oid + b"\n")
        process.stdin.flush()
        header = process.stdout.readline().split()
        size = int(header[2])
        data = process.stdout.read(size)
        process.stdout.read(1)
        if header[1] != b"blob":
            continue
        checked += 1
        for name, pattern in RULES.items():
            if pattern.search(data):
                findings.append((oid.decode(), name))
    process.stdin.close()
    process.wait()
    print(f"Scanned {checked} reachable Git blobs; {len(findings)} potential findings.")
    for oid, rule in findings:
        print(f"{oid}: {rule} (value redacted)")
    return bool(findings)


if __name__ == "__main__":
    raise SystemExit(main())
