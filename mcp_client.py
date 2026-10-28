"""Local JSON-lines bridge to the user's existing Bonsai MCP; no Codex settings changed."""
import json
from pathlib import Path
import queue
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parent
SERVER = ROOT / "tools/bonsai-mcp-server/BonsaiMcpServer/bin/Release/net8.0-windows/BonsaiMcpServer.dll"


def main():
    with (ROOT / "logs/mcp-server.log").open("w", encoding="utf-8") as errors:
        process = subprocess.Popen(["dotnet", str(SERVER), "--bonsai-exe", str(ROOT / "runtime/Bonsai.exe"),
                                    "--workspace", str(ROOT)], cwd=ROOT, stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=errors, text=True, encoding="utf-8")
        inbox = queue.Queue()

        def receive():
            for line in process.stdout:
                try:
                    inbox.put(json.loads(line))
                except json.JSONDecodeError:
                    pass

        threading.Thread(target=receive, daemon=True).start()
        counter = 0

        def rpc(method, params):
            nonlocal counter
            counter += 1
            request_id = counter
            process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params}) + "\n")
            process.stdin.flush()
            while True:
                response = inbox.get(timeout=45)
                if response.get("id") == request_id:
                    return response

        try:
            rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                               "clientInfo": {"name": "delta-recovery", "version": "1.0"}})
            process.stdin.write('{"jsonrpc":"2.0","method":"notifications/initialized"}\n')
            process.stdin.flush()
            available = rpc("tools/list", {}).get("result", {}).get("tools", [])
            (ROOT / "logs/mcp-tools.json").write_text(json.dumps(available, indent=2), encoding="utf-8")
            print(f"Bonsai MCP ready: {len(available)} tools. Enter tool calls as JSON objects with name and arguments.", flush=True)
            for line in sys.stdin:
                request = json.loads(line)
                if request.get("exit"):
                    break
                result = rpc("tools/call", request)
                destination = ROOT / "logs" / ("mcp-" + request["name"] + ".json")
                destination.write_text(json.dumps(result, indent=2), encoding="utf-8")
                print(json.dumps(result, ensure_ascii=False)[:2200], flush=True)
        finally:
            try:
                rpc("tools/call", {"name": "stop_workflow", "arguments": {}})
            finally:
                process.terminate()
                process.wait(timeout=10)


if __name__ == "__main__":
    main()
