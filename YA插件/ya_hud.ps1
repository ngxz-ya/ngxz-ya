# YA 状态小窗（白底卡）。开源包通用版：布局、TOKEN / 经验调用统计逻辑沿用旧 YA 白底卡，不绑定任何一家机械软件。第三块是「任务完成度」（2026-11-10 改）：面板只显示两项「经验 已调用/未调用」（search 或本任务有检索）与「结果 已核对/未核对」（inspect 独立读回），完成度按这两项+已验收三段计；compare/draft/claim 只留在流程日志，不在面板计分。原说明：读经验库 流程.json 当前任务的五项自检（search/compare/draft/claim/inspect）过了几项，已验收才算 100%（2026-11-04 由原合格率改）。
# 连接态只看 io\link.json（由同目录 ya_link.ps1 soft=软件名 pid=软件主窗口进程号 写入）：
#   两段（2026-11-10）：握手读回+登记通过即显示「已连接 · 软件」；当前登记会话通过 Connect 轻读回验收后显示「已验收 · 软件」。
#   本窗口不探测、不附着、不修改任何机械软件，只读文件。
# TOKEN：读 Agent 的 stdout 日志（Grok streaming-json usage / Codex / tokens used），日志路径来自 link.json 的 log 或环境变量 YALINK_USAGE_LOG。
# 经验调用（2026-11-05 分列）：消耗.json generic 槽 calls = 通用；当前已连软件槽 calls + 连接卡命中(io\card_hits.json) = 软件。数字旁写「次 · 通用x·软件y」。
# 经验库/新收：通用 = 经验库\槽\generic（索引+草稿）+ 经验库\通用技能库\索引.json；软件 = 经验库\槽\<当前已连软件槽>。写「通用x·软件y」，未连软件时软件侧「—」。连接没核对过（登记还在，但进程不在、未响应、窗口不可见、没有 pid、进程号读不了、state 不是 ok、槽号是 generic/all 或本包没有这个槽目录）时软件侧同样是「—」，不把残留 slot 算进去。槽号只是大小写不同，按小写槽计入。连接卡 hits 只进「软件调用」，不进任何库条数。
# 状态与计数放在 %LOCALAPPDATA%\YAHud（或 YALINK_HUD_HOME），不放经验库。经验库默认是本文件夹上一级的 经验库\。
# 右键：总计 / 重新计一次 / 全部重置 / 置顶 / 隐藏 / 退出；隐藏后在托盘（时钟旁 YA 图标）。位置记在 io\hud_pos.txt。
# 用法：
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File ya_hud.ps1            打开（已开着就不再开第二个）
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File ya_hud.ps1 -Show      把已开的小窗叫出来；没开就打开
#   powershell -NoProfile -STA -ExecutionPolicy Bypass -File ya_hud.ps1 -Preview   预览（独立互斥，不影响正式小窗）
# 关掉自动弹出：在运行目录建空文件 hud.off。测试用 -StatusFile（当作 link.json）/ -AgentFile / -StatsFile / -IndexFile。
# 必须是带 BOM 的 UTF-8。
param([Alias('SoftPid')][int]$NxPid, [switch]$Show, [string]$Home2 = '', [string]$StatusFile = '', [string]$AgentFile = '', [string]$StatsFile = '', [string]$IndexFile = '', [switch]$Preview)

$ErrorActionPreference = 'Stop'

# 软件无关：不按进程名找软件；连接态由 io\link.json 给出

$dir = $PSScriptRoot

. (Join-Path $dir '连接上下文.ps1') -PathsOnly
$Home2 = Get-YaPackageHudHome (Split-Path $dir -Parent) $Home2
if (-not (Test-Path -LiteralPath $Home2)) { New-Item -ItemType Directory -Path $Home2 -Force | Out-Null }

# 包路径 + HUD Home 定义实例；预览独立，不终止其它进程。
$lib = Join-Path (Split-Path $dir -Parent) '经验库'
Write-Output ('package: ' + (Split-Path $dir -Parent) + ' io=' + $Home2)

$io = Join-Path $Home2 'io'

if (-not (Test-Path -LiteralPath $io)) { New-Item -ItemType Directory -Path $io -Force | Out-Null }



Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Web.Extensions, System.Windows.Forms, System.Drawing

$refs = @([Windows.Window].Assembly.Location, [Windows.Media.Brush].Assembly.Location, [Windows.DependencyObject].Assembly.Location,

  [System.Xaml.XamlReader].Assembly.Location, [System.Web.Script.Serialization.JavaScriptSerializer].Assembly.Location,

  [System.Windows.Forms.NotifyIcon].Assembly.Location, [System.Drawing.Bitmap].Assembly.Location, [System.ComponentModel.Component].Assembly.Location)

$hudSource = @'

using System;

using System.Collections.Generic;

using System.Diagnostics;

using System.Globalization;

using System.Runtime.InteropServices;

using System.IO;

using System.Text;

using System.Windows;

using System.Windows.Controls;

using System.Windows.Input;

using System.Windows.Media;
using System.Windows.Media.Imaging;

using System.Windows.Media.Animation;

using System.Windows.Media.Effects;

using System.Windows.Shapes;

using System.Windows.Threading;

using System.Windows.Interop;

using System.Threading;

using System.Web.Script.Serialization;

using Path = System.Windows.Shapes.Path;

using WF = System.Windows.Forms;

using SD = System.Drawing;



public class YaCard : Window {
  public static string ShowEventName;

  static readonly CultureInfo IC = CultureInfo.InvariantCulture;

  // light product theme (white capsule): ink / secondary / hairline / soft fill
  static readonly Color Ink = Color.FromRgb(0x1F, 0x29, 0x37), Sub = Color.FromRgb(0x8B, 0x95, 0xA5), Line = Color.FromRgb(0xE8, 0xEC, 0xF2), Soft = Color.FromRgb(0xF6, 0xF8, 0xFB), Edge = Color.FromRgb(0xE1, 0xE6, 0xEE);
  static readonly Color OkBg = Color.FromRgb(0xEC, 0xFD, 0xF5), OkInk = Color.FromRgb(0x05, 0x96, 0x69), WarnBg = Color.FromRgb(0xFF, 0xF7, 0xED), WarnInk = Color.FromRgb(0xC2, 0x41, 0x0C);
  static readonly FontFamily NumFont = new FontFamily("Segoe UI, Microsoft YaHei UI");

  static readonly Color C1 = Color.FromRgb(0x38, 0xD5, 0xEC), C2 = Color.FromRgb(0x3B, 0x82, 0xF6);

  static readonly Color Ok = Color.FromRgb(0x22, 0xC5, 0x5E), Idle = Color.FromRgb(0xB9, 0xBF, 0xC8), Warn = Color.FromRgb(0xF5, 0x9E, 0x0B);

  const string IcLib = "M2,4.5 C2,2.6 5.6,1 10,1 C14.4,1 18,2.6 18,4.5 C18,6.4 14.4,8 10,8 C5.6,8 2,6.4 2,4.5 Z M2,4.5 L2,15.5 C2,17.4 5.6,19 10,19 C14.4,19 18,17.4 18,15.5 L18,4.5 M2,10 C2,11.9 5.6,13.5 10,13.5 C14.4,13.5 18,11.9 18,10";

  const string IcUse = "M11.5,1 L3,11.5 L9.5,11.5 L8,19 L17,7.5 L10.5,7.5 Z";

  const string IcTok = "M1.5,10 A8.5,8.5 0 1 1 18.5,10 A8.5,8.5 0 1 1 1.5,10 Z M6.5,5.5 L10,9.8 L13.5,5.5 M10,9.8 L10,15 M6.8,10.6 L13.2,10.6 M6.8,13 L13.2,13";

  const string IcNew = "M1.5,10 A8.5,8.5 0 1 1 18.5,10 A8.5,8.5 0 1 1 1.5,10 Z M10,5.5 L10,14.5 M5.5,10 L14.5,10";

  const string IcTime = "M1.5,10 A8.5,8.5 0 1 1 18.5,10 A8.5,8.5 0 1 1 1.5,10 Z M10,5 L10,10 L13.5,12.5";

  const string IcYen = "M1.5,10 A8.5,8.5 0 1 1 18.5,10 A8.5,8.5 0 1 1 1.5,10 Z M7,6.5 L10,10 L13,6.5 M10,10 L10,14.5 M6.8,11.2 L13.2,11.2";
  const string IcDim = "M2,16 L16,4 M5,13 L7,15 M8,10 L10,12 M11,7 L13,9";
  const string IcHit = "M3,10 L8,15 L17,4";
  const string IcRate = "M1.5,10 A8.5,8.5 0 1 1 18.5,10 A8.5,8.5 0 1 1 1.5,10 Z M7,13 L13,7";
  const string IcPend = "M3,16 L3,12 L12,3 L16,7 L7,16 Z";

  const double Gap = 900; // seconds without any tool call: the next call starts a new run



  int nxPid; Process nx;

  string ioDir, libDir, posPath, runPath, totPath, statusOv, agentOv, statsOv, indexOv, errLog;

  TextBlock vAll, vLib, vUse, vTokn, vTok, vTime, uAll, uLib, uUse, uTokn, uTok, uTime, state, closeX;
  TextBlock vRate, uRate, stripText, dSub, sLabel, sUnit, connText; Border connTag;
  FrameworkElement tAll, tLib, tUse, tTokn, tTok, tTime, tRate, lastRow;
  Border strip, detailTray; StackPanel detail;
  bool open, previewMode;
  int seenUse = -1; double seenTok = -1, shownTok;
  DateTime useAt, tokAt, dimAt;
  int dimDraw, dimHit, dimPend; double dimRate; bool dimKnown, dimPerfect; string dimReport = ""; DateTime mtDim = DateTime.MinValue;
  bool dimStale; string dimShort = "", dimKey = "", jPart = ""; DateTime mtJour = DateTime.MinValue; // dim row: stale/other-part guard

  Ellipse dot; TranslateTransform lift; Border cardFace; MenuItem miTop; WF.NotifyIcon tray; bool tipShown, quitting; EventWaitHandle showEv;

  DispatcherTimer poll; DateTime mtStats, mtIndex, mtAgent; bool posDirty, dragging;

