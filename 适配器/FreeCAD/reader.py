import json
import os
from pathlib import Path
import FreeCAD as App

def measure(context):
    data = json.loads(Path(context).read_text(encoding="utf-8-sig"))
    doc = App.openDocument(data["model"])
    obj = doc.getObject("VerifiedBox")
    if obj is None or obj.TypeId != "Part::Box" or not obj.Shape.isValid():
        raise ValueError("Missing valid parametric solid")
    bounds = obj.Shape.BoundBox
    actual = {"length": bounds.XLength, "width": bounds.YLength, "height": bounds.ZLength,
              "body_count": len(obj.Shape.Solids)}
    return {"pid": os.getpid(), "version": ".".join(App.Version()[:3]),
            "model": doc.FileName, "measurements": actual}