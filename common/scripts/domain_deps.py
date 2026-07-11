#!/usr/bin/env python3
"""Query domain topology and runtime state from config-registry/env/domains.yml.

Used by common/Makefile to avoid embedding multi-line Python inside recipes.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
DOMAINS_FILE = ROOT / "config-registry" / "env" / "domains.yml"


def load_domains() -> list[dict]:
    try:
        data = yaml.safe_load(DOMAINS_FILE.read_text())
    except (OSError, yaml.YAMLError):
        return []
    return (data or {}).get("domains", []) or []


def find_domain(domains: list[dict], name: str) -> dict | None:
    return next((d for d in domains if d.get("name") == name), None)


def cmd_requires(args: argparse.Namespace) -> None:
    target = find_domain(load_domains(), args.domain)
    required = (target or {}).get("requires") or []
    print(" ".join(required))


def cmd_dependents(args: argparse.Namespace) -> None:
    domains = load_domains()
    dependents = [d["name"] for d in domains if args.domain in (d.get("requires") or [])]
    print(" ".join(dependents))


def cmd_is_running(args: argparse.Namespace) -> None:
    compose_file = ROOT / "generated" / args.domain / "compose.yml"
    if not compose_file.exists():
        sys.exit(1)

    try:
        result = subprocess.run(
            ["docker", "compose", "-f", str(compose_file), "ps", "--status", "running", "--format", "json"],
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        sys.exit(1)

    running = []
    for line in result.stdout.splitlines():
        if not line.strip():
            continue
        try:
            running.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    sys.exit(0 if running else 1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_requires = sub.add_parser("requires", help="Print space-separated domains this domain requires")
    p_requires.add_argument("domain")
    p_requires.set_defaults(func=cmd_requires)

    p_dependents = sub.add_parser("dependents", help="Print space-separated domains that require this domain")
    p_dependents.add_argument("domain")
    p_dependents.set_defaults(func=cmd_dependents)

    p_running = sub.add_parser("is-running", help="Exit 0 if the domain has running containers, 1 otherwise")
    p_running.add_argument("domain")
    p_running.set_defaults(func=cmd_is_running)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
