// Consistency gate, not an execution attestation or security boundary.
public static class YaEvidence {
  static string S(System.Collections.Generic.IDictionary<string, object> d, string k) {
    object v; return d != null && d.TryGetValue(k, out v) ? System.Convert.ToString(v, System.Globalization.CultureInfo.InvariantCulture) : "";
  }
  public static string Identity(string pkg) {
    using (var h = System.Security.Cryptography.SHA256.Create())
      return System.BitConverter.ToString(h.ComputeHash(System.Text.Encoding.UTF8.GetBytes(System.IO.Path.GetFullPath(pkg).TrimEnd('\\').ToLowerInvariant()))).Replace("-", "").ToLowerInvariant();
  }
  // Short work dir id (12 hex) keeps task paths well under Windows MAX_PATH; an existing full-length dir is still honoured.
  static string WorkDir(string baseDir, string slot, string pkg) {
    string full = Identity(pkg);
    string longDir = System.IO.Path.Combine(baseDir, slot, full);
    if (System.IO.Directory.Exists(longDir)) return longDir;
    return System.IO.Path.Combine(baseDir, slot, full.Substring(0, 12));
  }
  public static string Work(string pkg, string slot) {
    if (!System.Text.RegularExpressions.Regex.IsMatch(slot, "^[a-z][a-z0-9_-]{0,31}$") || slot == "all" || slot == "generic") throw new System.ArgumentException("slot= must be a dedicated slot id");
    string marker = System.IO.Path.Combine(pkg, "包信息.json");
    if (System.IO.File.Exists(marker) && S(Read(marker), "stage") == "UserWorkspace") {
      string parent = System.IO.Directory.GetParent(pkg).FullName;
      // ASCII artifacts avoids GBK/UTF-8 path corruption across pipes and native bridges.
      string ascii = WorkDir(System.IO.Path.Combine(parent, "artifacts"), slot, pkg);
      string legacy = System.IO.Path.Combine(parent, "成果", slot, Identity(pkg));
      if (System.IO.Directory.Exists(ascii) || !System.IO.Directory.Exists(legacy)) return ascii;
      return legacy;
    }
    string root = System.Environment.GetEnvironmentVariable("LOCALAPPDATA");
    if (System.Text.RegularExpressions.Regex.IsMatch(root, @"[^\x00-\x7F]")) root = System.Environment.GetEnvironmentVariable("ProgramData");
    return WorkDir(System.IO.Path.Combine(root, "YALink", "work"), slot, pkg);
  }

