# -*- coding: utf-8 -*-
# ngxz-ya FreeCAD 常驻连接（在 FreeCAD 前台窗口里运行）。
# 做法：GUI 线程上一个 0.2 秒定时器查收件箱 inbox\*.json，在前台文档里执行命令，
# 重算并刷新视图，从模型实读尺寸写回 outbox\<id>.json，同时写 运行数据\状态.json 给 YA 显示。
# 只用本机文件，不开网络端口。由 一键连接.ps1 启动：FreeCAD.exe fc_link.py
import os, re, json, time, math, traceback, io
import FreeCAD as App
import FreeCADGui as Gui
import Part
try:
    from PySide import QtCore
except ImportError:
    from PySide2 import QtCore

VERSION = "1.0"
RUN = os.environ.get("NGXZ_RUN") or os.path.join(os.getcwd(), "运行数据")
IO = os.path.join(RUN, "FreeCAD")
INBOX, OUTBOX = os.path.join(IO, "inbox"), os.path.join(IO, "outbox")
for d in (INBOX, OUTBOX):
    if not os.path.isdir(d):
        os.makedirs(d)
SW = "FreeCAD " + ".".join(App.Version()[:3])
PID = os.getpid()
LAST = {"动作": "", "实读": "", "结果": "", "时间": ""}


def now():
    return time.strftime("%Y-%m-%d %H:%M:%S")


def wjson(path, obj):
    tmp = path + ".tmp"
    with io.open(tmp, "w", encoding="utf-8") as f:
        f.write(json.dumps(obj, ensure_ascii=False, indent=1))
    os.replace(tmp, path)


def log(msg):
    try:
        with io.open(os.path.join(IO, "host.log"), "a", encoding="utf-8") as f:
            f.write("%s [pid=%d] %s\n" % (now(), PID, msg))
    except Exception:
        pass


def doc():
    d = App.ActiveDocument
    if d is None:
        d = App.newDocument("ngxz")
        d.UndoMode = 1
    return d


def nums(p):
    """'1,2,3' / '1 2 3' / '1x2x3' / [1,2,3] -> [1.0,2.0,3.0]"""
    if isinstance(p, (list, tuple)):
        return [float(x) for x in p]
    if isinstance(p, (int, float)):
        return [float(p)]
    return [float(x) for x in re.split(r"[,\s x×*]+", str(p).strip()) if x]


def V(p, default=(0, 0, 0)):
    if p is None:
        p = default
    p = nums(p)
    return App.Vector(*[float(x) for x in p])


def solids(d=None):
    d = d or doc()
    out = []
    for o in d.Objects:
        try:
            vis = o.ViewObject.Visibility if o.ViewObject else True
        except Exception:
            vis = True
        if vis and hasattr(o, "Shape") and not o.Shape.isNull() and o.Shape.Solids and not o.TypeId.startswith("App::"):
            out.append(o)
    return out


def target(name=None):
    d = doc()
    if name:
        o = d.getObject(name) or (d.getObjectsByLabel(name) or [None])[0]
        if o is None:
            raise ValueError("找不到对象 %s；用 fc.ps1 status 看对象名" % name)
        return o
    s = solids(d)
    if not s:
        raise ValueError("当前文档没有实体")
    return s[-1]


def r3(x):
    return round(float(x), 4)