  [DllImport("user32.dll")] static extern bool ReleaseCapture();

  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);

  [DllImport("gdi32.dll")] static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);

  [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);

  [DllImport("user32.dll", EntryPoint = "GetClassLongPtrW")] static extern IntPtr GetClassLongPtr64(IntPtr h, int i);

  [DllImport("user32.dll", EntryPoint = "SetClassLongPtrW")] static extern IntPtr SetClassLongPtr64(IntPtr h, int i, IntPtr v);

  [DllImport("user32.dll", EntryPoint = "GetClassLongW")] static extern int GetClassLong32(IntPtr h, int i);

  [DllImport("user32.dll", EntryPoint = "SetClassLongW")] static extern int SetClassLong32(IntPtr h, int i, int v);

  double lastStats, agentTime; Dictionary<string, object> stats;

  JavaScriptSerializer js = new JavaScriptSerializer();

  // library index

  string indexedPath = "";
  HashSet<string> libIds = new HashSet<string>(); int libN, libVer, libM, libK, libR; bool libKnown;
  // 2026-11-05 split: generic slot = general experience; current software slot + connection-card hits = software experience
  double genAbs, bGen; bool bGenOk; HashSet<string> genIds = new HashSet<string>(), bGenLib = new HashSet<string>();
  HashSet<string> IdxIds(string slot) { var ids = new HashSet<string>(); try { string dir = System.IO.Path.Combine(libDir, "\u69FD\\" + slot); string ix = System.IO.Path.Combine(dir, "\u7D22\u5F15.json");
    if (File.Exists(ix)) { var d = ReadJson(ix); object e; if (d != null && d.TryGetValue("entries", out e) && e is object[]) foreach (var o in (object[])e) { var en = o as Dictionary<string, object>; if (en == null) continue; string id = Str(en, "id"); ids.Add(id != "" ? id : ("#" + ids.Count)); } }
    string dr = System.IO.Path.Combine(dir, "_\u8349\u7A3F"); if (Directory.Exists(dr)) foreach (var df in Directory.GetFiles(dr, "*.json", SearchOption.AllDirectories)) ids.Add(System.IO.Path.GetFileNameWithoutExtension(df));
    if (slot == "generic") { string sk = System.IO.Path.Combine(libDir, "\u901A\u7528\u6280\u80FD\u5E93\\\u7D22\u5F15.json"); if (File.Exists(sk)) foreach (var ln in File.ReadAllLines(sk, Encoding.UTF8)) { if (!ln.StartsWith("{\"id\":\"")) continue; int q = ln.IndexOf((char)34, 7); if (q > 7) ids.Add("skill:" + ln.Substring(7, q - 7)); } } } catch { } return ids; }
  bool SoftOn() { return linkLast && HasLocalSlot(); }
  bool HasLocalSlot() {
    if (!linkSlotBound || linkSlot == "" || linkSlot == "generic" || linkSlot == "all" || linkSlot.Length > 32) return false;
    for (int i = 0; i < linkSlot.Length; i++) { char c = linkSlot[i]; if (i == 0 && (c < 'a' || c > 'z')) return false; if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' || c == '-')) return false; }
    try { return Directory.Exists(System.IO.Path.Combine(libDir, "\u69FD\\" + linkSlot)); } catch { return false; }
  }

  // this NX session (io\exp_stats.json): current values

  bool snap, cNoUse; string cSrc = "", cSw = "", cAgent = ""; double cUses, cReal, cEst, cDistinct, cTaskStart; HashSet<string> cIds = new HashSet<string>();

  double cIn, cCa, cOut;            // real split of this session's tokens: input cache miss, input cache hit, output

  double pIn = 1.08, pCa = 0.0216, pOut = 4.32; // CNY/1M = official USD($0.15/$0.003/$0.60)*7.2; exp_stats.json price wins when its unit is CNY

  // this run: values at its start, first and last activity

  bool runReady, bSplit, libRebase; double bUses, bReal, bEst, bIn, bCa, bOut, rAct, rLast; HashSet<string> bIds = new HashSet<string>(), bLib = new HashSet<string>();

  // totals on this computer (io\hud_totals.json)

  double tUses, tReal, tEst, tSec, tSince, tPid, tLU, tLR, tLE, tLact, tIn, tCa, tOut, tLI, tLC, tLO;

  Window totWin; StackPanel totBody; string totSig = "";
  // right-click "全部重置": display baseline for the whole-NX-session section (io\hud_reset.json); exp_stats.json itself is never touched
  bool zOn; double zUses, zIn, zCa, zOut, zEst, zReal, zT; string rstPath;



  static YaCard() { try { System.Windows.Media.RenderOptions.ProcessRenderMode = System.Windows.Interop.RenderMode.Default; } catch { } }

  public YaCard(int pid, string io, string lib, string sOv, string aOv, string tOv, string iOv, bool preview) {

    previewMode = preview; nxPid = pid; ioDir = io; libDir = lib; statusOv = sOv; agentOv = aOv; statsOv = tOv; indexOv = iOv;

    posPath = System.IO.Path.Combine(io, "hud_pos.txt"); errLog = System.IO.Path.Combine(io, "hud_error.log");

    runPath = System.IO.Path.Combine(io, "hud_run.json"); totPath = System.IO.Path.Combine(io, "hud_totals.json"); rstPath = System.IO.Path.Combine(io, "hud_reset.json");

    try { nx = Process.GetProcessById(pid); } catch { }

    Safe(LoadRun); Safe(LoadTot); Safe(LoadZ);

    // opaque window: a layered (AllowsTransparency) window is re-presented on every move = laggy drag

    Title = "YA"; WindowStyle = WindowStyle.None; AllowsTransparency = false; Background = new SolidColorBrush(Edge);

    ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; ShowActivated = false; SizeToContent = SizeToContent.WidthAndHeight;

    UseLayoutRounding = true; TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);

    FontFamily = new FontFamily("Microsoft YaHei UI, Microsoft YaHei, Segoe UI");



    // card: thin cyan-blue line at the top, white inside

    lift = new TranslateTransform();

    var card = cardFace = new Border { CornerRadius = new CornerRadius(14), Background = new LinearGradientBrush(C1, C2, 0), BorderBrush = new SolidColorBrush(Edge), BorderThickness = new Thickness(1) };

    var inner = new Border { CornerRadius = new CornerRadius(13, 13, 14, 14), Background = Brushes.White, Margin = new Thickness(0, 2, 0, 0), Padding = new Thickness(16, 9, 14, 10) };

    card.Child = inner;

    var root = new StackPanel(); inner.Child = root;
    System.Windows.Documents.TextElement.SetFontFamily(root, NumFont);
    System.Windows.Documents.TextElement.SetFontSize(root, 13);



    // YA word mark + "connected" tag + one summary (call / TOKEN / pass rate). Click the scene to expand; click again to collapse.
    state = new TextBlock { Visibility = Visibility.Collapsed };
    var barRow = new Grid { Width = 304, Height = 34 };
    barRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
    barRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
    barRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
    barRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
    var ya = new Grid { Height = 34, Background = Brushes.Transparent, Cursor = Cursors.SizeAll, ToolTip = "所属包：" + System.IO.Path.GetDirectoryName(libDir), Margin = new Thickness(0, 0, 9, 0) };
    var yaWord = new TextBlock {
      Text = "YA", FontSize=20, FontFamily=NumFont, FontWeight = FontWeights.Bold, Foreground = new LinearGradientBrush(C1, C2, 0),
      VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 1) };
    ya.Children.Add(yaWord);
    ya.MouseLeftButtonDown += (s, e) => { e.Handled = true; Drag(); };
    barRow.Children.Add(ya);
    dot = new Ellipse { Width = 6, Height = 6, Fill = new SolidColorBrush(Idle), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 1, 5, 0) };
    connText = new TextBlock { Text = "\u8fde\u63a5\u4e2d", FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center };
    connText.TextTrimming = TextTrimming.CharacterEllipsis;
    var tagRow = new DockPanel();
    DockPanel.SetDock(dot, Dock.Left);
    tagRow.Children.Add(dot); tagRow.Children.Add(connText);
    connTag = new Border { MaxWidth = 132, CornerRadius = new CornerRadius(10), Background = new SolidColorBrush(Soft), Padding = new Thickness(8, 2, 9, 3), VerticalAlignment = VerticalAlignment.Center, Child = tagRow, Cursor = Cursors.SizeAll };
    connTag.MouseLeftButtonDown += (s, e) => { e.Handled = true; Drag(); };
    Grid.SetColumn(connTag, 1);
    barRow.Children.Add(connTag);
    strip = new Border {
      Height = 34, Margin = new Thickness(8, 0, 2, 0),
      Background = Brushes.White,
      BorderBrush = new SolidColorBrush(Line), BorderThickness = new Thickness(1, 0, 0, 0),
      Cursor = Cursors.Hand, ClipToBounds = true,
      HorizontalAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Center,
      ToolTip = "\u5355\u51fb\u5c55\u5f00" };
    var sg = new DockPanel();
    sLabel = new TextBlock { Text = "\u8c03\u7528", FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center };
    var sv = new DockPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0) };
    stripText = new TextBlock {
      Text = "0", FontSize=19, FontWeight = FontWeights.Light, FontFamily = NumFont,
      Foreground = new SolidColorBrush(Ink), VerticalAlignment = VerticalAlignment.Center, TextAlignment = TextAlignment.Right,
      TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap };
    sUnit = new TextBlock { Text = "\u6b21", Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(3, 0, 0, 0) };
    DockPanel.SetDock(sUnit, Dock.Right);
    DockPanel.SetDock(sLabel, Dock.Left);
    sv.Children.Add(sUnit); sv.Children.Add(stripText);
    sg.Children.Add(sLabel); sg.Children.Add(sv);
    strip.Child = new Border { Padding = new Thickness(6, 0, 0, 0), Child = sg };
    strip.MouseLeftButtonDown += (s, e) => { e.Handled = true; };
    strip.MouseLeftButtonUp += (s, e) => { e.Handled = true; Toggle(); };
    Grid.SetColumn(strip, 2);
    barRow.Children.Add(strip);
    closeX = new TextBlock { Text = "\u2715", Foreground = new SolidColorBrush(Sub), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Opacity = 0, Cursor = Cursors.Hand, Margin = new Thickness(0), Padding = new Thickness(4), ToolTip = "\u9690\u85CF\u5230\u6258\u76D8" };
    closeX.MouseLeftButtonUp += (s, e) => { e.Handled = true; HideCard(); };
    closeX.MouseLeftButtonDown += (s, e) => { e.Handled = true; };
    Grid.SetColumn(closeX, 3);
    barRow.Children.Add(closeX);
    root.Children.Add(barRow);
    // expanded: three white cards of the same style (TOKEN / experience / pass rate) on a soft tray
    var tray0 = new Border { Background = new SolidColorBrush(Soft), CornerRadius = new CornerRadius(10), Padding = new Thickness(6, 6, 6, 0), Margin = new Thickness(-6, 10, -4, 0) };
    detail = new StackPanel { Width = 302, Visibility = Visibility.Collapsed };
    var tokBody = MkCard(detail, "TOKEN", "本次", out vTokn, out uTokn, "tok"); tTokn = lastRow;
    // Legacy computation fields stay available for details, without a visible TOKEN footer.
    vTok=new TextBlock();uTok=new TextBlock();tTok=new Border();vTime=new TextBlock();uTime=new TextBlock();tTime=new Border();
    var expBody = MkCard(detail, "经验调用", "本次", out vUse, out uUse, "\u6b21"); tUse = lastRow;
    Mini(expBody, "\u7ecf\u9a8c\u5e93", out vAll, out uAll, "\u6761"); tAll = lastRow;
    Mini(expBody, "\u65b0\u6536", out vLib, out uLib, "\u6761"); tLib = lastRow;
    foreach (var row in new FrameworkElement[] { tAll, tUse, tLib, tTokn }) {
      row.Cursor = Cursors.Hand;
      row.MouseLeftButtonUp += (s, e) => { e.Handled = true; if(row==tTokn) ShowUsageDetails(); else ShowActualDetails(); };
    }
    var rateBody = MkCard(detail, "任务完成度", "本次任务", out vRate, out uRate, "%"); tRate = lastRow;
    dSub = new TextBlock { Text = "", Foreground = new SolidColorBrush(Sub), Margin = new Thickness(0, 3, 0, 0), TextWrapping = TextWrapping.Wrap };
    rateBody.Children.Add(dSub);
    tray0.Child = detail;
    tray0.Visibility = Visibility.Collapsed; detailTray = tray0;
    root.Children.Add(tray0);



    Content = card;

    // Win32 caption drag (ReleaseCapture + WM_NCLBUTTONDOWN/HTCAPTION): refresh and file reads pause until the button is released

    // round window region (skipped while dragging)

    card.MouseEnter += (s, e) => Hover(true);

    card.MouseLeave += (s, e) => Hover(false);

    LocationChanged += (s, e) => { if (!dragging) posDirty = true; };

    Closing += (s, e) => { SavePos(); if (totWin != null) { try { totWin.Close(); } catch { } } };

    Closed += (s, e) => { quitting = true; try { if (tray != null) { tray.Visible = false; tray.Dispose(); } } catch { } };



    var miTot = new MenuItem { Header = "\u603B\u8BA1\u2026" }; miTot.Click += (s, e) => Safe(ShowTotals);

    var miNew = new MenuItem { Header = "刷新" }; miNew.Click += (s, e) => Safe(() => { ForceRefresh(); Show4(); if (totWin != null) FillTotals(); });

    var miReset = new MenuItem { Header = "重置统计…" };
    miReset.Click += (s, e) => Safe(ShowReset);
    miTop = new MenuItem { Header = "\u7F6E\u9876", IsCheckable = true };

    miTop.Click += (s, e) => { Topmost = miTop.IsChecked; SavePos(); };

    var miHide = new MenuItem { Header = "\u9690\u85CF\u5230\u6258\u76D8" }; miHide.Click += (s, e) => HideCard();

    var miClose = new MenuItem { Header = "\u9000\u51FA" }; miClose.Click += (s, e) => Close();

    var cm = new ContextMenu(); Safe(() => StyleMenu(cm)); cm.Items.Add(miTot); cm.Items.Add(miNew); cm.Items.Add(miReset); cm.Items.Add(new Separator()); cm.Items.Add(miTop); cm.Items.Add(miHide); cm.Items.Add(miClose); card.ContextMenu = cm;

    Safe(MakeTray);
    ContentRendered += (s, e) => Safe(ConfirmShown);

    try { showEv = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);

      var th = new Thread(() => { while (!quitting) { try { if (showEv.WaitOne(1000) && !quitting) Dispatcher.BeginInvoke(new Action(ShowCard)); } catch { return; } } }) { IsBackground = true }; th.Start(); } catch { }



    // position: last place, else near the top right of the work area

    double x = double.NaN, y = double.NaN; bool top = true;

    try { var a = File.ReadAllText(posPath).Trim().Split(','); x = double.Parse(a[0], IC); y = double.Parse(a[1], IC); if (a.Length > 2) top = a[2] == "1"; if (a.Length < 4) { x += 18; y += 14; } } catch { }

    var wa = SystemParameters.WorkArea;

    if (double.IsNaN(x) || x < SystemParameters.VirtualScreenLeft - 50 || x > SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth - 80 || y < SystemParameters.VirtualScreenTop - 20 || y > SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight - 60) { x = wa.Right - 400; y = wa.Top + 70; }

    WindowStartupLocation = WindowStartupLocation.Manual; Left = x; Top = y; Topmost = top; miTop.IsChecked = top;



    poll = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };

    poll.Tick += (s, e) => { if (!dragging) Safe(Poll); };

    poll.Start();

    Loaded += (s, e) => { Safe(Fit); Safe(Round); Safe(DropShadowClass); Safe(Poll); }; SizeChanged += (s, e) => { if (!dragging) Safe(Round); };

  }



  // drag: Windows' own move loop on an opaque window (no WPF redraw while moving); refresh and the breathing dot pause until release

  // classic Win32 caption drag: Windows runs its own move loop and returns when the button is released

  void Drag() {

    if (dragging) return;

    dragging = true; poll.Stop();

    try { var h = new WindowInteropHelper(this).Handle; ReleaseCapture(); SendMessage(h, 0xA1 /* WM_NCLBUTTONDOWN */, new IntPtr(2) /* HTCAPTION */, IntPtr.Zero); } catch { }

    dragging = false; posDirty = false; SavePos(); poll.Start();

    Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() => { if (!dragging) Safe(Poll); }));

  }

  // rounded corners for the opaque window (region in device pixels) and the light system drop shadow

  void Round() {

    if (dragging) return;

    var src = PresentationSource.FromVisual(this) as HwndSource; if (src == null) return;

    var m = src.CompositionTarget.TransformToDevice;

    int w = (int)Math.Round(ActualWidth * m.M11), h = (int)Math.Round(ActualHeight * m.M22), r = (int)Math.Round(28 * m.M11);

    SetWindowRgn(src.Handle, CreateRoundRectRgn(0, 0, w + 1, h + 1, r, r), true);

  }

  void DropShadowClass() {

    var h = new WindowInteropHelper(this).Handle; const int GCL_STYLE = -26, CS_DROPSHADOW = 0x20000;

    if (IntPtr.Size == 8) SetClassLongPtr64(h, GCL_STYLE, new IntPtr(GetClassLongPtr64(h, GCL_STYLE).ToInt64() | CS_DROPSHADOW));

    else SetClassLong32(h, GCL_STYLE, GetClassLong32(h, GCL_STYLE) | CS_DROPSHADOW);

  }

  // tray icon (near the clock): click = show / hide; right-click = show / hide / exit

  void MakeTray() {

    // 2026-11-05 维护者定：托盘/窗口小图标用白底黑字 YA（不用蓝底）
    var bmp = new SD.Bitmap(32, 32); IntPtr hIcon = IntPtr.Zero; using (var g = SD.Graphics.FromImage(bmp)) {

      g.SmoothingMode = SD.Drawing2D.SmoothingMode.AntiAlias; g.TextRenderingHint = SD.Text.TextRenderingHint.AntiAliasGridFit; g.Clear(SD.Color.Transparent);

      using (var p = new SD.Drawing2D.GraphicsPath()) { int r = 8; p.AddArc(0, 0, r, r, 180, 90); p.AddArc(31 - r, 0, r, r, 270, 90); p.AddArc(31 - r, 31 - r, r, r, 0, 90); p.AddArc(0, 31 - r, r, r, 90, 90); p.CloseFigure();
        using (var br = new SD.SolidBrush(SD.Color.White)) g.FillPath(br, p);
        using (var edge = new SD.Pen(SD.Color.FromArgb(0xC8, 0xCE, 0xD8), 1f)) g.DrawPath(edge, p); }

      // Match the stroke weights and leave a clear gap at tray size.
      using (var ink = new SD.Pen(SD.Color.FromArgb(0x1C, 0x1B, 0x19), 3.2f)) {
        ink.LineJoin = SD.Drawing2D.LineJoin.Round;
        g.DrawLines(ink, new[] { new SD.PointF(5f, 10f), new SD.PointF(10f, 16f), new SD.PointF(15f, 10f) });
        g.DrawLine(ink, 10f, 15.5f, 10f, 23f);
        g.DrawLines(ink, new[] { new SD.PointF(17f, 23f), new SD.PointF(22f, 10f), new SD.PointF(27f, 23f) });
      }
    }

    hIcon = bmp.GetHicon();
    tray = new WF.NotifyIcon { Icon = SD.Icon.FromHandle(hIcon), Text = "YA", Visible = true };
    try { var src = System.Windows.Interop.Imaging.CreateBitmapSourceFromHIcon(hIcon, System.Windows.Int32Rect.Empty, System.Windows.Media.Imaging.BitmapSizeOptions.FromEmptyOptions()); src.Freeze(); this.Icon = src; } catch { }

    var m = new WF.ContextMenuStrip();

    m.Items.Add("\u663E\u793A", null, (s, e) => Dispatcher.BeginInvoke(new Action(ShowCard)));

    m.Items.Add("\u9690\u85CF", null, (s, e) => Dispatcher.BeginInvoke(new Action(HideCard)));

    m.Items.Add(new WF.ToolStripSeparator());

    m.Items.Add("\u9000\u51FA", null, (s, e) => Dispatcher.BeginInvoke(new Action(Close)));

    tray.ContextMenuStrip = m;

    tray.MouseClick += (s, e) => { if (e.Button == WF.MouseButtons.Left) Dispatcher.BeginInvoke(new Action(() => { if (IsVisible) HideCard(); else ShowCard(); })); };

  }

  void ConfirmShown() {
    var handle=new WindowInteropHelper(this).Handle;
    if (previewMode || !IsVisible || WindowState == WindowState.Minimized || !YaWindow.UserVisible(nxPid,handle.ToInt64())) return;
    var request=YaEvidence.Read(System.IO.Path.Combine(ioDir,"hud_show_request.json"));
    string package=System.IO.Directory.GetParent(libDir).FullName;
    if(Convert.ToString(request["package_id"])!=YaEvidence.Identity(package) || !System.Text.RegularExpressions.Regex.IsMatch(Convert.ToString(request["request"]),"^[a-f0-9]{32}$") || (DateTime.UtcNow-DateTime.Parse(Convert.ToString(request["issued_utc"]),IC,System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime()).TotalSeconds>60)return;
    var record=new Dictionary<string,object>{{"request",request["request"]},{"package_id",request["package_id"]},{"pid",nxPid},{"process_start",nx.StartTime.ToUniversalTime().Ticks.ToString()},{"handle",handle.ToInt64()},{"desktop",YaWindow.Desktop()},{"verified_utc",DateTime.UtcNow.ToString("o")}};
    string path=System.IO.Path.Combine(ioDir,"hud_window.json"),temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
    try{File.WriteAllText(temp,js.Serialize(record),new UTF8Encoding(false));if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);}finally{if(File.Exists(temp))File.Delete(temp);}
    try { using (var ready = EventWaitHandle.OpenExisting(ShowEventName + "-Visible")) ready.Set(); } catch (WaitHandleCannotBeOpenedException) { }
  }
  void ShowCard() { if (!IsVisible) Show(); if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal; var t = Topmost; Topmost = false; Topmost = true; Topmost = t; Safe(Fit); Safe(Poll); Safe(ConfirmShown); }

  void HideCard() {

    if (totWin != null) { try { totWin.Close(); } catch { } }

    SavePos(); Hide();

    if (!tipShown && tray != null) { tipShown = true; try { tray.ShowBalloonTip(2500, "YA", "\u5355\u51FB\u56FE\u6807\u518D\u6253\u5F00", WF.ToolTipIcon.None); } catch { } }

  }

  // right-click menu in the card's own look: white, thin line, rounded, ink text, cyan-blue highlight

  void StyleMenu(ContextMenu cm) {

    string x = @"<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>

  <Style TargetType='ContextMenu'>

    <Setter Property='OverridesDefaultStyle' Value='True'/>

    <Setter Property='HasDropShadow' Value='True'/>

    <Setter Property='FontFamily' Value='Microsoft YaHei UI, Microsoft YaHei, Segoe UI'/>

    <Setter Property='FontSize' Value='12.5'/>

    <Setter Property='Foreground' Value='#2B3037'/>

    <Setter Property='Template'><Setter.Value>

      <ControlTemplate TargetType='ContextMenu'>

        <Border Margin='6,4,10,12' Background='White' BorderBrush='#E3E6EA' BorderThickness='1' CornerRadius='10' Padding='5'>

          <StackPanel IsItemsHost='True' KeyboardNavigation.DirectionalNavigation='Cycle' MinWidth='132'/>

        </Border>

      </ControlTemplate>

    </Setter.Value></Setter>

  </Style>

  <Style TargetType='Separator'>

    <Setter Property='OverridesDefaultStyle' Value='True'/>

    <Setter Property='Template'><Setter.Value>

      <ControlTemplate TargetType='Separator'><Border Height='1' Margin='8,4' Background='#ECEEF1'/></ControlTemplate>

    </Setter.Value></Setter>

  </Style>

  <Style TargetType='MenuItem'>

    <Setter Property='OverridesDefaultStyle' Value='True'/>

    <Setter Property='Foreground' Value='#2B3037'/>

    <Setter Property='Cursor' Value='Hand'/>

    <Setter Property='Template'><Setter.Value>

      <ControlTemplate TargetType='MenuItem'>

        <Border x:Name='bg' Background='Transparent' CornerRadius='6' Padding='8,6,14,6' SnapsToDevicePixels='True'>

          <Grid>

            <Grid.ColumnDefinitions><ColumnDefinition Width='18'/><ColumnDefinition Width='*'/></Grid.ColumnDefinitions>

            <TextBlock x:Name='chk' Text='&#x2713;' Foreground='#3B82F6' FontWeight='SemiBold' VerticalAlignment='Center' Visibility='Hidden'/>

            <ContentPresenter Grid.Column='1' ContentSource='Header' RecognizesAccessKey='True' VerticalAlignment='Center'/>

          </Grid>

        </Border>

        <ControlTemplate.Triggers>

          <Trigger Property='IsChecked' Value='True'><Setter TargetName='chk' Property='Visibility' Value='Visible'/></Trigger>

          <Trigger Property='IsHighlighted' Value='True'><Setter TargetName='bg' Property='Background' Value='#EEF5FF'/><Setter Property='Foreground' Value='#3B82F6'/></Trigger>

          <Trigger Property='IsEnabled' Value='False'><Setter Property='Foreground' Value='#B9BFC8'/></Trigger>

        </ControlTemplate.Triggers>

      </ControlTemplate>

    </Setter.Value></Setter>

  </Style>

</ResourceDictionary>";

    var rd = (ResourceDictionary)System.Windows.Markup.XamlReader.Parse(x);

    cm.Resources = rd;

    cm.Style = (Style)rd[typeof(ContextMenu)];

  }

  void Safe(Action a) { try { a(); } catch (Exception ex) { try { File.AppendAllText(errLog, DateTime.Now.ToString("s") + " " + ex + "\r\n"); } catch { } } }

  FrameworkElement Tile(string icon, string label, out TextBlock val, out TextBlock unit, string u, int row, int col) {

    var sp = new StackPanel { Margin = new Thickness(0, 0, 8, 8), Background = Brushes.Transparent };

    var h = new StackPanel { Orientation = Orientation.Horizontal };

    h.Children.Add(new Path { Data = Geometry.Parse(icon), Stroke = new SolidColorBrush(Sub), StrokeThickness = 1.5, StrokeLineJoin = PenLineJoin.Round, Width = 13, Height = 13, Stretch = Stretch.Uniform, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) });

    h.Children.Add(new TextBlock { Text = label, FontSize = 12, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center });

    sp.Children.Add(h);

    var v = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 2, 0, 0) };

    val = new TextBlock { Text = "\u672A\u7EDF\u8BA1", FontSize = 13, FontWeight = FontWeights.SemiBold, FontFamily = NumFont, Foreground = new SolidColorBrush(Ink), VerticalAlignment = VerticalAlignment.Center };

    unit = new TextBlock { Text = u, FontSize = 11.5, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(3, 0, 0, 0) };

    v.Children.Add(val); v.Children.Add(unit); sp.Children.Add(v);

    Grid.SetRow(sp, row); Grid.SetColumn(sp, col);

    return sp;

  }

  void Hover(bool on) {

    if (dragging) return;

    closeX.Opacity = on ? 0.75 : 0;

  }





  // ---------- data ----------

  static readonly DateTime E0 = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);

  static double Epoch() { return (DateTime.UtcNow - E0).TotalSeconds; }

  static string Clock(double t) { return E0.AddSeconds(t).ToLocalTime().ToString("MM-dd HH:mm", IC); }

  Dictionary<string, object> ReadJson(string f) { try { using (var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) using (var sr = new StreamReader(fs, Encoding.UTF8)) return js.DeserializeObject(sr.ReadToEnd()) as Dictionary<string, object>; } catch { return null; } }

  void WriteJson(string f, Dictionary<string, object> d) { try { File.WriteAllText(f, js.Serialize(d), new UTF8Encoding(false)); } catch { } }

  static bool Has(Dictionary<string, object> d, string k) { object v; return d != null && d.TryGetValue(k, out v) && v != null; }

  static double Num(Dictionary<string, object> d, string k) { object v; if (d == null || !d.TryGetValue(k, out v) || v == null) return 0; try { return Convert.ToDouble(v, IC); } catch { return 0; } }

  static string Str(Dictionary<string, object> d, string k) { object v; if (d == null || !d.TryGetValue(k, out v) || v == null) return ""; return Convert.ToString(v, IC); }

  static HashSet<string> Ids(Dictionary<string, object> d, string k) {

    var r = new HashSet<string>(); object v;

    if (d != null && d.TryGetValue(k, out v) && v is object[]) foreach (var o in (object[])v) if (o != null) r.Add(Convert.ToString(o, IC));

    return r;

  }

  static double[] Trio(Dictionary<string, object> d, string k) {

    var r = new double[3]; var a = Str(d, k).Split(',');

    for (int i = 0; i < 3 && i < a.Length; i++) { double v; if (double.TryParse(a[i].Trim(), NumberStyles.Float, IC, out v) && v > 0) r[i] = v; }

    return r;

  }

  static int NewIn(HashSet<string> now, HashSet<string> before) { int n = 0; foreach (var s in now) if (!before.Contains(s)) n++; return n; }

  static string Big(double n) {

    if (n >= 1e8) return (n / 1e8).ToString(n >= 1e9 ? "0" : "0.0", IC) + "\u4EBF";

    if (n >= 1e4) return (n / 1e4).ToString(n >= 1e5 ? "0" : "0.0", IC) + "\u4E07";

    return Math.Round(n).ToString("N0", IC);

  }

  static void Dur(double sec, out string v, out string u) {

    int m = (int)Math.Round(sec / 60);

    if (sec < 60) { v = Math.Max(0, (int)sec).ToString(IC); u = "\u79D2"; }

    else if (m < 60) { v = m.ToString(IC); u = "\u5206\u949F"; }

    else { v = (m / 60).ToString(IC) + ":" + (m % 60).ToString("00", IC); u = "\u5C0F\u65F6"; }

  }

  static string DurText(double sec) { string v, u; Dur(sec, out v, out u); return v + " " + u; }

  // tokens between two points: real when the client records them (and the start is known), else the estimate of tool traffic

  // money: rough price in CNY (yuan); tiny amounts get more decimals so they never read as 0

  static string Yuan(double c) {

    if (c <= 0) return "0.00";

    if (c >= 10000) return (c / 10000).ToString(c >= 100000 ? "0" : "0.0", IC) + "\u4E07";

    if (c >= 100) return c.ToString("0", IC);

    if (c >= 0.1) return c.ToString("0.00", IC);

    if (c >= 0.01) return c.ToString("0.000", IC);

    if (c >= 0.0001) return c.ToString("0.0000", IC);

    return "<0.0001";

  }

  double CostOf(double miss, double hit, double o) { return (Math.Max(0, miss) * pIn + Math.Max(0, hit) * pCa + Math.Max(0, o) * pOut) / 1e6; }

  double CostEst(double est) { return Math.Max(0, est) * pIn / 1e6; }

  string PriceLine() { return "\u5B98\u65B9 DeepSeek-flash \u975E\u9AD8\u5CF0\uFF08USD/\u767E\u4E07\uFF09\uFF1A\u547D\u4E2D $0.003 \u00B7 \u672A\u547D\u4E2D $0.15 \u00B7 \u8F93\u51FA $0.60\n\u6298\u7B97\u00D77.2\uFF1A\u547D\u4E2D \u00A50.0216 \u00B7 \u672A\u547D\u4E2D \u00A51.08 \u00B7 \u8F93\u51FA \u00A54.32\uFF08\u6BCF\u767E\u4E07 token\uFF09"; }

  string MoneyText(double miss, double hit, double o, double est, bool realOk) {

    return realOk ? "\u00A5" + Yuan(CostOf(miss, hit, o)) + " \u5143" : "\u00A5" + Yuan(CostEst(est)) + " \u5143\uFF08\u4F30\uFF09";

  }

  // DeepSeek-style horizontal bars: little text; hover/click shows detail

  Border Seg(double w, Color c) {

    double ww = 0; if (w > 0) ww = Math.Max(w, 2);

    return new Border { Width = ww, Height = 10, Background = new SolidColorBrush(c), SnapsToDevicePixels = true };

  }

  void BarBlock(string title, string tip, params FrameworkElement[] segs) {

    if (totBody == null) return;

    var wrap = new StackPanel { Margin = new Thickness(0, 2, 0, 8) };

    if (!string.IsNullOrEmpty(title))

      wrap.Children.Add(new TextBlock { Text = title, FontSize = 11, Foreground = new SolidColorBrush(Sub), Margin = new Thickness(0, 0, 0, 4) });

    var track = new Border { Width = 260, Height = 10, Background = new SolidColorBrush(Color.FromRgb(0xEE, 0xF0, 0xF3)), CornerRadius = new CornerRadius(5), ClipToBounds = true, HorizontalAlignment = HorizontalAlignment.Left };

    var row = new StackPanel { Orientation = Orientation.Horizontal };

    foreach (var s in segs) if (s != null) row.Children.Add(s);

    track.Child = row;

    wrap.Children.Add(track);

    if (!string.IsNullOrEmpty(tip)) {

      var tt = new ToolTip { Content = tip, Placement = System.Windows.Controls.Primitives.PlacementMode.Bottom };

      wrap.ToolTip = tt; track.ToolTip = tt;

    }

    totBody.Children.Add(wrap);

  }

  void SplitBars(double miss, double hit, double o) {

    miss = Math.Max(0, miss); hit = Math.Max(0, hit); o = Math.Max(0, o);

    double sum = miss + hit + o; if (sum <= 0) return;

    double W = 260;

    // colors approx DeepSeek: cache=green-teal, input=blue, output=violet

    var cHit = Color.FromRgb(0x34, 0xD3, 0x99);   // cache hit

    var cMiss = Color.FromRgb(0x60, 0xA5, 0xFA);  // input miss

    var cOut = Color.FromRgb(0xA7, 0x8B, 0xFA);   // output

    string tip = "\u603B TOKEN  " + Big(sum) + "\n"

      + "\u8F93\u5165\uFF08\u547D\u4E2D\u7F13\u5B58\uFF09  \u00A5" + Yuan(CostOf(0, hit, 0)) + "  \u00B7  " + Big(hit) + " token\n"

      + "\u8F93\u5165\uFF08\u672A\u547D\u4E2D\u7F13\u5B58\uFF09  \u00A5" + Yuan(CostOf(miss, 0, 0)) + "  \u00B7  " + Big(miss) + " token\n"

      + "\u8F93\u51FA  \u00A5" + Yuan(CostOf(0, 0, o)) + "  \u00B7  " + Big(o) + " token\n"

      + "\u4EF7\u683C\u53C2\u8003 DeepSeek V4.1";

    BarBlock("\u6D88\u8017\u6784\u6210", tip,

      Seg(W * hit / sum, cHit), Seg(W * miss / sum, cMiss), Seg(W * o / sum, cOut));

  }

  void LibBars() {

    if (!libKnown || libN <= 0) return;

    double W = 260;

    double m = Math.Max(0, libM), k = Math.Max(0, libK), r = Math.Max(0, libR);

    double sum = m + k + r; if (sum <= 0) sum = libN;

    var cM = Color.FromRgb(0x3B, 0x82, 0xF6);

    var cK = Color.FromRgb(0xF5, 0x9E, 0x0B);

    var cR = Color.FromRgb(0x10, 0xB9, 0x81);

    string tipCat = "\u7ECF\u9A8C\u5E93 " + libN + " \u6761\n\u62DB\u5F0F " + libM + " \u00B7 \u5751 " + libK + " \u00B7 \u65B9\u6848 " + libR;

    BarBlock("\u5206\u7C7B", tipCat, Seg(W * m / sum, cM), Seg(W * k / sum, cK), Seg(W * r / sum, cR));

    double ver = Math.Max(0, libVer), un = Math.Max(0, libN - libVer), vs = ver + un; if (vs <= 0) return;

    var cV = Color.FromRgb(0x22, 0xC5, 0x5E);

    var cU = Color.FromRgb(0xCB, 0xD5, 0xE1);

    string tipVer = "\u5DF2\u9A8C\u8BC1 " + libVer + " \u6761\uFF1A\u6838\u5BF9\u901A\u8FC7\u3001\u6B63\u5F0F\u5165\u5E93\uFF08\u7D22\u5F15\u91CC v\u22651\uFF09\n\u672A\u9A8C\u8BC1 " + Math.Max(0, libN - libVer) + " \u6761\uFF1A\u8FD8\u662F\u8349\u7A3F\uFF08exp_done \u672A exp_save / v=0\uFF09\uFF0C\u4E0D\u7B97\u6210\u719F\u7ECF\u9A8C";

    BarBlock("\u9A8C\u8BC1", tipVer, Seg(W * ver / vs, cV), Seg(W * un / vs, cU));

  }



  // run state (this time): io\hud_run.json, only kept while it belongs to this NX

  void LoadRun() {

    var d = ReadJson(runPath); if (d == null || (int)Num(d, "nx_pid") != nxPid) return;

    bUses = Num(d, "uses"); bReal = Num(d, "real"); bEst = Num(d, "est"); rAct = Num(d, "act"); rLast = Num(d, "last");

    bSplit = Has(d, "r_in"); bIn = Num(d, "r_in"); bCa = Num(d, "r_cache"); bOut = Num(d, "r_out");

    bIds = Ids(d, "ids"); bLib = Ids(d, "lib"); if (Has(d, "gen")) { bGen = Num(d, "gen"); bGenOk = true; } bGenLib = Ids(d, "glib"); runReady = true; if (!string.Equals(Str(d, "lib_dir"), libDir, StringComparison.OrdinalIgnoreCase)) libRebase = true;   // baseline was taken against another library (old path / path changed): re-take it once the index is read

  }

  void SaveRun() {

    var d = new Dictionary<string, object>();

    d["nx_pid"] = nxPid; d["uses"] = bUses; d["real"] = bReal; d["est"] = bEst; d["act"] = rAct; d["last"] = rLast;

    d["r_in"] = bIn; d["r_cache"] = bCa; d["r_out"] = bOut;

    d["ids"] = new List<string>(bIds); d["lib"] = new List<string>(bLib); d["gen"] = bGen; d["glib"] = new List<string>(bGenLib); d["lib_dir"] = libDir; d["saved"] = Epoch();

    WriteJson(runPath, d);

  }

  void ForceRefresh() {

    try {

      string tf = statsOv != "" ? statsOv : System.IO.Path.Combine(ioDir, "exp_stats.json");

      if (File.Exists(tf)) { var s = ReadJson(tf); if (s != null && (int)Num(s, "nx_pid") == nxPid) { stats = s; Take(s, Epoch()); } }

      mtIndex = DateTime.MinValue; mtStats = DateTime.MinValue;

    } catch { }

  }

  // which agent's log the real tokens came from (hover text "来源")
  string SrcName() {
    string a = cSrc == "agy-local" ? "\u8C37\u6B4C agy \u65E5\u5FD7" : cSrc == "grok-local" ? "Grok \u65E5\u5FD7" : cSrc == "deepseek-local" ? "DeepSeek \u672C\u673A\u8BB0\u5F55" : cSrc == "codex-local" ? "Codex \u65E5\u5FD7" : cSrc == "log-local" ? "Agent \u65E5\u5FD7 tokens used" : "";
    if (cAgent != "" && !a.ToLowerInvariant().Contains(cAgent.ToLowerInvariant())) a = a == "" ? cAgent : cAgent + "\uFF08" + a + "\uFF09";
    return a == "" ? "" : " \u00B7 " + a;
  }
  void NewRun() {

    bool z = swFresh; swFresh = false; if (snap && z) { bUses = Math.Max(0, cUses - cardHits); bReal = 0; bEst = 0; bIn = 0; bCa = 0; bOut = 0; bIds = new HashSet<string>(); } else if (snap) { bUses = cUses; bReal = cReal; bEst = cEst; bIn = cIn; bCa = cCa; bOut = cOut; bIds = new HashSet<string>(cIds); } else { bUses = 0; bReal = 0; bEst = 0; bIn = 0; bCa = 0; bOut = 0; bIds = new HashSet<string>(); }

    bSplit = true;

    bLib = new HashSet<string>(libIds); bGen = genAbs; bGenLib = new HashSet<string>(genIds); libRebase = !libKnown; rAct = Epoch(); rLast = rAct; runReady = true; SaveRun();

  }

  // right-click "全部重置": this run + whole NX session (display baseline) + totals on this computer -> 0. The experience library is untouched.
  void ResetAll() {
    ForceRefresh();
    NewRun();   // this run: TOKEN / cost / time / calls / new entries from now
    double now = Epoch();
    tUses = 0; tReal = 0; tEst = 0; tSec = 0; tIn = 0; tCa = 0; tOut = 0; tSince = now; tLact = 0;
    tPid = nxPid; tLU = cUses; tLR = cReal; tLE = cEst; tLI = cIn; tLC = cCa; tLO = cOut;   // count only what is added after the reset
    SaveTot();
    zOn = true; zUses = cUses; zIn = cIn; zCa = cCa; zOut = cOut; zEst = cEst; zReal = cReal; zT = now; SaveZ();
    totSig = ""; Show4(); if (totWin != null) FillTotals();
  }
  void LoadZ() {
    var d = ReadJson(rstPath); if (d == null || (int)Num(d, "nx_pid") != nxPid) { zOn = false; return; }
    zUses = Num(d, "uses"); zIn = Num(d, "in"); zCa = Num(d, "cache"); zOut = Num(d, "out"); zEst = Num(d, "est"); zReal = Num(d, "real"); zT = Num(d, "t"); zOn = true;
  }
  void SaveZ() {
    var d = new Dictionary<string, object>();
    d["nx_pid"] = nxPid; d["uses"] = zUses; d["in"] = zIn; d["cache"] = zCa; d["out"] = zOut; d["est"] = zEst; d["real"] = zReal; d["t"] = zT;
    WriteJson(rstPath, d);
  }

  // totals on this computer: io\hud_totals.json, summed from what each NX session adds

  void LoadTot() {

    var d = ReadJson(totPath); if (d == null) return;

    tUses = Num(d, "uses"); tReal = Num(d, "real"); tEst = Num(d, "est"); tSec = Num(d, "active_sec"); tSince = Num(d, "since");

    tPid = Num(d, "pid"); tLU = Num(d, "last_uses"); tLR = Num(d, "last_real"); tLE = Num(d, "last_est"); tLact = Num(d, "last_act");

    tIn = Num(d, "real_in"); tCa = Num(d, "real_cache"); tOut = Num(d, "real_out"); tLI = Num(d, "last_in"); tLC = Num(d, "last_cache"); tLO = Num(d, "last_out");

  }

  void SaveTot() {

    var d = new Dictionary<string, object>();

    d["uses"] = tUses; d["real"] = tReal; d["est"] = tEst; d["active_sec"] = tSec; d["since"] = tSince;

    d["pid"] = tPid; d["last_uses"] = tLU; d["last_real"] = tLR; d["last_est"] = tLE; d["last_act"] = tLact;

    d["real_in"] = tIn; d["real_cache"] = tCa; d["real_out"] = tOut; d["last_in"] = tLI; d["last_cache"] = tLC; d["last_out"] = tLO;

    WriteJson(totPath, d);

  }



  // ---------- 通用软件连接态（io\link.json，ya.ps1 hud 写入）与数据喂入 ----------
  string linkReason = "", linkSoft = "", linkSlot = "generic", linkState = "none"; DateTime linkChk = DateTime.MinValue, feedAt = DateTime.MinValue; bool linkLast, linkSlotBound; double feedStart; string feedSig = "", feedLog = "", feedAg = ""; bool cNoLog; double cardHits; string feedSwKey = ""; double feedSwT; bool swFresh; DateTime feedMt = DateTime.MinValue;
  [DllImport("user32.dll", EntryPoint = "IsWindowVisible")] static extern bool YaWinVisible(IntPtr h);
  Dictionary<string, object> LinkRead() { try { string p = statusOv != "" ? statusOv : System.IO.Path.Combine(ioDir, "link.json"); return File.Exists(p) ? ReadJson(p) : null; } catch { return null; } }
  bool LinkOk() {
    if ((DateTime.UtcNow - linkChk).TotalMilliseconds < 1500) return linkLast; linkChk = DateTime.UtcNow;
    linkReason = "";
    var d = LinkRead(); linkSoft = d == null ? "" : Str(d, "soft"); string sl = d == null ? "" : Str(d, "slot").Trim().ToLowerInvariant(); linkSlot = (sl == "" || sl == "all") ? "generic" : sl;
    linkSlotBound = d != null && Str(d, "package_id") == YaEvidence.Identity(System.IO.Path.GetDirectoryName(libDir));
    string home = Directory.GetParent(ioDir).FullName, quickFile = System.IO.Path.Combine(home,"quick_request.json");
    if(File.Exists(quickFile)) { var reference = ReadJson(quickFile); string stateFile = Str(reference,"state_file"), quickState = "";
      try { if(System.IO.Path.GetFullPath(stateFile).StartsWith(System.IO.Path.Combine(home,"quick")+"\\",StringComparison.OrdinalIgnoreCase)) quickState=Str(ReadJson(stateFile),"status"); } catch { }
      if(quickState!="completed" && quickState!="failed") { linkState="recovery";linkReason="连接请求尚未完成，保留现场核查";linkLast=false;return false; }
    }
    if (d == null || Str(d, "state") != "ok") { linkState = d != null && Str(d, "state") == "opened" ? "evidence" : "none"; linkLast = false; return false; }
    double rawPid = Num(d, "pid"); int p = 0; if (rawPid > 0 && rawPid <= 2147483647d && rawPid == Math.Floor(rawPid)) p = (int)rawPid;
    if (p > 0) {
      try { var pr = Process.GetProcessById(p); if (pr.HasExited) { linkState = "lost"; linkLast = false; return false; }
        bool resp = false; try { resp = pr.Responding; } catch { } if (!resp) { linkState = "hang"; linkLast = false; return false; }
        IntPtr mw = IntPtr.Zero; try { mw = YaWindow.Find(pr.Id); } catch { } if (mw == IntPtr.Zero) { linkState = "hidden"; linkLast = false; return false; } }
      catch { linkState = "lost"; linkLast = false; return false; }
    }
    else { linkState = "nopid"; linkLast = false; return false; }
    linkReason = YaEvidence.CheckRegistered(System.IO.Path.GetDirectoryName(libDir), ioDir, d);
    if (linkReason != "") { linkState = "evidence"; linkLast = false; return false; }
    if (!YaEvidence.HasFrontendAcceptance(System.IO.Path.GetDirectoryName(libDir), ioDir, d)) {
      linkState = "awaitingAcceptance"; linkLast = true; return true;   // 握手已通：显示「已连接」，软件侧计数生效；验收后才是「已验收」
    }
    linkState = "ok"; linkLast = true; return true;
  }
  string LinkText() {
    string n = linkSoft == "" ? "" : linkSoft + " ";
    if (linkState == "recovery") return "连接待复核";
    if (linkState == "awaitingAcceptance") return "已连接" + (linkSoft == "" ? "" : " · " + linkSoft);
    if (linkState == "ok") return "已验收" + (linkSoft == "" ? "" : " · " + linkSoft);
    if (linkState == "evidence") return n + "已打开 · 待读回";
    if (linkState == "lost") return n + "\u5DF2\u6389\u7EBF";
    if (linkState == "hang") return n + "\u672A\u54CD\u5E94";
    if (linkState == "hidden") return n + "\u7A97\u53E3\u4E0D\u53EF\u89C1";
    if (linkState == "nopid") return n + "\u672A\u786E\u8BA4\u7A97\u53E3";
    return "\u672A\u8FDE\u63A5";
  }
  string LinkTip(bool agentOk) {
    if (linkState == "ok") return (linkSoft == "" ? "\u5DF2\u8FDE\u63A5" : linkSoft) + " \u00B7 \u69FD " + linkSlot + " · 轻读回已验收";
    if (linkState == "awaitingAcceptance") return (linkSoft == "" ? "已连接" : linkSoft) + " · 槽 " + linkSlot + " · 握手已通，轻读回验收后显示已验收";
    if (linkState == "none") return "\u672A\u8FDE\u63A5";
    return LinkText() + (linkReason == "" ? "" : " · " + linkReason);
  }
  string SlotIndex() { if (linkSlot == "") linkSlot = "generic"; return System.IO.Path.Combine(libDir, "\u69FD\\" + linkSlot + "\\\u7D22\u5F15.json"); }
  // 把本包已有的数据（消耗.json 当前槽 calls、Agent 日志、Agent 进程）按旧统计逻辑要的格式写进 io\exp_stats.json / usage_log.txt / agent.json
  void Feed() {
    if ((DateTime.UtcNow - feedAt).TotalMilliseconds < 1500) return; feedAt = DateTime.UtcNow;
    try {
      LinkOk(); var L = LinkRead(); if (feedStart <= 0) feedStart = Epoch();
      double calls = 0, gc = 0, softCalls = 0; bool soFeed = SoftOn(); string uf = System.IO.Path.Combine(libDir, "\u6D88\u8017.json");
      if (File.Exists(uf)) { var u = ReadJson(uf); object so;
        if (u != null && u.TryGetValue("slots", out so) && so is object[]) foreach (var o in (object[])so) { var r = o as Dictionary<string, object>; if (r == null) continue; string rid = Str(r, "id"); if (rid == "generic") gc = Num(r, "calls"); else if (soFeed && rid == linkSlot) softCalls = Num(r, "calls"); } }
      string log = L == null ? "" : Str(L, "log");
      // 2026-11-05：无有效「本次」日志时显示未挂/0，勿吞旧 Temp\ya_draw_*.log
      int apCheck = L == null ? 0 : (int)Num(L, "agent_pid"); bool agentAlive = false;
      if (apCheck > 0) { try { agentAlive = !Process.GetProcessById(apCheck).HasExited; } catch { } }
      bool linkAlive = linkLast;
      if (log != "") {
        try {
          string fn = System.IO.Path.GetFileName(log);
          bool isOldDraw = fn.StartsWith("ya_draw_", StringComparison.OrdinalIgnoreCase) && fn.EndsWith(".log", StringComparison.OrdinalIgnoreCase);
          if (!linkAlive) log = "";
          else if (apCheck > 0 && !agentAlive) log = "";
          else if (isOldDraw && !File.Exists(log)) log = "";
          else if (isOldDraw && File.Exists(log) && !agentAlive && (DateTime.UtcNow - File.GetLastWriteTimeUtc(log)).TotalMinutes > 30) log = "";
        } catch { log = ""; }
      }
      cNoLog = log == "" || !File.Exists(log);
      if (cNoLog) { try { File.WriteAllText(System.IO.Path.Combine(ioDir, "usage_log.txt"), "", new UTF8Encoding(false)); feedLog = ""; } catch { } }
      // connection-card hits (连接经验.ps1 find / 快连.ps1; read-only on the package) are logged outside the package in io\card_hits.json: this agent's hits count as experience calls
      cardHits = 0;
      if (soFeed) {
      try { string chp = System.IO.Path.Combine(ioDir, "card_hits.json"); if (File.Exists(chp)) { var ch = ReadJson(chp); object lo; int lap = L == null ? 0 : (int)Num(L, "agent_pid"); double lt = 0;
        try { if (L != null && Str(L, "time") != "") lt = (DateTime.Parse(Str(L, "time"), IC).ToUniversalTime() - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds; } catch { }
        double hits = 0; if (ch != null && ch.TryGetValue("log", out lo) && lo is object[]) foreach (var o in (object[])lo) { var r = o as Dictionary<string, object>; if (r == null) continue; int hp = (int)Num(r, "agent_pid"); double ht = Num(r, "t");
          if ((lap > 0 && hp == lap) || (lap <= 0 && lt > 0 && ht >= lt - 7200 && ht <= lt + 600)) hits += 1; }
        cardHits = hits; } } catch { }
      }
      genAbs = gc; calls = gc + (soFeed ? (softCalls + cardHits) : 0); if (!bGenOk) { bGen = gc; bGenOk = true; }
      string ag = L == null ? "" : Str(L, "agent");
      var d = new Dictionary<string, object>();
      d["nx_pid"] = nxPid; d["uses"] = calls; d["task_start"] = feedStart; d["agent"] = ag; d["agent_switch"] = log; d["soft"] = linkSoft; d["slot"] = linkSlot;
      // a new registration with an agent log (new agent / new link): this run is that agent's whole log from 0, so TOKEN covers its connect phase too (not only after the card opened)
      string swKey = log + "|" + (L == null ? "" : Str(L, "time")) + "|" + (L == null ? "" : Str(L, "agent_pid")); if (log != "" && swKey != feedSwKey) { feedSwKey = swKey; feedSwT = Epoch() + 1; swFresh = true; } if (log != "") d["agent_switch_t"] = feedSwT;
      string sig = js.Serialize(d);
      string sfp = System.IO.Path.Combine(ioDir, "exp_stats.json"); if (sig != feedSig || !File.Exists(sfp) || File.GetLastWriteTimeUtc(sfp) != feedMt) { feedSig = sig; File.WriteAllText(sfp, sig, new UTF8Encoding(false)); feedMt = File.GetLastWriteTimeUtc(sfp); }
      if (log != feedLog) { feedLog = log; File.WriteAllText(System.IO.Path.Combine(ioDir, "usage_log.txt"), log, new UTF8Encoding(false)); }
      int ap = L == null ? 0 : (int)Num(L, "agent_pid"); string a2 = ap + "|" + ag;
      if (agentOv == "" && a2 != feedAg) { feedAg = a2; var a = new Dictionary<string, object>(); a["pid"] = ap; a["agent"] = ag; a["time"] = Epoch(); File.WriteAllText(System.IO.Path.Combine(ioDir, "agent.json"), js.Serialize(a), new UTF8Encoding(false)); }
    } catch { }
  }

  void Poll() {

    if (dragging) return;

    ReadPreviewCmd();

    try { if (nx == null || nx.HasExited) { poll.Stop(); Close(); return; } } catch { }

    if (posDirty) { posDirty = false; SavePos(); }

    // link: NX heartbeat (about every second) and the assistant process (io\agent.json, written by the MCP server)

    Feed();

    bool nxOk = LinkOk();

    string af = agentOv != "" ? agentOv : System.IO.Path.Combine(ioDir, "agent.json");

    bool agentOk = false;

    try { if (File.Exists(af)) { var mt = File.GetLastWriteTimeUtc(af); var a = ReadJson(af);

        if (a != null) { if (mt != mtAgent) { mtAgent = mt; agentTime = Num(a, "time"); }

          int p = (int)Num(a, "pid"); if (p > 0) { try { agentOk = !Process.GetProcessById(p).HasExited; } catch { } } } } } catch { }

          var col = !nxOk ? Warn : Ok;

      var fb = (SolidColorBrush)dot.Fill; if (fb.Color != col) dot.Fill = new SolidColorBrush(col);

      state.Text = LinkText();

      state.Foreground = new SolidColorBrush(!nxOk ? Warn : Ok);

      if (connText != null) { string ct = LinkText(); if (connText.Text != ct) { connText.Text = ct; connText.Foreground = new SolidColorBrush(!nxOk ? WarnInk : OkInk); connTag.Background = new SolidColorBrush(!nxOk ? WarnBg : OkBg); } connTag.ToolTip = dot.ToolTip; }

      dot.ToolTip = LinkTip(agentOk);

      if (!dragging && nxOk && agentOk) { double ph = (DateTime.UtcNow.Ticks / 3000000.0) % (Math.PI * 2); dot.Opacity = 0.7 + 0.3 * Math.Abs(Math.Sin(ph)); }

      else { dot.Opacity = 1; }



    // library index: ids, by category, verified

    try { Safe(RefreshLib); bool soCount = HasLocalSlot(); string ix = indexOv != "" ? indexOv : (soCount ? SlotIndex() : "");

      if (ix != "" && File.Exists(ix)) { var mt = File.GetLastWriteTimeUtc(ix); string dRoot = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(ix), "_\u8349\u7A3F"); string[] dFiles = Directory.Exists(dRoot) ? Directory.GetFiles(dRoot, "*.json", SearchOption.AllDirectories) : new string[0]; foreach (var df in dFiles) { var dm = File.GetLastWriteTimeUtc(df); if (dm > mt) mt = dm; } mt = mt.AddTicks(dFiles.Length);   // 2026-11-05: drafts (v=0) of this software slot count too, so the library grows as tasks save experience

        if (mt != mtIndex || ix != indexedPath) { var d = ReadJson(ix); object e;

          if (d != null && d.TryGetValue("entries", out e) && e is object[]) { mtIndex = mt; indexedPath = ix;

            var ids = new HashSet<string>(); int n = 0, ver = 0, cm = 0, ck = 0, cr = 0;

            foreach (var o in (object[])e) { var en = o as Dictionary<string, object>; if (en == null) continue; n++;

              string id = Str(en, "id"); if (id != "") ids.Add(id);

              if (Num(en, "v") >= 1) ver++;

              string c = Str(en, "c"); if (c == "\u62DB\u5F0F") cm++; else if (c == "\u5751") ck++; else if (c == "\u65B9\u6848") cr++; }

            foreach (var df in dFiles) { string did = System.IO.Path.GetFileNameWithoutExtension(df); if (ids.Contains(did)) continue; ids.Add(did); n++; string fd = System.IO.Path.GetFileName(System.IO.Path.GetDirectoryName(df)); if (fd == "\u62DB\u5F0F\u5E93") cm++; else if (fd == "\u5751\u5E93") ck++; else if (fd == "\u96F6\u4EF6\u65B9\u6848\u5E93") cr++; }

            libIds = ids; libN = n; libVer = ver; libM = cm; libK = ck; libR = cr; libKnown = true; if (libRebase && runReady) { libRebase = false; bLib = new HashSet<string>(ids); bGenLib = new HashSet<string>(genIds); SaveRun(); } } } }

      else { indexedPath = ""; libIds = new HashSet<string>(); libN = 0; libVer = 0; libM = 0; libK = 0; libR = 0; libKnown = true; } } catch { }



    try { genIds = IdxIds("generic"); } catch { }

    // this NX session (io\exp_stats.json, written by nx_exp.ps1); a change = a tool call

    string tf = statsOv != "" ? statsOv : System.IO.Path.Combine(ioDir, "exp_stats.json");

    if (File.Exists(tf)) { var mt = File.GetLastWriteTimeUtc(tf);

      if (mt != mtStats) { var s = ReadJson(tf);

        if (s != null) { mtStats = mt; lastStats = (mt - E0).TotalSeconds;

          stats = (int)Num(s, "nx_pid") == nxPid ? s : null;

          if (stats != null) Take(stats, lastStats); } } }

    if (stats != null && LiveChanged()) Take(stats, (DateTime.UtcNow - E0).TotalSeconds);   // realtime: agent usage log grew
    if (!runReady && libKnown) NewRun();

    Show4();

    if (totWin != null) {

      string sig = libN + "|" + libVer + "|" + cUses + "|" + cIn + "|" + cCa + "|" + cOut + "|" + cEst + "|" + tUses + "|" + tIn + "|" + tCa + "|" + tOut + "|" + tSec.ToString("0", IC);

      if (sig != totSig) { totSig = sig; FillTotals(); }

    }

  }




  // ---------- realtime agent usage (Grok streaming-json {"type":"usage"} / agy stream-json step usage) ----------
  // Reads io\usage_log.txt -> newest agent stdout log, every 1.5 s, so TOKEN moves while the agent thinks, not only at NX calls.
  double luSw = -1; string luPath = ""; long luLen = -1; DateTime luMt = DateTime.MinValue, luChk = DateTime.MinValue; double[] luVal; bool luNew;
  bool LiveChanged() { LiveRefresh(); bool b = luNew; luNew = false; return b; }
  void LiveRefresh() {
    if ((DateTime.UtcNow - luChk).TotalMilliseconds < 1500) return; luChk = DateTime.UtcNow;
    try {
      string best = !cNoLog && linkLast && File.Exists(feedLog) ? feedLog : null;
      DateTime bm = best == null ? DateTime.MinValue : File.GetLastWriteTimeUtc(best);
      if (best == null) { if (luVal != null) { luVal = null; luPath = ""; luNew = true; } return; }
      long len = new FileInfo(best).Length;
      if (len == 0) { if (luVal != null || luPath != best) luNew = true; luVal = null; luPath = best; luLen = 0; luMt = bm; luSw = CxSwitchT(); return; }   // empty agent log (0 byte, e.g. Doubao): no usage, drop the cached value
      double swNow = CxSwitchT();   // a new nx_agent_switch on the same log also needs a fresh baseline
      if (best == luPath && len == luLen && bm == luMt && swNow == luSw && (cxPath == "" || !File.Exists(cxPath) || File.GetLastWriteTimeUtc(cxPath) == cxMt)) return;
      luSw = swNow;
      string t; using (var fs = new FileStream(best, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) using (var r = new StreamReader(fs, Encoding.UTF8)) t = r.ReadToEnd();
      t = t.Replace("\0", "");   // PowerShell may write parts of a redirected log as UTF-16
      if (CxIs(t)) { luPath = best; luLen = len; luMt = bm; luVal = CxUsage(t); luNew = true; return; }   // Codex CLI log
      bool grok = t.Contains("\"type\":\"usage\"") && t.Contains("cache_read_input_tokens");
      var steps = new Dictionary<string, double[]>(); double[] resV = null;   // agy: final {"event":"result"} repeats the step total -> only a fallback, never added (was counted twice)
      foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(t, "(?m)^.*\"usage\":\\{([^{}]*)\\}.*$")) {
        string line = m.Value, body = m.Groups[1].Value;
        if (grok && !System.Text.RegularExpressions.Regex.IsMatch(line, "^\\s*\\{\"type\":\"usage\"")) continue;
        var c = System.Text.RegularExpressions.Regex.Match(line, "\"conversation_id\":\"([^\"]+)\""); var st = System.Text.RegularExpressions.Regex.Match(line, "\"step_index\":(\\d+)");
        string k = st.Success ? c.Groups[1].Value + "#" + st.Groups[1].Value : "L" + m.Index;
        var v = new double[3]; string[] f = { "input_tokens", grok ? "cache_read_input_tokens" : "cache_read_tokens", "output_tokens" };
        for (int j = 0; j < 3; j++) { var g = System.Text.RegularExpressions.Regex.Match(body, "\"" + f[j] + "\":(\\d+)"); if (g.Success) v[j] = double.Parse(g.Groups[1].Value, IC); }
        if (!grok && !st.Success && line.Contains("\"event\":\"result\"")) { resV = v; continue; }
        steps[k] = v;
      }
      if (steps.Count == 0 && resV != null) steps["result"] = resV;
      double a = 0, bb = 0, cc = 0; foreach (var v in steps.Values) { a += v[0]; bb += v[1]; cc += v[2]; }
      luPath = best; luLen = len; luMt = bm; luVal = steps.Count > 0 ? new double[] { a, bb, cc, grok ? 1 : 0 } : CxUsage(t); luNew = true;   // no usage lines: any "tokens used N"
    } catch { }
  }
  // ---------- Codex CLI: header "OpenAI Codex" + "session id: <uuid>"; real split from %CODEX_HOME%\sessions\**\rollout-*-<uuid>.jsonl
  string cxPath = "", cxSid = ""; DateTime cxMt = DateTime.MinValue;
  bool CxIs(string t) { string h = t.Length > 6000 ? t.Substring(0, 6000) : t; return h.Contains("OpenAI Codex") || (System.Text.RegularExpressions.Regex.IsMatch(h, "session id:\\s*[0-9a-fA-F-]{36}") && t.Contains("tokens used")); }
  // Codex session total at the agent switch (cached per rollout+switch): last token_count stamped before the switch; 0 when the session began after it
  string cxBaseKey = ""; double[] cxBase = null;
  double CxSwitchT() { try { string p = System.IO.Path.Combine(ioDir, "agent_switch.json"); if (!File.Exists(p)) return 0; var g = System.Text.RegularExpressions.Regex.Match(File.ReadAllText(p, Encoding.UTF8), "\"t\":\\s*([0-9.]+)"); return g.Success ? double.Parse(g.Groups[1].Value, IC) : 0; } catch { return 0; } }
  double[] CxTot(string b) { double inp = CxNum(b, "input_tokens"), ca = CxNum(b, "cached_input_tokens"), o = CxNum(b, "output_tokens"); return new double[] { Math.Max(0, inp - ca), ca, o }; }
  double[] CxBaseAt(string path, double swT) {
    string key = path + "|" + swT.ToString("0.000", IC);
    if (key == cxBaseKey && cxBase != null) return cxBase;
    var res = new double[3];
    if (swT > 0) {
      string swIso = E0.AddSeconds(swT).ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", IC);
      var rx = new System.Text.RegularExpressions.Regex("\"timestamp\":\"([^\"]+)\"[^\\n]*?\"total_token_usage\":\\{([^{}]*)\\}");
      try {
        using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
          long end = fs.Length; const int chunk = 4 << 20; bool found = false;
          while (end > 0 && !found) {
            long st = Math.Max(0, end - chunk); int n = (int)(end - st); var buf = new byte[n]; fs.Seek(st, SeekOrigin.Begin);
            int rd = 0; while (rd < n) { int k = fs.Read(buf, rd, n - rd); if (k <= 0) break; rd += k; }
            int from = 0; if (st > 0) { int nl = Array.IndexOf(buf, (byte)10, 0, rd); if (nl < 0) { end = st; continue; } from = nl + 1; }
            var ms = rx.Matches(Encoding.UTF8.GetString(buf, from, rd - from));
            for (int i = ms.Count - 1; i >= 0; i--) if (string.CompareOrdinal(ms[i].Groups[1].Value, swIso) < 0) { res = CxTot(ms[i].Groups[2].Value); found = true; break; }
            end = st + from;
            if (st == 0) break;
          }
        }
      } catch { }
    }
    cxBaseKey = key; cxBase = res; return res;
  }
  double CxNum(string b, string k) { var g = System.Text.RegularExpressions.Regex.Match(b, "\"" + k + "\":(\\d+)"); return g.Success ? double.Parse(g.Groups[1].Value, IC) : 0; }
  double[] CxUsage(string t) {
    bool isCx = CxIs(t);
    var ms = System.Text.RegularExpressions.Regex.Match(t, "session id:\\s*([0-9a-fA-F-]{36})");
    if (ms.Success) {
      string sid = ms.Groups[1].Value;
      if (sid != cxSid || cxPath == "" || !File.Exists(cxPath)) {
        cxSid = sid; cxPath = "";
        try {
          string h = Environment.GetEnvironmentVariable("CODEX_HOME"); if (string.IsNullOrEmpty(h)) h = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex");
          string d = System.IO.Path.Combine(h, "sessions");
          if (Directory.Exists(d)) { var fl = Directory.GetFiles(d, "rollout-*" + sid + ".jsonl", SearchOption.AllDirectories); if (fl.Length > 0) cxPath = fl[0]; }
        } catch { }
      }
      if (cxPath != "") {
        try {
          cxMt = File.GetLastWriteTimeUtc(cxPath); string tail;
          using (var fs = new FileStream(cxPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) { fs.Seek(Math.Max(0, fs.Length - (1 << 20)), SeekOrigin.Begin); using (var r = new StreamReader(fs, Encoding.UTF8)) tail = r.ReadToEnd(); }
          var all = System.Text.RegularExpressions.Regex.Matches(tail, "\"total_token_usage\":\\{([^{}]*)\\}");
          // total_token_usage is the WHOLE Codex session (a resumed session carries all earlier turns, mostly cache hits).
          // TOKEN = this run only: subtract the session total stamped just before nx_agent_switch (io\agent_switch.json "t").
          if (all.Count > 0) { double[] cur = CxTot(all[all.Count - 1].Groups[1].Value), bs = CxBaseAt(cxPath, CxSwitchT()); return new double[] { Math.Max(0, cur[0] - bs[0]), Math.Max(0, cur[1] - bs[1]), Math.Max(0, cur[2] - bs[2]), 2 }; }
        } catch { }
      }
    }
    var tu = System.Text.RegularExpressions.Regex.Matches(t, "(?i)tokens used[\\s:]*([\\d,]+)");
    if (tu.Count > 0) return new double[] { double.Parse(tu[tu.Count - 1].Groups[1].Value.Replace(",", ""), IC), 0, 0, isCx ? 2 : 3 };
    return null;
  }
  // live split for this NX task, same bookkeeping as nx_exp.ps1 Get-RealSpent (prev sessions + current - base)
  double[] LiveUsage(Dictionary<string, object> s) {
    LiveRefresh(); if (luVal == null || luPath == "") return null;
    string name = System.IO.Path.GetFileName(luPath), sid = Str(s, "real_sid"), sw = Str(s, "agent_switch");
    double[] bd = Trio(s, "real_bd"), pd = Trio(s, "real_pd");
    if (sid == "grok:" + name || (sid.StartsWith("agy:") && luVal[3] == 0 && sw.Contains(luPath)) || ((sid.StartsWith("codex:") || sid.StartsWith("log:")) && luVal[3] >= 2 && sw.Contains(luPath))) {
      if (luVal[3] >= 2 && (luVal[0] < bd[0] || luVal[1] < bd[1] || luVal[2] < bd[2])) bd = new double[3];   // old base was a whole-session total; Codex values are now deltas since the switch
      return new double[] { Math.Max(0, pd[0] + luVal[0] - bd[0]), Math.Max(0, pd[1] + luVal[1] - bd[1]), Math.Max(0, pd[2] + luVal[2] - bd[2]), luVal[3] }; }
    // agent switched but no NX call yet: this log belongs to the new run, counted from 0
    if (sw.Contains(luPath)) return new double[] { luVal[0], luVal[1], luVal[2], luVal[3] };
    return null;
  }

  void Take(Dictionary<string, object> s, double now) {

    double real = Has(s, "task_tokens_real") ? Num(s, "task_tokens_real") : 0;

    string src = Str(s, "spent_source"); cSrc = src; if (src == "" || src == "estimate") real = 0;
    // another agent was started through nx_agent_switch.py: this run starts again from 0 (same as right-click "重新计一次")
    string sw = Str(s, "agent_switch"); cAgent = Str(s, "agent");
    if (sw != "" && sw != cSw) { if (cSw != "" || Num(s, "agent_switch_t") > rAct) { bUses = 0; bReal = 0; bEst = 0; bIn = 0; bCa = 0; bOut = 0; bSplit = true; bIds = new HashSet<string>(); bLib = new HashSet<string>(libIds); bGen = genAbs; bGenLib = new HashSet<string>(genIds); rAct = Epoch(); rLast = rAct; snap = false; if (runReady) { swFresh = false; SaveRun(); } } cSw = sw; }

    object po; var pr = s.TryGetValue("price", out po) ? po as Dictionary<string, object> : null;

    if (pr != null && Str(pr, "unit").ToUpperInvariant().Contains("CNY")) {

      if (Has(pr, "in")) pIn = Num(pr, "in"); if (Has(pr, "cache")) pCa = Num(pr, "cache"); if (Has(pr, "out")) pOut = Num(pr, "out"); }

    // real split of this session (nx_exp.ps1 "spent": in_uncached, cache_read, out)

    double ri = 0, rc = 0, ro = 0; object so; var sp = s.TryGetValue("spent", out so) ? so as Dictionary<string, object> : null;

    if (real > 0 && sp != null) { ri = Num(sp, "in_uncached"); rc = Num(sp, "cache_read"); ro = Num(sp, "out"); }

    if (ri + rc + ro <= 0) {

      // no "spent" this time: use the split nx_exp.ps1 keeps in real_bd / real_ld / real_pd ("in_uncached,cache_read,out")

      double[] bd = Trio(s, "real_bd"), ld = Trio(s, "real_ld"), pd = Trio(s, "real_pd");

      ri = Math.Max(0, pd[0] + ld[0] - bd[0]); rc = Math.Max(0, pd[1] + ld[1] - bd[1]); ro = Math.Max(0, pd[2] + ld[2] - bd[2]);

      // nothing new since the task began: this run = 0. Never fill it with the whole client session (real_ld / real_bd), e.g. an old DeepSeek local record.


    }

    double[] lv = LiveUsage(s);
    // agent mounted via nx_agent_switch but its log is empty / has no usage: this run = 0 (not counted). Never reuse the last run's or another agent's (e.g. DeepSeek local record) real/cache numbers.
    // read io\agent_switch.json directly as well: the status / exp_stats copy ("agent_switch") is cleared when a new task starts
    string swAgent = "", swLog = "";
    try { string swp = System.IO.Path.Combine(ioDir, "agent_switch.json"); if (File.Exists(swp)) { string swt = File.ReadAllText(swp, Encoding.UTF8);
      var ma = System.Text.RegularExpressions.Regex.Match(swt, "\"agent\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""); if (ma.Success) swAgent = System.Text.RegularExpressions.Regex.Unescape(ma.Groups[1].Value).Trim();
      var ml = System.Text.RegularExpressions.Regex.Match(swt, "\"log\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""); if (ml.Success) swLog = System.Text.RegularExpressions.Regex.Unescape(ml.Groups[1].Value).Trim(); } } catch { }
    if (cAgent == "") cAgent = swAgent;
    string agL = cAgent.ToLowerInvariant(); bool agDs = agL.IndexOf("deepseek") >= 0 || agL.IndexOf("dsh") >= 0;
    bool mounted = sw != "" || swAgent != "";
    bool logBad = swLog != "" && (!File.Exists(swLog) || new FileInfo(swLog).Length == 0);   // agent log deleted or 0 byte (e.g. Doubao)
    // mounted non-DeepSeek agent with no usage of its own (no live log value, or its log is missing / empty): this run = 0, never DeepSeek real_ld / spent
    cNoUse = mounted && !agDs && (lv == null || logBad);
    if (cNoUse) lv = null;
    if (cNoUse) { ri = 0; rc = 0; ro = 0; cSrc = "none"; }
    if (lv != null) { ri = lv[0]; rc = lv[1]; ro = lv[2]; if (cSrc == "" || cSrc == "estimate") cSrc = lv[3] == 1 ? "grok-local" : lv[3] == 2 ? "codex-local" : lv[3] == 3 ? "log-local" : "agy-local"; }
    real = ri + rc + ro;
    // a baseline above the current numbers is stale (old reset / previous agent): drop it, so a reset never keeps a stale real as base
    if (runReady && (ri < bIn || rc < bCa || ro < bOut)) { bIn = 0; bCa = 0; bOut = 0; bReal = 0; SaveRun(); }
    if (zOn && (ri < zIn || rc < zCa || ro < zOut)) { zIn = 0; zCa = 0; zOut = 0; zReal = 0; SaveZ(); }

    double u = Num(s, "uses"), est = Math.Max(0, Num(s, "tool_tokens")) + Math.Max(0, Num(s, "exp_tokens"));

    var ids = Ids(s, "used_ids");

    bool changed = !snap || u != cUses || est != cEst || real != cReal || ri != cIn || rc != cCa || ro != cOut;

    if (runReady && snap && changed) {

      if (u < bUses || est < bEst) { bUses = 0; bReal = 0; bEst = 0; bIn = 0; bCa = 0; bOut = 0; bSplit = true; bIds = new HashSet<string>(); rAct = 0; rLast = 0; }   // the session counters restarted

      else if (rLast > 0 && now - rLast > Gap) { bUses = cUses; bReal = cReal; bEst = cEst; bIn = cIn; bCa = cCa; bOut = cOut; bSplit = true; bIds = new HashSet<string>(cIds); bLib = new HashSet<string>(libIds); bGen = genAbs; bGenLib = new HashSet<string>(genIds); rAct = 0; rLast = 0; }  // idle long enough: a new run

      if (rAct <= 0) rAct = now; rLast = now; SaveRun();

    }

    // totals: add what this session added since last seen

    if (changed) {

      if (tSince <= 0) tSince = Num(s, "task_start") > 0 ? Num(s, "task_start") : now;

      if ((int)tPid != nxPid) { tUses += u; tReal += real; tEst += est; tIn += ri; tCa += rc; tOut += ro; }

      else { tUses += u >= tLU ? u - tLU : u; tReal += real >= tLR ? real - tLR : real; tEst += est >= tLE ? est - tLE : est;

        tIn += ri >= tLI ? ri - tLI : ri; tCa += rc >= tLC ? rc - tLC : rc; tOut += ro >= tLO ? ro - tLO : ro; }

      if (snap && tLact > 0 && now > tLact && now - tLact <= Gap) tSec += now - tLact;

      tPid = nxPid; tLU = u; tLR = real; tLE = est; tLI = ri; tLC = rc; tLO = ro; if (snap) tLact = now; SaveTot();

    }

    cUses = u; cReal = real; cEst = est; cIn = ri; cCa = rc; cOut = ro; cIds = ids; cDistinct = Num(s, "session_used"); cTaskStart = Num(s, "task_start"); snap = true;

  }



  // the five numbers: library total + this run

  // consumption tile: always a real amount. Order: this run (real split) -> whole session (real) -> this run (estimate) -> session estimate -> totals on this computer

  Dictionary<string,object> CurrentTask(Dictionary<string,object> flow) {
    if(flow==null) return null;
    var current=Has(flow,"current") ? flow["current"] as Dictionary<string,object> : null;
    if(current!=null) return current;
    var history=Has(flow,"history") ? JArr(flow["history"]) : null;
    return history!=null && history.Length>0 ? history[history.Length-1] as Dictionary<string,object> : null;
  }
  List<Dictionary<string,object>> IndexEntries(string dir) {
    var result=new List<Dictionary<string,object>>();
    var index=ReadJson(System.IO.Path.Combine(dir,"索引.json"));
    var entries=Has(index,"entries") ? JArr(index["entries"]) : null;
    var ids=new HashSet<string>();
    if(entries!=null) foreach(var item in entries) { var row=item as Dictionary<string,object>; if(row!=null && ids.Add(Str(row,"id"))) result.Add(row); }
    return result;
  }
  string TaskSlot() {
    var task=CurrentTask(ReadJson(System.IO.Path.Combine(libDir,"流程.json")));
    string slot=Str(task,"slot");
    return System.Text.RegularExpressions.Regex.IsMatch(slot,"^[a-z][a-z0-9_-]{0,31}$") && slot!="generic" && slot!="all" ? slot : "";
  }
  int CommonCount() { return IndexEntries(System.IO.Path.Combine(libDir,"槽","generic")).Count+IndexEntries(System.IO.Path.Combine(libDir,"通用技能库")).Count; }
  int SoftwareCount(string slot) { return slot=="" ? 0 : IndexEntries(System.IO.Path.Combine(libDir,"槽",slot)).Count; }
  List<Dictionary<string,object>> ActualEvents() {
    var result=new List<Dictionary<string,object>>();
    string dir=System.IO.Path.Combine(System.IO.Path.GetDirectoryName(ioDir),"events");
    if(Directory.Exists(dir)) foreach(string file in Directory.GetFiles(dir,"*.json")) { var e=ReadJson(file); if(e!=null) result.Add(e); }
    return result;
  }
  bool VerifiedEvent(Dictionary<string,object> e) {
    var d=Has(e,"data") ? e["data"] as Dictionary<string,object> : null;
    return Str(e,"kind")=="experience_verified" && (Str(d,"verification")=="independent_adapter_readback" || Str(d,"verification")=="independent_software_readback");
  }
  bool Retrieval(Dictionary<string,object> d) {
    var command=Has(d,"command") ? JArr(d["command"]) : null;
    return command!=null && command.Length>0 && Array.IndexOf(new[]{"exp_search","exp_recall","exp_get","skill_search","skill_get"},Convert.ToString(command[0],IC))>=0 && Num(d,"exit_code")==0;
  }
  bool AfterDisplayReset(Dictionary<string,object> e) {
    var reset=ReadJson(System.IO.Path.Combine(ioDir,"actual_display_reset.json"));
    return reset==null || string.CompareOrdinal(Str(e,"time"),Str(reset,"time"))>0;
  }
  Dictionary<string,object> UsageSessions() {
    var sessions=new Dictionary<string,object>();
    foreach(var e in ActualEvents()) {
      var d=Has(e,"data") ? e["data"] as Dictionary<string,object> : null;
      if(Str(e,"kind")!="usage_snapshot" || Str(d,"source_kind")!="runtime_measured" || Str(d,"session")=="") continue;
      string session=Str(d,"session"); double old=sessions.ContainsKey(session) ? Convert.ToDouble(sessions[session],IC) : 0;
      sessions[session]=Math.Max(old,Num(d,"total_tokens"));
    }
    var current=ReadJson(System.IO.Path.Combine(ioDir,"actual_usage.json"));
    if(Str(current,"source_kind")=="runtime_measured" && Str(current,"session")!="") {
      string session=Str(current,"session"); double old=sessions.ContainsKey(session) ? Convert.ToDouble(sessions[session],IC) : 0;
      sessions[session]=Math.Max(old,Num(current,"total_tokens"));
    }
    return sessions;
  }
  void ResetActualDisplay() {
    var reset=new Dictionary<string,object>();reset["time"]=DateTime.UtcNow.ToString("o");reset["sessions"]=UsageSessions();
    var usage=ReadJson(System.IO.Path.Combine(ioDir,"actual_usage.json"));
    reset["session"]=Str(usage,"session");reset["task"]=Str(usage,"task");reset["task_tokens"]=Num(usage,"task_tokens");
    string target=System.IO.Path.Combine(ioDir,"actual_display_reset.json"), temp=System.IO.Path.Combine(ioDir,Guid.NewGuid().ToString("N")+".tmp");
    try { File.WriteAllText(temp,js.Serialize(reset),new UTF8Encoding(false)); if(File.Exists(target)) File.Replace(temp,target,null); else File.Move(temp,target); }
    finally { if(File.Exists(temp)) File.Delete(temp); }
  }
  Button SmallButton(string text, Action click, bool primary) {
    var button=new Button { Content=text, Padding=new Thickness(14,7,14,7), Margin=new Thickness(6,0,0,0), Cursor=Cursors.Hand, FontSize=12,
      Background=primary ? new SolidColorBrush(C2) : new SolidColorBrush(Soft), Foreground=primary ? Brushes.White : new SolidColorBrush(Ink), BorderThickness=new Thickness(0) };
    var border=new FrameworkElementFactory(typeof(Border));border.SetValue(Border.CornerRadiusProperty,new CornerRadius(8));
    border.SetBinding(Border.BackgroundProperty,new System.Windows.Data.Binding("Background"){RelativeSource=new System.Windows.Data.RelativeSource(System.Windows.Data.RelativeSourceMode.TemplatedParent)});
    border.SetBinding(Border.PaddingProperty,new System.Windows.Data.Binding("Padding"){RelativeSource=new System.Windows.Data.RelativeSource(System.Windows.Data.RelativeSourceMode.TemplatedParent)});
    var presenter=new FrameworkElementFactory(typeof(ContentPresenter));presenter.SetValue(ContentPresenter.HorizontalAlignmentProperty,HorizontalAlignment.Center);border.AppendChild(presenter);
    button.Template=new ControlTemplate(typeof(Button)){VisualTree=border};button.Click+=(s,e)=>click();return button;
  }
  Window RoundedDialog(string title, out StackPanel body) {
    var w=new Window {Title="YA · "+title,Owner=this,WindowStyle=WindowStyle.None,AllowsTransparency=true,Background=Brushes.Transparent,ResizeMode=ResizeMode.NoResize,
      ShowInTaskbar=false,SizeToContent=SizeToContent.WidthAndHeight,FontFamily=FontFamily,UseLayoutRounding=true,WindowStartupLocation=WindowStartupLocation.CenterOwner};
    TextOptions.SetTextFormattingMode(w,TextFormattingMode.Display);
    var frame=new Border {Width=350,CornerRadius=new CornerRadius(15),BorderThickness=new Thickness(1),BorderBrush=new SolidColorBrush(Edge),Background=Brushes.White,Padding=new Thickness(18),Margin=new Thickness(12),Effect=new DropShadowEffect{BlurRadius=12,ShadowDepth=2,Opacity=0.12}};
    var stack=new StackPanel();frame.Child=stack;
    var head=new DockPanel {Margin=new Thickness(0,0,0,12)};
    var close=new TextBlock{Text="×",FontSize=18,Foreground=new SolidColorBrush(Sub),Cursor=Cursors.Hand,Padding=new Thickness(6,0,0,0)};
    close.MouseLeftButtonUp+=(s,e)=>w.Close();DockPanel.SetDock(close,Dock.Right);head.Children.Add(close);
    var caption=new TextBlock{Text=title,FontSize=14,FontWeight=FontWeights.SemiBold,Foreground=new SolidColorBrush(Ink),Padding=new Thickness(0,3,0,0)};
    caption.MouseLeftButtonDown+=(s,e)=>{if(e.ChangedButton==MouseButton.Left)try{w.DragMove();}catch{}};head.Children.Add(caption);stack.Children.Add(head);
    body=new StackPanel();stack.Children.Add(new ScrollViewer{Content=body,MaxHeight=460,VerticalScrollBarVisibility=ScrollBarVisibility.Auto,HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled});
    w.Content=frame;w.KeyDown+=(s,e)=>{if(e.Key==Key.Escape)w.Close();};return w;
  }
  void InfoRow(StackPanel body,string label,string value) {
    var row=new Grid{Margin=new Thickness(0,5,0,5)};row.ColumnDefinitions.Add(new ColumnDefinition{Width=new GridLength(100)});row.ColumnDefinitions.Add(new ColumnDefinition());
    row.Children.Add(new TextBlock{Text=label,FontSize=12,Foreground=new SolidColorBrush(Sub)});
    var text=new TextBlock{Text=value,FontSize=12,Foreground=new SolidColorBrush(Ink),TextWrapping=TextWrapping.Wrap};Grid.SetColumn(text,1);row.Children.Add(text);body.Children.Add(row);
  }
  void ShowReset() {
    StackPanel body;var w=RoundedDialog("重置统计",out body);
    body.Children.Add(new TextBlock{Text="清零显示统计，经验和任务记录保留。",FontSize=12,Foreground=new SolidColorBrush(Sub),TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,2,0,18)});
    var buttons=new StackPanel{Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right};
    buttons.Children.Add(SmallButton("取消",()=>w.Close(),false));buttons.Children.Add(SmallButton("重置",()=>{ResetActualDisplay();ResetAll();w.Close();},true));body.Children.Add(buttons);w.ShowDialog();
  }
  List<Dictionary<string,object>> InventoryRows() {
    var rows=new List<Dictionary<string,object>>();var dirs=new HashSet<string>();dirs.Add(System.IO.Path.Combine(libDir,"槽","generic"));
    var slots=ReadJson(System.IO.Path.Combine(libDir,"槽位.json"));var all=Has(slots,"slots") ? JArr(slots["slots"]) : null;
    if(all!=null)foreach(var item in all){string id=Str(item as Dictionary<string,object>,"id");if(id!="all" && System.Text.RegularExpressions.Regex.IsMatch(id,"^[a-z][a-z0-9_-]{0,31}$"))dirs.Add(System.IO.Path.Combine(libDir,"槽",id));}
    dirs.Add(System.IO.Path.Combine(libDir,"通用技能库"));
    foreach(string dir in dirs)foreach(var row in IndexEntries(dir)){row["_library_dir"]=dir;rows.Add(row);}return rows;
  }
  void InventoryBars(List<Dictionary<string,object>> rows) {
    if(rows.Count==0)return;double moves=0,pits=0,plans=0,other=0,verified=0;
    foreach(var row in rows){string category=Str(row,"c");if(category=="招式")moves++;else if(category=="坑")pits++;else if(category=="零件方案")plans++;else other++;
      try{string dir=Str(row,"_library_dir"),file=System.IO.Path.GetFullPath(System.IO.Path.Combine(dir,Str(row,"f")));if(file.StartsWith(dir+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)&&file.EndsWith(".json",StringComparison.OrdinalIgnoreCase)){var record=ReadJson(file);if(JFlag(record,"independently_verified")&&Str(record,"lifecycle")!="withdrawn")verified++;}}catch{}
    }
    double width=260,total=rows.Count;
    BarBlock("分类","招式 "+moves+" · 坑 "+pits+" · 方案 "+plans+" · 候选/其他 "+other,
      Seg(width*moves/total,C2),Seg(width*pits/total,Warn),Seg(width*plans/total,Ok),Seg(width*other/total,Idle));
    BarBlock("核验记录","有独立核验记录 "+verified+" · 待核验/已停用 "+(total-verified)+"。记录状态不替代本次工程验收。",
      Seg(width*verified/total,Ok),Seg(width*(total-verified)/total,Idle));
  }
  void CurrentTokenBar() {
    var usage=ReadJson(System.IO.Path.Combine(ioDir,"actual_usage.json"));
    if(Str(usage,"source_kind")!="runtime_measured" || !Has(usage,"task_input_tokens") || !Has(usage,"task_output_tokens"))return;
    // A display reset has only a total baseline; do not invent an input/output split after it.
    if(ReadJson(System.IO.Path.Combine(ioDir,"actual_display_reset.json"))!=null)return;
    double input=Num(usage,"task_input_tokens"),output=Num(usage,"task_output_tokens"),total=input+output;
    if(input<0||output<0||total<=0||Math.Abs(total-Num(usage,"task_tokens"))>0.001)return;
    BarBlock("用量构成","本次已接入的实测输入 "+Big(input)+" · 输出 "+Big(output)+" Token；不代表估算费用。",
      Seg(260*input/total,Color.FromRgb(0x34,0xD3,0x99)),Seg(260*output/total,Color.FromRgb(0x60,0xA5,0xFA)));
  }
  void FillActualTotals() {
    if(totBody==null)return;totBody.Children.Clear();int calls=0,reused=0;double seconds=0;var tasks=new HashSet<string>();
    foreach(var e in ActualEvents()){if(!AfterDisplayReset(e))continue;var d=Has(e,"data") ? e["data"] as Dictionary<string,object> : null;
      if(Str(e,"kind")=="runtime" && Retrieval(d))calls++;
      if(VerifiedEvent(e)){tasks.Add(Str(d,"task"));seconds+=Num(d,"elapsed_ms")/1000;if(Str(d,"reused_experience")!="")reused++;}}
    var sessions=UsageSessions();var reset=ReadJson(System.IO.Path.Combine(ioDir,"actual_display_reset.json"));var bases=Has(reset,"sessions") ? reset["sessions"] as Dictionary<string,object> : null;double tokens=0;
    foreach(var session in sessions){double baseline=bases!=null && bases.ContainsKey(session.Key) ? Convert.ToDouble(bases[session.Key],IC) : 0;tokens+=Math.Max(0,Convert.ToDouble(session.Value,IC)-baseline);}
    Sec("本次");Row("TOKEN",vTokn.Text+(uTokn.Text!="" ? " "+uTokn.Text : ""));Row("用时",vTime.Text+uTime.Text);Row("新收",vLib.Text+" 条");Row("成功复用",SuccessfulCurrentReuses()+" 次");
    CurrentTokenBar();
    Sec("经验库");var inventory=InventoryRows();Row("总条数",inventory.Count+" 条");InventoryBars(inventory);
    Sec("本次任务");var current=CurrentTask(ReadJson(System.IO.Path.Combine(libDir,"流程.json")));Row("状态",current==null ? "未开任务" : Str(current,"status"));Row("调用",vUse.Text+" 次");
    Sec(reset==null ? "本工作区累计" : "本工作区累计（重置后）");Row("调用",calls+" 次");Row("总 TOKEN",sessions.Count>0 ? Big(tokens) : "未统计");Row("核验任务",tasks.Count+" 次");Row("成功复用",reused+" 次");Row("软件用时",DurText(seconds));
    totBody.Children.Add(new TextBlock{Text="悬停条形看明细 · 来自本工作区记录",FontSize=10.5,Foreground=new SolidColorBrush(Sub),TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,8,0,0)});
  }
  int SuccessfulCurrentReuses(){int count=0;string task=Str(CurrentTask(ReadJson(System.IO.Path.Combine(libDir,"流程.json"))),"id");foreach(var e in ActualEvents()){var d=Has(e,"data") ? e["data"] as Dictionary<string,object> : null;if(AfterDisplayReset(e)&&VerifiedEvent(e)&&Str(d,"task")==task&&Str(d,"reused_experience")!="")count++;}return count;}

  void AddMethodRows(StackPanel body,string dir,string prefix) {
    int count=0;foreach(var row in IndexEntries(dir)) {
      if(++count>20)break;
      string file=Str(row,"f"), full="";Dictionary<string,object> record=null;
      try{full=System.IO.Path.GetFullPath(System.IO.Path.Combine(dir,file));if(full.StartsWith(System.IO.Path.GetFullPath(dir)+System.IO.Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase) && full.EndsWith(".json",StringComparison.OrdinalIgnoreCase))record=ReadJson(full);}catch{}
      string title=JText(row,"t","title","name"),id=Str(row,"id");
      var item=new Expander{Header=new TextBlock{Text=prefix+" · "+title,TextWrapping=TextWrapping.Wrap},FontSize=12,Margin=new Thickness(0,7,0,7),Foreground=new SolidColorBrush(Ink)};
      var content=new StackPanel();item.Content=content;
      string status=record==null ? "记录缺失" : Str(record,"lifecycle")=="withdrawn" ? "已停用" : JFlag(record,"independently_verified") ? "独立核验" : "待核验";
      InfoRow(content,"编号",id);InfoRow(content,"状态",status);
      var recipe=Has(record,"recipe") ? record["recipe"] as Dictionary<string,object> : null;
      var conditions=Has(recipe,"conditions") ? recipe["conditions"] as Dictionary<string,object> : null;
      if(conditions!=null)InfoRow(content,"适用条件",Str(conditions,"software")+" "+Str(conditions,"version")+" · "+Str(conditions,"interface"));
      if(Has(conditions,"parameters"))InfoRow(content,"参数",js.Serialize(conditions["parameters"]));
      InfoRow(content,"来源",recipe!=null ? JText(recipe,"source") : JText(record,"source"));InfoRow(content,"适用边界",Str(recipe,"applicability"));
      var steps=Has(recipe,"steps") ? JArr(recipe["steps"]) : null;if(steps!=null)foreach(var step in steps)content.Children.Add(new TextBlock{Text="· "+Convert.ToString(step,IC),FontSize=12,TextWrapping=TextWrapping.Wrap,Margin=new Thickness(0,4,0,0)});
      if(Has(record,"context")) {var context=record["context"] as Dictionary<string,object>;InfoRow(content,"验证任务",Str(context,"task"));}
      // Evidence stays available on demand, without dumping the event ledger into the main dialog.
      var evidence=new Expander{Header="原始记录",FontSize=11,Foreground=new SolidColorBrush(Sub),Margin=new Thickness(0,10,0,0)};
      evidence.Content=new TextBox{Text=record==null ? "记录缺失" : js.Serialize(record),IsReadOnly=true,TextWrapping=TextWrapping.Wrap,MaxHeight=160,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};content.Children.Add(evidence);body.Children.Add(item);
    }
    if(count>20)body.Children.Add(new TextBlock{Text="显示前20条，完整记录保存在本机经验库。",FontSize=11,Foreground=new SolidColorBrush(Sub)});
  }

  void ShowMoney(bool live) { ShowActualUsage(); }
  void ShowActualUsage() {
    var d = ReadJson(System.IO.Path.Combine(ioDir, "actual_usage.json"));
    bool known = d != null && Str(d, "source_kind") == "runtime_measured";
    vTokn.Text = known ? Big(Num(d, "task_tokens")) : "未统计";
    uTokn.Text = known ? "tok" : "";vTokn.FontSize=known ? 24 : 18;
    vTok.Text = "待对照"; uTok.Text = "Token 节省";
    tTokn.ToolTip = known ? "运行环境实测 · " + Str(d,"model") + "\n会话累计 " + Num(d,"total_tokens") + "\n来源时间 " + Str(d,"source_time") + "\n点击查看来源与任务" : "未接入真实用量源；不使用估算";
    var reset=ReadJson(System.IO.Path.Combine(ioDir,"actual_display_reset.json"));
    double baseline=known && Str(reset,"session")==Str(d,"session") && Str(reset,"task")==Str(d,"task") ? Num(reset,"task_tokens") : 0;
    shownTok = known ? Math.Max(0,Num(d,"task_tokens")-baseline) : 0;
    if(known) vTokn.Text=Big(shownTok);
  }
  string ActualDetails() {
    var b = new StringBuilder("真实事件记录（命中/调取不等于复用成功）\nToken 节省：待对照\n\n");
    string usage = System.IO.Path.Combine(ioDir, "actual_usage.json");
    if (File.Exists(usage)) b.AppendLine(File.ReadAllText(usage, Encoding.UTF8));
    string events = System.IO.Path.Combine(System.IO.Path.GetDirectoryName(ioDir), "events");
    if (Directory.Exists(events)) {
      var files = new List<string>(Directory.GetFiles(events, "*.json"));
      files.Sort((a,c) => File.GetLastWriteTimeUtc(c).CompareTo(File.GetLastWriteTimeUtc(a)));
      int n=0; foreach (string f in files) { if (++n > 100) break; b.AppendLine(File.ReadAllText(f, Encoding.UTF8)); }
    }
    return b.ToString();
  }
  void ShowActualEvents() {
    int searches=0, reads=0, verified=0, reused=0; double measuredSeconds=0, retrievalSeconds=0, commandSeconds=0;
    string verifiedMode="";
    var current=CurrentTask(ReadJson(System.IO.Path.Combine(libDir,"流程.json")));
    string task=Str(current,"id"), slot=TaskSlot();
    int common=CommonCount(), software=SoftwareCount(slot);
    vAll.Text=InventoryRows().Count.ToString(IC);uAll.Text="条";
    tAll.ToolTip="本工作区总库存，不随调用次数变化。通用正式 "+IndexEntries(System.IO.Path.Combine(libDir,"槽","generic")).Count+"，候选知识 "+IndexEntries(System.IO.Path.Combine(libDir,"通用技能库")).Count+"；合计还包含已登记软件槽的条目，按软件分槽保存。";
    string events=System.IO.Path.Combine(System.IO.Path.GetDirectoryName(ioDir),"events");
    if (Directory.Exists(events)) foreach(string f in Directory.GetFiles(events,"*.json")) {
      var ev=ReadJson(f); if(ev==null || !AfterDisplayReset(ev)) continue;
      if(Str(ev,"kind")=="experience_verified") {
        var proof=ev["data"] as Dictionary<string,object>;
        if(proof!=null && task!="" && Str(proof,"task")==task && Str(proof,"slot")==Str(current,"slot") && (Str(proof,"verification")=="independent_software_readback" || Str(proof,"verification")=="independent_adapter_readback")) {
          verified++; verifiedMode=Str(proof,"mode"); measuredSeconds+=Num(proof,"elapsed_ms")/1000.0; if(Str(proof,"reused_experience")!="") reused++;
        }
        continue;
      }
      if(Str(ev,"kind")=="command_result") { var commandData=ev["data"] as Dictionary<string,object>; if(task!="" && Str(commandData,"task")==task) commandSeconds+=Num(commandData,"elapsed_ms")/1000.0; continue; }
      if(Str(ev,"kind")!="runtime") continue;
      var d=ev["data"] as Dictionary<string,object>; if(d==null || Num(d,"exit_code")!=0) continue;
      var t=Has(d,"task") ? d["task"] as Dictionary<string,object> : null;
      if(task=="" || t==null || Str(t,"id")!=task) continue;
      var command=d["command"] as object[];
      if(command==null || command.Length==0) continue;
      string action=Convert.ToString(command[0]);
      if(action=="exp_search" || action=="exp_recall" || action=="skill_search") searches++;
      else if(action=="exp_get" || action=="skill_get") reads++;
      else continue;
      retrievalSeconds+=Num(d,"elapsed_ms")/1000.0;
    }
    int calls=searches+reads;
    vUse.Text=calls.ToString(IC); uUse.Text="次";
    vUse.ToolTip="检索 "+searches+" 次 · 读取全文 "+reads+" 次";
    vLib.Text=verified.ToString(IC); uLib.Text="条";
    if(verified>0) { string val,unit; Dur(measuredSeconds,out val,out unit); vTime.Text=val;uTime.Text=unit; }
    else { vTime.Text="未统计";uTime.Text=""; }
    tTime.ToolTip="前台命令等待（未等同工程验收）："+commandSeconds.ToString("0.###",IC)+" 秒；软件执行及独立验证："+measuredSeconds.ToString("0.###",IC)+" 秒；检索/调取："+retrievalSeconds.ToString("0.###",IC)+" 秒。来源为持久化事件。";

    tLib.ToolTip="适配器回报不等于独立工程验收；点击查看原始事件。";
    hudCalls=calls;
    if(current!=null) dSub.Text=TwoChecks()+" · "+(verifiedMode=="batch" ? "批处理已验收" : Str(current,"status"));
    try {
      var view=new Dictionary<string,object>();
      view["rendered_utc"]=DateTime.UtcNow.ToString("o");view["task_id"]=task;
      view["token_text"]=vTokn.Text;view["savings_text"]=vTok.Text;
      view["library_text"]=vAll.Text;view["common_entries"]=common;view["software_entries"]=software;view["task_percent"]=taskPct;view["task_status"]=Str(current,"status");view["retrieval_calls"]=calls;view["verified_new"]=verified;view["successful_reuses"]=reused;
      view["task_text"]=dSub.Text;view["software_status"]=LinkText();view["command_seconds"]=commandSeconds;view["measured_seconds"]=measuredSeconds;view["retrieval_seconds"]=retrievalSeconds;
      view["retrieval_count"]=searches;view["read_count"]=reads;view["verified_task_mode"]=verifiedMode;
      File.WriteAllText(System.IO.Path.Combine(ioDir,"hud_view.json"),js.Serialize(view),new UTF8Encoding(false));
    } catch { }
    if(totWin!=null) FillActualTotals();

  }
  void ShowUsageDetails() {
    StackPanel body;var w=RoundedDialog("用量来源",out body);
    var data=ReadJson(System.IO.Path.Combine(ioDir,"actual_usage.json"));
    if(Str(data,"source_kind")!="runtime_measured") InfoRow(body,"Token","未统计 · 尚未接入真实来源");
    else {
      InfoRow(body,"服务商",Str(data,"provider"));InfoRow(body,"模型",Str(data,"model"));
      InfoRow(body,"输入 Token",Big(Num(data,"input_tokens")));InfoRow(body,"输出 Token",Big(Num(data,"output_tokens")));
      InfoRow(body,"会话累计",Big(Num(data,"total_tokens")));InfoRow(body,"本次显示",vTokn.Text);InfoRow(body,"来源时间",Str(data,"source_time"));
      var provenance=new Expander{Header="来源记录",FontSize=11,Foreground=new SolidColorBrush(Sub),Margin=new Thickness(0,8,0,0)};
      var info=new StackPanel();InfoRow(info,"会话",Str(data,"session"));InfoRow(info,"任务",Str(data,"task"));InfoRow(info,"日志",Str(data,"source"));provenance.Content=info;body.Children.Add(provenance);
    }
    w.Show();
  }
  void ShowActualDetails() {
    StackPanel body;var w=RoundedDialog("经验记录",out body);
    InfoRow(body,"经验库","通用 "+CommonCount()+" · 软件 "+SoftwareCount(TaskSlot()));
    body.Children.Add(new TextBlock{Text="点击方法查看条件与验证记录",FontSize=11,Foreground=new SolidColorBrush(Sub),Margin=new Thickness(0,6,0,8)});
    AddMethodRows(body,System.IO.Path.Combine(libDir,"槽","generic"),"通用");
    AddMethodRows(body,System.IO.Path.Combine(libDir,"通用技能库"),"候选");
    string slot=TaskSlot();if(slot!="") AddMethodRows(body,System.IO.Path.Combine(libDir,"槽",slot),"软件");
    if(CommonCount()+SoftwareCount(slot)==0) body.Children.Add(new TextBlock{Text="还没有经验，完成任务后逐步积累。",Foreground=new SolidColorBrush(Sub),FontSize=12});
    w.Show();
  }

  int JInt(Dictionary<string, object> d, params string[] keys) {
    if (d == null) return -1;
    foreach (string k in keys) if (Has(d, k)) return (int)Math.Round(Num(d, k));
    return -1;
  }
  string JText(Dictionary<string, object> d, params string[] keys) {
    if (d == null) return "";
    foreach (string k in keys) {
      if (!Has(d, k)) continue;
      string s = Str(d, k);
      double n;
      if (double.TryParse(s, NumberStyles.Float, IC, out n)) {
        if (Math.Abs(n - Math.Round(n)) < 1e-6) return Math.Round(n).ToString(IC);
        return n.ToString("0.###", IC);
      }
      return s;
    }
    return "";
  }
  bool JOk(Dictionary<string, object> it) {
    object v;
    if (it == null || !it.TryGetValue("ok", out v) || v == null) return false;
    if (v is bool) return (bool)v;
    string s = Convert.ToString(v, IC);
    return s == "1" || s.Equals("true", StringComparison.OrdinalIgnoreCase);
  }
  object[] JArr(object o) {
    if (o is object[]) return (object[])o;
    System.Collections.ArrayList al = o as System.Collections.ArrayList;
    if (al != null) return al.ToArray();
    return null;
  }
  // library switched (installer / 切库 rewrote library_path.txt): follow it live, no need to restart the card
  DateTime mtLibTxt = DateTime.MinValue;
  void RefreshLib() { } // 本卡始终绑定启动它的包。
  // dim row guard: the current part is the leaf of the last nx_new_part in io\<pid>\journal.jsonl (empty = unknown, no check)
  static string PartLeaf(string p) {
    if (p == null) return "";
    p = p.Trim().Trim('"');
    int i = Math.Max(p.LastIndexOf('\\'), p.LastIndexOf('/'));
    if (i >= 0) p = p.Substring(i + 1);
    if (p.EndsWith(".prt", StringComparison.OrdinalIgnoreCase)) p = p.Substring(0, p.Length - 4);
    return p;
  }
  string CurPartLeaf() {
    try {
      string jf = System.IO.Path.Combine(ioDir, nxPid + "\\journal.jsonl");
      if (!File.Exists(jf)) { jPart = ""; mtJour = DateTime.MinValue; return ""; }
      DateTime mj = File.GetLastWriteTimeUtc(jf);
      if (mj == mtJour) return jPart;
      string last = "";
      var rxT = new System.Text.RegularExpressions.Regex("\"tool\"\\s*:\\s*\"nx_new_part\"");
      var rxP = new System.Text.RegularExpressions.Regex("\"path\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
      var rxN = new System.Text.RegularExpressions.Regex("\"name\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");   // nx_new_part may give only a name (no path)
      using (var fs = new FileStream(jf, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
      using (var sr = new StreamReader(fs, new UTF8Encoding(false))) {
        string line;
        while ((line = sr.ReadLine()) != null) {
          if (!rxT.IsMatch(line)) continue;
          var m = rxP.Match(line);
          if (!m.Success) m = rxN.Match(line);
          if (m.Success) last = m.Groups[1].Value.Replace("\\\\", "\\");
        }
      }
      mtJour = mj; jPart = PartLeaf(last);
    } catch { }
    return jPart;
  }
  void SetStale(string why) {
    dimKnown = false; dimStale = true; dimPerfect = false;
    dimShort = "\u672a\u5bf9\u7167 \u00b7 " + why.Split('\n')[0];
    dimReport = "\u5c3a\u5bf8\u6838\u5bf9\n\u672a\u5bf9\u7167\uff08\u4e0d\u662f\u5f53\u524d\u8fd9\u4e00\u5355\u7684\u7ed3\u679c\uff09\n" + why;
  }
  void ReadDim() {
    string f = System.IO.Path.Combine(ioDir, "dim_check.json");
    if (!File.Exists(f)) { dimKnown = false; dimStale = false; dimPerfect = false; dimKey = ""; dimReport = "\u8fd8\u6ca1\u6709 io\\dim_check.json"; return; }
    DateTime mt;
    try { mt = File.GetLastWriteTimeUtc(f); } catch { return; }
    string cur = CurPartLeaf();
    string key = mt.Ticks.ToString(IC) + "|" + (runReady ? rAct : 0).ToString("0.###", IC) + "|" + cur;
    if ((dimKnown || dimStale) && key == dimKey) return;
    Dictionary<string, object> d = ReadJson(f);
    if (d == null) { dimKnown = false; dimStale = false; dimPerfect = false; dimKey = ""; dimReport = "dim_check.json \u8bfb\u4e0d\u4e86"; return; }
    dimKey = key;
    string fPart0 = JText(d, "part", "\u96f6\u4ef6");
    if (fPart0 == "") { string fSet = JText(d, "set"); if (fSet != "" && cur != "" && (cur.Equals(fSet, StringComparison.OrdinalIgnoreCase) || cur.EndsWith("_" + fSet, StringComparison.OrdinalIgnoreCase))) fPart0 = cur; }   // no "part" field: "set" names it (dim_check_<set>)
    if (cur != "" && !string.Equals(PartLeaf(fPart0), cur, StringComparison.OrdinalIgnoreCase)) {
      SetStale("\u5f53\u524d\u96f6\u4ef6 " + cur + " \u8fd8\u6ca1\u5bf9\u7167\n\u6587\u4ef6\u91cc\u662f " + (fPart0 == "" ? "?" : fPart0) + " \u7684\u65e7\u7ed3\u679c");
      return;
    }
    if (runReady && rAct > 0 && (mt - E0).TotalSeconds < rAct) {
      SetStale("\u7ed3\u679c\u65e9\u4e8e\u672c\u6b21\u5f00\u59cb\n\u6587\u4ef6\u91cc\u662f " + (fPart0 == "" ? "?" : fPart0) + " \u7684\u65e7\u7ed3\u679c");
      return;
    }
    dimStale = false; dimShort = "";
    mtDim = mt;   // dim_check no longer drives the strip (task completion does)
    object rawItems = null;
    d.TryGetValue("items", out rawItems);
    if (rawItems == null) d.TryGetValue("\u660e\u7ec6", out rawItems);
    object[] arr = JArr(rawItems);
    var lines = new List<string>();
    int okN = 0, badN = 0;
    if (arr != null) {
      foreach (object o in arr) {
        Dictionary<string, object> it = o as Dictionary<string, object>;
        if (it == null) continue;
        bool ok = JOk(it);
        if (ok) okN++; else badN++;
        string name = JText(it, "name", "id");
        if (name == "") name = "\u5c3a\u5bf8";
        string one = name + "  \u56fe\u9762 " + JText(it, "drawing", "\u56fe\u9762") + "  \u5b9e\u6d4b " + JText(it, "measured", "\u5b9e\u6d4b") + (ok ? "  \u91cd\u5408" : "  \u5f85\u6539");
        string note = JText(it, "note", "\u6ce8");
        if (note != "") one += "  " + note;
        lines.Add(one);
      }
    }
    int draw = JInt(d, "drawing", "\u56fe\u9762");
    int hit = JInt(d, "matched", "\u5df2\u91cd\u5408");
    int pend = JInt(d, "pending", "\u5f85\u6539");
    if (draw < 0) draw = okN + badN;
    if (hit < 0) hit = okN;
    if (pend < 0) pend = Math.Max(0, draw - hit);
    double rate = draw > 0 ? (double)hit / (double)draw : 0;
    dimDraw = Math.Max(0, draw); dimHit = Math.Max(0, hit); dimPend = Math.Max(0, pend); dimRate = rate;
    // perfect only when every drawing dimension has its own ok item; otherwise never show 100% / perfect
    dimPerfect = dimDraw > 0 && dimHit == dimDraw && dimPend == 0 && okN == dimDraw && badN == 0;
    if (!dimPerfect) {
      dimHit = Math.Min(dimHit, okN);
      dimPend = Math.Max(dimPend, dimDraw - dimHit);
      dimRate = dimDraw > 0 ? Math.Min((double)dimHit / (double)dimDraw, 0.99) : 0;
    }
    dimKnown = dimDraw > 0;   // no drawing dimensions = nothing compared yet
    string part = JText(d, "part", "\u96f6\u4ef6");
    string layer = JText(d, "layer", "\u56fe\u5c42");
    int pct = (int)Math.Round(dimRate * 100.0);
    string head = dimPerfect ? "\u5b8c\u7f8e\uff0c\u53ef\u4ee5\u6536\u5de5" : "\u672a\u5230 100%\uff0c\u4e0d\u8bb8\u6536\u5de5";
    dimReport = "\u5c3a\u5bf8\u6838\u5bf9\n" + head + "\n\u56fe\u9762 " + dimDraw + "  \u5df2\u91cd\u5408 " + dimHit + "  \u91cd\u5408\u7387 " + pct + "%  \u5f85\u6539 " + dimPend;
    if (part != "") dimReport += "\n\u96f6\u4ef6 " + part;
    if (layer != "") dimReport += "\n\u56fe\u5c42 " + layer;
    if (lines.Count > 0) dimReport += "\n\n" + string.Join("\n", lines.ToArray());
    else dimReport += "\n\n\u6ca1\u6709\u660e\u7ec6";
  }
  StackPanel MkCard(StackPanel host, string title, string hint, out TextBlock val, out TextBlock unit, string u) {
    var card = new Border { Background = Brushes.White, BorderBrush = new SolidColorBrush(Line), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(9), Padding = new Thickness(12, 8, 12, 9), Margin = new Thickness(0, 0, 0, 6) };
    var sp = new StackPanel(); card.Child = sp;
    var head = new Grid();
    head.Children.Add(new TextBlock { Text = title, FontSize = 11.5, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Sub) });
    head.Children.Add(new TextBlock { Text = hint, FontSize = 10.5, Foreground = new SolidColorBrush(Idle), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center });
    sp.Children.Add(head);
    var vr = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 1, 0, 0) };
    val = new TextBlock { Text = "\u2014", FontSize = 24, FontWeight = FontWeights.Light, FontFamily = NumFont, Foreground = new SolidColorBrush(Ink), VerticalAlignment = VerticalAlignment.Bottom };
    unit = new TextBlock { Text = u, FontSize = 11.5, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(5, 0, 0, 5) };
    vr.Children.Add(val); vr.Children.Add(unit); sp.Children.Add(vr);
    host.Children.Add(card);
    lastRow = card;
    return sp;
  }
  void Mini(StackPanel card, string label, out TextBlock val, out TextBlock unit, string u) {
    var wp = card.Tag as WrapPanel;
    if (wp == null) { wp = new WrapPanel { Margin = new Thickness(0, 4, 0, 0) }; card.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Line), Margin = new Thickness(0, 6, 0, 0) }); card.Children.Add(wp); card.Tag = wp; }
    var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 16, 0), Background = Brushes.Transparent };
    row.Children.Add(new TextBlock { Text = label, FontSize = 11, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center });
    val = new TextBlock { Text = "\u2014", FontSize = 12.5, FontFamily = NumFont, Foreground = new SolidColorBrush(Ink), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(6, 0, 0, 0) };
    unit = new TextBlock { Text = u, FontSize = 11, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(3, 0, 0, 0) };
    row.Children.Add(val); row.Children.Add(unit);
    wp.Children.Add(row);
    lastRow = row;
  }
  void AddRow(StackPanel host, string label, out TextBlock val, out TextBlock unit, string u) {
    var g = new Grid { Height = 22, Margin = new Thickness(0, 1, 0, 1) };
    g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(72) });
    g.ColumnDefinitions.Add(new ColumnDefinition());
    g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
    var lb = new TextBlock { Text = label, FontSize = 12, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center };
    val = new TextBlock { Text = "\u2014", FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Ink), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
    unit = new TextBlock { Text = u, FontSize = 11, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(4, 0, 0, 0) };
    Grid.SetColumn(val, 1);
    Grid.SetColumn(unit, 2);
    g.Children.Add(lb); g.Children.Add(val); g.Children.Add(unit);
    host.Children.Add(g);
    lastRow = g;
  }
  void Toggle() {
    open = !open;
    if (detail != null) detail.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
    if (detailTray != null) detailTray.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
  }
  void ReadPreviewCmd() {
    if (!previewMode) return;
    try {
      string f = System.IO.Path.Combine(ioDir, "hud_cmd.txt");
      if (!File.Exists(f)) return;
      string raw = File.ReadAllText(f, Encoding.UTF8).Trim();
      try { File.Delete(f); } catch { }
      string cmd = raw.ToLowerInvariant();
      if (cmd == "open" && !open) Toggle();
      else if (cmd == "close" && open) Toggle();
      else if (cmd == "totals") ShowTotals();
      else if (cmd == "details") ShowActualDetails();
      else if (cmd == "reset") ShowReset();
      else if (cmd.StartsWith("shot:")) SaveVisual(raw.Substring(5).Trim());
    } catch { }
  }
  void SaveVisual(string path) {
    try {
      if (string.IsNullOrEmpty(path)) return;
      UpdateLayout();
      FrameworkElement el = Content as FrameworkElement;
      if (el == null) el = this;
      const double k = 3;   // preview shots at 3x for video
      int w = Math.Max(1, (int)Math.Ceiling(el.ActualWidth * k));
      int h = Math.Max(1, (int)Math.Ceiling(el.ActualHeight * k));
      var rtb = new RenderTargetBitmap(w, h, 96 * k, 96 * k, PixelFormats.Pbgra32);
      rtb.Render(el);
      var enc = new PngBitmapEncoder();
      enc.Frames.Add(BitmapFrame.Create(rtb));
      using (var fs = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.Read)) enc.Save(fs);
    } catch (Exception ex) {
      try { File.AppendAllText(errLog, DateTime.Now.ToString("s") + " shot " + ex + "\r\n"); } catch { }
    }
  }
  void ApplyStrip(int uses, double toks) {
    var now = DateTime.UtcNow;
    bool useUp = seenUse >= 0 && uses > seenUse;
    bool tokUp = seenTok >= 0 && toks > seenTok + 0.5;
    bool dimUp = taskPulse;   // scene 3 = task completion (was pass rate)
    taskPulse = false;
    if (useUp) useAt = now;
    if (tokUp) tokAt = now;
    if (dimUp) dimAt = now;
    seenUse = uses;
    seenTok = toks;
    int sc = 1;
    if (dimUp) sc = 3;
    else if (useUp) sc = 1;
    else if (tokUp) sc = 2;
    else {
      DateTime best = useAt;
      if (tokAt > best) { best = tokAt; sc = 2; }
      if (dimAt > best) sc = 3;
    }
    string lab = "调用", val = uses.ToString("N0", IC), un = "\u6b21";
    Color fg = Ink;
    string tip = "\u672c\u6b21\u8c03\u7528 " + uses.ToString(IC) + " \u6b21";
    if (sc == 2) {
      lab = "TOKEN"; val = (vTokn != null && (vTokn.Text == "\u2014" || vTokn.Text == "\u672A\u7EDF\u8BA1")) ? "\u672A\u7EDF\u8BA1" : Big(toks); un = uTokn != null ? uTokn.Text : "tok";
      if (val.EndsWith("\u4e07") || val.EndsWith("\u4ebf")) { un = val.Substring(val.Length - 1) + " " + un; val = val.Substring(0, val.Length - 1); }
      tip = tTokn != null && tTokn.ToolTip != null ? Convert.ToString(tTokn.ToolTip, IC) : "TOKEN";
    } else if (sc == 3) {
      lab = "\u5b8c\u6210\u5ea6";
      if (!taskKnown || taskPct == 99) { val = taskWord; un = ""; fg = Sub; tip = taskReport; }
      else { val = taskPct.ToString(IC); un = "%"; fg = Ink; tip = taskReport + (linkState == "ok" ? "" : "\n\u8FDE\u63A5\u672A\u6838\u9A8C\uFF08\u4EFB\u52A1\u81EA\u68C0\u2260\u5DF2\u8FDE\u63A5\uFF09"); }
    }
    string label = lab + " " + val + (un == "" ? "" : " " + un);
    if (stripText != null) {
      stripText.Text = val;
      stripText.Foreground = new SolidColorBrush(fg);
    }
    if (sLabel != null) sLabel.Text = lab;
    if (sUnit != null) sUnit.Text = un;
    if (strip != null) strip.ToolTip = open ? "\u5355\u51FB\u6536\u8D77" : "\u5355\u51FB\u5C55\u5F00";
    if (previewMode) {
      try {
        var br = stripText.Foreground as SolidColorBrush;
        string col = br == null ? "" : br.Color.ToString();
        File.WriteAllText(System.IO.Path.Combine(ioDir, "hud_strip.txt"), (open ? "open" : "shut") + "\t" + label + "\t" + col + "\t" + ActualWidth.ToString("0.0", IC) + "\t" + (strip == null ? "0" : strip.ActualWidth.ToString("0.0", IC)), new UTF8Encoding(false));
      } catch { }
    }
  }
  // ---------- task completion (replaces pass rate, 2026-11-04): 经验库\流程.json current task, five self-checks ----------
  bool taskKnown, taskDone, taskPulse, taskExp, taskRes; int hudCalls; int taskPct = -1, taskPass, taskTotal;
  string TwoChecks() { return "经验 " + (taskExp || hudCalls > 0 ? "已调用" : "未调用") + " · 结果 " + (taskRes ? "已核对" : "未核对"); } string taskWord = "\u672a\u5f00\u4efb\u52a1", taskReport = "", taskKey = "", taskSub = "";
  static bool JFlag(Dictionary<string, object> it, string k) {
    object v; if (it == null || !it.TryGetValue(k, out v) || v == null) return false;
    if (v is bool) return (bool)v; string s = Convert.ToString(v, CultureInfo.InvariantCulture); return s == "1" || s.Equals("true", StringComparison.OrdinalIgnoreCase);
  }
  void ReadTask() {
    string f = System.IO.Path.Combine(libDir, "\u6d41\u7a0b.json");
    if (!File.Exists(f)) { taskKnown = false; taskDone = false; taskWord = "\u672A\u5F00\u4EFB\u52A1"; taskSub = "\u5F00\u4EFB\u52A1\u540E\u81EA\u52A8\u8BA1"; taskReport = taskSub; taskKey = ""; return; }
    DateTime mt; try { mt = File.GetLastWriteTimeUtc(f); } catch { return; }
    string key = f + "|" + mt.Ticks.ToString(IC);
    if (key == taskKey) return;
    Dictionary<string, object> d = ReadJson(f);
    if (d == null) return;
    taskKey = key;
    var cur = CurrentTask(d);
    int oldPct = taskPct; bool oldKnown = taskKnown;
    if (cur == null) {
      taskKnown = false; taskDone = false; taskPct = -1; taskWord = "\u672a\u5f00\u4efb\u52a1";
      taskSub = "\u5F00\u4EFB\u52A1\u540E\u81EA\u52A8\u8BA1";
      taskReport = "\u4efb\u52a1\u5b8c\u6210\u5ea6\n\u5f53\u524d\u6ca1\u6709\u4efb\u52a1";
      return;
    }
    string status = JText(cur, "status"), title = JText(cur, "title");
    object[] arr = JArr(cur.ContainsKey("checks") ? cur["checks"] : null);
    // 面板只计两项：search→经验已调用，inspect→结果已核对；其余三项（compare/draft/claim）只留流程日志
    bool expUsed = JFlag(cur, "retrieved"), resChecked = false; var lines = new List<string>();
    if (arr != null) foreach (object o in arr) { var it = o as Dictionary<string, object>; if (it == null) continue; bool ok = JFlag(it, "pass"); string cid = JText(it, "id"); if (cid == "search" && ok) expUsed = true; if (cid == "inspect" && ok) resChecked = true; }
    taskExp = expUsed; taskRes = resChecked;
    lines.Add(((expUsed || hudCalls > 0) ? "\u2713 " : "\u00b7 ") + "经验 " + ((expUsed || hudCalls > 0) ? "已调用" : "未调用"));
    lines.Add((resChecked ? "\u2713 " : "\u00b7 ") + "结果 " + (resChecked ? "已核对" : "未核对"));
    int total = 2, pass = (expUsed ? 1 : 0) + (resChecked ? 1 : 0);
    taskPass = pass; taskTotal = total;
    taskDone = status == "\u5df2\u9a8c\u6536";   // 已验收
    int pct = (int)Math.Round(100.0 * pass / 3);    // 三段：经验、结果、已验收
    if (!taskDone && pass >= total) pct = 99;         // both checks passed but not accepted yet: never show 100%
    if (taskDone) pct = 100;
    taskPct = pct; taskKnown = true;
    if (pct == 99) taskWord = "\u5F85\u9A8C\u6536";
    taskSub = TwoChecks() + " \u00b7 " + (status == "" ? "\u8fdb\u884c\u4e2d" : status) + (title == "" ? "" : " \u00b7 " + title);
    taskReport = "\u4efb\u52a1\u5b8c\u6210\u5ea6 " + (pct == 99 ? taskWord : pct + "%") + "\n" + taskSub + (lines.Count > 0 ? "\n\n" + string.Join("\n", lines.ToArray()) : "");
    if (oldKnown && oldPct != pct) taskPulse = true;
    else if (!oldKnown && (DateTime.UtcNow - mt).TotalSeconds <= 45) taskPulse = true;
  }
  void ShowDim() {
    ReadTask();
    if (vRate == null) return;
    // task checklist is self-report only; never treat it as connection success while evidence pending
    string sub = taskKnown ? TwoChecks() : "";

    if (!taskKnown || taskPct == 99) {
      vRate.Text = taskWord; uRate.Text = "";
      vRate.Foreground = new SolidColorBrush(Sub);
    } else {
      vRate.Text = taskPct.ToString(IC); uRate.Text = "%";
      // while not link-ok, never paint completion as green success
      vRate.Foreground = new SolidColorBrush(Ink);
    }
    if (dSub != null) { dSub.Text = sub; dSub.Visibility = taskKnown ? Visibility.Visible : Visibility.Collapsed; dSub.Foreground = new SolidColorBrush(Sub); dSub.ToolTip = null; }
    if (tRate != null) tRate.ToolTip = taskReport + (linkState == "ok" ? "" : "\n\u8FDE\u63A5\u672A\u6838\u9A8C");
  }

  void Show4() {

    bool live = stats != null && snap;

    Safe(() => ShowMoney(live));

    if (!runReady) { Safe(NewRun); }

    double u = live ? Math.Max(0, cUses - bUses) : 0;

    int saved = libKnown ? NewIn(libIds, bLib) : 0;

    int firstUsed = live ? NewIn(cIds, bIds) : 0;

    bool so = SoftOn(), localSlot = HasLocalSlot(); int gN = genIds.Count, sN = localSlot ? libN : 0;
    int sGen = NewIn(genIds, bGenLib), sSoft = localSlot ? saved : 0;
    double uG = live ? Math.Min(u, Math.Max(0, genAbs - bGen)) : 0, uS = Math.Max(0, u - uG);

    vAll.Text = ("\u901A\u7528 " + gN + (localSlot ? " \u00B7 \u8F6F\u4EF6 " + (libKnown ? sN.ToString(IC) : "\u2014") : ""));

    tAll.ToolTip = null;
    if (localSlot && libKnown) {
      var cardIndex = ReadJson(System.IO.Path.Combine(System.IO.Path.GetDirectoryName(libDir), "\u8FDE\u63A5\u6559\u7EC3", "\u8FDE\u63A5\u7ECF\u9A8C", "\u7D22\u5F15.json"));
      object rows;
      int cards = 0;
      if (cardIndex != null && cardIndex.TryGetValue("entries", out rows) && rows is object[]) {
        foreach (var row in (object[])rows) {
          var entry = row as Dictionary<string, object>;
          if (entry != null && String.Equals(Str(entry, "slot"), linkSlot, StringComparison.OrdinalIgnoreCase)) cards++;
        }
      }
      tAll.ToolTip = "\u8FDE\u63A5\u5361 " + cards + " · \u8349\u7A3F " + (sN - libVer) + " · \u6B63\u5F0F " + libVer;
    }

    vLib.Text = "\u901A\u7528 " + sGen + (localSlot ? " \u00B7 \u8F6F\u4EF6 " + sSoft.ToString(IC) : "");

    tLib.ToolTip = null;

    vUse.Text = ((int)u).ToString(IC); uUse.Text = "\u6B21" + (so ? " \u00B7 \u901A\u7528 " + (int)uG + " \u00B7 \u8F6F\u4EF6 " + (int)uS : "");
    tUse.ToolTip = null;

    

    // live clock: keep ticking until this run ends (15min idle gap / new run / exit)

    double nowE = Epoch();

    double startT = rAct > 0 ? rAct : (cTaskStart > 0 ? cTaskStart : 0);

    if (startT <= 0 && runReady) { startT = nowE; rAct = nowE; SaveRun(); }

    if (startT > 0) {

      string v, un; Dur(Math.Max(0, nowE - startT), out v, out un); vTime.Text = v; uTime.Text = un;

      tTime.ToolTip = null;

    } else { vTime.Text = "0"; uTime.Text = "\u79D2"; tTime.ToolTip = null; }
    Safe(ShowDim);
    Safe(ShowActualEvents);
    int usesNow=0;int.TryParse(vUse.Text,out usesNow);
    Safe(() => ApplyStrip(usesNow, shownTok));

  }



  // ---------- totals (right-click) ----------

  void ShowTotals() {

    if (totWin != null) { totWin.Activate(); return; }

    var w = new Window { Title = "YA \u603B\u8BA1", WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent, ResizeMode = ResizeMode.NoResize,

      ShowInTaskbar = false, SizeToContent = SizeToContent.WidthAndHeight, Topmost = true, FontFamily = FontFamily, UseLayoutRounding = true, Owner = this };

    TextOptions.SetTextFormattingMode(w, TextFormattingMode.Display);

    var card = new Border { CornerRadius = new CornerRadius(14), Background = new LinearGradientBrush(C1, C2, 0), Margin = new Thickness(18, 14, 18, 22),

      Effect = new DropShadowEffect { BlurRadius = 16, ShadowDepth = 3, Direction = 270, Opacity = 0.13, Color = Colors.Black } };

    var inner = new Border { CornerRadius = new CornerRadius(13, 13, 14, 14), Background = Brushes.White, Margin = new Thickness(0, 2, 0, 0), Padding = new Thickness(16, 9, 14, 10) };

    card.Child = inner; var root = new StackPanel { Width = 256 }; inner.Child = root;

    var head = new Grid { Height = 24 };

    head.Children.Add(new TextBlock { Text = "\u603B\u8BA1", FontSize = 13, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Ink), VerticalAlignment = VerticalAlignment.Center });

    var x = new TextBlock { Text = "\u2715", FontSize = 11, Foreground = new SolidColorBrush(Sub), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Cursor = Cursors.Hand, Padding = new Thickness(6, 2, 0, 2), ToolTip = "\u5173\u95ED" };

    x.MouseLeftButtonDown += (s, e) => { e.Handled = true; };

    x.MouseLeftButtonUp += (s, e) => { e.Handled = true; w.Close(); };

    head.Children.Add(x); root.Children.Add(head);

    root.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Line), Margin = new Thickness(0, 6, 0, 6) });

    totBody = new StackPanel(); root.Children.Add(totBody);

    w.Content = card;

    card.MouseLeftButtonDown += (s, e) => { try { w.DragMove(); } catch { } };

    w.KeyDown += (s, e) => { if (e.Key == Key.Escape) w.Close(); };

    w.Closed += (s, e) => { totWin = null; totBody = null; };

    totWin = w; totSig = ""; FillTotals();

    w.WindowStartupLocation = WindowStartupLocation.Manual; w.Left = Left - 18; w.Top = Top + ActualHeight - 8;

    w.Loaded += (s, e) => { var wa = SystemParameters.WorkArea;

      if (w.Top + w.ActualHeight > wa.Bottom) w.Top = Math.Max(wa.Top, Top - w.ActualHeight + 14);

      if (w.Left + w.ActualWidth > wa.Right) w.Left = Math.Max(wa.Left, wa.Right - w.ActualWidth); };

    w.Show();

  }

  void Sec(string t) { totBody.Children.Add(new TextBlock { Text = t, FontSize = 11.5, Foreground = new SolidColorBrush(C2), Margin = new Thickness(0, 6, 0, 2) }); }

  void Row(string k, string v) {

    var g = new Grid { Margin = new Thickness(0, 1, 0, 1) };

    g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(76) }); g.ColumnDefinitions.Add(new ColumnDefinition());

    var a = new TextBlock { Text = k, FontSize = 12, Foreground = new SolidColorBrush(Sub) };

    var b = new TextBlock { Text = v, FontSize = 12, Foreground = new SolidColorBrush(Ink), TextWrapping = TextWrapping.Wrap }; Grid.SetColumn(b, 1);

    g.Children.Add(a); g.Children.Add(b); totBody.Children.Add(g);

  }

  void FillTotals() { FillActualTotals(); }

  // keep the whole card on screen (an old place may come from a bigger window)

  void Fit() {

    var wa = SystemParameters.WorkArea; double w = ActualWidth, h = ActualHeight;

    if (Left + w > wa.Right) Left = Math.Max(wa.Left, wa.Right - w);

    if (Top + h > wa.Bottom) Top = Math.Max(wa.Top, wa.Bottom - h);

    if (Left < SystemParameters.VirtualScreenLeft) Left = wa.Left;

    if (Top < SystemParameters.VirtualScreenTop) Top = wa.Top;

  }

  void SavePos() {

    try { File.WriteAllText(posPath, Left.ToString(IC) + "," + Top.ToString(IC) + "," + (Topmost ? "1" : "0") + ",2"); } catch { }

  }

}

