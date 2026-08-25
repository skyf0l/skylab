#!/usr/bin/env python3
# Reconciles Uptime Kuma to /etc/provision/provision.json (rendered from the
# chart values): creates the admin account on a fresh instance, then creates or
# updates the public status page — one section per public group, an "overview"
# section holding the group monitors, and an SLO table in the description with
# live 30-day uptime badges (served by Kuma's badge API, so the numbers are the
# real measured ones, not text).
#
# Monitors and groups are NOT managed here: the AutoKuma sidecar owns them.
# This script only waits until every monitor the page needs exists, then maps
# names to Kuma ids. Idempotent: runs on every sync.
#
# Everything goes through the socket.io API (Kuma has no REST for management):
#   setup(username, password)              first-run only, errors afterwards
#   login({username, password, token})     -> monitorList event
#   getStatusPage / addStatusPage / saveStatusPage(slug, config, logo, groups)
import json
import os
import sys
import time
import urllib.request

import socketio

URL = os.environ["KUMA_URL"]
USERNAME = os.environ["KUMA_ADMIN_USERNAME"]
PASSWORD = os.environ["KUMA_ADMIN_PASSWORD"]
MONITOR_WAIT = int(os.environ.get("MONITOR_WAIT_SECONDS", "900"))

with open("/etc/provision/provision.json") as f:
    CFG = json.load(f)
PAGE = CFG["statusPage"]
PUBLIC_GROUPS = [g for g in CFG["groups"] if g["public"]]


def log(msg):
    print(msg, flush=True)


def fail(msg):
    log(f"error: {msg}")
    sys.exit(1)


def wait_http(url, timeout=300):
    deadline = time.time() + timeout
    while True:
        try:
            urllib.request.urlopen(url, timeout=5)
            return
        except Exception as e:  # noqa: BLE001 - any answer at all is progress
            if getattr(e, "code", None):
                return
            if time.time() > deadline:
                fail(f"{url} unreachable after {timeout}s: {e}")
            time.sleep(5)


state = {"monitors": None}
sio = socketio.Client()


@sio.on("monitorList")
def on_monitor_list(data):
    state["monitors"] = data


def call(event, *args, timeout=60):
    res = sio.call(event, args if len(args) != 1 else args[0], timeout=timeout)
    return res if isinstance(res, dict) else {"ok": False, "msg": str(res)}


def ensure_admin():
    res = call("setup", USERNAME, PASSWORD)
    if res.get("ok"):
        log("admin account created")
    else:
        log(f"setup skipped: {res.get('msg')}")
    res = call("login", {"username": USERNAME, "password": PASSWORD, "token": ""})
    if not res.get("ok"):
        fail(f"login failed: {res.get('msg')}")
    log("logged in")


def resolve_monitors():
    """Map every public group and its monitors to Kuma monitor ids, waiting for
    AutoKuma to create the ones that do not exist yet."""
    deadline = time.time() + MONITOR_WAIT
    while True:
        if state["monitors"] is None:
            call("getMonitorList")
        monitors = list((state["monitors"] or {}).values())
        by_group = {m["name"]: m["id"] for m in monitors if m.get("type") == "group"}
        resolved, missing = [], []
        for g in PUBLIC_GROUPS:
            gid = by_group.get(g["name"])
            if gid is None:
                missing.append(f"group {g['name']}")
                continue
            children = {m["name"]: m["id"] for m in monitors if m.get("parent") == gid}
            ids = []
            for name in g["monitors"]:
                if name in children:
                    ids.append(children[name])
                else:
                    missing.append(f"{g['name']}/{name}")
            resolved.append({"name": g["name"], "slo": g["slo"], "id": gid, "monitors": ids})
        if not missing:
            return resolved
        if time.time() > deadline:
            fail(f"monitors still missing after {MONITOR_WAIT}s: {', '.join(missing)}")
        log(f"waiting for AutoKuma: {len(missing)} missing ({missing[0]} ...)")
        state["monitors"] = None
        time.sleep(15)


def slo_table(groups):
    window = PAGE["sloWindow"]
    rows = [
        f"### {PAGE['sloHeading']}",
        "",
        "| Service group | SLO target | Measured |",
        "| --- | :-: | :-: |",
    ]
    for g in groups:
        badge = f"/api/badge/{g['id']}/uptime/{window}?label={window}"
        rows.append(f"| {g['name']} | {g['slo']} % | ![{g['name']} uptime, last {window}]({badge}) |")
    return "\n".join(rows)


def save_status_page(groups):
    slug = PAGE["slug"]
    res = call("getStatusPage", slug)
    if not res.get("ok"):
        res = call("addStatusPage", PAGE["title"], slug)
        if not res.get("ok"):
            fail(f"addStatusPage failed: {res.get('msg')}")
        log(f"status page /status/{slug} created")
    config = {
        "slug": slug,
        "title": PAGE["title"],
        "description": PAGE["description"].rstrip() + "\n\n" + slo_table(groups),
        "footerText": PAGE["footerText"],
        "theme": PAGE["theme"],
        "published": True,
        "showTags": False,
        "customCSS": "",
        "logo": "/icon.svg",
        "showPoweredBy": PAGE["showPoweredBy"],
        "showCertificateExpiry": PAGE["showCertificateExpiry"],
        "autoRefreshInterval": PAGE["autoRefreshInterval"],
    }
    sections = [
        {"name": PAGE["overviewSection"], "monitorList": [{"id": g["id"], "sendUrl": 0} for g in groups]},
    ]
    for g in groups:
        sections.append({"name": g["name"], "monitorList": [{"id": i, "sendUrl": 0} for i in g["monitors"]]})
    res = call("saveStatusPage", slug, config, "/icon.svg", sections)
    if not res.get("ok"):
        fail(f"saveStatusPage failed: {res.get('msg')}")
    log(f"status page /status/{slug} reconciled: {len(groups)} groups, "
        f"{sum(len(g['monitors']) for g in groups)} monitors")


wait_http(URL + "/")
sio.connect(URL, transports=["websocket"])
try:
    ensure_admin()
    groups = resolve_monitors()
    save_status_page(groups)
finally:
    sio.disconnect()
