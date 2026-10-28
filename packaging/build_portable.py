"""Package the verified installed environment with a source snapshot and hashes."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NAME = "DeltaFly-Bonsai-2.7.1-win-x64"
DIST = ROOT / "dist"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    source_commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    if subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT):
        raise RuntimeError("Commit tracked package changes before building a release.")
    installed = ET.parse(ROOT / "runtime/Bonsai.config")
    expected = ET.parse(ROOT / "environment/Bonsai.config")
    package_versions = lambda tree: {p.get("id"): p.get("version") for p in tree.findall("./Packages/Package")}
    packages = package_versions(installed)
    if packages != package_versions(expected) or len(packages) != 27:
        raise RuntimeError("Installed packages differ from the verified pinned environment.")
    for entry in installed.findall("./AssemblyLocations/AssemblyLocation"):
        if not (ROOT / "runtime" / entry.get("location")).is_file():
            raise FileNotFoundError(entry.get("location"))

    # Include the committed project, not caches, recordings, local MCP sources or settings.
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    files = {p: ROOT / p for p in tracked if p and p not in {".gitignore", ".gitattributes", "mcp_client.py"}}
    for path in (ROOT / "runtime").rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT).as_posix()
        if ".bonsai" in path.parts or path.name.endswith((".settings", ".log")) or relative == "runtime/Bonsai32.exe":
            continue
        files[relative] = path
    validator = ROOT / "validation/bin/CompileWorkflow.exe"
    if not validator.is_file():
        raise FileNotFoundError("Build validation/CompileWorkflow.cs before packaging.")
    files["validation/CompileWorkflow.exe"] = validator
    if not (ROOT / "runtime/Extensions/Recovery.Offline.dll").is_file():
        raise FileNotFoundError("The compiled offline extension is missing.")

    generated = {"START HERE.txt": (ROOT / "packaging/PORTABLE-START-HERE.txt").read_bytes()}
    # Launching this copy has no remote package feed. All assemblies are already installed.
    for filename, local_source in [("NuGet.config", "local-packages"), ("runtime/NuGet.config", "..\\local-packages")]:
        files.pop(filename, None)
        generated[filename] = ("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
            "<configuration><packageSources><clear />"
            f"<add key=\"Bundled local packages\" value=\"{local_source}\" />"
            "</packageSources><disabledPackageSources><clear /></disabledPackageSources></configuration>\n").encode()

    notices = ["THIRD PARTY PACKAGE INFORMATION", "",
               "The installed packages and their original .nupkg archives are included under runtime/Packages.",
               "Each component retains its own license. License files and package metadata are preserved.",
               "Bonsai upstream: https://github.com/bonsai-rx/bonsai/releases/tag/2.7.1", ""]
    for identifier, version in sorted(packages.items(), key=lambda p: p[0].lower()):
        notices.append(f"{identifier} {version}")
        folder = ROOT / "runtime/Packages" / f"{identifier}.{version}"
        for nuspec in folder.glob("*.nuspec"):
            metadata = ET.parse(nuspec).find("{*}metadata")
            if metadata is not None:
                for key in ["authors", "projectUrl", "license", "licenseUrl", "copyright"]:
                    value = metadata.find("{*}" + key)
                    if value is not None and value.text:
                        notices.append(f"  {key}: {value.text.strip()}")
        notices.append("")
    generated["THIRD-PARTY-NOTICES.txt"] = "\n".join(notices).encode("utf-8")

    manifest_files = []
    for relative in sorted(set(files) | set(generated)):
        data = generated[relative] if relative in generated else files[relative].read_bytes()
        manifest_files.append({"path": relative, "bytes": len(data), "sha256": sha256(data)})
    manifest = {"package": NAME, "bonsai_version": "2.7.1", "architecture": "win-x64",
                "source_commit": source_commit, "created_utc": datetime.now(timezone.utc).isoformat(),
                "installed_packages": packages, "remote_package_sources": False,
                "files": manifest_files}
    generated["PACKAGE-MANIFEST.json"] = json.dumps(manifest, indent=2).encode("utf-8")
    DIST.mkdir(exist_ok=True)
    archive = DIST / (NAME + ".zip")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as out:
        for relative in sorted(set(files) | set(generated)):
            data = generated[relative] if relative in generated else files[relative].read_bytes()
            info = zipfile.ZipInfo(NAME + "/" + relative, date_time=(2026, 10, 28, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            out.writestr(info, data)
        for directory in ["logs/", "controller/recordings/", "runtime/Gallery/"]:
            out.writestr(NAME + "/" + directory, b"")
    archive_hash = sha256(archive.read_bytes())
    (DIST / "SHA256SUMS.txt").write_text(f"{archive_hash}  {archive.name}\n", encoding="ascii")
    (DIST / "PACKAGE-MANIFEST.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({"zip": str(archive), "files": len(manifest_files),
                      "size_MiB": round(archive.stat().st_size / 1048576, 2),
                      "sha256": archive_hash, "installed_packages": len(packages)}, indent=2))


if __name__ == "__main__":
    main()
