// Consistency gate, not an execution attestation or security boundary.
public static class YaEvidence {
  static string S(System.Collections.Generic.IDictionary<string, object> d, string k) {
    object v; return d != null && d.TryGetValue(k, out v) ? System.Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture) : "";
  }
  public static string Identity(string pkg) {
    using (var h = System.Security.Cryptography.SHA256.Create())
      return System.BitConverter.ToString(h.ComputeHash(System.Text.Encoding.UTF8.GetBytes(System.IO.Path.GetFullPath(pkg).TrimEnd('\\').ToLowerInvariant()))).Replace("-", "").ToLowerInvariant();
  }
  public static string Work(string pkg, string slot) {
    if (!System.Text.RegularExpressions.Regex.IsMatch(slot, "^[a-z][a-z0-9_-]{0,31}$") || slot == "all" || slot == "generic") throw new System.ArgumentException("slot= must be a dedicated slot id");
    string marker = System.IO.Path.Combine(pkg, "包信息.json");
    if (System.IO.File.Exists(marker) && S(Read(marker), "stage") == "UserWorkspace")
      return System.IO.Path.Combine(System.IO.Directory.GetParent(pkg).FullName, "成果", slot, Identity(pkg));
    string root = System.Environment.GetEnvironmentVariable("LOCALAPPDATA");
    if (System.Text.RegularExpressions.Regex.IsMatch(root, @"[^\x00-\x7F]")) root = System.Environment.GetEnvironmentVariable("ProgramData");
    return System.IO.Path.Combine(root, "YALink", "work", slot, Identity(pkg));
  }
  public static System.Collections.Generic.Dictionary<string, object> Read(string path) {
    return new System.Web.Script.Serialization.JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string, object>>(System.IO.File.ReadAllText(path, System.Text.Encoding.UTF8));
  }
  public static string Hash(string path) {
    using (var h = System.Security.Cryptography.SHA256.Create())
      return System.BitConverter.ToString(h.ComputeHash(System.IO.File.ReadAllBytes(path))).Replace("-", "");
  }
  static System.DateTime Time(string s) { return System.DateTime.Parse(s, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime(); }
  public static string Check(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link) {
    return CheckCore(pkg, io, link, false);
  }
  public static string CheckRegistered(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link) {
    if (S(link, "state") != "ok") return "not-registered";
    return CheckCore(pkg, io, link, true);
  }
  static string CheckCore(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link, bool registered) {
    try {
      if (S(link, "package_id") != Identity(pkg)) return "wrong-package";
      string slot = S(link, "slot"), session = S(link, "session");
      if (!System.Text.RegularExpressions.Regex.IsMatch(session, "^[a-f0-9]{32}$")) return "missing-session";
      var c = Read(System.IO.Path.Combine(io, "challenge.json"));
      string dir = System.IO.Path.Combine(Work(pkg, slot), session);
      string file = System.IO.Path.Combine(dir, "readback.json");
      var r = Read(file);
      foreach (string k in new string[] { "package_id", "slot", "session", "nonce", "pid", "process_start" }) {
        if (S(c, k) == "" || S(c, k) != S(r, k) || S(c, k) != S(link, k)) return "mismatch-" + k;
      }
      var now = System.DateTime.UtcNow; var issued = Time(S(c, "issued_utc")); var read = Time(S(r, "written_utc"));
      string stamp = S(link, "registered_utc");
      // Older packages recorded local time rounded down to whole seconds.
      bool legacy = registered && stamp == "";
      var checkedAt = registered ? Time(legacy ? S(link, "time") : stamp) : now;
      if (checkedAt > now.AddSeconds(5) || read < issued || read > checkedAt.AddSeconds(legacy ? 1 : 0) ||
          (checkedAt - issued).TotalSeconds > 120 || System.IO.File.GetLastWriteTimeUtc(file) < issued) return "stale";
      if (S(r, "channel") != "software" || S(r, "software_state").Trim() == "") return "missing-software-state";
      var proc = System.Diagnostics.Process.GetProcessById(int.Parse(S(c, "pid")));
      if (proc.HasExited || proc.StartTime.ToUniversalTime().Ticks.ToString() != S(c, "process_start")) return "wrong-process";
      if (S(link, "readback_sha256") != Hash(file)) return "changed-readback";
      return "";
    } catch { return "missing-or-invalid-evidence"; }
  }
}

// Read-only discovery within this logon session; desktop access denial is not success.
public static class YaWindow {
  delegate bool EnumProc(System.IntPtr window, System.IntPtr param);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, System.IntPtr param);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool EnumDesktopWindows(System.IntPtr desktop, EnumProc callback, System.IntPtr param);
  [System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] static extern System.IntPtr OpenDesktop(string name, uint flags, bool inherit, uint access);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool CloseDesktop(System.IntPtr desktop);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(System.IntPtr window, out uint pid);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool IsWindowVisible(System.IntPtr window);
  [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr window);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool IsHungAppWindow(System.IntPtr window);
  [System.Runtime.InteropServices.DllImport("user32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode)] static extern int GetWindowText(System.IntPtr window, System.Text.StringBuilder text, int count);
  static string RawTitle(System.IntPtr window) { var text=new System.Text.StringBuilder(2048); GetWindowText(window,text,text.Capacity); return text.ToString(); }
  sealed class Info { public System.IntPtr Handle; public string Text=""; public bool Ready; }
  static Info Inspect(int pid, System.IntPtr target) {
    try {
      if (pid>0 && System.Diagnostics.Process.GetProcessById(pid).SessionId != System.Diagnostics.Process.GetCurrentProcess().SessionId) return new Info();
      Info found=new Info();
      EnumProc callback=delegate(System.IntPtr window,System.IntPtr unused) {
        uint owner; GetWindowThreadProcessId(window,out owner);
        string title=RawTitle(window); if ((target!=System.IntPtr.Zero ? window==target : owner==(uint)pid) && IsWindowVisible(window) && title.Length>0) { found.Handle=window; found.Text=title; found.Ready=!IsIconic(window) && !IsHungAppWindow(window); return false; }
        return true;
      };
      EnumWindows(callback,System.IntPtr.Zero);
      if (found.Handle!=System.IntPtr.Zero) return found;
      System.IntPtr desktop=OpenDesktop("Default",0,false,0x0041); // READOBJECTS | ENUMERATE
      if (desktop==System.IntPtr.Zero) return found;
      try { EnumDesktopWindows(desktop,callback,System.IntPtr.Zero); } finally { CloseDesktop(desktop); }
      return found;
    } catch { return new Info(); }
  }
  public static System.IntPtr Find(int pid) { return Inspect(pid,System.IntPtr.Zero).Handle; }
  public static string Title(System.IntPtr window) { return window==System.IntPtr.Zero ? "" : Inspect(0,window).Text; }
  public static bool Ready(int pid) { return Inspect(pid,System.IntPtr.Zero).Ready; }
}
