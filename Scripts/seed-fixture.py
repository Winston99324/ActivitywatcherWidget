#!/usr/bin/env python3
"""Seed synthetic records ONLY into a dedicated, empty local test server on port 5679."""
import json
import urllib.request

BASE = "http://127.0.0.1:5679/api/0/"

def request(path, data=None):
    body = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(BASE + path, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as response:
        payload = response.read()
        return json.loads(payload) if payload else None

BUCKETS = [("widget-test-window", "currentwindow"), ("widget-test-afk", "afkstatus"),
           ("widget-test-browser-window", "currentwindow"), ("widget-test-browser-afk", "afkstatus"),
           ("widget-test-chromework", "web.tab.current"), ("widget-test-chromepersonal", "web.tab.current")]
existing = request("buckets/")
for name, metadata in existing.items():
    if name not in dict(BUCKETS) or metadata.get("client") != "widget-test" or request("buckets/" + name + "/events/count") != 0:
        raise SystemExit("Refusing to seed a nonempty server. Use a new, isolated fixture database.")

for name, kind in BUCKETS:
    if name not in existing:
        request("buckets/" + name, {"client": "widget-test", "type": kind, "hostname": "widget-fixture"})

request("buckets/widget-test-window/events", [
    {"timestamp": "2026-10-25T23:59:30Z", "duration": 90, "data": {"app": "Safari", "title": "synthetic"}},
    {"timestamp": "2026-10-26T00:02:00Z", "duration": 120, "data": {"app": "Xcode"}},
    {"timestamp": "2026-10-26T00:59:30Z", "duration": 120, "data": {"app": "Safari"}},
])
request("buckets/widget-test-afk/events", [
    {"timestamp": "2026-10-25T23:59:00Z", "duration": 240, "data": {"status": "not-afk"}},
    {"timestamp": "2026-10-26T00:03:00Z", "duration": 120, "data": {"status": "afk"}},
    {"timestamp": "2026-10-26T00:59:00Z", "duration": 240, "data": {"status": "not-afk"}},
])
print("Synthetic fixtures ready. Expected active time: 150s; foreground time: 210s.")

request("buckets/widget-test-browser-window/events", [
    {"timestamp": "2026-10-26T00:00:00Z", "duration": 30, "data": {"app": "Google Chrome", "title": "Work - Google Chrome"}},
    {"timestamp": "2026-10-26T00:00:30Z", "duration": 30, "data": {"app": "Google Chrome", "title": "Personal"}},
    {"timestamp": "2026-10-26T00:01:00Z", "duration": 30, "data": {"app": "Google Chrome", "title": "Same"}},
    {"timestamp": "2026-10-26T00:01:30Z", "duration": 30, "data": {"app": "Xcode", "title": "Work"}},
])
request("buckets/widget-test-browser-afk/events", [
    {"timestamp": "2026-10-26T00:00:00Z", "duration": 120, "data": {"status": "not-afk"}},
])
for name, title, domain in [("chromework", "Work", "work.example.com"), ("chromepersonal", "Personal", "personal.example.com")]:
    request("buckets/widget-test-" + name + "/events", [
        {"timestamp": "2026-10-26T00:00:00Z", "duration": 60, "data": {"title": title, "url": "https://" + domain + "/", "incognito": False}},
        {"timestamp": "2026-10-26T00:01:00Z", "duration": 30, "data": {"title": "Same", "url": "https://same.example.com/", "incognito": False}},
    ])
print("Chrome fixtures ready. Work: 30s; Personal: 30s; ambiguous: 30s.")