def measure(name=None):
    o = target(name)
    sh = o.Shape
    bb = sh.BoundBox
    cyl, cones, planes = {}, [], {}
    for f in sh.Faces:
        s = f.Surface
        t = type(s).__name__
        if t == "Cylinder":
            # 法向朝轴外=外圆，朝轴内=内孔
            u0, u1, v0, v1 = f.ParameterRange
            p = f.valueAt((u0 + u1) / 2, (v0 + v1) / 2)
            n = f.normalAt((u0 + u1) / 2, (v0 + v1) / 2)
            c = s.Center
            ax = s.Axis
            radial = (p - c) - ax * ((p - c).dot(ax))
            kind = "外圆" if radial.dot(n) > 0 else "内孔"
            key = (kind, r3(2 * s.Radius), tuple(r3(abs(a)) for a in ax))
            cyl.setdefault(key, []).append([r3(c.x), r3(c.y), r3(c.z)])
        elif t == "Cone":
            rs = [e.Curve.Radius for e in f.Edges if type(e.Curve).__name__ == "Circle"]
            fb = f.BoundBox
            cones.append({"半角": r3(abs(math.degrees(s.SemiAngle))), "径向": r3(max(rs) - min(rs)) if rs else None,
                          "轴向": r3(fb.ZLength), "大径": r3(2 * max(rs)) if rs else None, "面积": r3(f.Area)})
        elif t == "Plane":
            n = f.normalAt(0, 0)
            ax = max(range(3), key=lambda i: abs(n[i]))
            if abs(abs(n[ax]) - 1) < 1e-6:
                k = "XYZ"[ax]
                planes.setdefault(k, set()).add(r3(f.CenterOfMass[ax]))
    edges_c = sorted({r3(2 * e.Curve.Radius) for e in sh.Edges if type(e.Curve).__name__ == "Circle"})
    return {
        "对象": o.Name, "类型": o.TypeId,
        "包围盒": [r3(bb.XLength), r3(bb.YLength), r3(bb.ZLength)],
        "最小点": [r3(bb.XMin), r3(bb.YMin), r3(bb.ZMin)],
        "体积": r3(sh.Volume), "面数": len(sh.Faces), "棱数": len(sh.Edges),
        "实体数": len(sh.Solids), "有效": bool(sh.isValid()),
        "圆柱面": [{"类别": k[0], "直径": k[1], "轴向": list(k[2]), "中心": v[:4]} for k, v in sorted(cyl.items())],
        "锥面(倒角)": cones,
        "平面位置": {k: sorted(v) for k, v in planes.items()},
        "圆棱直径": edges_c,
    }


def short(m):
    b = m["包围盒"]
    s = "%s×%s×%s mm · %d 面 · 体积 %s" % (fmt(b[0]), fmt(b[1]), fmt(b[2]), m["面数"], fmt(m["体积"]))
    holes = [c["直径"] for c in m["圆柱面"] if c["类别"] == "内孔"]
    if holes:
        s += " · 孔 Ø" + "/Ø".join(fmt(h) for h in holes)
    return s


def fmt(x):
    x = float(x)
    return ("%d" % x) if abs(x - round(x)) < 1e-6 else ("%.3f" % x).rstrip("0").rstrip(".")


def refresh(first=False):
    d = doc()
    d.recompute()
    try:
        gd = Gui.getDocument(d.Name)
        Gui.ActiveDocument = gd
        v = gd.activeView()
        if first:
            v.viewIsometric()
        v.fitAll()
    except Exception:
        pass
    Gui.updateGui()


def expect_check(m, exp, tol):
    bad = []
    if "bbox" in exp:
        want = nums(exp["bbox"])
        got = sorted(m["包围盒"]) if exp.get("any_order") else m["包围盒"]
        if exp.get("any_order"):
            want = sorted(want)
        for w, g in zip(want, got):
            if abs(w - g) > tol:
                bad.append("包围盒 要 %s 实读 %s" % (want, m["包围盒"]))
                break
    for k, key in (("volume", "体积"), ("faces", "面数"), ("solids", "实体数")):
        if k in exp and abs(float(exp[k]) - float(m[key])) > (tol if k == "volume" else 0.5):
            bad.append("%s 要 %s 实读 %s" % (key, exp[k], m[key]))
    return bad


# ---------------------------------------------------------------- 命令
def c_ping(a):
    return {"软件": SW, "pid": PID, "连接版本": VERSION}


def c_status(a):
    d = App.ActiveDocument
    objs = []
    if d:
        for o in d.Objects:
            item = {"名": o.Name, "标签": o.Label, "类型": o.TypeId}
            for p in ("Length", "Width", "Height", "Radius", "Size"):
                if hasattr(o, p):
                    try:
                        item[p] = fmt(getattr(o, p).Value)
                    except Exception:
                        pass
            objs.append(item)
    r = {"软件": SW, "pid": PID, "文档": d.Name if d else "", "文件": d.FileName if d else "", "对象": objs}
    if d and solids(d):
        r["实读"] = measure()
    return r


