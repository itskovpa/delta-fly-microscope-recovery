"""Archive only software sources, and derive hardware-free tests from the real controller."""
from pathlib import Path
import copy
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET

RECOVERY = Path(__file__).resolve().parent
ROOT = RECOVERY.parent
B = "{https://bonsai-rx.org/2018/workflow}"
XSI = "{http://www.w3.org/2001/XMLSchema-instance}type"
NS = {
    "": B[1:-1], "xsi": XSI[1:XSI.index("}")],
    "cv": "clr-namespace:Bonsai.Vision;assembly=Bonsai.Vision",
    "rx": "clr-namespace:Bonsai.Reactive;assembly=Bonsai.Core",
    "scr": "clr-namespace:Bonsai.Scripting.Expressions;assembly=Bonsai.Scripting.Expressions",
    "wie": "clr-namespace:Bonsai.Windows.Input;assembly=Bonsai.Windows.Input",
    "rec": "clr-namespace:Recovery;assembly=Recovery.Offline",
}
for prefix, uri in NS.items():
    ET.register_namespace(prefix, uri)


def software_files():
    for base in [ROOT, ROOT / "Bonsai", ROOT / "Bonsai/ImageSta", ROOT / "Bonsai/ImageSta/extensions"]:
        if not base.is_dir():
            continue
        for p in base.iterdir():
            if p.is_file() and (p.name.endswith((".bonsai", ".bonsai.layout", ".cs", ".csproj"))):
                yield p


def make_combinator(type_name, properties=None):
    expr = ET.Element(B + "Expression", {XSI: "Combinator"})
    value = ET.SubElement(expr, B + "Combinator", {XSI: type_name})
    prefix = type_name.split(":")[0] if ":" in type_name else ""
    uri = "{" + NS[prefix] + "}"
    for name, text in (properties or {}).items():
        ET.SubElement(value, uri + name).text = str(text)
    return expr


def replace_combinator(expr, type_name, properties=None):
    expr.clear()
    replacement = make_combinator(type_name, properties)
    expr.attrib.update(replacement.attrib)
    expr.extend(list(replacement))


