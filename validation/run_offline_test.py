"""Run only the derived synthetic self-test; fail on timeout, errors, or missing assertions."""
from pathlib import Path
import json
import subprocess
import argparse

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", choices=["april10", "april13"], default="april10")
    options = parser.parse_args()
    workflow = "Offline-SelfTest.bonsai" if options.variant == "april10" else "Offline-SelfTest-Apr13.bonsai"
    result_file = ROOT / "offline/offline-test-result.json"
    if result_file.exists():
        result_file.unlink()
    with (ROOT / "logs/offline-selftest.stdout.log").open("w", encoding="utf-8") as out, \
            (ROOT / "logs/offline-selftest.stderr.log").open("w", encoding="utf-8") as err:
        process = subprocess.Popen([str(ROOT / "runtime/Bonsai.exe"),
                                    str(ROOT / "offline" / workflow), "--no-editor"],
                                   cwd=ROOT / "offline", stdout=out, stderr=err)
        try:
            code = process.wait(timeout=20)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
            raise RuntimeError("Synthetic workflow did not finish within 20 seconds. See logs.")
    if code != 0:
        raise RuntimeError(f"Synthetic workflow exited with {code}. See logs.")
    if not result_file.exists():
        raise RuntimeError("No self-test assertion result was produced. See logs.")
    result = json.loads(result_file.read_text(encoding="utf-8"))
    result["variant"] = options.variant
    if result.get("passed") is not True or result["tracking_commands"] != 72:
        raise RuntimeError(f"Self-test failed: {result}")
    (ROOT / "validation" / ("offline-test-result-" + options.variant + ".json")).write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
