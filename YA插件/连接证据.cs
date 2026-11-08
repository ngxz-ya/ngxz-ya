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
      if (remaining<1 || !pipe.WriteAsync(bytes,0,bytes.Length).Wait(remaining)) throw new System.TimeoutException("CHANNEL_WRITE_UNKNOWN: do not resend");
      using (var data=new System.IO.MemoryStream()) {
        var buffer=new byte[4096]; bool done=false;
        while (data.Length<262144) {
          remaining=timeoutMs-(int)clock.ElapsedMilliseconds;
          if (remaining<1) throw new System.TimeoutException("CHANNEL_READ_UNKNOWN: do not resend");
          var read=pipe.ReadAsync(buffer,0,buffer.Length);
          // Wait on this exact read until completion; no abandoned concurrent readers consuming the frame.
          if (!read.Wait(remaining)) throw new System.TimeoutException("CHANNEL_READ_UNKNOWN: do not resend");
          if (read.Result==0) throw new System.IO.EndOfStreamException("INCOMPLETE_CHANNEL_FRAME");
          for (int j=0;j<read.Result;j++) {
            if (buffer[j]==10) { done=true; break; }
            if (data.Length>=262144) throw new System.IO.InvalidDataException("CHANNEL_FRAME_TOO_LARGE");
            data.WriteByte(buffer[j]);
          }
          if (done) break;
        }
        if (!done) throw new System.IO.InvalidDataException("CHANNEL_FRAME_TOO_LARGE");
        var reply=serializer.Deserialize<System.Collections.Generic.Dictionary<string,object>>(utf8.GetString(data.ToArray()));
        foreach (string key in new string[]{"protocol","action","request"}) if (S(reply,key)!=S(message,key)) throw new System.IO.InvalidDataException("WRONG_REPLY_"+key);
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
          byte[] bytes=System.Text.Encoding.UTF8.GetBytes(serializer.Serialize(query)+"\n");
          if (!pipe.WriteAsync(bytes,0,bytes.Length).Wait(1500)) return "channel-write-timeout";
          var data=new System.IO.MemoryStream(); var clock=System.Diagnostics.Stopwatch.StartNew(); bool done=false;
          byte[] buffer=new byte[1];
          while (data.Length<16384 && clock.ElapsedMilliseconds<1500) {
            var read=pipe.ReadAsync(buffer,0,1);
            if (!read.Wait(System.Math.Max(1,1500-(int)clock.ElapsedMilliseconds))) return "channel-read-timeout";
            if (read.Result==0) return "channel-closed";
            if (buffer[0]==10) { done=true; break; }
            data.WriteByte(buffer[0]);
          }
          if (!done) return "invalid-channel-response";
          var reply=serializer.Deserialize<System.Collections.Generic.Dictionary<string,object>>(System.Text.Encoding.UTF8.GetString(data.ToArray()));
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
  public static string Check(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link) {
    return CheckCore(pkg, io, link, false);
  }
  public static string CheckRegistered(string pkg, string io, System.Collections.Generic.IDictionary<string, object> link) {
    if (S(link, "state") != "ok") return "not-registered";
    return CheckCore(pkg, io, link, true);
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
      var proc = System.Diagnostics.Process.GetProcessById(int.Parse(S(c, "pid")));
      if (proc.HasExited || proc.StartTime.ToUniversalTime().Ticks.ToString() != S(c, "process_start")) return "wrong-process";
      if (S(link, "readback_sha256") != Hash(file)) return "changed-readback";
      return CheckChannel(r,proc.Id,S(c,"process_start"),registered);
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
    ProcessInfo info;if(!CreateProcess(exe,line,System.IntPtr.Zero,System.IntPtr.Zero,false,0x08000000,System.IntPtr.Zero,directory,ref startup,out info))throw new System.ComponentModel.Win32Exception(System.Runtime.InteropServices.Marshal.GetLastWin32Error(),"INTERACTIVE_DESKTOP_START_FAILED");
    CloseHandle(info.thread);CloseHandle(info.process);return info.pid;
  }
  public static bool InputVisible(int pid,long handle){
    if(Desktop()!="WinSta0\\Default")return false;
    var desktop=OpenInputDesktop(0,false,0x41);if(desktop==System.IntPtr.Zero)return false;bool visible=false;
    try{
      EnumProc cb=delegate(System.IntPtr window,System.IntPtr unused){uint owner;GetWindowThreadProcessId(window,out owner);if(window.ToInt64()!=handle || owner!=(uint)pid)return true;
        int cloaked;Rect r;if(!IsWindowVisible(window)||IsIconic(window)||IsHungAppWindow(window)||DwmGetWindowAttribute(window,14,out cloaked,4)!=0||cloaked!=0||!GetWindowRect(window,out r))return false;
        int left=System.Math.Max(r.Left,GetSystemMetrics(76)),top=System.Math.Max(r.Top,GetSystemMetrics(77)),right=System.Math.Min(r.Right,GetSystemMetrics(76)+GetSystemMetrics(78)),bottom=System.Math.Min(r.Bottom,GetSystemMetrics(77)+GetSystemMetrics(79));
        if(right-left<24||bottom-top<24)return false;
        foreach(int y in new int[]{top+12,(top+bottom)/2,bottom-12}){uint at;GetWindowThreadProcessId(WindowFromPoint(new Point{X=(left+right)/2,Y=y}),out at);if(at==(uint)pid){visible=true;break;}}
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