  // Bridge/DLL used for SoftOn must live under this package or its managed workspace (or be generated this run under Work()).
  public static string AssertLocalBridge(string pkg, string bridgePath) {
    if (string.IsNullOrWhiteSpace(bridgePath)) return "bridge-path-required";
    string full = System.IO.Path.GetFullPath(bridgePath);
    if (!System.IO.File.Exists(full)) return "bridge-missing";
    string pkgFull = System.IO.Path.GetFullPath(pkg).TrimEnd('\\');
    System.IO.DirectoryInfo parentInfo = System.IO.Directory.GetParent(pkgFull);
    string parent = parentInfo != null ? parentInfo.FullName.TrimEnd('\\') : pkgFull;
    string workAscii = System.IO.Path.Combine(parent, "artifacts");
    string workLegacy = System.IO.Path.Combine(parent, "成果");
    bool underPkg = full.StartsWith(pkgFull + "\\", System.StringComparison.OrdinalIgnoreCase);
    bool underWs = full.StartsWith(parent + "\\", System.StringComparison.OrdinalIgnoreCase)
      && (full.StartsWith(workAscii + "\\", System.StringComparison.OrdinalIgnoreCase)
       || full.StartsWith(workLegacy + "\\", System.StringComparison.OrdinalIgnoreCase)
       || full.IndexOf("\\工作区\\", System.StringComparison.OrdinalIgnoreCase) >= 0
       || full.IndexOf("\\连接教练\\", System.StringComparison.OrdinalIgnoreCase) >= 0);
    if (underPkg || underWs) return "";
    return "foreign-bridge-refused";
  }
  public static System.Collections.Generic.Dictionary<string, object> Read(string path) {
    return new System.Web.Script.Serialization.JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string, object>>(System.IO.File.ReadAllText(path, System.Text.Encoding.UTF8));
  }
  public static string Hash(string path) {
    using (var h = System.Security.Cryptography.SHA256.Create())
      return System.BitConverter.ToString(h.ComputeHash(System.IO.File.ReadAllBytes(path))).Replace("-", "");
  }
  static System.DateTime Time(string s) { return System.DateTime.Parse(s, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime(); }
  [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
  static extern bool GetNamedPipeServerProcessId(Microsoft.Win32.SafeHandles.SafePipeHandle pipe, out uint pid);
  // One bounded UTF-8 JSONL exchange. Never retry a software action after an unknown result.
  public static System.Collections.Generic.Dictionary<string,object> SendMessage(string name, int pid, string start, System.Collections.Generic.Dictionary<string,object> message, int timeoutMs) {
    if (!System.Text.RegularExpressions.Regex.IsMatch(name,"^ngxz-ya-[a-f0-9]{32}$") || timeoutMs<1 || timeoutMs>1800000)
      throw new System.ArgumentException("INVALID_CHANNEL_ARGUMENT");
    foreach (string key in new string[]{"protocol","action","request"}) if (S(message,key)=="") throw new System.ArgumentException("MESSAGE_FIELD_REQUIRED: "+key);
    if (!System.Text.RegularExpressions.Regex.IsMatch(S(message,"request"),"^[a-f0-9]{32}$")) throw new System.ArgumentException("INVALID_REQUEST");
    var proc=System.Diagnostics.Process.GetProcessById(pid);
    if (proc.StartTime.ToUniversalTime().Ticks.ToString()!=start) throw new System.InvalidOperationException("SOFTWARE_SESSION_CHANGED");
    var serializer=new System.Web.Script.Serialization.JavaScriptSerializer();
    var utf8=new System.Text.UTF8Encoding(false,true);
    byte[] bytes=utf8.GetBytes(serializer.Serialize(message)+"\n");
    if (bytes.Length>262144) throw new System.ArgumentException("MESSAGE_TOO_LARGE");
    var clock=System.Diagnostics.Stopwatch.StartNew();
    using (var pipe=new System.IO.Pipes.NamedPipeClientStream(".",name,System.IO.Pipes.PipeDirection.InOut,System.IO.Pipes.PipeOptions.Asynchronous)) {
      pipe.Connect(timeoutMs);
      uint owner;
      if (!GetNamedPipeServerProcessId(pipe.SafePipeHandle,out owner) || owner!=(uint)pid) throw new System.InvalidOperationException("WRONG_CHANNEL_PROCESS");
      int remaining=timeoutMs-(int)clock.ElapsedMilliseconds;
      using (var data=new System.IO.MemoryStream()) {
        var buffer=new byte[4096]; bool done=false;
        // Arm the first read before writing to avoid duplex deadlock with push-style bridges.
        var read=pipe.ReadAsync(buffer,0,buffer.Length);
        remaining=timeoutMs-(int)clock.ElapsedMilliseconds;
        if (remaining<1 || !pipe.WriteAsync(bytes,0,bytes.Length).Wait(remaining)) throw new System.TimeoutException("CHANNEL_WRITE_UNKNOWN: do not resend");
        while (data.Length<262144) {
          remaining=timeoutMs-(int)clock.ElapsedMilliseconds;
          if (remaining<1) throw new System.TimeoutException("CHANNEL_READ_UNKNOWN: do not resend");
          if (!read.Wait(remaining)) throw new System.TimeoutException("CHANNEL_READ_UNKNOWN: do not resend");
          if (read.Result==0) throw new System.IO.EndOfStreamException("INCOMPLETE_CHANNEL_FRAME");
          for (int j=0;j<read.Result;j++) {
            if (buffer[j]==10) { done=true; break; }
            if (data.Length>=262144) throw new System.IO.InvalidDataException("CHANNEL_FRAME_TOO_LARGE");
            data.WriteByte(buffer[j]);
          }
          if (done) break;
          read=pipe.ReadAsync(buffer,0,buffer.Length);
        }
        if (!done) throw new System.IO.InvalidDataException("CHANNEL_FRAME_TOO_LARGE");
        var reply=serializer.Deserialize<System.Collections.Generic.Dictionary<string,object>>(utf8.GetString(data.ToArray()));
        // Surface the bridge's own error text (R8: a NullReferenceException inside the bridge surfaced only as WRONG_REPLY_protocol).
        string rawReply=utf8.GetString(data.ToArray()); if (rawReply.Length>800) rawReply=rawReply.Substring(0,800);
        string bridgeError=S(reply,"error"); if (bridgeError=="") bridgeError=S(reply,"message");
        foreach (string key in new string[]{"protocol","action","request"}) if (S(reply,key)!=S(message,key)) throw new System.IO.InvalidDataException("WRONG_REPLY_"+key+(bridgeError!=""?" bridge_error="+bridgeError:"")+" raw_reply="+rawReply);
        if (message.ContainsKey("nonce") && S(reply,"nonce")!=S(message,"nonce")) throw new System.IO.InvalidDataException("WRONG_REPLY_nonce");
        proc.Refresh();
        if (proc.HasExited || proc.StartTime.ToUniversalTime().Ticks.ToString()!=start) throw new System.InvalidOperationException("SOFTWARE_SESSION_CHANGED");
        return reply;
      }
    }
  }
  // Bind the endpoint to the actual GUI process, rather than a PID copied into JSON.
  // This is not protection against code injection or an untrusted in-process adapter.
  static string CheckChannel(System.Collections.Generic.IDictionary<string, object> r, int pid, string start, bool registered, bool requireObjects=true) {
    string name=S(r,"probe_pipe");
    if (!System.Text.RegularExpressions.Regex.IsMatch(name,"^ngxz-ya-[a-f0-9]{32}$")) return "live-channel-required";
    if (S(r,"document_id").Trim()=="" || S(r,"document_path").Trim()=="") return "active-document-required";
    try {
      using (var pipe=new System.IO.Pipes.NamedPipeClientStream(".",name,System.IO.Pipes.PipeDirection.InOut,System.IO.Pipes.PipeOptions.Asynchronous)) {
        pipe.Connect(500);
        uint owner;
        if (!GetNamedPipeServerProcessId(pipe.SafePipeHandle,out owner) || owner!=(uint)pid) return "wrong-channel-process";
        // HUD liveness checks do not request software actions or wait on its UI thread.
        if (registered) return "";
        for (int i=0;i<2;i++) {
          string request=System.Guid.NewGuid().ToString("N");
          var query=new System.Collections.Generic.Dictionary<string,object>();
          query["protocol"]="ngxz-ya/session-probe/1"; query["action"]="QUERY_SESSION"; query["request"]=request;
          var serializer=new System.Web.Script.Serialization.JavaScriptSerializer();
          var utf8=new System.Text.UTF8Encoding(false,true);
          byte[] bytes=utf8.GetBytes(serializer.Serialize(query)+"\n");
          // Arm read before write so a push-style server cannot deadlock the client; one frame per probe.
          var data=new System.IO.MemoryStream(); var clock=System.Diagnostics.Stopwatch.StartNew(); bool done=false;
          byte[] buffer=new byte[4096];
          var read=pipe.ReadAsync(buffer,0,buffer.Length);
          if (!pipe.WriteAsync(bytes,0,bytes.Length).Wait(1500)) return "channel-write-timeout";
          while (data.Length<16384 && clock.ElapsedMilliseconds<1500) {
            if (!read.Wait(System.Math.Max(1,1500-(int)clock.ElapsedMilliseconds))) return "channel-read-timeout";
            if (read.Result==0) return "channel-closed";
            for (int j=0;j<read.Result;j++) {
              if (buffer[j]==10) { done=true; break; }
              if (data.Length>=16384) return "invalid-channel-response";
              data.WriteByte(buffer[j]);
            }
            if (done) break;
            read=pipe.ReadAsync(buffer,0,buffer.Length);
          }
          if (!done) return "invalid-channel-response";
          var reply=serializer.Deserialize<System.Collections.Generic.Dictionary<string,object>>(utf8.GetString(data.ToArray()));
          if (S(reply,"protocol")!="ngxz-ya/session-probe/1" || S(reply,"request")!=request) return "wrong-channel-request";
          if (S(reply,"pid")!=pid.ToString(System.Globalization.CultureInfo.InvariantCulture) || S(reply,"process_start")!=start) return "wrong-channel-identity";
          if (S(reply,"document_id")!=S(r,"document_id") || !System.String.Equals(S(reply,"document_path"),S(r,"document_path"),System.StringComparison.OrdinalIgnoreCase)) return "wrong-active-document";
          int count;
          if (!int.TryParse(S(reply,"object_count"),out count) || count<(requireObjects?1:0) || S(reply,"can_execute").ToLowerInvariant()!="true") return "software-channel-not-ready";
        }
      }
      return "";
    } catch (System.TimeoutException) { return "channel-unavailable"; }
      catch (System.UnauthorizedAccessException) { return "channel-access-denied"; }
      catch { return "invalid-channel-evidence"; }
  }
  class LiveState { public string Result; public System.DateTime Next; public int Delay; public System.DateTime Task; }
  static readonly System.Collections.Generic.Dictionary<string,LiveState> live=new System.Collections.Generic.Dictionary<string,LiveState>();
  // HUD liveness (R8: the panel reconnected every ~1.6 s and flooded the bridge log). Connect once after registration and
  // again only when a new task request appears (operation_request.json changes); failures back off 2 s -> 4 -> ... -> 30 s.
  // Process exit/restart is still detected every poll without touching the pipe (CheckCore checks the process first).
  static string LiveChannel(System.Collections.Generic.IDictionary<string,object> r, int pid, string start, string io) {
    string key=S(r,"probe_pipe")+"|"+pid.ToString(System.Globalization.CultureInfo.InvariantCulture)+"|"+start;
    System.DateTime task=System.DateTime.MinValue;
    try { string f=System.IO.Path.Combine(System.IO.Path.GetDirectoryName(io.TrimEnd('\\')),"operation_request.json"); if (System.IO.File.Exists(f)) task=System.IO.File.GetLastWriteTimeUtc(f); } catch {}
    var now=System.DateTime.UtcNow; LiveState st;
    lock (live) {
      if (live.TryGetValue(key,out st) && st.Task==task) {
        if (st.Result=="") return "";
        if (now<st.Next) return st.Result;
      }
    }
    string res=CheckChannel(r,pid,start,true);
    lock (live) {
      LiveState old; int delay=2000;
      if (live.TryGetValue(key,out old) && old.Task==task && old.Result!="" && res!="") delay=System.Math.Min(30000,System.Math.Max(2000,old.Delay*2));
      var ns=new LiveState(); ns.Result=res; ns.Next=now.AddMilliseconds(delay); ns.Delay=delay; ns.Task=task; live[key]=ns;
    }
    return res;
  }
  public static string Check(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link) {
    return CheckCore(pkg, io, link, false);
  }
  public static string CheckRegistered(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link) {
    if (S(link, "state") != "ok") return "not-registered";
    return CheckCore(pkg, io, link, true);
  }
  public static bool HasFrontendAcceptance(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link) {
    try {
      var acceptance = Read(System.IO.Path.Combine(io, "frontend-acceptance.json"));
      foreach (string key in new string[]{"package_id","slot","session","pid","process_start","readback_sha256"})
        if (S(link,key)=="" || S(acceptance,key)!=S(link,key)) return false;
      string request=S(acceptance,"request");
      if (!System.Text.RegularExpressions.Regex.IsMatch(request,"^[a-f0-9]{32}$")) return false;
      string job=System.IO.Path.Combine(Work(pkg,S(link,"slot")),request);
      string state=System.IO.Path.Combine(job,"request.json");
      var binding=Read(System.IO.Path.Combine(job,"frontend-session.json"));
      foreach (string key in new string[]{"session","pid","process_start"})
        if (S(binding,key)!=S(link,key)) return false;
      var result=Read(state);
      string methodPath=System.IO.Path.Combine(pkg,"连接教练","连接经验",S(link,"slot"),"方法.json");
      if (Hash(methodPath)!=S(result,"method_hash")) return false;
      var method=Read(methodPath);
      var frontend=method.ContainsKey("frontend") ? method["frontend"] as System.Collections.Generic.IDictionary<string,object> : null;
      string driver=S(method,"driver"), reader=frontend==null ? "" : S(frontend,"reader");
      string directory=System.IO.Path.GetDirectoryName(methodPath);
      if (!System.Text.RegularExpressions.Regex.IsMatch(driver,"^[A-Za-z0-9_-]+[.]ps1$") ||
          !System.Text.RegularExpressions.Regex.IsMatch(reader,"^[A-Za-z0-9_-]+[.]ps1$") ||
          Hash(System.IO.Path.Combine(directory,driver))!=S(method,"driver_sha256") ||
          Hash(System.IO.Path.Combine(directory,reader))!=S(frontend,"reader_sha256")) return false;
      if (method.ContainsKey("dependencies")) {
        var dependencies=method["dependencies"] as System.Collections.IEnumerable;
        if (dependencies==null) return false;
        foreach (var item in dependencies) {
          var dependency=item as System.Collections.Generic.IDictionary<string,object>;
          if (dependency==null || !System.IO.Path.IsPathRooted(S(dependency,"path")) ||
              Hash(S(dependency,"path"))!=S(dependency,"sha256")) return false;
        }
      }
      return S(result,"status")=="completed" && S(result,"mode")=="interactive" &&
        S(result,"request")==request && Hash(state)==S(acceptance,"state_sha256") &&
        Hash(System.IO.Path.Combine(job,"Verify.json"))==S(acceptance,"verify_sha256");
    } catch { return false; }
  }

  public static bool HasColdFastpathVerification(string pkg, string io, string slot) {
    try {
      var ev = Read(System.IO.Path.Combine(io, "fastpath-verified.json"));
      if (S(ev, "package_id") != Identity(pkg) || S(ev, "slot") != slot) return false;
      string cold = S(ev, "cold_start").Trim().ToLowerInvariant();
      if (cold != "true" && cold != "1") return false;
      if (S(ev, "result") != "OK") return false;
      string rel = S(ev, "card_file").Replace('/', '\\');
      if (rel == "" || rel.IndexOf("..", System.StringComparison.Ordinal) >= 0) return false;
      string cardPath = System.IO.Path.GetFullPath(System.IO.Path.Combine(pkg, rel));
      string root = System.IO.Path.GetFullPath(pkg).TrimEnd('\\') + "\\";
      if (!cardPath.StartsWith(root, System.StringComparison.OrdinalIgnoreCase)) return false;
      if (Hash(cardPath) != S(ev, "card_sha256")) return false;
      var card = Read(cardPath);
      string v = S(card, "v").Trim();
      if (v != "1") return false;
      if (S(card, "核验").Trim() == "") return false;
      return true;
    } catch { return false; }
  }
  public static bool HasFirstConnectComplete(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link) {
    try {
      if (!HasColdFastpathVerification(pkg, io, S(link, "slot"))) return false;
      if (HasFrontendAcceptance(pkg, io, link)) return true;
      var ev = Read(System.IO.Path.Combine(io, "fastpath-verified.json"));
      return S(ev, "pid") == S(link, "pid");
    } catch { return false; }
  }
  public static string CheckCommandChannel(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link) {
    string reason=CheckRegistered(pkg,io,link);
    if (reason!="") return reason;
    var r=Read(System.IO.Path.Combine(Work(pkg,S(link,"slot")),S(link,"session"),"readback.json"));
    return CheckChannel(r,int.Parse(S(link,"pid")),S(link,"process_start"),false,false);
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
      // SoftOn requires any recorded bridge/DLL path to be in-package or this-run workspace artifacts (never a foreign project path).
      foreach (string bk in new string[] { "bridge_path", "bridge", "adapter_path", "dll_path" }) {
        string bp = S(r, bk);
        if (bp == "") bp = S(link, bk);
        if (bp != "") {
          string refused = AssertLocalBridge(pkg, bp);
          if (refused != "") return refused;
        }
      }
      var proc = System.Diagnostics.Process.GetProcessById(int.Parse(S(c, "pid")));
      if (proc.HasExited || proc.StartTime.ToUniversalTime().Ticks.ToString() != S(c, "process_start")) return "wrong-process";
      if (S(link, "readback_sha256") != Hash(file)) return "changed-readback";
      return registered ? LiveChannel(r,proc.Id,S(c,"process_start"),io) : CheckChannel(r,proc.Id,S(c,"process_start"),false);
    } catch { return "missing-or-invalid-evidence"; }
  }
}

// Read-only discovery within this logon session; desktop access denial is not success.
public static class YaWindow {
  [System.Runtime.InteropServices.DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern System.IntPtr GetThreadDesktop(uint id);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern System.IntPtr GetProcessWindowStation();
  [System.Runtime.InteropServices.DllImport("user32.dll",CharSet=System.Runtime.InteropServices.CharSet.Unicode)] static extern bool GetUserObjectInformation(System.IntPtr h,int index,System.Text.StringBuilder text,int size,out uint needed);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern System.IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool GetWindowRect(System.IntPtr h,out Rect rect);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern System.IntPtr WindowFromPoint(Point point);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
  [System.Runtime.InteropServices.DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(System.IntPtr h,int attribute,out int value,int size);
  [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)] struct Rect {public int Left,Top,Right,Bottom;}
  [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)] struct Point {public int X,Y;}
  static string ObjectName(System.IntPtr h){uint needed;var text=new System.Text.StringBuilder(256);return GetUserObjectInformation(h,2,text,512,out needed)?text.ToString():"UNKNOWN";}
  public static string Desktop(){return ObjectName(GetProcessWindowStation())+"\\"+ObjectName(GetThreadDesktop(GetCurrentThreadId()));}
  public static string Quote(string value){var b=new System.Text.StringBuilder("\"");int slashes=0;foreach(char c in value){if(c=='\\'){slashes++;continue;}b.Append('\\',c=='"'?slashes*2+1:slashes);b.Append(c);slashes=0;}return b.Append('\\',slashes*2).Append('"').ToString();}
  [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential,CharSet=System.Runtime.InteropServices.CharSet.Unicode)] struct Startup {public int cb;public string reserved,desktop,title;public int x,y,w,h,xc,yc,fill,flags;public short show,extra;public System.IntPtr data,input,output,error;}
  [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)] struct ProcessInfo {public System.IntPtr process,thread;public int pid,tid;}
  [System.Runtime.InteropServices.DllImport("kernel32.dll",CharSet=System.Runtime.InteropServices.CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string exe,System.Text.StringBuilder args,System.IntPtr pa,System.IntPtr ta,bool inherit,uint flags,System.IntPtr env,string directory,ref Startup startup,out ProcessInfo info);
  [System.Runtime.InteropServices.DllImport("kernel32.dll")] static extern bool CloseHandle(System.IntPtr h);
  public static int LaunchInteractive(string exe,string[] args,string directory){
    var startup=new Startup();startup.cb=System.Runtime.InteropServices.Marshal.SizeOf(startup);startup.desktop="winsta0\\default";
    var line=new System.Text.StringBuilder(Quote(exe));foreach(string arg in args)line.Append(' ').Append(Quote(arg));
    ProcessInfo info;/* CREATE_BREAKAWAY_FROM_JOB|CREATE_NEW_PROCESS_GROUP so parent Agent job teardown cannot kill the GUI */if(!CreateProcess(exe,line,System.IntPtr.Zero,System.IntPtr.Zero,false,0x01000200,System.IntPtr.Zero,directory,ref startup,out info))throw new System.ComponentModel.Win32Exception(System.Runtime.InteropServices.Marshal.GetLastWin32Error(),"INTERACTIVE_DESKTOP_START_FAILED");
    CloseHandle(info.thread);CloseHandle(info.process);return info.pid;
  }
  // 用户看得见（2026-11-10 R10 修）：交互桌面、窗口可见、未最小化、未被系统隐藏(cloak)、在屏幕内有面积即可。
  // 不要求不被其它窗口遮挡、不要求置前：用户自己的聊天窗/浏览器盖在软件上面时软件依然算可见，也不为此抢前台或模拟键鼠。
  public static bool UserVisible(int pid,long handle){
    if(Desktop()!="WinSta0\\Default"||handle==0)return false;
    var window=new System.IntPtr(handle);uint owner;GetWindowThreadProcessId(window,out owner);if(owner!=(uint)pid)return false;
    int cloaked;Rect r;if(!IsWindowVisible(window)||IsIconic(window)||IsHungAppWindow(window)||DwmGetWindowAttribute(window,14,out cloaked,4)!=0||cloaked!=0||!GetWindowRect(window,out r))return false;
    int left=System.Math.Max(r.Left,GetSystemMetrics(76)),top=System.Math.Max(r.Top,GetSystemMetrics(77)),right=System.Math.Min(r.Right,GetSystemMetrics(76)+GetSystemMetrics(78)),bottom=System.Math.Min(r.Bottom,GetSystemMetrics(77)+GetSystemMetrics(79));
    return right-left>=24&&bottom-top>=24;
  }
  // 未被遮挡（更严）：只作提示记录，不作为验收条件。
  public static bool InputVisible(int pid,long handle){
    if(Desktop()!="WinSta0\\Default")return false;
    var desktop=OpenInputDesktop(0,false,0x41);if(desktop==System.IntPtr.Zero)return false;bool visible=false;
    try{
      EnumProc cb=delegate(System.IntPtr window,System.IntPtr unused){uint owner;GetWindowThreadProcessId(window,out owner);if(window.ToInt64()!=handle || owner!=(uint)pid)return true;
        int cloaked;Rect r;if(!IsWindowVisible(window)||IsIconic(window)||IsHungAppWindow(window)||DwmGetWindowAttribute(window,14,out cloaked,4)!=0||cloaked!=0||!GetWindowRect(window,out r))return false;
        int left=System.Math.Max(r.Left,GetSystemMetrics(76)),top=System.Math.Max(r.Top,GetSystemMetrics(77)),right=System.Math.Min(r.Right,GetSystemMetrics(76)+GetSystemMetrics(78)),bottom=System.Math.Min(r.Bottom,GetSystemMetrics(77)+GetSystemMetrics(79));
        if(right-left<24||bottom-top<24)return false;
        foreach(int x in new int[]{left+12,(left+right)/2,right-12})
          foreach(int y in new int[]{top+12,(top+bottom)/2,bottom-12}){
            uint at;GetWindowThreadProcessId(WindowFromPoint(new Point{X=x,Y=y}),out at);
            if(at==(uint)pid){visible=true;return false;}
          }
        return false;};
      EnumDesktopWindows(desktop,cb,System.IntPtr.Zero);return visible;
    }finally{CloseDesktop(desktop);}
  }
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern System.IntPtr GetForegroundWindow();
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetForegroundWindow(System.IntPtr h);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool BringWindowToTop(System.IntPtr h);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool ShowWindow(System.IntPtr h,int command);
  [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool AttachThreadInput(uint a,uint b,bool attach);
  public static bool Front(int pid){
    if(Desktop()!="WinSta0\\Default")return false;var window=Find(pid);if(window==System.IntPtr.Zero)return false;
    if(IsIconic(window))ShowWindow(window,9);
    uint owner,thread=GetWindowThreadProcessId(GetForegroundWindow(),out owner),mine=GetCurrentThreadId();bool attached=thread!=0&&thread!=mine&&AttachThreadInput(mine,thread,true);
    try{BringWindowToTop(window);SetForegroundWindow(window);}finally{if(attached)AttachThreadInput(mine,thread,false);}
    System.Threading.Thread.Sleep(200);return InputVisible(pid,window.ToInt64());
  }
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