def offline_workflow(original, automatic):
    source = ET.parse(original).getroot().find(B + "Workflow/" + B + "Nodes")
    commands, tracker = copy.deepcopy(source[35]), copy.deepcopy(source[36])
    ET.SubElement(tracker, B + "Name").text = "Tracking"
    tracking = tracker.find(B + "Workflow")
    nodes = tracking.find(B + "Nodes")
    # Drop the disabled legacy FLIR source chain; only camera index 0 was active.
    for item in list(nodes)[:3]:
        nodes.remove(item)
    for edge in list(tracking.find(B + "Edges")):
        a, z = int(edge.get("From")), int(edge.get("To"))
        if a < 3 or z < 3:
            tracking.find(B + "Edges").remove(edge)
        else:
            edge.set("From", str(a - 3))
            edge.set("To", str(z - 3))
    replace_combinator(nodes[0], "rec:SyntheticFly", {"FrameCount": 80 if automatic else 0})
    if automatic:
        command_nodes = commands.find(B + "Workflow/" + B + "Nodes")
        replace_combinator(command_nodes[3], "rec:AutomaticStop")
        replace_combinator(command_nodes[21], "rec:AutomaticStart")
        # Finite self-test: wire the two extracted processing groups directly.
        # The historical named subjects intentionally remain live until stopped.
        command_nodes[2].clear()
        command_nodes[2].set(XSI, "WorkflowInput")
        ET.SubElement(command_nodes[2], B + "Name").text = "Source1"
        command_nodes[23].clear()
        command_nodes[23].set(XSI, "Disable")
        ET.SubElement(command_nodes[23], B + "Builder", {XSI: "Combinator"}).append(ET.Element(B + "Combinator", {XSI: "rx:Skip"}))
        nodes[25].clear()
        nodes[25].set(XSI, "WorkflowOutput")
        nodes.remove(nodes[26])
        for edge in list(tracking.find(B + "Edges")):
            if edge.get("From") == "25":
                tracking.find(B + "Edges").remove(edge)
    root = ET.Element(B + "WorkflowBuilder", {"Version": "2.7.1"})
    graph = ET.SubElement(root, B + "Workflow")
    output = ET.SubElement(graph, B + "Nodes")
    if automatic:
        output.extend([tracker, commands, make_combinator("rec:CommandProbe", {"Verify": "true"})])
    else:
        output.append(make_combinator("StringProperty", {"Value": "OFFLINE_ONLY"}))
        initial = ET.SubElement(output, B + "Expression", {XSI: "rx:BehaviorSubject"})
        ET.SubElement(initial, B + "Name").text = "Command"
        output.extend([commands, tracker])
        subscription = ET.SubElement(output, B + "Expression", {XSI: "SubscribeSubject"})
        ET.SubElement(subscription, B + "Name").text = "Command"
        output.append(make_combinator("rec:CommandProbe", {"Verify": "false"}))
    edges = ET.SubElement(graph, B + "Edges")
    for a, z in ([(0, 1), (1, 2)] if automatic else [(0, 1), (4, 5)]):
        ET.SubElement(edges, B + "Edge", {"From": str(a), "To": str(z), "Label": "Source1"})
    # QName-valued attributes need declarations even when no element uses that prefix.
    used_uris = {element.tag[1:].split("}")[0] for element in root.iter() if element.tag.startswith("{")}
    for prefix in ["cv", "rx", "scr", "rec"] + ([] if automatic else ["wie"]):
        if NS[prefix] not in used_uris:
            root.set("xmlns:" + prefix, NS[prefix])
    serialized = ET.tostring(root, encoding="unicode")
    for prohibited in ["CameraCapture", "MvCamCtrlCapture", "SpinnakerCapture", "SerialString", "CreateSerialPort", "CsvWriter", "VideoWriter", "G28", "G01 Z"]:
        assert prohibited not in serialized, prohibited
    ET.indent(root, space="  ")
    return ET.ElementTree(root)


def camera_check_workflow(original):
    source = ET.parse(original).getroot().find(B + "Workflow/" + B + "Nodes")
    tracker = copy.deepcopy(source[36])
    ET.SubElement(tracker, B + "Name").text = "Camera Tracking Check"
    tracking = tracker.find(B + "Workflow")
    nodes = tracking.find(B + "Nodes")
    # Remove the disabled legacy Spinnaker source chain; CameraCapture index 0 is active.
    for item in list(nodes)[:3]:
        nodes.remove(item)
    edges = tracking.find(B + "Edges")
    for edge in list(edges):
        a, z = int(edge.get("From")), int(edge.get("To"))
        if a < 3 or z < 3:
            edges.remove(edge)
        else:
            edge.set("From", str(a - 3))
            edge.set("To", str(z - 3))

    # The tracker outputs the centroid's X/Y error from image center here.
    output = nodes[25]
    output.clear()
    output.set(XSI, "WorkflowOutput")
    ET.SubElement(output, B + "Name").text = "CenteredXYErrorPx"
    nodes.remove(nodes[26])
    for edge in list(edges):
        if edge.get("From") == "25":
            edges.remove(edge)

    camera = nodes[0].find(B + "Combinator")
    assert camera is not None and camera.get(XSI) == "cv:CameraCapture"
    camera_index = camera.find("{" + NS["cv"] + "}Index")
    assert camera_index is not None and camera_index.text == "0"
    serialized = ET.tostring(tracker, encoding="unicode")
    for prohibited in ["SpinnakerCapture", "CreateSerialPort", "SerialString", "SerialPort",
                       "CsvWriter", "VideoWriter", "Keyboard", "KeyDown", "KeyUp",
                       "G28", "G01", "COM19"]:
        assert prohibited.casefold() not in serialized.casefold(), prohibited
    for required in ["ThresholdValue", "163", "MinArea", "20", "Centroid",
                     "Item1-(it.Item2/2)", "CenteredXYErrorPx"]:
        assert required in serialized, required

    root = ET.Element(B + "WorkflowBuilder", {"Version": "2.7.1"})
    ET.SubElement(root, B + "Description").text = "Camera-only tracking check; centered X/Y error in pixels."
    graph = ET.SubElement(root, B + "Workflow")
    output_nodes = ET.SubElement(graph, B + "Nodes")
    output_nodes.append(tracker)
    ET.SubElement(graph, B + "Edges")
    ET.indent(root, space="  ")
    return ET.ElementTree(root)


