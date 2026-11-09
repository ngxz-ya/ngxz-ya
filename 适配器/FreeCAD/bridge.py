import ctypes
from ctypes import wintypes
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import re
import uuid
import FreeCAD as App
import FreeCADGui as Gui
try:
    from PySide import QtCore, QtNetwork
except ImportError:
    try:
        from PySide6 import QtCore, QtNetwork
    except ImportError:
        from PySide2 import QtCore, QtNetwork

root = Path(os.environ["YA_FREECAD_SESSION"])
config = json.loads((root / "bridge-config.json").read_text(encoding="utf-8-sig"))
io_dir = Path(config["io"])
work = Path(config["work"]).resolve()
pid = os.getpid()
kernel = ctypes.WinDLL("kernel32", use_last_error=True)
kernel.GetCurrentProcess.restype = wintypes.HANDLE
kernel.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
values = [wintypes.FILETIME() for _ in range(4)]
if not kernel.GetProcessTimes(kernel.GetCurrentProcess(), *(ctypes.byref(v) for v in values)):
    raise ctypes.WinError(ctypes.get_last_error())
start = str((values[0].dwHighDateTime << 32) + values[0].dwLowDateTime + 504911232000000000)
bridge_hash = hashlib.sha256((root / "FrontProbe.FCMacro").read_bytes()).hexdigest().upper()
version = ".".join(App.Version()[:3])
document = App.newDocument("YAOpenModel")
box = document.addObject("Part::Box", "VerifiedBox")
box.Length, box.Width, box.Height = 10, 12, 14
document.recompute()
document_path = str(root / "Active.FCStd")
document.saveAs(document_path)
Gui.activeDocument().activeView().viewAxonometric()
Gui.activeDocument().activeView().fitAll()
pipe_name = "ngxz-ya-" + uuid.uuid4().hex
server = QtNetwork.QLocalServer(Gui.getMainWindow())
server.setSocketOptions(QtNetwork.QLocalServer.UserAccessOption)
if not server.listen(pipe_name):
    raise RuntimeError(server.errorString())

def save_json(path, data):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def state():
    active = App.ActiveDocument
    is_test = active is not None and active.Name == document.Name and active.FileName == document_path and active.getObject(box.Name) is not None
    return {"pid": pid, "process_start": start, "document_id": active.Name if active else "",
            "document_path": active.FileName if active else "", "object_count": len(active.Objects) if active else 0,
            "can_execute": is_test}

def measure():
    bounds = box.Shape.BoundBox
    return [bounds.XLength, bounds.YLength, bounds.ZLength]

def dispatch(q):
    keys = ("protocol", "action", "request", "nonce")
    reply = {k: q[k] for k in keys if k in q}
    reply.update(state())
    try:
        if (q["protocol"], q["action"]) == ("ngxz-ya/session-probe/1", "QUERY_SESSION"):
            return reply
        if q["protocol"] != "ngxz-ya/frontend-task/1" or not reply["can_execute"]:
            raise ValueError("Wrong protocol or active document")
        reply.update(ok=True, software_version=version, bridge_sha256=bridge_hash)
        if q["action"] in ("Check", "Execute") and "steps" in q:
            steps = q["steps"]
            if len(steps) != 1 or steps[0].get("action") != "set_box":
                raise ValueError("Only the set_box operation is supported")
            request = q["request"]
            target = Path(q["output_path"]).resolve()
            if not re.fullmatch("[a-f0-9]{32}", request) or target.parent != work / request or target.name != "model.fcstd":
                raise ValueError("Output outside test request")
            marker = target.parent / "open-test-dispatch.json"
            if target.exists() or marker.exists():
                raise FileExistsError("Request already dispatched")
            dims = [float(q["parameters"][key]) for key in ("length", "width", "height")]
            if any(not math.isfinite(value) or not 1 <= value <= 1000 for value in dims):
                raise ValueError("Dimensions must be 1 to 1000 mm")
        if q["action"] == "Check":
            reply["status"] = "READY"
        elif q["action"] == "Execute":
            if "document_id" in q and (q["document_id"], q["document_path"]) != (reply["document_id"], reply["document_path"]):
                raise ValueError("Active document changed after preflight")
            before = measure()
            save_json(marker, {"pid": pid, "document": document.Name, "object": box.Name, "before": before})
            box.Length, box.Width, box.Height = dims
            document.recompute()
            Gui.activeDocument().activeView().fitAll()
            if not document.saveCopy(str(target)) and not target.is_file():
                raise OSError("Could not save the native document")
            reply.update(status="EXECUTED", saved_file=str(target), object_id=box.Name,
                         actual_before=before, actual_after=measure())
        else:
            raise ValueError("Unsupported test action")
    except Exception as exc:
        reply.update(ok=False, error=str(exc))
    return reply

def read_socket(sock):
    while sock.canReadLine():
        line = bytes(sock.readLine(65537))
        if len(line) > 65536 or not line.endswith(b"\n"):
            sock.abort()
            return
        try:
            reply = dispatch(json.loads(line))
        except Exception:
            sock.abort()
            return
        sock.write((json.dumps(reply) + "\n").encode("utf-8"))
        sock.flush()

def connect_clients():
    while server.hasPendingConnections():
        sock = server.nextPendingConnection()
        sock.setReadBufferSize(65537)
        sock.readyRead.connect(lambda s=sock: read_socket(s))
        sock.disconnected.connect(sock.deleteLater)
        read_socket(sock)

def publish_challenge():
    challenge = io_dir / "challenge.json"
    if not challenge.exists():
        return
    q = json.loads(challenge.read_text(encoding="utf-8-sig"))
    if q["pid"] != pid or q["process_start"] != start or not re.fullmatch("[a-f0-9]{32}", q["session"]):
        return
    target = work / q["session"] / "readback.json"
    if not target.parent.is_dir() or target.exists() or not state()["can_execute"]:
        return
    q.update(state(), channel="software", software_state="Active FreeCAD test document",
             probe_pipe=pipe_name, written_utc=now())
    save_json(target, q)

server.newConnection.connect(connect_clients)
timer = QtCore.QTimer(server)
timer.timeout.connect(publish_challenge)
timer.start(200)
save_json(root / "bridge-ready.json", dict(state(), pipe=pipe_name, version=version,
          bridge_sha256=bridge_hash, object_id=box.Name, dimensions=measure(), created_utc=now()))