def c_new(a):
    d = App.newDocument(a.get("name") or "ngxz")
    d.UndoMode = 1
    App.setActiveDocument(d.Name)
    return {"文档": d.Name}


def c_box(a):
    d = doc()
    first = not solids(d)
    d.openTransaction("box")
    o = d.addObject("Part::Box", a.get("name") or "Box")
    o.Length, o.Width, o.Height = float(a["L"]), float(a["W"]), float(a["H"])
    o.Placement.Base = V(a.get("at"))
    d.commitTransaction()
    refresh(first)
    return {"新对象": o.Name}


def c_cyl(a):
    d = doc()
    first = not solids(d)
    d.openTransaction("cyl")
    o = d.addObject("Part::Cylinder", a.get("name") or "Cylinder")
    o.Radius = float(a["D"]) / 2.0
    o.Height = float(a["H"])
    o.Placement = App.Placement(V(a.get("at")), App.Rotation(App.Vector(0, 0, 1), V(a.get("dir"), (0, 0, 1))))
    d.commitTransaction()
    refresh(first)
    return {"新对象": o.Name}


def c_set(a):
    d = doc()
    o = target(a["obj"])
    d.openTransaction("set")
    old = getattr(o, a["prop"])
    val = a["value"]
    try:
        val = float(val)
    except Exception:
        pass
    setattr(o, a["prop"], val)
    d.commitTransaction()
    refresh()
    try:
        old = fmt(old.Value)
    except Exception:
        old = str(old)
    return {"对象": o.Name, "属性": a["prop"], "原值": old, "新值": fmt(val) if isinstance(val, float) else val}


def _cut(base, tool, name):
    d = doc()
    c = d.addObject("Part::Cut", name)
    c.Base, c.Tool = base, tool
    for x in (base, tool):
        try:
            x.ViewObject.Visibility = False
        except Exception:
            pass
    return c


def c_hole(a):
    """通孔：沿 Z（或 dir）从实体外穿到外，圆柱求差。x,y 为孔心。"""
    d = doc()
    base = target(a.get("obj"))
    bb = base.Shape.BoundBox
    dia = float(a["D"])
    d.openTransaction("hole")
    t = d.addObject("Part::Cylinder", "HoleTool")
    t.Radius = dia / 2.0
    depth = a.get("depth")
    if depth is None:
        t.Height = bb.ZLength + 2.0
        z0 = bb.ZMin - 1.0
    else:
        t.Height = float(depth)
        z0 = bb.ZMax - float(depth)
    t.Placement.Base = App.Vector(float(a.get("x", (bb.XMin + bb.XMax) / 2)), float(a.get("y", (bb.YMin + bb.YMax) / 2)), z0)
    c = _cut(base, t, a.get("name") or "Hole")
    d.commitTransaction()
    refresh()
    return {"新对象": c.Name, "孔径": dia}


def pick_edges(sh, sel):
    bb = sh.BoundBox
    out = []
    for i, e in enumerate(sh.Edges, 1):
        z = [v.Point.z for v in e.Vertexes] or [e.CenterOfMass.z]
        circ = type(e.Curve).__name__ == "Circle"
        ok = False
        if sel == "all":
            ok = True
        elif sel == "top":
            ok = all(abs(v - bb.ZMax) < 1e-6 for v in z) and abs(e.CenterOfMass.z - bb.ZMax) < 1e-6
        elif sel == "bottom":
            ok = all(abs(v - bb.ZMin) < 1e-6 for v in z) and abs(e.CenterOfMass.z - bb.ZMin) < 1e-6
        elif sel == "vertical":
            ok = (not circ) and len(z) == 2 and abs(z[0] - z[1]) > 1e-6 and abs(e.Vertexes[0].Point.x - e.Vertexes[1].Point.x) < 1e-6 and abs(e.Vertexes[0].Point.y - e.Vertexes[1].Point.y) < 1e-6
        elif sel in ("outer", "inner") and circ:
            rs = [x.Curve.Radius for x in sh.Edges if type(x.Curve).__name__ == "Circle"]
            ok = abs(e.Curve.Radius - (max(rs) if sel == "outer" else min(rs))) < 1e-6
        elif sel == "circle":
            ok = circ
        if ok:
            out.append(i)
    return out


