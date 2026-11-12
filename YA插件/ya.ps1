# YA 状态小窗（白底卡，沿用旧版 YA 的布局与交互）。只读 运行数据\状态.json 和 运行数据\经验使用.json，不碰软件、不影响连接。
# 收起时一行：YA · 连接状态 · 最近改模实读；单击那一行展开/收起详情（最近改模、经验调用、经验存储）。
# 拖动 YA 字样或连接标签移动；× 或右键「隐藏到托盘」收到时钟旁 YA 图标，单击图标再打开；右键：刷新 / 置顶 / 隐藏到托盘 / 退出。位置记在 运行数据\ya_pos.txt。
# 用法：powershell -NoProfile -STA -ExecutionPolicy Bypass -File ya.ps1 [-Show] [-Open]
# 必须是带 BOM 的 UTF-8。
param([switch]$Show, [switch]$Open, [string]$Run = '')
$ErrorActionPreference = 'Stop'
# 藏掉宿主控制台：任务栏不出 PowerShell 图标，只留 YA 面板。
Add-Type -Name Con -Namespace NgxzYa -MemberDefinition '[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow(); [DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr h, int n);'
$hc = [NgxzYa.Con]::GetConsoleWindow(); if ($hc -ne [IntPtr]::Zero) { [void][NgxzYa.Con]::ShowWindow($hc, 0) }
$dir = $PSScriptRoot
if (-not $Run) { $Run = Join-Path (Split-Path $dir -Parent) '运行数据' }
if (-not (Test-Path -LiteralPath $Run)) { New-Item -ItemType Directory -Path $Run -Force | Out-Null }
# 单例：整台机器（本用户会话）只一个 YA。已有就把它提到前面（-Open 时顺便展开），自己退出；多个 Agent、多轮测试也只一个面板。
$name = 'Local\ngxz-ya-YA'
$showEventName = $name + '-Show'
$openEventName = $name + '-Open'
function Wake-Existing { try { $ev = [Threading.EventWaitHandle]::OpenExisting($(if ($Open) { $openEventName } else { $showEventName })); [void]$ev.Set(); $ev.Dispose() } catch { } }
if ($Show) { Wake-Existing; exit 0 }
$created = $false
$mutex = New-Object Threading.Mutex($true, $name, [ref]$created)
if (-not $created) {
  # 上一个 YA 被强杀时互斥量会留成“已放弃”，能拿到就当自己是唯一的；拿不到说明真有一个在跑
  $mine = $false; try { $mine = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $mine = $true }
  if (-not $mine) { Wake-Existing; exit 0 }
}
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
using System.Windows.Shapes;
using System.Windows.Threading;
using System.Windows.Interop;
using System.Threading;
using System.Web.Script.Serialization;
using WF = System.Windows.Forms;
using SD = System.Drawing;

public class YaCard : Window {
  public static string OpenEventName = ""; public static string ShowEventName;
  static readonly CultureInfo IC = CultureInfo.InvariantCulture;
  static readonly Color Ink = Color.FromRgb(0x1F, 0x29, 0x37), Sub = Color.FromRgb(0x8B, 0x95, 0xA5), Line = Color.FromRgb(0xE8, 0xEC, 0xF2), Soft = Color.FromRgb(0xF6, 0xF8, 0xFB), Edge = Color.FromRgb(0xE1, 0xE6, 0xEE);
  static readonly Color OkBg = Color.FromRgb(0xEC, 0xFD, 0xF5), OkInk = Color.FromRgb(0x05, 0x96, 0x69), WarnBg = Color.FromRgb(0xFF, 0xF7, 0xED), WarnInk = Color.FromRgb(0xC2, 0x41, 0x0C);
  static readonly FontFamily NumFont = new FontFamily("Segoe UI, Microsoft YaHei UI");
  static readonly Color C1 = Color.FromRgb(0x38, 0xD5, 0xEC), C2 = Color.FromRgb(0x3B, 0x82, 0xF6);
  static readonly Color Ok = Color.FromRgb(0x22, 0xC5, 0x5E), Idle = Color.FromRgb(0xB9, 0xBF, 0xC8), Warn = Color.FromRgb(0xF5, 0x9E, 0x0B);