'@
Add-Type -ReferencedAssemblies $refs -TypeDefinition ($hudSource + [IO.File]::ReadAllText((Join-Path $dir '连接证据.cs'), [Text.Encoding]::UTF8))
if([YaWindow]::Desktop() -cne 'WinSta0\Default'){throw 'HUD_INTERACTIVE_DESKTOP_REQUIRED: use show_ya.ps1 or 打开YA插件.bat; a background desktop is not user-visible'}
$mutexName = Get-YaHudInstanceName $dir $Home2
if ($Preview) { $mutexName += '-Preview' }
$showEventName = $mutexName + '-Show'
if ($Show) { try { $ev = [Threading.EventWaitHandle]::OpenExisting($showEventName); [void]$ev.Set(); $ev.Dispose(); exit 0 } catch { } }

$NxPid = $PID   # 统计会话锚在本窗口进程上；软件进程只用来判断连接态

if (-not $NxPid) { exit 2 }

if (-not $Show -and (Test-Path -LiteralPath (Join-Path $Home2 'hud.off'))) { exit 0 }

$created = $false



$mutex = New-Object Threading.Mutex($true, $mutexName, [ref]$created)

if (-not $created) { exit 0 }

try { [void](Get-Process -Id $NxPid -ErrorAction Stop) } catch { exit 0 }



[YaCard]::ShowEventName = $showEventName
$w = New-Object YaCard($NxPid, $io, $lib, $StatusFile, $AgentFile, $StatsFile, $IndexFile, [bool]$Preview)

$app = New-Object Windows.Application

$app.ShutdownMode = 'OnMainWindowClose'

[void]$app.Run($w)

$mutex.ReleaseMutex()