def _edge_op(a, kind):
    d = doc()
    base = target(a.get("obj"))
    sel = str(a.get("edges", "top")).strip()
    if re.fullmatch(r"[\d,\s]+", sel):
        ids = [int(x) for x in re.split(r"[,\s]+", sel) if x]
    else:
        ids = []
        for s in sel.split("+"):
            ids += [i for i in pick_edges(base.Shape, s) if i not in ids]
    if not ids:
        raise ValueError("没选到棱边：edges=%s" % sel)
    size = float(a["size"])
    d.openTransaction(kind)
    o = d.addObject("Part::Chamfer" if kind == "chamfer" else "Part::Fillet", a.get("name") or ("Chamfer" if kind == "chamfer" else "Fillet"))
    o.Base = base
    o.Edges = [(i, size, size) for i in ids]
    try:
        base.ViewObject.Visibility = False
    except Exception:
        pass
    d.commitTransaction()
    refresh()
    return {"新对象": o.Name, "棱边": ids, "尺寸": size}


def c_chamfer(a):
    return _edge_op(a, "chamfer")


def c_fillet(a):
    return _edge_op(a, "fillet")


def c_undo(a):
    d = doc()
    n = int(a.get("n", 1))
    for _ in range(n):
        d.undo()
    refresh()
    return {"撤回步数": n}


def c_clear(a):
    d = doc()
    d.openTransaction("clear")
    for o in list(d.Objects):
        try:
            d.removeObject(o.Name)
        except Exception:
            pass
    d.commitTransaction()
    refresh()
    return {"已清空": d.Name}


def _ann_group():
    d = doc()
    g = d.getObject("标注") or d.addObject("App::DocumentObjectGroup", "标注")
    g.Label = "标注"
    return g


def _dec(v):
    """数值要几位小数：19→0，1.5→1，0.25→2，最多 3 位。"""
    for k in range(4):
        if abs(round(v, k) - v) < 5e-4:
            return k
    return 3


def _style_dim(dm, val, pre, n, text=None):
    """统一标注样式：数值 (号)，不带单位，小数位跟数值走，字号按零件大小。"""
    vo = dm.ViewObject
    for k, v in (("ShowUnit", False), ("Decimals", _dec(val) if val is not None else 2)):
        try:
            setattr(vo, k, v)
        except Exception:
            pass
    try:
        bb = None
        for o in solids():
            bb = o.Shape.BoundBox if bb is None else bb.united(o.Shape.BoundBox)
        size = max(bb.XLength, bb.YLength, bb.ZLength) if bb else 50.0
        fs = max(1.0, min(8.0, size * 0.065))
        for k, v in (("FontSize", fs), ("ArrowSize", fs * 0.35), ("ArrowSizeStart", fs * 0.35), ("ArrowSizeEnd", fs * 0.35), ("ExtOvershoot", fs * 0.3), ("DimOvershoot", 0.0)):
            if hasattr(vo, k):
                try:
                    setattr(vo, k, v)
                except Exception:
                    pass
    except Exception:
        pass
    vo.Override = text if text else "%s$dim (%s)" % (pre, n)