  string runDir, posPath, errLog;
  TextBlock connText, stripText, closeX, vMod, hMod, dMod, vUse, dUse, vNew, dNew;
  Border connTag, strip, detailTray; StackPanel detail; Ellipse dot;
  bool openAtStart, open, dragging, tipShown, quitting; MenuItem miTop; WF.NotifyIcon tray; EventWaitHandle showEv; DispatcherTimer poll;
  JavaScriptSerializer js = new JavaScriptSerializer();
  [DllImport("user32.dll")] static extern bool ReleaseCapture();
  [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
  [DllImport("gdi32.dll")] static extern IntPtr CreateRoundRectRgn(int x1, int y1, int x2, int y2, int w, int h);
  [DllImport("user32.dll")] static extern int SetWindowRgn(IntPtr h, IntPtr rgn, bool redraw);
  [DllImport("user32.dll", EntryPoint = "GetClassLongPtrW")] static extern IntPtr GetClassLongPtr64(IntPtr h, int i);
  [DllImport("user32.dll", EntryPoint = "SetClassLongPtrW")] static extern IntPtr SetClassLongPtr64(IntPtr h, int i, IntPtr v);
  [DllImport("user32.dll", EntryPoint = "GetClassLongW")] static extern int GetClassLong32(IntPtr h, int i);
  [DllImport("user32.dll", EntryPoint = "SetClassLongW")] static extern int SetClassLong32(IntPtr h, int i, int v);

  public YaCard(string run, bool startOpen) {
    runDir = run; posPath = System.IO.Path.Combine(run, "ya_pos.txt"); errLog = System.IO.Path.Combine(run, "ya_error.log");
    Title = "YA"; WindowStyle = WindowStyle.None; AllowsTransparency = false; Background = new SolidColorBrush(Edge);
    ResizeMode = ResizeMode.NoResize; ShowInTaskbar = false; ShowActivated = false; SizeToContent = SizeToContent.WidthAndHeight;
    UseLayoutRounding = true; TextOptions.SetTextFormattingMode(this, TextFormattingMode.Display);
    FontFamily = new FontFamily("Microsoft YaHei UI, Microsoft YaHei, Segoe UI");
    var card = new Border { CornerRadius = new CornerRadius(14), Background = new LinearGradientBrush(C1, C2, 0), BorderBrush = new SolidColorBrush(Edge), BorderThickness = new Thickness(1) };
    var inner = new Border { CornerRadius = new CornerRadius(13, 13, 14, 14), Background = Brushes.White, Margin = new Thickness(0, 2, 0, 0), Padding = new Thickness(16, 9, 14, 10) };
    card.Child = inner;
    var root = new StackPanel(); inner.Child = root;
    System.Windows.Documents.TextElement.SetFontFamily(root, NumFont);
    System.Windows.Documents.TextElement.SetFontSize(root, 13);

    // 收起时的一行：YA 字样 + 连接标签 + 最近改模摘要（单击展开/收起）+ ×（隐藏到托盘）
    var barRow = new Grid { Width = 372, Height = 34 };
    barRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
    barRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
    barRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
    barRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
    var ya = new Grid { Height = 34, Background = Brushes.Transparent, Cursor = Cursors.SizeAll, Margin = new Thickness(0, 0, 9, 0), ToolTip = "拖动移动" };
    ya.Children.Add(new TextBlock { Text = "YA", FontSize = 20, FontFamily = NumFont, FontWeight = FontWeights.Bold, Foreground = new LinearGradientBrush(C1, C2, 0), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 0, 1) });
    ya.MouseLeftButtonDown += (s, e) => { e.Handled = true; Drag(); };
    barRow.Children.Add(ya);
    dot = new Ellipse { Width = 6, Height = 6, Fill = new SolidColorBrush(Idle), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 1, 5, 0) };
    connText = new TextBlock { Text = "未连接", FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Sub), VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
    var tagRow = new DockPanel(); DockPanel.SetDock(dot, Dock.Left); tagRow.Children.Add(dot); tagRow.Children.Add(connText);
    connTag = new Border { MaxWidth = 150, CornerRadius = new CornerRadius(10), Background = new SolidColorBrush(Soft), Padding = new Thickness(8, 2, 9, 3), VerticalAlignment = VerticalAlignment.Center, Child = tagRow, Cursor = Cursors.SizeAll };
    connTag.MouseLeftButtonDown += (s, e) => { e.Handled = true; Drag(); };
    Grid.SetColumn(connTag, 1); barRow.Children.Add(connTag);
    strip = new Border { Height = 34, Margin = new Thickness(8, 0, 2, 0), Background = Brushes.White, BorderBrush = new SolidColorBrush(Line), BorderThickness = new Thickness(1, 0, 0, 0), Cursor = Cursors.Hand, ClipToBounds = true, ToolTip = "单击展开 / 收起" };
    stripText = new TextBlock { Text = "还没有改模", FontSize = 12.5, Foreground = new SolidColorBrush(Ink), VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap };
    strip.Child = new Border { Padding = new Thickness(8, 0, 0, 0), Child = stripText };
    strip.MouseLeftButtonDown += (s, e) => { e.Handled = true; };
    strip.MouseLeftButtonUp += (s, e) => { e.Handled = true; Toggle(); };
    Grid.SetColumn(strip, 2); barRow.Children.Add(strip);
    closeX = new TextBlock { Text = "\u2715", Foreground = new SolidColorBrush(Sub), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Opacity = 0, Cursor = Cursors.Hand, Padding = new Thickness(4), ToolTip = "隐藏到托盘" };
    closeX.MouseLeftButtonUp += (s, e) => { e.Handled = true; HideCard(); };
    closeX.MouseLeftButtonDown += (s, e) => { e.Handled = true; };
    Grid.SetColumn(closeX, 3); barRow.Children.Add(closeX);
    root.Children.Add(barRow);

