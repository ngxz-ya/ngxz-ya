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