def main():
    manifest = []
    sources = sorted(software_files()) if (ROOT / "DeltaX2Move2PashaModifyed_Last_3cameras.bonsai").is_file() else []
    for file in sources:
        relative = file.relative_to(ROOT)
        destination = RECOVERY / "originals" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() and destination.read_bytes() != file.read_bytes():
            raise RuntimeError(f"Original snapshot differs; refusing to overwrite {relative}")
        shutil.copy2(file, destination)
        row = {"path": relative.as_posix(), "bytes": file.stat().st_size,
               "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
        if file.suffix == ".bonsai":
            tree = ET.parse(file)
            row["bonsai_version"] = tree.getroot().get("Version")
            row["xml_valid"] = True
            row["edge_errors"] = []
            for graph in tree.iter(B + "Workflow"):
                count = len(graph.find(B + "Nodes"))
                for edge in graph.find(B + "Edges"):
                    if not (0 <= int(edge.get("From")) < count and 0 <= int(edge.get("To")) < count):
                        row["edge_errors"].append(edge.attrib)
        manifest.append(row)
    if sources:
        (RECOVERY / "source-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    else:
        # A standalone clone uses the committed originals, without the surrounding lab folder.
        manifest = json.loads((RECOVERY / "source-manifest.json").read_text(encoding="utf-8"))
        for row in manifest:
            archived = RECOVERY / "originals" / row["path"]
            if hashlib.sha256(archived.read_bytes()).hexdigest() != row["sha256"]:
                raise RuntimeError(f"Archived source checksum changed: {row['path']}")
    baseline = RECOVERY / "originals/DeltaX2Move2PashaModifyed_Last_3cameras.bonsai"
    latest = RECOVERY / "originals/Bonsai/ImageSta/DeltaX2Move2PashaModifyed_Last_3cameras.bonsai"
    for name, automatic, original in [("Offline-SelfTest.bonsai", True, baseline),
                                      ("Offline-SelfTest-Apr13.bonsai", True, latest),
                                      ("Offline-Demo.bonsai", False, latest)]:
        offline_workflow(original, automatic).write(RECOVERY / "offline" / name, encoding="utf-8", xml_declaration=True)
    controller = RECOVERY / "controller"
    controller.mkdir(exist_ok=True)
    (controller / "recordings").mkdir(exist_ok=True)
    original_text = latest.read_text(encoding="utf-8-sig")
    old_path = r"C:\Users\itsko\OneDrive\Desktop\deltarobot\commands.csv"
    assert original_text.count(old_path) == 1
    (controller / "Delta-Controller.bonsai").write_text(original_text.replace(old_path, r"recordings\commands.csv"), encoding="utf-8")
    shutil.copy2(Path(str(latest) + ".layout"), controller / "Delta-Controller.bonsai.layout")
    camera_check_workflow(latest).write(controller / "Camera-Tracking-Check.bonsai", encoding="utf-8", xml_declaration=True)
    print(f"Archived {len(manifest)} software files. Created controller copy, three hardware-free workflows, and a camera-only check.")


if __name__ == "__main__":
    main()
