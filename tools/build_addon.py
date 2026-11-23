"""Build physically isolated release/developer ZIPs from explicit source regions."""
from pathlib import Path
import argparse
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "WarbandPvP"
VERSION = "0.7.10"
PRODUCTION = ["Model.lua", "Theme.lua", "Windows.lua", "Scope.lua", "ReportChannel.lua", "ReportTransport.lua",
              "Presence.lua", "SessionLog.lua", "WarbandProtocol.lua", "Warbands.lua", "Finder.lua",
              "Scouting.lua", "ScoutingUI.lua", "WarbandUI.lua", "UI.lua", "Help.lua", "Activity.lua", "Map.lua", "MapPins.xml", "Report.lua", "AutoReports.lua",
              "Notifications.lua", "Core.lua", "Bindings.xml", "README.txt", "CHANGELOG.txt", "LICENSE.txt"]
DEVELOPMENT = ["Diagnostics.lua", "DamageDiagnostics.lua", "Control.lua", "WarbandSimulation.lua", "Development.lua", "WARBAND_TESTING.txt", "DAMAGE_TESTING.txt"]

def compile_lua(text, flavor):
    output, depth = [], 0
    for number, line in enumerate(text.splitlines(), 1):
        token = line.strip()
        if token == "--@dev":
            depth += 1
        elif token == "--@enddev":
            depth -= 1
            if depth < 0:
                raise ValueError(f"Unmatched development boundary at {number}")
        elif token.startswith("--@release "):
            if depth:
                raise ValueError(f"Release alternative inside development region at {number}")
            if flavor == "release":
                output.append(line[:len(line)-len(line.lstrip())] + token[len("--@release "):])
        elif not depth or flavor == "dev":
            output.append(line)
    if depth:
        raise ValueError("Unclosed development region")
    return "\n".join(output) + "\n"

def build(flavor="release"):
    if flavor not in ("release", "dev"):
        raise ValueError("Unknown build flavor")
    version = VERSION + ("-dev" if flavor == "dev" else "")
    files = PRODUCTION.copy()
    if flavor == "dev":
        index = files.index("Core.lua")
        files[index:index] = DEVELOPMENT
    files += [p.relative_to(SOURCE).as_posix() for p in sorted((SOURCE / "Media").glob("Campaign*.tga"))]
    data = {}
    for relative in files:
        path = SOURCE / relative
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Missing/unsafe build input: {relative}")
        if path.suffix == ".lua":
            data[relative] = compile_lua(path.read_text(encoding="utf-8"), flavor).encode()
        elif path.suffix in (".txt", ".xml", ".toc"):
            # Stable archives across Windows development and Linux Actions runners.
            data[relative] = path.read_text(encoding="utf-8").encode()
        else:
            data[relative] = path.read_bytes()
    toc = ["## Interface: 16001", "## Title: TotalWarcraft" + (" (Developer)" if flavor == "dev" else ""),
           "## Notes: Form parties to seek out world PvP or rally your faction against enemy attacks.",
           "## X-Curse-Project-ID: 1819796",
           "## Author: TotalWarcraft", "## Version: " + version,
           "## Dependencies: Blizzard_MapCanvas", "## OptionalDeps: OpenMap",
           "## SavedVariables: WarbandPvPDB" + (", WarbandPvPDiagnosticsDB" if flavor == "dev" else ""), "Build.lua"]
    toc += [f for f in files if f.endswith((".lua", ".xml")) and f != "Bindings.xml"]
    data["Build.lua"] = f'local _, A = ...\nA.release = "{version}"\nA.buildFlavor = "{flavor}"\n'.encode()
    data["WarbandPvP.toc"] = ("\n".join(toc) + "\n").encode()
    out = ROOT / "releases" / f"TotalWarcraft-{VERSION}-{flavor}"
    stage = out / "WarbandPvP"
    stage.mkdir(parents=True, exist_ok=True)
    for old in stage.rglob("*"):
        if old.is_file() and old.relative_to(stage).as_posix() not in data:
            old.unlink()
    for relative, content in data.items():
        target = stage / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    archive = out.parent / (out.name + ".zip")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for relative, content in sorted(data.items()):
            entry = zipfile.ZipInfo("WarbandPvP/" + relative, (2026, 11, 20, 0, 0, 0))
            entry.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(entry, content)
    manifest = {"flavor": flavor, "version": version, "zip": str(archive),
                "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                "files": {p: hashlib.sha256(b).hexdigest() for p, b in sorted(data.items())}}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return stage, manifest

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--flavor", choices=["release", "dev", "both"], default="both")
    args = parser.parse_args()
    for flavor in (["release", "dev"] if args.flavor == "both" else [args.flavor]):
        _, manifest = build(flavor)
        print(json.dumps({k: v for k, v in manifest.items() if k != "files"}))
