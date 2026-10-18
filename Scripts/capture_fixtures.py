#!/usr/bin/env python3
"""Capture signed-out YouTube Music API responses as parser test fixtures.

Usage: python3 -I Scripts/capture_fixtures.py AppleTubeTests/Fixtures
Mirrors YTMusicAPI's guest requests (WEB_REMIX client, SOCS cookie, scraped API key).
"""
import json, re, sys, urllib.request, pathlib

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
ORIGIN = "https://music.youtube.com"
out = pathlib.Path(sys.argv[1])

def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Cookie": "SOCS=CAI"})
    return urllib.request.urlopen(req, timeout=30).read().decode()

key = re.search(r'"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"', get(ORIGIN)).group(1)

def call(endpoint, body):
    body = dict(body, context={"client": {"clientName": "WEB_REMIX", "clientVersion": "1.20231204.01.00",
                                          "hl": "en", "gl": "US", "platform": "DESKTOP", "userAgent": UA},
                               "user": {"lockedSafetyMode": False}})
    req = urllib.request.Request(f"{ORIGIN}/youtubei/v1/{endpoint}?key={key}&prettyPrint=false",
                                 data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json", "User-Agent": UA, "Origin": ORIGIN,
                                          "Referer": ORIGIN, "Cookie": "SOCS=CAI"})
    return json.loads(urllib.request.urlopen(req, timeout=30).read())

def save(name, data):
    (out / f"{name}.json").write_text(json.dumps(data))
    print(f"{name}: {len(json.dumps(data)) // 1024} KB")

def find(obj, key):
    """First value for `key` anywhere in the tree whose value is a str starting with the given prefix."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield k, v
            yield from find(v, key)
    elif isinstance(obj, list):
        for v in obj:
            yield from find(v, key)

def first_browse_id(data, prefix):
    return next(v for k, v in find(data, None) if k == "browseId" and isinstance(v, str) and v.startswith(prefix))

nxt = lambda vid, pl=None: dict({"videoId": vid, "enablePersistentPlaylistPanel": True, "isAudioOnly": True,
                                 "tunerSettingValue": "AUTOMIX_SETTING_NORMAL"}, **({"playlistId": pl} if pl else {}))

save("home", call("browse", {"browseId": "FEmusic_home"}))
search = call("search", {"query": "coldplay"}); save("search", search)
save("suggestions", call("music/get_search_suggestions", {"input": "coldp"}))
save("album", call("browse", {"browseId": first_browse_id(search, "MPREb_")}))
save("artist", call("browse", {"browseId": first_browse_id(search, "UC")}))
pl_search = call("search", {"query": "coldplay playlist", "params": "EgWKAQIoAWoKEAoQAxAEEAkQBQ%3D%3D"})
save("playlist", call("browse", {"browseId": first_browse_id(pl_search, "VL")}))
save("radio", call("next", nxt("dQw4w9WgXcQ", "RDAMVMdQw4w9WgXcQ")))
song_next = call("next", nxt("dQw4w9WgXcQ"))
lyrics_id = next((v for k, v in find(song_next, None) if k == "browseId" and isinstance(v, str) and v.startswith("MPLY")), None)
if lyrics_id:
    save("lyrics", call("browse", {"browseId": lyrics_id}))
else:
    print("lyrics: no lyrics tab for test track")
