"""Fallback client for the TaskRadar MCP server, for sessions where the
`taskradar` MCP tools did not load. Reads url + token from the user-scope
`mcpServers.taskradar` entry in ~/.claude.json, so no secret lives here.

Usage:
  python -I -X utf8 mcp_call.py tools                      # list tools + input schemas
  python -I -X utf8 mcp_call.py <tool> '<json arguments>'  # call a tool, print its result
  python -I -X utf8 mcp_call.py get_task '{"taskId":"..."}' --images DIR
      # also save the images of the answer into DIR (they are not printed)
"""
import base64
import json
import os
import sys
import urllib.request

cfg = json.load(open(os.path.expanduser("~/.claude.json"), encoding="utf-8"))
srv = cfg.get("mcpServers", {}).get("taskradar")
if not srv:
    sys.exit("No user-scope mcpServers.taskradar in ~/.claude.json")

HEADERS = {
    "Content-Type": "application/json",
    "Accept": "application/json, text/event-stream",
    **srv.get("headers", {}),
}
session_id = None


def rpc(method, params=None, req_id=None):
    global session_id
    headers = dict(HEADERS)
    if session_id:
        headers["Mcp-Session-Id"] = session_id
    body = {"jsonrpc": "2.0", "method": method}
    if req_id is not None:
        body["id"] = req_id
    if params is not None:
        body["params"] = params
    req = urllib.request.Request(srv["url"], json.dumps(body).encode(), headers)
    with urllib.request.urlopen(req, timeout=60) as resp:
        session_id = resp.headers.get("Mcp-Session-Id") or session_id
        text = resp.read().decode("utf-8")
    if not text.strip():
        return None
    if "data:" in text and not text.lstrip().startswith("{"):
        text = [l[5:] for l in text.splitlines() if l.startswith("data:")][-1]
    msg = json.loads(text)
    if "error" in msg:
        sys.exit(f"MCP error: {msg['error']}")
    return msg.get("result")


args = sys.argv[1:]
images_dir = None
if "--images" in args:
    i = args.index("--images")
    images_dir = args[i + 1]
    del args[i : i + 2]

rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                   "clientInfo": {"name": "taskradar-skill", "version": "1"}}, 1)
rpc("notifications/initialized")

if not args or args[0] == "tools":
    for t in rpc("tools/list", {}, 2)["tools"]:
        print(f"## {t['name']}\n{t.get('description', '')}")
        print(json.dumps(t.get("inputSchema", {}).get("properties", {}), ensure_ascii=False), "\n")
    sys.exit(0)

res = rpc("tools/call", {"name": args[0], "arguments": json.loads(args[1]) if len(args) > 1 else {}}, 3)
if res.get("isError"):
    print("TOOL ERROR:", end=" ")
saved = 0
for block in res.get("content", []):
    if block.get("type") == "text":
        try:
            print(json.dumps(json.loads(block["text"]), ensure_ascii=False, indent=1))
        except ValueError:
            print(block["text"])
    elif block.get("type") == "image":
        if images_dir is None:
            print(f"[image {block.get('mimeType')} not saved: pass --images DIR]")
            continue
        os.makedirs(images_dir, exist_ok=True)
        ext = (block.get("mimeType") or "image/jpeg").split("/")[-1]
        saved += 1
        path = os.path.join(images_dir, f"{args[0]}-{saved}.{ext}")
        with open(path, "wb") as f:
            f.write(base64.b64decode(block["data"]))
        print(f"[image saved: {path}]")
