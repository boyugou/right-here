#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["jsonschema"]
# ///
"""Check that the MCP server speaks the protocol versions it says it does.

Starts `rh mcp` in a trial home (an empty folder: nothing of this Mac is read or written), talks to it in each version of
`MCPServer.supportedVersions`, and validates what it answers against the official JSON Schema of that version: the initialize
result and its envelope, `tools/list`, the result of the read-only tools, `ping`, the error for an unknown method, the answer
to a method the server did not declare (`resources/list`, `prompts/list`) and to a tool that does not exist.

The schemas are the protocol's own (github.com/modelcontextprotocol/modelcontextprotocol, `schema/<version>/schema.json`). They are
downloaded once into `.build/mcp-schemas/`, so this needs the network the first time and `swift build` before it. It is not part of
`verify_all.sh`, because it depends on files outside the repository: run it after a change to the MCP server or when the server
learns a new protocol version.

    ./script/verify_mcp_protocol.py
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

from jsonschema import validators

ROOT = Path(__file__).resolve().parent.parent
RH = ROOT / ".build" / "debug" / "rh"
CACHE = ROOT / ".build" / "mcp-schemas"
SCHEMA_URL = "https://raw.githubusercontent.com/modelcontextprotocol/modelcontextprotocol/main/schema/{version}/schema.json"
SAFE_TOOLS = {"right_here_actions": {}, "right_here_catalog": {}, "right_here_doctor": {}, "right_here_bookmarks": {}}


def supported_versions() -> list[str]:
    source = (ROOT / "Sources" / "RightHereMCP" / "MCPServer.swift").read_text(encoding="utf-8")
    match = re.search(r"supportedVersions\s*=\s*\[([^\]]*)\]", source)
    if not match:
        sys.exit("cannot find supportedVersions in MCPServer.swift")
    return re.findall(r'"([^"]+)"', match.group(1))


def schema_for(version: str) -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"{version}.json"
    if not path.exists():
        with urllib.request.urlopen(SCHEMA_URL.format(version=version), timeout=60) as response:
            path.write_bytes(response.read())
    return json.loads(path.read_text(encoding="utf-8"))


class Session:
    def __init__(self, version: str):
        self.version = version
        self.schema = schema_for(version)
        self.defs = self.schema.get("$defs", self.schema.get("definitions", {}))
        self.problems: list[str] = []
        self.home = tempfile.mkdtemp(prefix="rh-mcp-")
        environment = dict(os.environ, RH_NO_UI="1", RH_HOME=self.home, HOME=self.home)
        self.process = subprocess.Popen([str(RH), "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        env=environment, text=True)
        self.next_id = 0

    def send(self, method: str, params=None, notify: bool = False):
        message = {"jsonrpc": "2.0", "method": method}
        if params is not None:
            message["params"] = params
        if not notify:
            self.next_id += 1
            message["id"] = self.next_id
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()
        if notify:
            return None
        line = self.process.stdout.readline()
        return json.loads(line) if line else None

    def validate(self, definition: str, instance, what: str) -> None:
        key = "$defs" if "$defs" in self.schema else "definitions"
        root = {"$schema": self.schema.get("$schema"), key: self.defs, "$ref": f"#/{key}/{definition}"}
        for error in sorted(validators.validator_for(root)(root).iter_errors(instance), key=lambda e: list(e.path))[:5]:
            self.problems.append(f"[{self.version}] {what}: {'/'.join(map(str, error.path)) or '(root)'}: {error.message[:180]}")

    def first(self, *names: str) -> str:
        return next(name for name in names if name in self.defs)

    def run(self) -> list[str]:
        init = self.send("initialize", {"protocolVersion": self.version, "capabilities": {}, "clientInfo": {"name": "verify_mcp_protocol", "version": "0"}})
        if not init or "result" not in init:
            return [f"[{self.version}] initialize: no result: {init}"]
        self.validate("InitializeResult", init["result"], "initialize result")
        self.validate(self.first("JSONRPCResultResponse", "JSONRPCResponse"), init, "initialize envelope")
        if init["result"].get("protocolVersion") != self.version:
            self.problems.append(f"[{self.version}] initialize answered {init['result'].get('protocolVersion')} to a request for {self.version}")
        self.send("notifications/initialized", notify=True)
        listed = self.send("tools/list", {})
        self.validate("ListToolsResult", (listed or {}).get("result", {}), "tools/list result")
        for tool in (listed or {}).get("result", {}).get("tools", []):
            if tool["name"] in SAFE_TOOLS:
                answer = self.send("tools/call", {"name": tool["name"], "arguments": SAFE_TOOLS[tool["name"]]})
                if not answer or "result" not in answer:
                    self.problems.append(f"[{self.version}] tools/call {tool['name']}: {str(answer)[:160]}")
                else:
                    self.validate("CallToolResult", answer["result"], f"tools/call {tool['name']}")
        ping = self.send("ping")
        if ping and "result" in ping:
            self.validate("EmptyResult", ping["result"], "ping result")
        else:
            self.problems.append(f"[{self.version}] ping: {ping}")
        unknown = self.send("no/such/method", {})
        if not unknown or unknown.get("error", {}).get("code") != -32601:
            self.problems.append(f"[{self.version}] an unknown method should be error -32601, got {str(unknown)[:160]}")
        else:
            self.validate(self.first("JSONRPCErrorResponse", "JSONRPCError"), unknown, "unknown-method error")
        capabilities = init["result"].get("capabilities", {})
        for method, definition in (("resources/list", "ListResourcesResult"), ("prompts/list", "ListPromptsResult")):
            answer = self.send(method, {})
            if method.split("/")[0] in capabilities:
                self.validate(definition, (answer or {}).get("result", {}), method)
            elif not answer or "error" not in answer:
                self.problems.append(f"[{self.version}] {method} is not declared and should be an error, got {str(answer)[:160]}")
        bad = self.send("tools/call", {"name": "no_such_tool", "arguments": {}})
        if bad is None or ("error" not in bad and not bad.get("result", {}).get("isError")):
            self.problems.append(f"[{self.version}] an unknown tool is neither a protocol error nor isError: {str(bad)[:160]}")
        self.process.stdin.close()
        self.process.wait(timeout=20)
        return self.problems


def main() -> int:
    if not RH.exists():
        print("run `swift build` first: .build/debug/rh is not there", file=sys.stderr)
        return 2
    problems: list[str] = []
    versions = supported_versions()
    for version in versions:
        problems += Session(version).run()
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 1
    print(f"ok: the MCP server answers conformantly in {', '.join(versions)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