def c_dim(a):
    """模型上标尺寸，文字统一显示 数值 (号)，如 ⌀19 (5)、1.5 (3)；不带 mm，小数位跟数值走，字号按零件大小。
    kind=len：p1 p2 两点距离（点从 measure 结果取），pre=⌀ 可加前缀（轴类侧视的直径）；kind=dia：直径，D= 选这个直径的圆棱（或 edge= 编号），数值由软件从圆棱实测。
    text= 可整段自定义（如 2×C0.5 (7)），但数值要来自实测。"""
    import Draft
    d = doc()
    n = a.get("n", "")
    at = V(a.get("at"))
    if a.get("kind", "len") == "dia":
        o = target(a.get("obj"))
        if a.get("edge"):
            ei = int(a["edge"])
        else:
            want = float(a["D"])
            cs = [(abs(2 * e.Curve.Radius - want), i) for i, e in enumerate(o.Shape.Edges, 1) if type(e.Curve).__name__ == "Circle"]
            if not cs:
                raise ValueError("没有圆棱")
            ei = min(cs)[1]
        dm = Draft.make_radial_dimension_obj(o, ei, "diameter", at)
        if dm is None:
            raise ValueError("第 %d 条棱不能标直径" % ei)
        pre = "⌀"
    else:
        dm = Draft.make_linear_dimension(V(a["p1"]), V(a["p2"]), at)
        pre = a.get("pre", "")
    _ann_group().addObject(dm)
    d.recompute()
    val = dm.Distance.Value if hasattr(dm, "Distance") else None
    try:
        _style_dim(dm, val, pre, n, a.get("text"))
    except Exception:
        pass
    refresh()
    shown = (a.get("text") or "%s%s (%s)" % (pre, ("%%.%df" % _dec(val)) % val if val is not None else "?", n))
    return {"标注": dm.Name, "号": n, "实测": r3(val) if val is not None else None, "显示": shown}


def c_py(a):
    """在前台 FreeCAD 里跑一段 Python。可用：App Gui Part doc measure target refresh result(dict) 以及 vars 里的变量。"""
    ns = {"App": App, "Gui": Gui, "Part": Part, "doc": doc(), "measure": measure, "target": target,
          "refresh": refresh, "V": V, "result": {}}
    for k, v in (a.get("vars") or {}).items():
        ns[k] = v
    d = doc()
    d.openTransaction("py")
    try:
        exec(compile(a["code"], "<fc.ps1 py>", "exec"), ns)
    finally:
        d.commitTransaction()
    refresh(bool(a.get("iso")))
    return {"result": ns["result"]}


def c_measure(a):
    m = measure(a.get("obj"))
    exp = {k: a[k] for k in ("bbox", "volume", "faces", "solids", "any_order") if k in a}
    r = {"实读": m}
    if exp:
        bad = expect_check(m, exp, float(a.get("tol", 0.01)))
        r["核对"] = "通过" if not bad else "不通过"
        r["差异"] = bad
    return r


def export_step(d, p):
    """把可见实体导出成 STEP，再从文件读回体积核对。"""
    objs = solids(d)
    if not objs:
        raise ValueError("没有可见实体可导出")
    p = os.path.abspath(p)
    if os.path.splitext(p)[1].lower() not in (".step", ".stp"):
        p += ".step"
    if not os.path.isdir(os.path.dirname(p)):
        os.makedirs(os.path.dirname(p))
    try:
        import Import
        Import.export(objs, p)
    except Exception:
        Part.export(objs, p)
    sh = Part.Shape()
    sh.read(p)
    return {"STEP": p, "实体数": len(objs), "读回体积": round(sh.Volume, 4),
            "模型体积": round(sum(o.Shape.Volume for o in objs), 4)}


def c_save(a):
    d = doc()
    p = a.get("path")
    if p and os.path.splitext(p)[1].lower() in (".step", ".stp"):
        return export_step(d, p)
    if p:
        d.saveAs(p)
    else:
        d.save()
    return {"文件": d.FileName}


def c_step(a):
    """导出 STEP：fc step path=成果\\零件\\零件.step（成果统一用 STEP）。"""
    return export_step(doc(), a["path"])


def c_shot(a):
    v = Gui.ActiveDocument.activeView()
    p = a["path"]
    v.saveImage(p, int(a.get("w", 1200)), int(a.get("h", 800)), "White")
    return {"截图": p}


def c_view(a):
    v = Gui.ActiveDocument.activeView()
    k = a.get("to", "iso")
    {"iso": v.viewIsometric, "top": v.viewTop, "front": v.viewFront, "right": v.viewRight}.get(k, v.viewIsometric)()
    v.fitAll()
    return {"视图": k}


