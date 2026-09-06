#!/usr/bin/env python3
"""Audit starter compose services vs each bot repo's declared mix releases.

Run inside the VM:  python3 /vagrant/scripts/audit_releases.py
Reports, per service: whether it builds from source, the BOT_NAME the
Dockerfile's `mix release ${BOT_NAME}` will use, and whether that release
exists in repos/<dir>/mix.exs.
"""
import os
import re

BASE = os.path.expanduser("~/bot-army")
compose = open(os.path.join(BASE, "docker-compose.yml")).read()

# service blocks: "  <name>:" at exactly two-space indent, body until next
entries = re.split(r"\n(?=  [a-z_0-9]+:\n)", compose)
for block in entries[1:]:
    head = re.match(r"  ([a-z_0-9]+):\n", block)
    if not head:
        continue
    name = head.group(1)
    body = block[head.end():]
    build = "build:" in body
    m = re.search(r"BOT_NAME:\s*([a-z_0-9]+)", body)
    bot_name = m.group(1) if m else "-"
    # map service -> repos dir via BOT_REPO arg
    cm = re.search(r"BOT_REPO:\s*([A-Za-z_0-9./-]+)", body)
    ctx = cm.group(1).rstrip("/") if cm else "?"
    if build and bot_name != "-" and ctx not in ("?", ".", "scripts"):
        mix = os.path.join(BASE, "repos", ctx, "mix.exs")
        rels = []
        if os.path.exists(mix):
            src = open(mix).read()
            rels = re.findall(r"^        ([a-z_0-9]+): \[", src, re.M)
        ok = "OK " if bot_name in rels else "MISMATCH"
        print(f"{ok} service={name:20s} BOT_NAME={bot_name:20s} repo={ctx:28s} releases={rels}")