    // 展开：浅灰托盘上三张同样式白卡
    var tray0 = new Border { Background = new SolidColorBrush(Soft), CornerRadius = new CornerRadius(10), Padding = new Thickness(6, 6, 6, 0), Margin = new Thickness(-6, 10, -4, 0) };
    detail = new StackPanel { Width = 370 };
    MkCard(detail, "最近改模", out hMod, out vMod, out dMod);
    TextBlock h2, h3;
    MkCard(detail, "经验调用", out h2, out vUse, out dUse); h2.Text = "本次";
    MkCard(detail, "经验存储", out h3, out vNew, out dNew); h3.Text = "本次新存";
    tray0.Child = detail; tray0.Visibility = Visibility.Collapsed; detailTray = tray0;
    root.Children.Add(tray0);
    Content = card;

    card.MouseEnter += (s, e) => { if (!dragging) closeX.Opacity = 0.75; };
    card.MouseLeave += (s, e) => { if (!dragging) closeX.Opacity = 0; };
    Closing += (s, e) => SavePos();
    Closed += (s, e) => { quitting = true; try { if (tray != null) { tray.Visible = false; tray.Dispose(); } } catch { } };
    var miNew = new MenuItem { Header = "刷新" }; miNew.Click += (s, e) => Safe(Poll);
    miTop = new MenuItem { Header = "置顶", IsCheckable = true }; miTop.Click += (s, e) => { Topmost = miTop.IsChecked; SavePos(); };
    var miHide = new MenuItem { Header = "隐藏到托盘" }; miHide.Click += (s, e) => HideCard();
    var miClose = new MenuItem { Header = "退出" }; miClose.Click += (s, e) => Close();
    var cm = new ContextMenu(); Safe(() => StyleMenu(cm)); cm.Items.Add(miNew); cm.Items.Add(new Separator()); cm.Items.Add(miTop); cm.Items.Add(miHide); cm.Items.Add(miClose); card.ContextMenu = cm;
    Safe(MakeTray);
    try { showEv = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
      var th = new Thread(() => { while (!quitting) { try { if (showEv.WaitOne(1000) && !quitting) Dispatcher.BeginInvoke(new Action(ShowCard)); } catch { return; } } }) { IsBackground = true }; th.Start(); } catch { }
    try { var openEv = new EventWaitHandle(false, EventResetMode.AutoReset, OpenEventName);
      var th2 = new Thread(() => { while (!quitting) { try { if (openEv.WaitOne(1000) && !quitting) Dispatcher.BeginInvoke(new Action(() => { ShowCard(); if (!open) Toggle(); })); } catch { return; } } }) { IsBackground = true }; th2.Start(); } catch { }
    double x = double.NaN, y = double.NaN; bool top = true;
    try { var a = File.ReadAllText(posPath).Trim().Split(','); x = double.Parse(a[0], IC); y = double.Parse(a[1], IC); if (a.Length > 2) top = a[2] == "1"; } catch { }
    var wa = SystemParameters.WorkArea;
    if (double.IsNaN(x) || x < SystemParameters.VirtualScreenLeft - 50 || x > SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth - 80 || y < SystemParameters.VirtualScreenTop - 20 || y > SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight - 60) { x = wa.Right - 420; y = wa.Top + 70; }
    WindowStartupLocation = WindowStartupLocation.Manual; Left = x; Top = y; Topmost = top; miTop.IsChecked = top;
    openAtStart = startOpen;
    poll = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(800) };
    poll.Tick += (s, e) => { if (!dragging) Safe(Poll); };
    poll.Start();
    Loaded += (s, e) => { Safe(Poll); if (openAtStart && !open) Toggle(); Safe(Fit); Safe(Round); Safe(DropShadowClass); };
    SizeChanged += (s, e) => { if (!dragging) { Safe(Round); Safe(Fit); } };
  }

  void MkCard(StackPanel host, string title, out TextBlock hint, out TextBlock val, out TextBlock sub) {
    var card = new Border { Background = Brushes.White, BorderBrush = new SolidColorBrush(Line), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(9), Padding = new Thickness(12, 8, 12, 9), Margin = new Thickness(0, 0, 0, 6) };
    var sp = new StackPanel(); card.Child = sp;
    var head = new Grid();
    head.Children.Add(new TextBlock { Text = title, FontSize = 11.5, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Sub) });
    hint = new TextBlock { Text = "", FontSize = 10.5, Foreground = new SolidColorBrush(Idle), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
    head.Children.Add(hint);
    sp.Children.Add(head);
    val = new TextBlock { Text = "—", FontSize = 17, FontWeight = FontWeights.Normal, Foreground = new SolidColorBrush(Ink), Margin = new Thickness(0, 2, 0, 0), TextWrapping = TextWrapping.Wrap };
    sp.Children.Add(val);
    sub = new TextBlock { Text = "", FontSize = 12, Foreground = new SolidColorBrush(Sub), Margin = new Thickness(0, 3, 0, 0), TextWrapping = TextWrapping.Wrap };
    sp.Children.Add(sub);
    host.Children.Add(card);
  }

  // ---------- data（只读两个状态文件） ----------
  Dictionary<string, object> ReadJson(string f) { try { using (var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) using (var sr = new StreamReader(fs, Encoding.UTF8)) return js.DeserializeObject(sr.ReadToEnd()) as Dictionary<string, object>; } catch { return null; } }
  static string Str(Dictionary<string, object> d, string k) { object v; if (d == null || !d.TryGetValue(k, out v) || v == null) return ""; return Convert.ToString(v, IC); }
  static double Num(Dictionary<string, object> d, string k) { object v; if (d == null || !d.TryGetValue(k, out v) || v == null) return 0; try { return Convert.ToDouble(v, IC); } catch { return 0; } }
  static List<string> Ids(Dictionary<string, object> d, params string[] keys) {
    var r = new List<string>();
    foreach (var k in keys) { object v; if (d == null || !d.TryGetValue(k, out v) || v == null) continue;
      var arr = v as object[]; var list = new List<string>();
      if (arr != null) { foreach (var o in arr) list.Add(Convert.ToString(o, IC)); } else list.Add(Convert.ToString(v, IC));
      foreach (var s in list) foreach (var p in s.Split(new[] { ',', ' ', '，', ';' }, StringSplitOptions.RemoveEmptyEntries)) if (!r.Contains(p)) r.Add(p); }
    return r;
  }
  static string Short(string t) { if (string.IsNullOrEmpty(t)) return ""; int i = t.IndexOf(" · ", StringComparison.Ordinal); return i > 0 ? t.Substring(0, i) : t; }

  void Poll() {
    var s = ReadJson(System.IO.Path.Combine(runDir, "状态.json"));
    bool ok = false; string sw = Str(s, "软件");
    if (s != null) {
      double age = (DateTime.UtcNow - new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc)).TotalSeconds - Num(s, "心跳");
      bool alive = false; try { var p = Process.GetProcessById((int)Num(s, "pid")); alive = !p.HasExited; } catch { }
      ok = age < 5 && alive;
    }
    connText.Text = ok ? "已连接 · " + sw.Split(' ')[0] : "未连接"; connTag.ToolTip = ok ? sw + " 前台连接中" : "没有收到软件心跳";
    connText.Foreground = new SolidColorBrush(ok ? OkInk : WarnInk);
    connTag.Background = new SolidColorBrush(ok ? OkBg : WarnBg);
    dot.Fill = new SolidColorBrush(ok ? Ok : Warn);
    connTag.ToolTip = ok ? (sw + " · 前台 · pid " + Str(s, "pid") + " · 文档 " + Str(s, "文档")) : "前台没有带连接的软件";
    object mo; var m = (s != null && s.TryGetValue("最近改模", out mo)) ? mo as Dictionary<string, object> : null;
    string act = Str(m, "动作"), res = Str(m, "结果"), rd = Str(m, "实读"), tm = Str(m, "时间");
    if (act == "") { stripText.Text = "还没有改模"; vMod.Text = "还没有改模"; dMod.Text = ""; hMod.Text = ""; }
    else {
      bool good = res.StartsWith("成功");
      stripText.Text = act + (good ? " · " + Short(rd) : " 失败");
      stripText.Foreground = new SolidColorBrush(good ? Ink : WarnInk);
      vMod.Text = act + " " + (good ? "成功" : res);
      vMod.Foreground = new SolidColorBrush(good ? Ink : WarnInk);
      dMod.Text = rd != "" ? "实读 " + rd : "";
      hMod.Text = tm.Length >= 8 ? tm.Substring(tm.Length - 8) : tm;
    }
    var u = ReadJson(System.IO.Path.Combine(runDir, "经验使用.json"));
    var used = Ids(u, "用上", "命中"); var saved = Ids(u, "存入");
    int n = (int)Num(u, "搜索次数");
    vUse.Text = used.Count > 0 ? used.Count + " 条" : (n > 0 ? "没命中" : "未调用");
    dUse.Text = used.Count > 0 ? string.Join("、", used) + (n > 0 ? "（搜了 " + n + " 次）" : "") : (n > 0 ? "搜了 " + n + " 次" : "");
    vNew.Text = saved.Count > 0 ? saved.Count + " 条" : "未新存";
    dNew.Text = saved.Count > 0 ? string.Join("、", saved) : "";
  }

  void Toggle() { open = !open; detailTray.Visibility = open ? Visibility.Visible : Visibility.Collapsed; }
  void Drag() {
    if (dragging) return;
    dragging = true; poll.Stop();
    try { var h = new WindowInteropHelper(this).Handle; ReleaseCapture(); SendMessage(h, 0xA1, new IntPtr(2), IntPtr.Zero); } catch { }
    dragging = false; SavePos(); poll.Start();
  }
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

  void ShowCard() { if (!IsVisible) Show(); if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal; var t = Topmost; Topmost = false; Topmost = true; Topmost = t; Safe(Fit); Safe(Poll); }
  void HideCard() {
    SavePos(); Hide();
    if (!tipShown && tray != null) { tipShown = true; try { tray.ShowBalloonTip(2500, "YA", "单击图标再打开", WF.ToolTipIcon.None); } catch { } }
  }
  void Safe(Action a) { try { a(); } catch (Exception ex) { try { File.AppendAllText(errLog, DateTime.Now.ToString("s") + " " + ex + "\r\n"); } catch { } } }
  void Fit() {
    var wa = SystemParameters.WorkArea; double w = ActualWidth, h = ActualHeight;
    if (Left + w > wa.Right) Left = Math.Max(wa.Left, wa.Right - w);
    if (Top + h > wa.Bottom) Top = Math.Max(wa.Top, wa.Bottom - h);
    if (Left < SystemParameters.VirtualScreenLeft) Left = wa.Left;
    if (Top < SystemParameters.VirtualScreenTop) Top = wa.Top;
  }
  void SavePos() { try { File.WriteAllText(posPath, Left.ToString(IC) + "," + Top.ToString(IC) + "," + (Topmost ? "1" : "0")); } catch { } }
}
'@
Add-Type -ReferencedAssemblies $refs -TypeDefinition $hudSource
[IO.File]::WriteAllText((Join-Path $Run 'ya.pid'), [string]$PID)
[YaCard]::OpenEventName = $openEventName
[YaCard]::ShowEventName = $showEventName
$w = New-Object YaCard($Run, [bool]$Open)
$app = New-Object Windows.Application
$app.ShutdownMode = 'OnMainWindowClose'
[void]$app.Run($w)
$mutex.ReleaseMutex()