def c_reload(a):
    """改了 fc_link.py 后重载（不用关 FreeCAD）。"""
    path = os.path.join(os.path.dirname(os.path.abspath(a.get("file") or __file__)), "fc_link.py") if "__file__" in globals() else a["file"]
    def go():
        App._ngxz_timer.stop()
        App._ngxz_timer = None
        exec(compile(io.open(path, encoding="utf-8").read(), path, "exec"), {"__file__": path, "__name__": "__main__"})
    QtCore.QTimer.singleShot(300, go)
    return {"重载": path}


CMDS = {"reload": c_reload, "ping": c_ping, "status": c_status, "new": c_new, "box": c_box, "cyl": c_cyl, "set": c_set,
        "hole": c_hole, "chamfer": c_chamfer, "fillet": c_fillet, "undo": c_undo, "clear": c_clear,
        "dim": c_dim, "py": c_py, "measure": c_measure, "save": c_save, "step": c_step, "shot": c_shot, "view": c_view}
CHANGES = {"new", "box", "cyl", "set", "hole", "chamfer", "fillet", "undo", "clear", "dim", "py"}
NAMES = {"box": "建方块", "cyl": "建圆柱", "set": "改尺寸", "hole": "打孔", "chamfer": "倒角", "fillet": "倒圆",
         "undo": "撤回", "clear": "清空", "dim": "标注", "py": "脚本建模", "new": "新文档"}


def write_state():
    s = {"软件": SW, "pid": PID, "心跳": time.time(), "文档": App.ActiveDocument.Name if App.ActiveDocument else "",
         "最近改模": LAST}
    try:
        wjson(os.path.join(RUN, "状态.json"), s)
    except Exception:
        pass


def handle(path):
    try:
        with io.open(path, "r", encoding="utf-8-sig") as f:
            job = json.load(f)
    except Exception:
        return  # 还没写完，下一轮再读
    os.remove(path)
    jid = job.get("id") or os.path.splitext(os.path.basename(path))[0]
    cmd = job.get("cmd", "ping")
    a = job.get("args") or {}
    t0 = time.time()
    rep = {"id": jid, "cmd": cmd, "ok": False}
    try:
        if cmd not in CMDS:
            raise ValueError("未知命令 %s；可用：%s" % (cmd, ", ".join(sorted(CMDS))))
        rep.update(CMDS[cmd](a))
        if cmd in CHANGES and solids():
            m = measure()
            rep["实读"] = m
            LAST.update({"动作": NAMES.get(cmd, cmd), "实读": short(m), "结果": "成功", "时间": now()})
        rep["ok"] = True
    except Exception as e:
        rep["error"] = "%s: %s" % (type(e).__name__, e)
        rep["trace"] = traceback.format_exc()[-1200:]
        if cmd in CHANGES:
            LAST.update({"动作": NAMES.get(cmd, cmd), "结果": "失败：" + str(e)[:60], "时间": now()})
        try:
            App.ActiveDocument and App.ActiveDocument.abortTransaction()
        except Exception:
            pass
    rep["耗时秒"] = round(time.time() - t0, 3)
    wjson(os.path.join(OUTBOX, jid + ".json"), rep)
    write_state()
    log("%s %s ok=%s" % (cmd, jid, rep["ok"]))


_beat = [0.0]


def tick():
    try:
        for n in sorted(os.listdir(INBOX)):
            if n.endswith(".json"):
                handle(os.path.join(INBOX, n))
        if time.time() - _beat[0] > 1.0:
            _beat[0] = time.time()
            write_state()
    except Exception as e:
        log("tick error " + str(e))


if getattr(App, "_ngxz_timer", None) is None:
    doc()
    _t = QtCore.QTimer()
    _t.timeout.connect(tick)
    _t.start(200)
    App._ngxz_timer = _t
    write_state()
    log("link up %s io=%s" % (SW, IO))
    App.Console.PrintMessage("ngxz-ya 连接已就绪：%s\n" % IO)
