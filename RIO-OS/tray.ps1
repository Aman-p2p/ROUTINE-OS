param(
    [switch]$Startup,
    [switch]$MakeIcon,
    [switch]$Stop
)
$ErrorActionPreference = 'Stop'
# Any startup error is written to rio-error.log (next to this script) because the launcher window is hidden.
trap {
    try { Add-Content -LiteralPath (Join-Path $PSScriptRoot 'rio-error.log') -Value ((Get-Date -Format 's') + '  ' + $_.Exception.Message + '  @ line ' + $_.InvocationInfo.ScriptLineNumber) } catch {}
    break
}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function New-RioIcon {
    $bmp = New-Object Drawing.Bitmap 64, 64
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAlias
    $g.Clear([Drawing.Color]::Transparent)
    $d = 24
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddArc(2, 2, $d, $d, 180, 90)
    $p.AddArc(62 - $d, 2, $d, $d, 270, 90)
    $p.AddArc(62 - $d, 62 - $d, $d, $d, 0, 90)
    $p.AddArc(2, 62 - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $fill = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 12, 18, 24))
    $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 34, 229, 255)), 4
    $g.FillPath($fill, $p)
    $g.DrawPath($pen, $p)
    $font = New-Object Drawing.Font 'Consolas', 34, ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $sf = New-Object Drawing.StringFormat
    $sf.Alignment = [Drawing.StringAlignment]::Center
    $sf.LineAlignment = [Drawing.StringAlignment]::Center
    $brush = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 34, 229, 255))
    $rect = New-Object Drawing.RectangleF 0, 2, 64, 64
    $g.DrawString('R', $font, $brush, $rect, $sf)
    $icon = [Drawing.Icon]::FromHandle($bmp.GetHicon())
    $g.Dispose(); $bmp.Dispose(); $p.Dispose(); $fill.Dispose(); $pen.Dispose(); $font.Dispose(); $brush.Dispose(); $sf.Dispose()
    return $icon
}

if ($MakeIcon) {
    $icon = New-RioIcon
    $fs = [IO.File]::Create((Join-Path $PSScriptRoot 'rio.ico'))
    try { $icon.Save($fs) } finally { $fs.Dispose(); $icon.Dispose() }
    exit 0
}

# Win32 helpers: find/hide/restore windows, global hotkeys, idle time, fullscreen check, no-activate windows.
if (-not ('RioWindowApiV4' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Windows.Forms' -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class RioHotkeyV4 : NativeWindow, IDisposable {
    [DllImport("user32.dll", SetLastError=true)] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError=true)] static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public event EventHandler Pressed;
    public int LastId { get; private set; }
    public RioHotkeyV4() { CreateHandle(new CreateParams()); }
    public bool Register(int id, uint modifiers, uint vk) { return RegisterHotKey(Handle, id, modifiers | 0x4000, vk); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312) { LastId = m.WParam.ToInt32(); EventHandler h = Pressed; if (h != null) h(this, EventArgs.Empty); }
        base.WndProc(ref m);
    }
    public void Dispose() {
        if (Handle != IntPtr.Zero) { UnregisterHotKey(Handle, 1); UnregisterHotKey(Handle, 2); UnregisterHotKey(Handle, 3); DestroyHandle(); }
    }
}
public class RioWindowApiV4 {
    delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rc);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr hWnd, int index, int value);
    public static IntPtr Find(string contains) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr h, IntPtr l) {
            StringBuilder s = new StringBuilder(512); GetWindowText(h, s, s.Capacity);
            string title = s.ToString();
            foreach (string part in contains.Split('|')) {
                if (part.Length > 0 && title.IndexOf(part, StringComparison.OrdinalIgnoreCase) >= 0) { found = h; return false; }
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static uint IdleMs() {
        LASTINPUTINFO l = new LASTINPUTINFO();
        l.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref l)) return 0;
        return unchecked((uint)Environment.TickCount - l.dwTime);
    }
    public static void NoActivate(IntPtr h) {
        int ex = GetWindowLong(h, -20);
        SetWindowLong(h, -20, ex | 0x08000000 | 0x00000080);
    }
    public static string ClassOf(IntPtr h) { StringBuilder s = new StringBuilder(128); GetClassName(h, s, 128); return s.ToString(); }
    public static bool IsFullscreen(IntPtr h, int l, int t, int r, int b) {
        RECT rc; if (!GetWindowRect(h, out rc)) return false;
        return rc.Left <= l && rc.Top <= t && rc.Right >= r && rc.Bottom >= b;
    }
}
'@
}

if (-not ('RioLayerFormV2' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Windows.Forms','System.Drawing' -TypeDefinition @'
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

// A borderless, click-through-where-transparent window that shows a 32-bit ARGB bitmap
// with real per-pixel alpha (smooth edges, soft shadows, no colour-key halo).
// V2: Push() can also apply an overall opacity, used for fade in / fade out.
public class RioLayerFormV2 : Form {
    [StructLayout(LayoutKind.Sequential)] struct PT { public int x; public int y; }
    [StructLayout(LayoutKind.Sequential)] struct SZ { public int cx; public int cy; }
    [StructLayout(LayoutKind.Sequential, Pack=1)] struct BLEND { public byte Op; public byte Flags; public byte Alpha; public byte Format; }
    [DllImport("user32.dll", SetLastError=true)] static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref PT pptDst, ref SZ psize, IntPtr hdcSrc, ref PT pptSrc, int crKey, ref BLEND pblend, int dwFlags);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr hDC);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr hObject);
    protected override CreateParams CreateParams {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x00080000 | 0x00000080 | 0x08000000 | 0x00000008; return cp; }
    }
    protected override bool ShowWithoutActivation { get { return true; } }
    public void Push(Bitmap bmp, int x, int y) { Push(bmp, x, y, (byte)255); }
    public void Push(Bitmap bmp, int x, int y, byte alpha) {
        IntPtr screenDc = GetDC(IntPtr.Zero);
        IntPtr memDc = CreateCompatibleDC(screenDc);
        IntPtr hBmp = IntPtr.Zero; IntPtr old = IntPtr.Zero;
        try {
            hBmp = bmp.GetHbitmap(Color.FromArgb(0));
            old = SelectObject(memDc, hBmp);
            SZ size = new SZ(); size.cx = bmp.Width; size.cy = bmp.Height;
            PT src = new PT(); src.x = 0; src.y = 0;
            PT dst = new PT(); dst.x = x; dst.y = y;
            BLEND bf = new BLEND(); bf.Op = 0; bf.Flags = 0; bf.Alpha = alpha; bf.Format = 1;
            UpdateLayeredWindow(this.Handle, screenDc, ref dst, ref size, memDc, ref src, 0, ref bf, 2);
        } finally {
            if (old != IntPtr.Zero) SelectObject(memDc, old);
            if (hBmp != IntPtr.Zero) DeleteObject(hBmp);
            DeleteDC(memDc);
            ReleaseDC(IntPtr.Zero, screenDc);
        }
    }
}

// Dark colour table so the pet's right-click menu matches the dashboard theme.
public class RioDarkColors : ProfessionalColorTable {
    static Color Rgb(int r, int g, int b) { return Color.FromArgb(255, r, g, b); }
    public override Color ToolStripDropDownBackground { get { return Rgb(20, 27, 38); } }
    public override Color ImageMarginGradientBegin { get { return Rgb(20, 27, 38); } }
    public override Color ImageMarginGradientMiddle { get { return Rgb(20, 27, 38); } }
    public override Color ImageMarginGradientEnd { get { return Rgb(20, 27, 38); } }
    public override Color MenuBorder { get { return Rgb(52, 64, 82); } }
    public override Color MenuItemBorder { get { return Rgb(52, 74, 100); } }
    public override Color MenuItemSelected { get { return Rgb(36, 50, 70); } }
    public override Color MenuItemSelectedGradientBegin { get { return Rgb(36, 50, 70); } }
    public override Color MenuItemSelectedGradientEnd { get { return Rgb(36, 50, 70); } }
    public override Color MenuItemPressedGradientBegin { get { return Rgb(30, 42, 60); } }
    public override Color MenuItemPressedGradientMiddle { get { return Rgb(30, 42, 60); } }
    public override Color MenuItemPressedGradientEnd { get { return Rgb(30, 42, 60); } }
    public override Color SeparatorDark { get { return Rgb(52, 64, 82); } }
    public override Color SeparatorLight { get { return Rgb(20, 27, 38); } }
    public override Color CheckBackground { get { return Rgb(36, 50, 70); } }
    public override Color CheckSelectedBackground { get { return Rgb(36, 50, 70); } }
    public override Color CheckPressedBackground { get { return Rgb(36, 50, 70); } }
}

// Per-monitor DPI awareness: windows are no longer stretched by Windows on scaled displays, so text stays sharp.
public static class RioDpi {
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    public static void Enable() {
        try { if (!SetProcessDpiAwarenessContext(new IntPtr(-4))) { SetProcessDPIAware(); } }
        catch (Exception) { try { SetProcessDPIAware(); } catch (Exception) { } }
    }
}
'@
}

# --- DPI: render at native resolution (crisp text). Set "dpi": false in pet.json to switch this off. ---
$script:ds = 1.0; $dpiOn = $true
try {
    try { $pc0 = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pet.json') -Raw | ConvertFrom-Json; if ($null -ne $pc0.dpi -and -not [bool]$pc0.dpi) { $dpiOn = $false } } catch {}
    if ($dpiOn) { [RioDpi]::Enable() }
    $gdc = [Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $script:ds = [Math]::Max(1.0, [Math]::Round($gdc.DpiX / 96.0, 2)); $gdc.Dispose()
} catch { $script:ds = 1.0 }

if ($Stop) {
    # Stop controller/server first so the close-to-tray watcher cannot reopen the window.
    $others = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and ($_.CommandLine -like '*tray.ps1*' -or $_.CommandLine -like '*server.ps1*') }
    foreach ($proc in $others) { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 250
    $h = [RioWindowApiV4]::Find('RIO LIFE OS')
    if ($h -ne [IntPtr]::Zero) { [RioWindowApiV4]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null }
    exit 0
}

$mutex = New-Object Threading.Mutex($false, 'Local\RIOLifeOSTray')
if (-not $mutex.WaitOne(0)) { exit 0 }

$script:quitting = $false
$script:windowDetected = $false
$script:lastRelaunch = [DateTime]::MinValue
$script:synth = $null
$script:serverProcess = $null
$Url = 'http://localhost:5173/'
$HotMods = 6 # Ctrl + Shift
$EdgeArgs = @('--app=' + $Url, '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows')

function Test-RioServer {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect('127.0.0.1', 5173, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne(400)) { return $false }
        $client.EndConnect($ar)
        return $true
    } catch { return $false } finally { $client.Close() }
}

function Start-RioServer {
    if (Test-RioServer) { return }
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $PSScriptRoot 'server.ps1') + '"'
    $script:serverProcess = Start-Process -FilePath $psExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    for ($i = 0; $i -lt 40; $i++) {
        if (Test-RioServer) { return }
        Start-Sleep -Milliseconds 250
    }
    throw 'RIO local server did not start on port 5173. Check server.ps1 or another app using this port.'
}

# Match the final title AND the early 'localhost:5173' title, so a relaunched window is hidden before it flashes.
function Find-RioWindow { return [RioWindowApiV4]::Find('RIO LIFE OS|localhost:5173') }

function Open-RioWindow([switch]$Hidden) {
    Start-RioServer
    $h = Find-RioWindow
    if ($h -eq [IntPtr]::Zero) {
        try {
            Start-Process -FilePath 'msedge.exe' -ArgumentList $EdgeArgs -ErrorAction Stop | Out-Null
        } catch {
            $edgePath = $null
            foreach ($candidate in @(
                "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
            )) { if ($candidate -and (Test-Path -LiteralPath $candidate)) { $edgePath = $candidate; break } }
            if ($edgePath) { Start-Process -FilePath $edgePath -ArgumentList $EdgeArgs | Out-Null }
            else { Start-Process -FilePath $Url | Out-Null }
        }
        $step = if ($Hidden) { 15 } else { 250 }
        for ($i = 0; $i -lt (12000 / $step); $i++) {
            Start-Sleep -Milliseconds $step
            $h = Find-RioWindow
            if ($h -ne [IntPtr]::Zero) { if ($Hidden) { [RioWindowApiV4]::ShowWindow($h, 0) | Out-Null }; break }
        }
    }
    if ($h -ne [IntPtr]::Zero) {
        $script:windowDetected = $true
        if ($Hidden) { [RioWindowApiV4]::ShowWindow($h, 0) | Out-Null }
        else { [RioWindowApiV4]::ShowWindow($h, 9) | Out-Null; [RioWindowApiV4]::SetForegroundWindow($h) | Out-Null }
        return $true
    }
    return $false
}

function Toggle-RioWindow {
    $h = Find-RioWindow
    if ($h -eq [IntPtr]::Zero) { [void](Open-RioWindow); return }
    if ([RioWindowApiV4]::IsWindowVisible($h) -and [RioWindowApiV4]::GetForegroundWindow() -eq $h) {
        [RioWindowApiV4]::ShowWindow($h, 0) | Out-Null
    } else {
        [RioWindowApiV4]::ShowWindow($h, 9) | Out-Null
        [RioWindowApiV4]::SetForegroundWindow($h) | Out-Null
    }
}

function Stop-Rio {
    if ($script:quitting) { return }
    $script:quitting = $true
    if ($script:watcher) { $script:watcher.Stop(); $script:watcher.Dispose() }
    $h = Find-RioWindow
    if ($h -ne [IntPtr]::Zero) { [RioWindowApiV4]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null }
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -like '*server.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($script:synth) { try { $script:synth.SpeakAsyncCancelAll(); $script:synth.Dispose() } catch {} }
    if ($script:notify) { $script:notify.Visible = $false; $script:notify.Dispose() }
    if ($script:hotkeys) { $script:hotkeys.Dispose() }
    if ($script:menu) { $script:menu.Dispose() }
    if ($script:petTimer) { try { $script:petTimer.Stop() } catch {} }
    if ($script:toast) { try { $script:toast.Close(); $script:toast.Dispose() } catch {} }
    if ($script:bub) { try { $script:bub.Close(); $script:bub.Dispose() } catch {} }
    if ($script:pet) { try { $script:pet.Close(); $script:pet.Dispose() } catch {} }
    if ($script:pg) { try { $script:pg.Dispose() } catch {} }
    if ($script:pbmp) { try { $script:pbmp.Dispose() } catch {} }
    [Windows.Forms.Application]::Exit()
}

function Speak-RioGreeting {
    try {
        Add-Type -AssemblyName System.Speech
        $now = Get-Date
        $hour = $now.Hour
        if ($hour -ge 5 -and $hour -lt 12) {
            $line = 'Good morning, Rio. A fresh day, a clear mind, and one step at a time. You have got this.'
        } elseif ($hour -ge 12 -and $hour -lt 17) {
            $line = 'Good afternoon, Rio. Welcome back. Keep your focus steady. Small progress still counts.'
        } elseif ($hour -ge 17 -and $hour -lt 22) {
            $line = 'Welcome back, Rio. Take a breath, reset your focus, and make this time count.'
        } else {
            $line = 'Welcome back, Rio. Keep tonight calm. One small step is enough.'
        }
        $script:synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $script:synth.Rate = 2
        $script:synth.Volume = 100
        $voice = $script:synth.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -eq 'en-IN' } | Select-Object -First 1
        if ($voice) { $script:synth.SelectVoice($voice.VoiceInfo.Name) }
        $script:synth.SpeakAsync($line) | Out-Null
    } catch {
        # Speech is optional: RIO still starts normally if Windows has no compatible voice.
    }
}

# =====================================================================
#  DESKTOP PET  (Spider-style / Bat-style)
#  - while you work: it hugs a screen edge, half visible, peeking
#  - when you are idle for a long time: it comes to the middle and plays
#  - mouse near it for 2 seconds: it teleports far away from the mouse
#  - speech bubbles only for events (task start/end, teleport, pomodoro...)
#  - when a task time is over it asks for confirmation (toast bottom-right)
# =====================================================================
$script:PetCfgFile = Join-Path $PSScriptRoot 'pet.json'
$script:SyncFile = Join-Path $PSScriptRoot 'sync.json'
$script:CmdFile = Join-Path $PSScriptRoot 'cmd.json'
$script:cmdLog = New-Object Collections.ArrayList
$script:cmdSeq = 0
$script:rnd = New-Object Random
$script:br = @{}

$script:skin = 'spider_2'; $script:petHidden = $false; $script:petAlways = $false
$script:pet = $null; $script:bub = $null; $script:toast = $null; $script:petTimer = $null
$script:petOn = $false
$script:mode = 'peek'      # peek | dash | roam | tp
$script:side = 'R'
$script:fx = 0.0; $script:fy = 0.0
$script:vis = 0.0; $script:visT = 46.0; $script:vis0 = 46.0; $script:visRest = 0
$script:peekY = 300.0; $script:gx = 0.0; $script:gy = 0.0; $script:speed = 4.0; $script:wait = 0
$script:scale = 1.0; $script:tpPhase = 0; $script:tpT = 0; $script:tpFrom = 'peek'; $script:tpQuip = $true
$script:tk = 0; $script:act = 'idle'; $script:actEnd = 0
$script:dragging = $false; $script:moved = $false; $script:menuOpen = $false
$script:lastClick = [DateTime]::MinValue; $script:nearTicks = 0
$script:idleMs = 0; $script:actv = 0.0; $script:fsHide = $false; $script:dashFocus = $false
$script:focusing = $false; $script:sleepy = $false
$script:sy = $null; $script:syTime = [DateTime]::MinValue; $script:lastEv = $null
$script:bText = ''; $script:bUntil = [DateTime]::MinValue; $script:bShown = $false; $script:bTail = 'd'
$script:sayWait = New-Object Collections.ArrayList
$script:curAsk = $null; $script:answered = ''; $script:toastId = ''
# --- real-image pet state ---
$script:PW = 280; $script:PH = 270
$script:img = $null; $script:pbmp = $null; $script:pg = $null
$script:poseFrom = 'B'; $script:poseTo = 'B'; $script:poseMix = 1.0; $script:pulse = 0.0
$script:thwip = -1; $script:jflip = $false; $script:face = 1
$script:vx = 0.0; $script:vy = 0.0; $script:lastX = 0.0; $script:lastY = 0.0
$script:trail = New-Object Collections.ArrayList
# --- v4 polish state ---
$script:lang = 'en'; $script:breaksOn = $true; $script:peekFrac = 0.55
$script:quietUntil = [DateTime]::MinValue; $script:workSec = 0; $script:sleepDay = ''; $script:hov = 0.0
$script:dot = [string][char]0x00B7; $script:dash = [string][char]0x2013
$script:bQ = New-Object Collections.ArrayList
$script:bAlpha = 0; $script:bFade = 0; $script:bBmp = $null; $script:bLast = ''
$script:ToastM = 16; $script:ToastW = 352
# --- v5 sprite engine state ---
$script:spr = $null; $script:aName = ''; $script:aT = 0.0; $script:aDone = $false; $script:aSpd = 1.0
$script:evActive = $false; $script:evNext = ''; $script:evEndTk = 0; $script:sit = $false; $script:wasSleep = $false; $script:greeted = $false
$script:fxName = ''; $script:fxT0 = 0; $script:fxDur = 1
$script:tpWeb = $false; $script:tdx = 0.0; $script:tdy = 0.0; $script:tdSide = 'R'; $script:tdPeekY = 0.0; $script:tox = 0.0; $script:toy = 0.0; $script:tpZ = 8
$script:sfxOn = $true; $script:sfxPl = @{}; $script:sfxLast = @{}; $script:lastDoneAt = [DateTime]::MinValue
$script:tBmp = $null; $script:tBtns = New-Object Collections.ArrayList; $script:tHover = -1; $script:tStage = 0; $script:tAnim = 0

function Get-Scr {
    $s = [Windows.Forms.Screen]::PrimaryScreen
    $d = $script:ds
    if ($d -le 1.001) { return $s }
    $b = $s.Bounds; $w = $s.WorkingArea
    return [pscustomobject]@{
        Bounds = [Drawing.Rectangle]::new([int]($b.X / $d), [int]($b.Y / $d), [int]($b.Width / $d), [int]($b.Height / $d))
        WorkingArea = [Drawing.Rectangle]::new([int]($w.X / $d), [int]($w.Y / $d), [int]($w.Width / $d), [int]($w.Height / $d))
    }
}
function Get-Cur {
    $c = [Windows.Forms.Cursor]::Position
    if ($script:ds -le 1.001) { return $c }
    return [Drawing.Point]::new([int]($c.X / $script:ds), [int]($c.Y / $script:ds))
}
function Reset-Tf($g) {
    $g.ResetTransform()
    if ($script:ds -gt 1.001) { $g.ScaleTransform([single]$script:ds, [single]$script:ds) }
}

# ---------------- sound effects (sfx\\*.wav - replace any file with your own) ----------------
function Play-Sfx([string]$name) {
    if (-not $script:sfxOn -or $script:fsHide) { return }
    if ((Get-Date) -lt $script:quietUntil) { return }
    if ($script:focusing -and @('chime', 'alert', 'done', 'celebrate', 'distract', 'break') -notcontains $name) { return }
    try {
        $now = [DateTime]::UtcNow
        if ($script:sfxLast.ContainsKey($name) -and ($now - $script:sfxLast[$name]).TotalMilliseconds -lt 350) { return }
        $script:sfxLast[$name] = $now
        $p = $script:sfxPl[$name]
        if ($null -eq $p) {
            $f = Join-Path (Join-Path $PSScriptRoot 'sfx') ($name + '.wav')
            if (-not (Test-Path -LiteralPath $f)) { $script:sfxPl[$name] = $false; return }
            $p = New-Object Media.SoundPlayer $f; $p.Load(); $script:sfxPl[$name] = $p
        }
        if ($p) { $p.Play() }
    } catch {}
}
function RR([double]$a, [double]$b) { if ($b -le $a) { return [int]$a }; return $script:rnd.Next([int]$a, [int]$b) }
function Test-PeekLike { return ($script:mode -eq 'peek' -or $script:mode -eq 'dash' -or ($script:mode -eq 'tp' -and $script:tpFrom -eq 'peek')) }

function Load-PetCfg {
    try {
        if (Test-Path -LiteralPath $script:PetCfgFile) {
            $c = Get-Content -LiteralPath $script:PetCfgFile -Raw | ConvertFrom-Json
            if ([string]$c.skin -match '^[\w\-]+$') { $script:skin = [string]$c.skin }
            $script:petHidden = [bool]$c.hidden
            $script:petAlways = [bool]$c.always
            if ($c.lang -eq 'hi' -or $c.lang -eq 'en') { $script:lang = [string]$c.lang }
            if ($null -ne $c.breaks) { $script:breaksOn = [bool]$c.breaks }
            if ($null -ne $c.sfx) { $script:sfxOn = [bool]$c.sfx }
            if ($c.side -eq 'L' -or $c.side -eq 'R') { $script:side = [string]$c.side }
            if ($c.peek) { $pv = [double]$c.peek; if ($pv -ge 0.08 -and $pv -le 0.92) { $script:peekFrac = $pv } }
        }
    } catch {}
}
function Save-PetCfg {
    try {
        $o = [ordered]@{ skin = $script:skin; hidden = $script:petHidden; always = $script:petAlways; lang = $script:lang; breaks = $script:breaksOn; sfx = $script:sfxOn; dpi = $dpiOn; side = $script:side; peek = [Math]::Round($script:peekFrac, 3) }
        [IO.File]::WriteAllText($script:PetCfgFile, ($o | ConvertTo-Json -Compress))
    } catch {}
}

function Remember-Peek {
    $wa = (Get-Scr).WorkingArea
    $f = ($script:peekY + 132 - $wa.Top) / [double]$wa.Height
    $script:peekFrac = [Math]::Max(0.08, [Math]::Min(0.92, $f))
    Save-PetCfg
}

function Send-Cmd([string]$c, [hashtable]$extra = @{}) {
    $script:cmdSeq++
    $o = [ordered]@{ id = ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 10 + ($script:cmdSeq % 10)); cmd = $c }
    foreach ($k in $extra.Keys) { $o[$k] = $extra[$k] }
    [void]$script:cmdLog.Add($o)
    while ($script:cmdLog.Count -gt 6) { $script:cmdLog.RemoveAt(0) }
    try { [IO.File]::WriteAllText($script:CmdFile, (ConvertTo-Json -InputObject @($script:cmdLog) -Compress)) } catch {}
}

function New-RoundPath([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Real-image skins: pets\<skin>-1.png (swing pose), pets\<skin>-2.png (crouch pose), optional pets\<skin>.json (anchors).
# If the PNGs are missing, the old drawn pet is used automatically.
function Load-Png([string]$p) {
    $bytes = [IO.File]::ReadAllBytes($p)
    $ms = New-Object IO.MemoryStream (, $bytes)
    try {
        $src = [Drawing.Image]::FromStream($ms)
        try { return [Drawing.Bitmap]::new($src) } finally { $src.Dispose() }
    } finally { $ms.Dispose() }
}
function Load-SkinImages([string]$name) {
    if ($script:img) { foreach ($k in 'A', 'B') { try { $script:img[$k].Dispose() } catch {} } }
    $script:img = $null
    $dir = Join-Path $PSScriptRoot 'pets'
    $pa = Join-Path $dir ($name + '-1.png'); $pb = Join-Path $dir ($name + '-2.png')
    if (-not ((Test-Path -LiteralPath $pa) -and (Test-Path -LiteralPath $pb))) { return }
    try {
        $o = @{ A = (Load-Png $pa); B = (Load-Png $pb); scale = 0.5; aHand = @(0.95, 0.08); bHand = @(0.95, 0.08); bShoot = @(0.2, 0.2) }
        $cf = Join-Path $dir ($name + '.json')
        if (Test-Path -LiteralPath $cf) {
            $c = Get-Content -LiteralPath $cf -Raw | ConvertFrom-Json
            if ($c.scale) { $o.scale = [double]$c.scale }
            if ($c.aHand) { $o.aHand = @([double]$c.aHand[0], [double]$c.aHand[1]) }
            if ($c.bHand) { $o.bHand = @([double]$c.bHand[0], [double]$c.bHand[1]) }
            if ($c.bShoot) { $o.bShoot = @([double]$c.bShoot[0], [double]$c.bShoot[1]) }
        }
        $script:img = $o
        $script:poseFrom = 'B'; $script:poseTo = 'B'; $script:poseMix = 1.0
    } catch { $script:img = $null }
}

function Set-Skin([string]$name) {
    if ($name -notmatch '^[\w\-]+$') { $name = 'spider_2' }
    $sp = Load-SpriteSet $name
    if (-not $sp -and $name -ne 'bat') { $name = 'spider' }
    $script:skin = $name
    if ($name -eq 'bat') {
        $c = @{ body = @(40, 44, 56); belly = @(72, 80, 100); skin = @(238, 198, 168); acc = @(255, 205, 40); cape = @(22, 24, 32); glove = @(30, 32, 42); bd = @(255, 205, 40) }
    } else {
        $c = @{ body = @(206, 32, 44); belly = @(32, 72, 172); skin = @(206, 32, 44); acc = @(240, 240, 255); cape = @(206, 32, 44); glove = @(206, 32, 44); bd = @(235, 60, 70) }
    }
    foreach ($k in @($c.Keys)) {
        $script:br[$k] = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, $c[$k][0], $c[$k][1], $c[$k][2]))
    }
    $script:accRGB = $c['acc']
    $script:bpBorder = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, $c['bd'][0], $c['bd'][1], $c['bd'][2])), 2
    if ($sp) { Load-SkinImages '__none__' } else { Load-SkinImages $name }
}

# ---------------- ghost (click-through, no-activate) forms ----------------
function New-GhostForm([string]$text, [int]$w, [int]$h) {
    $f = New-Object Windows.Forms.Form
    $f.Text = $text; $f.FormBorderStyle = 'None'; $f.ShowInTaskbar = $false; $f.TopMost = $true; $f.StartPosition = 'Manual'
    $f.BackColor = [Drawing.Color]::FromArgb(255, 0, 255); $f.TransparencyKey = $f.BackColor
    $f.Size = New-Object Drawing.Size $w, $h
    $f.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'NonPublic,Instance').SetValue($f, $true, $null)
    $null = $f.Handle
    [RioWindowApiV4]::NoActivate($f.Handle)
    return $f
}

# ---------------- shared card drawing (speech cards + task toast) ----------------
function Draw-Shadow($g, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    for ($i = 8; $i -ge 1; $i--) {
        $p = New-RoundPath ($x - $i) ($y - $i + 4) ($w + 2 * $i) ($h + 2 * $i) ($r + $i)
        $sb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(8, 0, 0, 0))
        $g.FillPath($sb, $p); $sb.Dispose(); $p.Dispose()
    }
}
function Draw-CardBase($g, [double]$x, [double]$y, [double]$w, [double]$h, [double]$r, $acc) {
    Draw-Shadow $g $x $y $w $h $r
    $p = New-RoundPath $x $y $w $h $r
    $p1 = [Drawing.PointF]::new([single]$x, [single]$y); $p2 = [Drawing.PointF]::new([single]$x, [single]($y + $h))
    $lg = New-Object Drawing.Drawing2D.LinearGradientBrush $p1, $p2, ([Drawing.Color]::FromArgb(255, 32, 44, 62)), ([Drawing.Color]::FromArgb(255, 17, 24, 36))
    $g.FillPath($lg, $p)
    $g.SetClip($p)
    $ab = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, $acc[0], $acc[1], $acc[2]))
    $g.FillRectangle($ab, [single]$x, [single]$y, [single]4, [single]$h)
    $g.ResetClip()
    $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(70, 148, 170, 200)), 1
    $g.DrawPath($pen, $p)
    $pen.Dispose(); $ab.Dispose(); $lg.Dispose(); $p.Dispose()
}
function Get-Accent([string]$kind) {
    if ($kind -eq 'imp') { return @(255, 194, 74) }
    if ($kind -eq 'ok') { return @(77, 255, 166) }
    return @(34, 229, 255)
}

# ---------------- speech card (events only): per-pixel alpha, shadow, fade, queue ----------------
function Build-BubbleBitmap([string]$t, [string]$title, [string]$kind) {
    $M = 16; $tl = 10
    $szB = $script:mg.MeasureString($t, $script:fBody, 250)
    $tw = [Math]::Ceiling($szB.Width); $th = [Math]::Ceiling($szB.Height)
    $hh = 0; $hw = 0
    if ($title) { $szH = $script:mg.MeasureString($title, $script:fHead); $hh = 16; $hw = [Math]::Ceiling($szH.Width) }
    $iw = [Math]::Max($tw, $hw)
    $cw = [int]($iw + 38); $ch = [int]($th + 22 + $hh)
    $ox = 0; $ex = 0; $ey = 0
    if ($script:bTail -eq 'd') { $ey = $tl } elseif ($script:bTail -eq 'r') { $ex = $tl } else { $ox = $tl }
    $bw = $cw + 2 * $M + $ex + $ox; $bh = $ch + 2 * $M + $ey
    $cx = $M + $ox; $cy = $M
    $ds = $script:ds
    $bmp = New-Object Drawing.Bitmap ([int][Math]::Ceiling($bw * $ds)), ([int][Math]::Ceiling($bh * $ds))
    $g = [Drawing.Graphics]::FromImage($bmp)
    try {
        $g.ScaleTransform([single]$ds, [single]$ds)
        $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.TextRenderingHint = 'AntiAlias'
        $acc = Get-Accent $kind
        Draw-CardBase $g $cx $cy $cw $ch 12 $acc
        # tail (overlaps the card edge by 1px so the border seam disappears)
        $mx = $cx + $cw / 2.0; $my = $cy + $ch / 2.0
        if ($script:bTail -eq 'd') {
            $pts = [Drawing.PointF[]]@([Drawing.PointF]::new([single]($mx - 8), [single]($cy + $ch - 1)), [Drawing.PointF]::new([single]($mx + 8), [single]($cy + $ch - 1)), [Drawing.PointF]::new([single]$mx, [single]($cy + $ch + $tl)))
            $tc = [Drawing.Color]::FromArgb(255, 18, 25, 38)
        } elseif ($script:bTail -eq 'r') {
            $pts = [Drawing.PointF[]]@([Drawing.PointF]::new([single]($cx + $cw - 1), [single]($my - 8)), [Drawing.PointF]::new([single]($cx + $cw - 1), [single]($my + 8)), [Drawing.PointF]::new([single]($cx + $cw + $tl), [single]$my))
            $tc = [Drawing.Color]::FromArgb(255, 24, 34, 48)
        } else {
            $pts = [Drawing.PointF[]]@([Drawing.PointF]::new([single]($cx + 1), [single]($my - 8)), [Drawing.PointF]::new([single]($cx + 1), [single]($my + 8)), [Drawing.PointF]::new([single]($cx - $tl), [single]$my))
            $tc = [Drawing.Color]::FromArgb(255, 24, 34, 48)
        }
        $tb0 = New-Object Drawing.SolidBrush $tc
        $tp0 = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(70, 148, 170, 200)), 1
        $g.FillPolygon($tb0, $pts); $g.DrawLine($tp0, $pts[0], $pts[2]); $g.DrawLine($tp0, $pts[1], $pts[2])
        $tb0.Dispose(); $tp0.Dispose()
        # text
        $x0 = $cx + 18
        if ($title) {
            $hb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, $acc[0], $acc[1], $acc[2]))
            $g.DrawString($title, $script:fHead, $hb, [single]$x0, [single]($cy + 10)); $hb.Dispose()
        }
        $bb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 226, 232, 240))
        $rc = [Drawing.RectangleF]::new([single]$x0, [single]($cy + 11 + $hh), [single]($iw + 12), [single]($th + 4))
        $g.DrawString($t, $script:fBody, $bb, $rc); $bb.Dispose()
    } finally { $g.Dispose() }
    return $bmp
}
function Place-Bubble {
    if (-not $script:bub -or -not $script:bShown -or -not $script:bBmp) { return }
    $s = Get-Scr; $wa = $s.WorkingArea; $b = $s.Bounds
    $w = $script:bBmp.Width / $script:ds; $h = $script:bBmp.Height / $script:ds; $M = 16
    $pcy = $script:fy + 132
    if ($script:bTail -eq 'r') { $x = $b.Right - $script:vis - 6 - $w + $M; $y = $pcy - $h / 2 - 8 }
    elseif ($script:bTail -eq 'l') { $x = $b.Left + $script:vis + 6 - $M; $y = $pcy - $h / 2 - 8 }
    else { $x = $script:fx + 110 - $w / 2; $y = $script:fy + 54 - $h + $M }
    $x = [Math]::Max($wa.Left - $M, [Math]::Min($wa.Right - $w + $M, $x))
    $y = [Math]::Max($wa.Top - $M, [Math]::Min($wa.Bottom - $h + $M, $y))
    $ix = [int]($x * $script:ds); $iy = [int]($y * $script:ds)
    $a = [int][Math]::Max(0, [Math]::Min(255, $script:bAlpha))
    $key = [string]$ix + ',' + [string]$iy + ',' + [string]$a
    if ($key -eq $script:bLast) { return }
    $script:bLast = $key
    $script:bub.Push($script:bBmp, $ix, $iy, [byte]$a)
}
function Show-Bubble([string]$t, [int]$sec, [string]$title = '', [string]$kind = 'norm') {
    if (-not $script:bub) { return }
    if (Test-PeekLike) { $script:bTail = if ($script:side -eq 'R') { 'r' } else { 'l' } } else { $script:bTail = 'd' }
    $old = $script:bBmp
    $script:bBmp = Build-BubbleBitmap $t $title $kind
    if ($old) { $old.Dispose() }
    $script:bText = $t
    $script:bUntil = (Get-Date).AddSeconds($sec)
    $script:bShown = $true; $script:bFade = 1; $script:bLast = ''
    Place-Bubble
    [RioWindowApiV4]::ShowWindow($script:bub.Handle, 4) | Out-Null
    if ($kind -eq 'imp') { Play-Sfx 'alert' } else { Play-Sfx 'pop' }
}
function Hide-Bubble {
    $script:bShown = $false; $script:bAlpha = 0; $script:bFade = 0; $script:bLast = ''
    if ($script:bub) { [RioWindowApiV4]::ShowWindow($script:bub.Handle, 0) | Out-Null }
}
function Next-Bubble {
    if ($script:bQ.Count -eq 0 -or $script:fsHide -or -not $script:petOn) { return }
    $it = $script:bQ[0]; $script:bQ.RemoveAt(0)
    Show-Bubble ([string]$it.t) ([int]$it.sec) ([string]$it.title) ([string]$it.kind)
}
function Tick-Bubble {
    if (-not $script:bShown) { return }
    if ((Get-Date) -gt $script:bUntil) { $script:bFade = -1 }
    if ($script:bFade -gt 0) {
        $script:bAlpha = [Math]::Min(255, $script:bAlpha + 55)
        if ($script:bAlpha -ge 255) { $script:bFade = 0 }
    } elseif ($script:bFade -lt 0) {
        $script:bAlpha = $script:bAlpha - 40
        if ($script:bAlpha -le 0) { Hide-Bubble; Next-Bubble; return }
    }
    Place-Bubble
}

# priority: 'imp' (important, interrupts), 'norm' (event, queued), 'low' (idle chatter, only while the pet is roaming)
function Pet-Say([string]$t, [int]$sec = 6, [string]$pr = 'norm', [string]$title = '', [string]$kind = '') {
    if (-not $t) { return }
    if ($pr -eq 'low' -and ($script:mode -ne 'roam' -or $script:focusing)) { return }
    if ($pr -ne 'imp' -and (Get-Date) -lt $script:quietUntil) { return }
    if (-not $kind) { $kind = if ($pr -eq 'imp') { 'imp' } else { 'norm' } }
    if ($script:fsHide) {
        if ($pr -ne 'low') { [void]$script:sayWait.Add(@($t, $sec)); if ($script:sayWait.Count -gt 5) { $script:sayWait.RemoveAt(0) } }
        return
    }
    if (-not $script:petOn) { return }
    if ($script:bShown -and $script:bFade -ge 0 -and (Get-Date) -le $script:bUntil -and $pr -ne 'imp') {
        if ($pr -eq 'low') { return }
        [void]$script:bQ.Add(@{ t = $t; sec = $sec; title = $title; kind = $kind })
        while ($script:bQ.Count -gt 4) { $script:bQ.RemoveAt(0) }
        return
    }
    Show-Bubble $t $sec $title $kind
}
function Pet-Jump {
    $script:act = 'jump'; $script:actEnd = $script:tk + 25
    if ($script:spr) {
        $script:jflip = $false
        if ($script:spr.anims.ContainsKey('jump')) { Play-Event 'jump' 'land'; Play-Sfx 'jump' } else { Play-Event 'wave' }
    } else {
        $script:jflip = ($script:rnd.Next(0, 3) -eq 0)
        if ($script:thwip -lt 0 -and $script:rnd.Next(0, 2) -eq 0) { $script:thwip = 0 }
    }
}
# One-shot reactions: 'click' (wave), 'happy' (celebrate), 'dance', 'greet' (wave). Falls back to a hop for classic pets.
function Pet-React([string]$kind) {
    if (-not $script:spr) { Pet-Jump; return }
    if ($kind -eq 'happy') { if ($script:rnd.Next(0, 2) -eq 0) { Play-Event 'cheer' } else { Play-Event 'celebrate' } }
    elseif ($kind -eq 'dance') { Play-Event 'dance' }
    elseif ($kind -eq 'point') { Play-Event 'point' }
    else { Play-Event 'wave'; Play-Sfx 'wave' }
}
# React to the text of a dashboard event (task done, goal reached, new block ...)
function Event-React([string]$txt) {
    if (-not $script:petOn) { return }
    if ($txt -match 'Distracted') { Play-Sfx 'distract'; Play-Event 'sit' }
    elseif ($txt -match 'Done mark') { if (((Get-Date) - $script:lastDoneAt).TotalSeconds -gt 20) { Play-Sfx 'done'; Pet-React 'happy' } }
    elseif ($txt -match 'complete|poora|Zabardast|goal|Beast') { Play-Sfx 'celebrate'; Pet-React 'happy' }
    elseif ($txt -match 'Ab shuru|Break khatam|Break time') { Pet-React 'click' }
}
function Pet-Click {
    $s = $script:sy; if ($s -and ($s.cur -or $s.next)) { Pet-React 'point' } else { Pet-React 'click' }; $hi = ($script:lang -eq 'hi'); $d = $script:dot; $nl = [Environment]::NewLine
    $ttl = ''
    if ($s -and $s.cur) {
        if ($hi) { $ttl = 'ABHI'; $txt = [string]$s.cur + $nl + [string]$s.curEnd + ' tak  ' + $d + '  Aage: ' + [string]$s.next + ' (' + [string]$s.nextAt + ')' }
        else { $ttl = 'NOW'; $txt = [string]$s.cur + $nl + 'Until ' + [string]$s.curEnd + '  ' + $d + '  Next: ' + [string]$s.next + ' at ' + [string]$s.nextAt }
    } elseif ($s -and $s.next) {
        if ($hi) { $ttl = 'FREE TIME'; $txt = 'Abhi free ho.' + $nl + 'Aage: ' + [string]$s.next + ' (' + [string]$s.nextAt + ')' }
        else { $ttl = 'FREE TIME'; $txt = 'Nothing scheduled right now.' + $nl + 'Next: ' + [string]$s.next + ' at ' + [string]$s.nextAt }
    } else {
        if ($hi) { $ttl = 'PLAN NAHI BANA'; $txt = 'Dashboard kholo aur aaj ka plan generate karo.' }
        else { $ttl = 'NO PLAN YET'; $txt = 'Open the dashboard and generate today''s plan.' }
    }
    Show-Bubble $txt 8 $ttl 'norm'
}
function Pet-Quip {
    $s = $script:sy
    if ($script:lang -eq 'hi') {
        $l = @('Chhote steps, bada result.', 'Posture seedha karo!', 'Aankhein 20 second door dekho.', 'Ek ghoont paani piyo.')
        if ($s) {
            if ($s.cur) { $l += ('Abhi: ' + $s.cur) }
            if ([int]$s.push -lt [int]$s.goal) { $l += ('Pushups: ' + $s.push + '/' + $s.goal + '. Ek set maar do!') }
            if ([int]$s.open -gt 0) { $l += ([string]$s.open + ' tasks baaki hain aaj ke.') }
        }
    } else {
        $l = @('Small steps, big results.', 'Check your posture.', 'Look 20 feet away for 20 seconds.', 'Have a sip of water.')
        if ($s) {
            if ($s.cur) { $l += ('Current focus: ' + $s.cur) }
            if ([int]$s.push -lt [int]$s.goal) { $l += ('Pushups: ' + $s.push + '/' + $s.goal + '. Time for a set?') }
            if ([int]$s.open -gt 0) { $l += ([string]$s.open + ' tasks still open today.') }
        }
    }
    Pet-Say (Get-Random -InputObject $l) 6 'low'
}
function Tp-Quip {
    if ($script:lang -eq 'hi') {
        if ($script:skin -eq 'bat') { $l = @('Shadows mein gayab!', 'I am the night. Mouse door rakho.', 'Pakde mat jao, Gotham rule.') }
        else { $l = @('Spider-sense tingling! Thwip!', 'Pakad ke dikhao, hero hoon main!', 'Itni jaldi nahi, bhai!') }
    } else {
        if ($script:skin -eq 'bat') { $l = @('Vanished into the shadows.', 'I am the night. Keep your distance.', 'Gotham rules.') }
        else { $l = @('Spider-sense tingling! Thwip!', 'Nice try. Too slow!', 'Catch me if you can!') }
    }
    return (Get-Random -InputObject $l)
}

# ---------------- position helpers ----------------
function Peek-TargetX {
    $b = (Get-Scr).Bounds
    if ($script:side -eq 'R') { return ($b.Right - $script:vis - 64) }
    return ($b.Left + $script:vis - 156)
}
function Pick-RoamGoal {
    $wa = (Get-Scr).WorkingArea
    $c = Get-Cur
    for ($i = 0; $i -lt 6; $i++) {
        $px = RR ($wa.Left + $wa.Width * 0.2) ($wa.Right - $wa.Width * 0.2)
        $py = RR ($wa.Top + $wa.Height * 0.3) ($wa.Bottom - $wa.Height * 0.2)
        if ([Math]::Abs($px - $c.X) + [Math]::Abs($py - $c.Y) -gt 260) { break }
    }
    $script:gx = $px - 110; $script:gy = $py - 132
}
function Go-Roam {
    if ($script:mode -ne 'peek' -or $script:sleepy) { return }
    $script:mode = 'roam'; $script:wait = 0; $script:speed = 4.0
    Pick-RoamGoal
}
function Go-Peek {
    if ($script:mode -ne 'roam') { return }
    $s = Get-Scr; $wa = $s.WorkingArea; $b = $s.Bounds
    $script:side = if (($script:fx + 110) -gt ($b.Left + $b.Width / 2)) { 'R' } else { 'L' }
    $script:peekY = [Math]::Max($wa.Top + 20, [Math]::Min($wa.Bottom - 190, $script:fy))
    $script:visT = $script:vis0; $script:mode = 'dash'
}
function Roam-Action {
    switch ($script:rnd.Next(0, 12)) {
        0 { Pick-RoamGoal }
        1 { Pick-RoamGoal }
        2 { Pick-RoamGoal }
        3 { Pet-Jump }
        4 { Pet-Jump }
        5 { Pet-Quip }
        6 { Start-Teleport $false }
        7 { if ($script:spr) { Pet-React 'dance' } else { Pick-RoamGoal } }
        8 { if ($script:spr) { Pet-React 'click' } else { Pick-RoamGoal } }
        9 { if ($script:spr) { Play-Fx 'flip' 22; Play-Sfx 'jump' } else { Pet-Jump } }
        10 { if ($script:spr) { Play-Event 'stretch'; Play-Sfx 'snap' } else { Pick-RoamGoal } }
        default { Pick-RoamGoal }
    }
}

# ---------------- teleport ----------------
function Start-Teleport([bool]$quip) {
    if ($script:mode -eq 'tp') { return }
    $script:tpFrom = if ($script:mode -eq 'roam') { 'roam' } else { 'peek' }
    $script:mode = 'tp'; $script:tpPhase = 0; $script:tpT = 0; $script:tpQuip = $quip; $script:nearTicks = 0
    $script:evActive = $false; $script:fxName = ''; $script:tpWeb = $false
    if ($script:spr -and $script:spr.anims.ContainsKey('thwip') -and $script:spr.anims['thwip'].ContainsKey('hands')) {
        # Spider characters: shoot a web at the destination and zip along it instead of vanishing.
        $ox = $script:fx; $oy = $script:fy; $os = $script:side; $opy = $script:peekY; $ov = $script:vis; $ovt = $script:visT; $ogx = $script:gx; $ogy = $script:gy
        Pick-Dest
        $script:tdx = $script:fx; $script:tdy = $script:fy; $script:tdSide = $script:side; $script:tdPeekY = $script:peekY
        $script:fx = $ox; $script:fy = $oy; $script:side = $os; $script:peekY = $opy; $script:vis = $ov; $script:visT = $ovt; $script:gx = $ogx; $script:gy = $ogy
        $script:tpWeb = $true
        $script:face = if ($script:tdx -ge $script:fx) { 1 } else { -1 }
    } else { Play-Sfx 'zip' }
}
function Pick-Dest {
    $s = Get-Scr; $wa = $s.WorkingArea
    $c = Get-Cur
    $midY = $wa.Top + $wa.Height / 2
    if ($script:tpFrom -eq 'peek') {
        if ($c.X -gt $wa.Left + $wa.Width * 0.65) { $script:side = 'L' }
        elseif ($c.X -lt $wa.Left + $wa.Width * 0.35) { $script:side = 'R' }
        else { $script:side = if ($script:rnd.Next(0, 2) -eq 0) { 'L' } else { 'R' } }
        # mouse low -> go high, mouse high -> go low
        if ($c.Y -gt $midY) { $cy = RR ($wa.Top + 140) ($midY - 40) } else { $cy = RR ($midY + 40) ($wa.Bottom - 140) }
        $script:peekY = $cy - 132
        $script:vis = $script:vis0; $script:visT = $script:vis0
        $script:fx = Peek-TargetX; $script:fy = $script:peekY
    } else {
        $best = @(($wa.Left + $wa.Width / 2), ($wa.Top + $wa.Height / 2)); $bs = -1
        for ($i = 0; $i -lt 14; $i++) {
            $px = RR ($wa.Left + 160) ($wa.Right - 160); $py = RR ($wa.Top + 160) ($wa.Bottom - 120)
            $d = [Math]::Sqrt([Math]::Pow($px - $c.X, 2) + [Math]::Pow($py - $c.Y, 2))
            $opp = (($c.Y -gt $midY) -and ($py -lt $midY)) -or (($c.Y -le $midY) -and ($py -ge $midY))
            $score = $d + $(if ($opp) { 250 } else { 0 })
            if ($score -gt $bs) { $bs = $score; $best = @($px, $py) }
        }
        $script:fx = $best[0] - 110; $script:fy = $best[1] - 132; $script:gx = $script:fx; $script:gy = $script:fy
    }
}
function Near-Check {
    $c = Get-Cur
    $dx = $c.X - ($script:fx + 110); $dy = $c.Y - ($script:fy + 132)
    $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
    $hv = 0.0; if ($d -lt 120 -and -not $script:menuOpen) { $hv = 1.0 }
    $script:hov = $script:hov * 0.8 + 0.2 * $hv
    if ($script:dragging -or $script:menuOpen -or $script:toast) { $script:nearTicks = 0; return }
    if ($d -lt 85 -and ((Get-Date) - $script:lastClick).TotalSeconds -gt 6) { $script:nearTicks++ } else { $script:nearTicks = 0 }
    if ($script:nearTicks -ge 40) { $script:nearTicks = 0; Start-Teleport ($script:rnd.Next(0, 10) -lt 6) }
}

# ---------------- confirmation toast (task time over) ----------------
# Custom-drawn card on a per-pixel-alpha window: smooth edges, soft shadow, hover effects, slide + fade in.
function Close-Toast {
    if ($script:toast) { try { $script:toast.Close(); $script:toast.Dispose() } catch {}; $script:toast = $null }
    if ($script:tBmp) { try { $script:tBmp.Dispose() } catch {}; $script:tBmp = $null }
    $script:tBtns = New-Object Collections.ArrayList; $script:tHover = -1; $script:toastId = ''
}
function Toast-YOff {
    $p = [Math]::Min(1.0, $script:tAnim / 6.0)
    return [int](18 * (1.0 - $p) * (1.0 - $p))
}
function Place-Toast([int]$yOff = 0) {
    $f = $script:toast; if (-not $f -or -not $script:tBmp) { return }
    $wa = (Get-Scr).WorkingArea
    $a = [int][Math]::Max(0, [Math]::Min(255, $script:tAnim * 46))
    $x = $wa.Right - $script:tBmp.Width / $script:ds + $script:ToastM - 12
    $y = $wa.Bottom - $script:tBmp.Height / $script:ds + $script:ToastM - 12 + $yOff
    $f.Push($script:tBmp, [int]($x * $script:ds), [int]($y * $script:ds), [byte]$a)
}
function Add-TBtn($list, [string]$tag, [string]$label, [int]$x, [int]$y, [int]$w, $col, [bool]$fill) {
    [void]$list.Add(@{ tag = $tag; label = $label; r = [Drawing.Rectangle]::new($x, $y, $w, 34); col = $col; fill = $fill })
}
function Draw-Btn($g, $b, [bool]$hot) {
    $r = $b.r; $c = $b.col
    $p = New-RoundPath $r.X $r.Y $r.Width $r.Height 8
    if ($b.fill) {
        $fa = 226; if ($hot) { $fa = 255 }
        $fb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb($fa, $c[0], $c[1], $c[2]))
        $g.FillPath($fb, $p); $fb.Dispose()
        $tb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 10, 16, 26))
    } else {
        $fa = 20; if ($hot) { $fa = 64 }
        $pa = 150; if ($hot) { $pa = 255 }
        $fb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb($fa, $c[0], $c[1], $c[2]))
        $g.FillPath($fb, $p); $fb.Dispose()
        $pn = New-Object Drawing.Pen ([Drawing.Color]::FromArgb($pa, $c[0], $c[1], $c[2])), 1.2
        $g.DrawPath($pn, $p); $pn.Dispose()
        $tb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, $c[0], $c[1], $c[2]))
    }
    $rc = [Drawing.RectangleF]::new([single]$r.X, [single]$r.Y, [single]$r.Width, [single]$r.Height)
    $g.DrawString([string]$b.label, $script:fBtn, $tb, $rc, $script:sf)
    $tb.Dispose(); $p.Dispose()
}
function Build-Toast([int]$stage) {
    $f = $script:toast; $a = $script:curAsk
    if (-not $f -or -not $a) { return }
    $M = $script:ToastM; $CW = $script:ToastW; $hi = ($script:lang -eq 'hi')
    $CH = 128; if ($stage -ne 0) { $CH = 172 }
    $ds = $script:ds
    $bmp = New-Object Drawing.Bitmap ([int][Math]::Ceiling(($CW + 2 * $M) * $ds)), ([int][Math]::Ceiling(($CH + 2 * $M) * $ds))
    $g = [Drawing.Graphics]::FromImage($bmp)
    $list = New-Object Collections.ArrayList
    try {
        $g.ScaleTransform([single]$ds, [single]$ds)
        $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.TextRenderingHint = 'AntiAlias'
        $amb = @(255, 194, 74); $grn = @(77, 255, 166); $cya = @(34, 229, 255)
        Draw-CardBase $g $M $M $CW $CH 14 $amb
        $x0 = $M + 22
        if ($stage -eq 0) { $lbl = 'TIME IS UP'; if ($hi) { $lbl = 'TASK KA TIME KHATAM' } }
        else { $lbl = 'EXTEND BY'; if ($hi) { $lbl = 'KITNA TIME EXTEND KARNA HAI' } }
        $hb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, $amb[0], $amb[1], $amb[2]))
        $g.DrawString($lbl, $script:fHead, $hb, [single]$x0, [single]($M + 12)); $hb.Dispose()
        $wb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 241, 245, 249))
        $rt = [Drawing.RectangleF]::new([single]$x0, [single]($M + 28), [single]($CW - 44), [single]26)
        $g.DrawString([string]$a.t, $script:fTitle, $wb, $rt, $script:sfL); $wb.Dispose()
        if ($stage -eq 0) {
            $q = 'Did you finish it?'; if ($hi) { $q = 'Ho gaya?' }
            $sub = [string]$a.s + ' ' + $script:dash + ' ' + [string]$a.e + '   ' + $script:dot + '   ' + $q
        } else {
            $sub = 'How much more time do you need?'; if ($hi) { $sub = 'Kitna aur time chahiye?' }
        }
        $gb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 148, 163, 184))
        $rs = [Drawing.RectangleF]::new([single]$x0, [single]($M + 56), [single]($CW - 44), [single]20)
        $g.DrawString($sub, $script:fBody, $gb, $rs, $script:sfL); $gb.Dispose()
        # auto-'distracted' countdown (the dashboard marks the task as distracted after 10 minutes)
        $rem = 600.0
        if ($a.t0) { try { $rem = [Math]::Max(0.0, 600.0 - ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - [long]$a.t0) / 1000.0) } catch {} }
        $mm = [int][Math]::Floor($rem / 60); $ss = [int]($rem % 60)
        $cd = 'Distracted in ' + $mm + ':' + $ss.ToString('00'); if ($hi) { $cd = 'Distracted mark hoga: ' + $mm + ':' + $ss.ToString('00') }
        $cb = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 148, 163, 184))
        $g.DrawString($cd, $script:fHead, $cb, [Drawing.RectangleF]::new([single]($M + 150), [single]($M + 12), [single]($CW - 172), [single]14), $script:sfR); $cb.Dispose()
        $bx = $M + 22; $bw2 = $CW - 44; $byy = $M + $CH - 9
        $tb2 = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(40, 255, 255, 255))
        $g.FillRectangle($tb2, [single]$bx, [single]$byy, [single]$bw2, [single]3); $tb2.Dispose()
        $fr = [Math]::Max(0.0, [Math]::Min(1.0, $rem / 600.0))
        if ($rem -lt 120) { $pc = @(255, 92, 92) } else { $pc = @(255, 194, 74) }
        $pb2 = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, $pc[0], $pc[1], $pc[2]))
        $g.FillRectangle($pb2, [single]$bx, [single]$byy, [single]($bw2 * $fr), [single]3); $pb2.Dispose()
        $by = $M + 82
        if ($stage -eq 0) {
            $l1 = 'Done'; $l2 = 'Need more time'; $l3 = 'Later'
            if ($hi) { $l1 = 'Ho gaya'; $l2 = 'Aur time chahiye'; $l3 = 'Baad mein' }
            Add-TBtn $list 'done' $l1 ($M + 20) $by 92 $grn $true
            Add-TBtn $list 'more' $l2 ($M + 120) $by 132 $amb $false
            Add-TBtn $list 'later' $l3 ($M + 260) $by 76 $cya $false
        } else {
            $i = 0
            foreach ($mn in 10, 15, 20, 30, 45) { Add-TBtn $list ('m:' + $mn) ('+' + $mn) ($M + 20 + $i * 64) $by 56 $amb $false; $i++ }
            $lb = 'Back'; if ($hi) { $lb = 'Wapas' }
            Add-TBtn $list 'back' $lb ($M + 20) ($by + 44) 84 $cya $false
        }
        for ($k = 0; $k -lt $list.Count; $k++) { Draw-Btn $g $list[$k] ($k -eq $script:tHover) }
    } finally { $g.Dispose() }
    $old = $script:tBmp
    $script:tBmp = $bmp; $script:tBtns = $list; $script:tStage = $stage
    if ($old) { $old.Dispose() }
    Place-Toast (Toast-YOff)
}
function Show-Toast {
    Close-Toast
    $a = $script:curAsk; if (-not $a) { return }
    $f = New-Object RioLayerFormV2
    $f.Text = 'RioToast'; $f.FormBorderStyle = 'None'; $f.ShowInTaskbar = $false; $f.TopMost = $true; $f.StartPosition = 'Manual'
    $null = $f.Handle
    $f.add_MouseMove({ param($s, $e) Toast-Hover $e.X $e.Y })
    $f.add_MouseLeave({ Toast-Hover (-1) (-1) })
    $f.add_MouseDown({ param($s, $e) if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { Toast-Press $e.X $e.Y } })
    $script:toast = $f; $script:toastId = [string]$a.id; $script:tAnim = 0; $script:tHover = -1
    Build-Toast 0
    [RioWindowApiV4]::ShowWindow($f.Handle, 4) | Out-Null
    Play-Sfx 'chime'
}
function Toast-Hover([int]$x, [int]$y) {
    if (-not $script:toast) { return }
    $x = [int]($x / $script:ds); $y = [int]($y / $script:ds)
    $h = -1
    for ($i = 0; $i -lt $script:tBtns.Count; $i++) { if ($script:tBtns[$i].r.Contains($x, $y)) { $h = $i; break } }
    if ($h -ne $script:tHover) {
        $script:tHover = $h
        if ($h -ge 0) { $script:toast.Cursor = [Windows.Forms.Cursors]::Hand } else { $script:toast.Cursor = [Windows.Forms.Cursors]::Default }
        Build-Toast $script:tStage
    }
}
function Toast-Press([int]$x, [int]$y) {
    $x = [int]($x / $script:ds); $y = [int]($y / $script:ds)
    for ($i = 0; $i -lt $script:tBtns.Count; $i++) {
        if ($script:tBtns[$i].r.Contains($x, $y)) { Toast-Click ([string]$script:tBtns[$i].tag); return }
    }
}
function Toast-Click([string]$tag) {
    $a = $script:curAsk
    if (-not $a) { Close-Toast; return }
    $id = [string]$a.id
    if ($tag -eq 'done') { Send-Cmd 'ans' @{ aid = $id; ok = 1; min = 0 }; $script:answered = $id; Close-Toast; $script:lastDoneAt = Get-Date; Play-Sfx 'done'; Pet-React 'happy' }
    elseif ($tag -eq 'more') { $script:tHover = -1; Build-Toast 1 }
    elseif ($tag -eq 'back') { $script:tHover = -1; Build-Toast 0 }
    elseif ($tag -eq 'later') { $script:answered = $id; Close-Toast }
    elseif ($tag.StartsWith('m:')) { Send-Cmd 'ans' @{ aid = $id; ok = 0; min = [int]$tag.Substring(2) }; $script:answered = $id; Close-Toast }
}
function Tick-Toast {
    if (-not $script:toast -or -not $script:tBmp) { return }
    if ($script:tAnim -lt 7) { $script:tAnim++; Place-Toast (Toast-YOff) }
    elseif ($script:tk % 20 -eq 0) { Build-Toast $script:tStage }
}

# ---------------- sync file from the dashboard ----------------
function Read-Sync {
    try {
        if (-not (Test-Path -LiteralPath $script:SyncFile)) { return }
        $w = (Get-Item -LiteralPath $script:SyncFile).LastWriteTime
        if ($w -eq $script:syTime) { return }
        $script:syTime = $w
        $n = Get-Content -LiteralPath $script:SyncFile -Raw | ConvertFrom-Json
        $script:sy = $n
        $script:focusing = [bool]$n.focusing
        $list = @($n.evs) | Where-Object { $_ } | Sort-Object { [long]$_.id }
        $mx = 0L
        foreach ($e in $list) { if ([long]$e.id -gt $mx) { $mx = [long]$e.id } }
        if ($null -eq $script:lastEv) { $script:lastEv = $mx }
        else {
            foreach ($e in $list) { if ([long]$e.id -gt $script:lastEv) { Pet-Say ([string]$e.txt) 7 ([string]$e.pr); Event-React ([string]$e.txt) } }
            if ($mx -gt $script:lastEv) { $script:lastEv = $mx }
        }
        if ($n.ask) {
            $script:curAsk = $n.ask
            $aid = [string]$n.ask.id
            if ($aid -ne $script:answered -and $aid -ne $script:toastId -and -not $script:dashFocus) { Show-Toast }
        } else { $script:curAsk = $null; Close-Toast }
    } catch {}
}

# ---------------- behaviour detection (runs once a second) ----------------
function Analyze {
    $script:idleMs = [RioWindowApiV4]::IdleMs()
    $a = if ($script:idleMs -lt 1500) { 1.0 } else { 0.0 }
    $script:actv = $script:actv * 0.93 + 0.07 * $a
    $fs = $false; $fg = [IntPtr]::Zero
    try {
        $fg = [RioWindowApiV4]::GetForegroundWindow()
        if ($fg -ne [IntPtr]::Zero) {
            $cls = [RioWindowApiV4]::ClassOf($fg)
            if (@('Progman', 'WorkerW', 'Shell_TrayWnd') -notcontains $cls) {
                $bd = [Windows.Forms.Screen]::FromHandle($fg).Bounds
                $fs = [RioWindowApiV4]::IsFullscreen($fg, $bd.Left, $bd.Top, $bd.Right, $bd.Bottom)
            }
        }
    } catch {}
    $dh = Find-RioWindow
    $script:dashFocus = ($dh -ne [IntPtr]::Zero) -and ($fg -eq $dh) -and [RioWindowApiV4]::IsWindowVisible($dh)
    $script:fsHide = $fs
    # wellbeing: gentle break reminder after ~50 minutes of real activity (never during focus sessions / quiet mode)
    if ($script:idleMs -lt 60000 -and -not $script:focusing -and -not $fs) { $script:workSec++ }
    elseif ($script:idleMs -ge 180000 -or $script:focusing) { $script:workSec = 0 }
    if ($script:breaksOn -and $script:workSec -ge 3000 -and $script:petOn -and -not $script:sleepy -and (Get-Date) -ge $script:quietUntil) {
        $script:workSec = 0
        if ($script:lang -eq 'hi') { Pet-Say 'Lagbhag 50 minute se kaam kar rahe ho. Uth ke stretch karo, aankhon ko aaram do.' 12 'norm' 'BREAK LO' 'ok' }
        else { Pet-Say 'You have been working for about 50 minutes. Stand up, stretch and rest your eyes for a few minutes.' 12 'norm' 'TAKE A BREAK' 'ok' }
        Play-Event 'stretch'; Play-Sfx 'break'
    }
    if (-not $fs -and $script:petOn -and $script:sayWait.Count -gt 0) {
        $it = $script:sayWait[0]; $script:sayWait.RemoveAt(0); Show-Bubble ([string]$it[0]) ([int]$it[1])
    }
    if ($script:mode -eq 'peek' -and $script:idleMs -ge 75000 -and -not $script:focusing -and (Get-Date) -ge $script:quietUntil) { Go-Roam }
    elseif ($script:mode -eq 'roam' -and ($script:idleMs -lt 3000 -or $script:sleepy)) { Go-Peek }
    # a toast that was waiting for the dashboard to lose focus
    if ($script:curAsk -and -not $script:toast -and -not $script:dashFocus -and [string]$script:curAsk.id -ne $script:answered) { Show-Toast }
}

# ---------------- main pet tick (50 ms) ----------------
function Pet-Tick {
    $script:tk++
    if ($script:thwip -ge 0) { $script:thwip++; if ($script:thwip -gt 34) { $script:thwip = -1 } }
    if ($script:act -eq 'jump' -and $script:tk -gt $script:actEnd) { $script:act = 'idle' }
    if ($script:tk % 40 -eq 0) {
        Read-Sync
        $m = (Get-Date).TimeOfDay.TotalMinutes; $sl = 1365
        if ($script:sy -and $script:sy.sleep) { try { $sl = [TimeSpan]::Parse([string]$script:sy.sleep).TotalMinutes } catch {} }
        $was = $script:sleepy
        $script:sleepy = ($m -ge $sl) -or ($m -lt 300)
        $dayKey = (Get-Date).ToString('yyyyMMdd')
        if ($script:sleepy -and -not $was -and $m -ge $sl -and ($m - $sl) -lt 20 -and $script:sleepDay -ne $dayKey -and (Get-Date) -ge $script:quietUntil) {
            $script:sleepDay = $dayKey
            $bt = ([TimeSpan]::FromMinutes($sl)).ToString('hh\:mm')
            if ($script:lang -eq 'hi') { Pet-Say ('Sone ka time ho gaya (' + $bt + '). Kaam samet lo aur aaram karo.') 12 'norm' 'SONE KA TIME' 'imp' }
            else { Pet-Say ('It is bedtime (' + $bt + '). Wrap up and get some rest.') 12 'norm' 'WIND DOWN' 'imp' }
        }
    }
    if ($script:tk % 20 -eq 0) { Analyze }
    try { Tick-Bubble } catch {}
    try { Tick-Toast } catch {}
    if (-not $script:petOn) { return }
    if ($script:dragging) { if ($script:spr) { try { Decide-Anim; Advance-Anim } catch {} }; Render-Pet ([int]($script:pet.Left / $script:ds)) ([int]($script:pet.Top / $script:ds)); return }
    switch ($script:mode) {
        'peek' {
            $script:vis += ($script:visT - $script:vis) * 0.18
            $script:fx += ((Peek-TargetX) - $script:fx) * 0.25
            $script:fy += ($script:peekY - $script:fy) * 0.2
            if ($script:sleepy -and $script:spr) { $script:visT = 140.0 } elseif ($script:visT -gt 100 -and $script:visRest -eq 0) { $script:visT = $script:vis0 }
            if ($script:tk % 400 -eq 0 -and -not $script:sleepy -and $script:rnd.Next(0, 3) -eq 0) { $script:visT = 70.0; $script:visRest = $script:tk + 90 }
            if ($script:visRest -gt 0 -and $script:tk -gt $script:visRest) { $script:visT = $script:vis0; $script:visRest = 0 }
            if ($script:thwip -lt 0 -and $script:tk % 20 -eq 0 -and -not $script:sleepy -and -not $script:focusing -and $script:rnd.Next(0, 24) -eq 0) { $script:thwip = 0 }
        }
        'dash' {
            $script:vis = $script:vis0
            $tx = Peek-TargetX; $dx = $tx - $script:fx; $dy = $script:peekY - $script:fy
            $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
            if ($d -gt 18) { $script:fx += $dx / $d * 18; $script:fy += $dy / $d * 18 }
            else { $script:fx = $tx; $script:fy = $script:peekY; $script:mode = 'peek' }
        }
        'roam' {
            $dx = $script:gx - $script:fx; $dy = $script:gy - $script:fy
            $d = [Math]::Sqrt($dx * $dx + $dy * $dy)
            if ($d -gt 4) {
                if (-not $script:evActive) {
                    $step = [Math]::Min($d, $script:speed)
                    $script:fx += $dx / $d * $step; $script:fy += $dy / $d * $step
                }
            } else {
                if ($script:wait -le 0) {
                    $script:wait = $script:rnd.Next(60, 160)
                    $script:sit = ($script:spr -and $script:spr.anims.ContainsKey('sit') -and $script:rnd.Next(0, 4) -eq 0)
                    if ($script:sit) { $script:wait = $script:rnd.Next(140, 260) }
                } elseif (-not $script:evActive) {
                    $script:wait--
                    if ($script:wait -eq 1) {
                        if ($script:sit) { $script:sit = $false; Play-Event 'stand_up' }
                        Roam-Action
                    }
                }
            }
        }
        'tp' {
            $script:tpT++
            if ($script:tpWeb) {
                if ($script:tpPhase -eq 0) {
                    if ($script:tpT -eq 5) { Play-Sfx 'thwip' }
                    if ($script:tpT -ge 10) {
                        $script:tpPhase = 1; $script:tpT = 0
                        $script:tox = $script:fx; $script:toy = $script:fy
                        $dd = [Math]::Sqrt([Math]::Pow($script:tdx - $script:fx, 2) + [Math]::Pow($script:tdy - $script:fy, 2))
                        $script:tpZ = [int][Math]::Max(5, [Math]::Min(12, $dd / 70.0))
                        Play-Sfx 'zip'
                    }
                } elseif ($script:tpPhase -eq 1) {
                    $pz = [Math]::Min(1.0, $script:tpT / [double]$script:tpZ); $ez = $pz * $pz
                    $script:fx = $script:tox + ($script:tdx - $script:tox) * $ez
                    $script:fy = $script:toy + ($script:tdy - $script:toy) * $ez
                    if ($script:tpT -ge $script:tpZ) {
                        $script:fx = $script:tdx; $script:fy = $script:tdy
                        if ($script:tpFrom -eq 'peek') { $script:side = $script:tdSide; $script:peekY = $script:tdPeekY; $script:vis = $script:vis0; $script:visT = $script:vis0 }
                        else { $script:gx = $script:fx; $script:gy = $script:fy }
                        $script:tpPhase = 2; $script:tpT = 0
                        Play-Sfx 'land'
                        if ($script:tpQuip) { Pet-Say (Tp-Quip) 4 'norm' }
                    }
                } else {
                    if ($script:tpT -ge 4) { $script:mode = $script:tpFrom; $script:wait = 0; $script:scale = 1.0; $script:tpWeb = $false; $script:trail.Clear(); Play-Event 'land' }
                }
            } elseif ($script:tpPhase -eq 0) {
                $script:scale = [Math]::Max(0.0, 1.0 - $script:tpT / 12.0)
                if ($script:tpT -ge 12) {
                    Pick-Dest
                    $script:tpPhase = 1; $script:tpT = 0
                    if ($script:tpQuip) { Pet-Say (Tp-Quip) 4 'norm' }
                }
            } else {
                $script:scale = [Math]::Min(1.0, $script:tpT / 12.0)
                if ($script:tpT -ge 12) { $script:scale = 1.0; $script:mode = $script:tpFrom; $script:wait = 0 }
            }
        }
    }
    if ($script:mode -ne 'tp') { Near-Check } else { $script:nearTicks = 0 }
    if ($script:mode -eq 'tp' -and -not ($script:tpWeb -and $script:tpPhase -eq 1)) { $script:vx = 0.0; $script:vy = 0.0; $script:trail.Clear() }
    else {
        $script:vx = $script:vx * 0.6 + ($script:fx - $script:lastX) * 0.4
        $script:vy = $script:vy * 0.6 + ($script:fy - $script:lastY) * 0.4
        [void]$script:trail.Add(@($script:fx, $script:fy)); if ($script:trail.Count -gt 5) { $script:trail.RemoveAt(0) }
    }
    $script:lastX = $script:fx; $script:lastY = $script:fy
    if ($script:spr) { try { Decide-Anim; Advance-Anim } catch {} }
    $nx = [int]$script:fx; $ny = [int]$script:fy
    if ($script:bShown) { Place-Bubble }
    Render-Pet $nx $ny
}

# ---------------- sprite animation engine ----------------
# Characters live in pets\<id>\ : one horizontal strip PNG per animation + pet.json (made by tools\bake_pets.py
# from the Spiderman-Pet repo). If an animation does not exist for a character, the next one in its chain is used.
$script:AnimFallback = @{
    idle = @('idle'); walk = @('walk', 'run', 'idle'); run = @('run', 'walk', 'idle')
    jump = @('jump', 'run', 'walk'); fall = @('fall', 'idle'); land = @('land', 'idle')
    perch = @('perch', 'idle'); hang = @('hang', 'perch', 'idle'); swing = @('swing', 'run', 'walk')
    sleep = @('sleep', 'sit', 'idle'); wake_up = @('wake_up', 'idle'); sit = @('sit', 'idle'); stand_up = @('stand_up', 'idle')
    wave = @('wave', 'interact', 'idle'); interact = @('interact', 'wave', 'idle')
    dance = @('dance', 'celebrate', 'wave', 'idle'); celebrate = @('celebrate', 'dance', 'wave', 'idle')
    dragged = @('dragged', 'hang', 'idle')
    thwip = @('thwip', 'wave', 'idle'); point = @('point', 'wave', 'idle'); stretch = @('stretch', 'wave', 'idle')
    think = @('think', 'idle'); cheer = @('cheer', 'celebrate', 'dance', 'wave', 'idle')
}
function Unload-Sprites {
    $s = $script:spr
    if ($s) { foreach ($k in @($s.strips.Keys)) { try { if ($s.strips[$k]) { $s.strips[$k].Dispose() } } catch {} } }
    $script:spr = $null; $script:aName = ''; $script:aT = 0.0; $script:aDone = $false
    $script:evActive = $false; $script:evNext = ''; $script:sit = $false; $script:wasSleep = $false
}
function Get-Strip([string]$n) {
    $s = $script:spr; if (-not $s) { return $null }
    if ($s.strips.ContainsKey($n)) { return $s.strips[$n] }
    $f = Join-Path $s.dir ($n + '.png'); $bm = $null
    if (Test-Path -LiteralPath $f) { try { $bm = Load-Png $f } catch { $bm = $null } }
    $s.strips[$n] = $bm
    return $bm
}
function Load-SpriteSet([string]$name) {
    Unload-Sprites
    $dir = Join-Path (Join-Path $PSScriptRoot 'pets') $name
    $mf = Join-Path $dir 'pet.json'
    if (-not (Test-Path -LiteralPath $mf)) { return $false }
    try {
        $m = Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json
        $anims = @{}
        foreach ($p in $m.anims.PSObject.Properties) {
            $an = @{ n = [int]$p.Value.n; fps = [double]$p.Value.fps; loop = [bool]$p.Value.loop }
            if ($p.Value.hands) { $hl = @(); foreach ($q in $p.Value.hands) { $hl += , @([double]$q[0], [double]$q[1]) }; $an['hands'] = $hl }
            $anims[[string]$p.Name] = $an
        }
        if (-not $anims.ContainsKey('idle')) { return $false }
        $script:spr = @{ dir = $dir; fw = [int]$m.fw; fh = [int]$m.fh; ax = [double]$m.ax; ay = [double]$m.ay; anims = $anims; strips = @{} }
        foreach ($n in 'idle', 'perch', 'walk', 'run', 'sit', 'sleep') { if ($anims.ContainsKey($n)) { [void](Get-Strip $n) } }
        return $true
    } catch { $script:spr = $null; return $false }
}
function Resolve-Anim([string]$want) {
    $chain = $script:AnimFallback[$want]
    if (-not $chain) { $chain = @($want, 'idle') }
    foreach ($n in $chain) { if ($script:spr.anims.ContainsKey($n)) { return $n } }
    return 'idle'
}
function Play-Anim([string]$want) {
    if (-not $script:spr) { return }
    $n = Resolve-Anim $want
    if ($n -eq $script:aName -and $script:spr.anims[$n].loop) { return }
    $script:aName = $n; $script:aT = 0.0; $script:aDone = $false
}
# A one-shot (wave, celebrate, jump ...). Movement pauses while it plays. 'next' is a second one-shot played right after.
function Play-Fx([string]$name, [int]$ticks) {
    if (-not $script:spr) { return }
    Play-Event 'idle'
    $script:evEndTk = $script:tk + $ticks
    $script:fxName = $name; $script:fxT0 = $script:tk; $script:fxDur = [Math]::Max(1, $ticks)
}
function Play-Event([string]$want, [string]$next = '') {
    if (-not $script:spr) { return }
    $script:aName = ''
    Play-Anim $want
    $script:evActive = $true; $script:evNext = $next; $script:evEndTk = $script:tk + 40
}
function Advance-Anim {
    $s = $script:spr; if (-not $s -or -not $script:aName) { return }
    $a = $s.anims[$script:aName]
    $script:aT += $a.fps * 0.05 * $script:aSpd
    if ($a.loop) { if ($script:aT -ge $a.n) { $script:aT = $script:aT % $a.n } }
    elseif ($script:aT -ge ($a.n - 0.001)) { $script:aT = [double]($a.n - 1); $script:aDone = $true }
}
# Chooses the animation from what the pet is doing (runs every tick before drawing).
function Decide-Anim {
    if (-not $script:spr) { return }
    $mode = $script:mode
    if ($script:dragging) { $script:evActive = $false; $script:fxName = ''; Play-Anim 'dragged'; return }
    if ($mode -eq 'tp') { return }
    if ($mode -eq 'dash') { $script:evActive = $false; $script:fxName = ''; Play-Anim 'run'; return }
    if ($script:evActive) {
        $a = $script:spr.anims[$script:aName]
        if ((-not $a.loop -and $script:aDone) -or ($a.loop -and $script:tk -gt $script:evEndTk)) {
            if ($script:evNext) { $nx = $script:evNext; Play-Event $nx ''; if ($nx -eq 'land') { Play-Sfx 'land' }; return }
            $script:evActive = $false; $script:fxName = ''
        } else { return }
    }
    $spd = [Math]::Sqrt($script:vx * $script:vx + $script:vy * $script:vy)
    if ($script:sleepy -and ($mode -eq 'peek' -or $spd -lt 0.5)) { if (-not $script:wasSleep) { Play-Sfx 'sleep' }; $script:wasSleep = $true; Play-Anim 'sleep'; return }
    if ($script:wasSleep) { $script:wasSleep = $false; Play-Sfx 'wake'; Play-Event 'wake_up'; return }
    if ($mode -eq 'roam') {
        if ($spd -gt 1.0) { if ($spd -gt 6.5) { Play-Anim 'run' } else { Play-Anim 'walk' }; return }
        if ($script:toast) { Play-Anim 'think'; return }
        if ($script:sit) { Play-Anim 'sit' } else { Play-Anim 'idle' }
        return
    }
    if ($script:toast) { Play-Anim 'think'; return }
    if ($script:focusing) { Play-Anim 'sit' } else { Play-Anim 'perch' }
}
# Draw one frame of an animation. (tx,ty) = body centre in window coordinates; feet are 90px below it.
function Draw-Frame($g, [string]$name, [double]$frame, [double]$tx, [double]$ty, [double]$rot, [double]$sx, [double]$sy, [double]$alpha, [double]$bright, [double]$pvOff = 0.0) {
    $s = $script:spr; $bm = Get-Strip $name; if (-not $bm) { return }
    $fw = [int]$s.fw; $fh = [int]$s.fh; $n = [int]$s.anims[$name].n
    $fi = [int][Math]::Floor($frame); if ($fi -lt 0) { $fi = 0 }; if ($fi -ge $n) { $fi = $n - 1 }
    Reset-Tf $g
    $g.TranslateTransform([single]$tx, [single]$ty)
    if ($rot -ne 0) { $g.RotateTransform([single]$rot) }
    $g.ScaleTransform([single]$sx, [single]$sy)
    $dest = [Drawing.Rectangle]::new([int](-$s.ax), [int](-($s.ay - 90.0) - $pvOff), $fw, $fh)
    if ($alpha -ge 0.99 -and [Math]::Abs($bright - 1.0) -lt 0.01) {
        $g.DrawImage($bm, $dest, ($fi * $fw), 0, $fw, $fh, [Drawing.GraphicsUnit]::Pixel)
    } else {
        $ia = New-Object Drawing.Imaging.ImageAttributes
        $cm = New-Object Drawing.Imaging.ColorMatrix
        $a = [single][Math]::Max(0.0, [Math]::Min(1.0, $alpha)); $b = [single]$bright
        $cm.Matrix00 = $b; $cm.Matrix11 = $b; $cm.Matrix22 = $b; $cm.Matrix33 = $a; $cm.Matrix44 = [single]1
        $ia.SetColorMatrix($cm)
        $g.DrawImage($bm, $dest, ($fi * $fw), 0, $fw, $fh, [Drawing.GraphicsUnit]::Pixel, $ia)
        $ia.Dispose()
    }
}
function Draw-PetSprite($g) {
    $t = $script:tk; $mode = $script:mode
    $spd = [Math]::Sqrt($script:vx * $script:vx + $script:vy * $script:vy)
    $web = ($mode -eq 'tp' -and $script:tpWeb)
    if ($spd -gt 1.2 -and $mode -ne 'tp') { $script:face = if ($script:vx -ge 0) { 1 } else { -1 } }
    $peekFace = ($mode -eq 'peek') -or ($mode -eq 'tp' -and $script:tpFrom -eq 'peek')
    if ($web) { $fl = [double]$script:face }
    elseif ($peekFace) { $fl = if ($script:side -eq 'L') { 1.0 } else { -1.0 } }
    else { $fl = [double]$script:face }
    if (-not $script:aName) { Play-Anim 'idle' }
    $aname = $script:aName; $aframe = $script:aT
    if ($web) { $aname = 'thwip'; if ($script:tpPhase -eq 0) { $aframe = [Math]::Min(7.0, $script:tpT * 0.9) } else { $aframe = 7.0 } }
    $jmp = 0.0; $rot = 0.0
    if ($script:act -eq 'jump') {
        $ph = 1.0 - ([double]($script:actEnd - $t) / 25.0); $ph = [Math]::Max(0.0, [Math]::Min(1.0, $ph))
        $jmp = [Math]::Sin($ph * [Math]::PI) * 30
    }
    $fxn = $script:fxName
    if ($fxn -eq 'flip') {
        $fp = [Math]::Max(0.0, [Math]::Min(1.0, ($t - $script:fxT0) / [double]$script:fxDur))
        $jmp = [Math]::Sin($fp * [Math]::PI) * 58; $rot = $fp * 360.0 * $fl
    }
    $sc = 1.0 + 0.04 * $script:hov; $alpha = 1.0; $bright = 1.0
    if ($mode -eq 'tp' -and -not $web) {
        $sc = $sc * [Math]::Max(0.02, $script:scale); $alpha = [Math]::Min(1.0, $script:scale * 1.2)
        $rot = (1.0 - $script:scale) * 300.0 * $fl
    }
    if ($script:sleepy) { $bright = 0.86 }
    $cx = 110.0; $cy = 132.0 - $jmp
    # soft ground shadow while roaming
    if ($mode -eq 'roam' -or ($mode -eq 'tp' -and $script:tpFrom -eq 'roam')) {
        $k = [Math]::Max(0.35, 1.0 - $jmp / 90.0) * [Math]::Max(0.0, $script:scale)
        $shw = 100.0 * $k; $shh = 14.0 * $k
        Reset-Tf $g
        if ($shw -gt 6 -and $shh -gt 2) {
            $sp = New-Object Drawing.Drawing2D.GraphicsPath
            $sp.AddEllipse([single](110 - $shw / 2), [single](222 - $shh / 2), [single]$shw, [single]$shh)
            $sbr = New-Object Drawing.Drawing2D.PathGradientBrush $sp
            $sbr.CenterColor = [Drawing.Color]::FromArgb(120, 0, 0, 0)
            $sbr.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 0, 0, 0))
            $g.FillPath($sbr, $sp)
            $sbr.Dispose(); $sp.Dispose()
        }
    }
    # soft cyan aura while a focus session is running
    if ($script:focusing -and $mode -ne 'tp') {
        Reset-Tf $g
        $gp = New-Object Drawing.Drawing2D.GraphicsPath
        $gp.AddEllipse([single]14, [single]($cy - 100), [single]192, [single]200)
        $pb = New-Object Drawing.Drawing2D.PathGradientBrush $gp
        $pb.CenterColor = [Drawing.Color]::FromArgb([int](46 + 24 * [Math]::Sin($t / 10.0)), 34, 229, 255)
        $pb.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 34, 229, 255))
        $g.FillPath($pb, $gp)
        $pb.Dispose(); $gp.Dispose()
    }
    # speed ghosts while dashing / zipping along the web
    if (($spd -gt 7) -and ($mode -ne 'tp' -or $web) -and $script:trail.Count -gt 1) {
        for ($i = 0; $i -lt $script:trail.Count - 1; $i++) {
            $o = $script:trail[$i]
            Draw-Frame $g $aname $aframe ($cx + $o[0] - $script:fx) ($cy + $o[1] - $script:fy) $rot ($fl * $sc) $sc ((0.07 + 0.06 * $i) * $alpha) $bright
        }
    }
    # the web strand of the web-shot teleport (behind the character so the hand overlaps the thread)
    if ($web) {
        $hl = $script:spr.anims['thwip'].hands; $hix = [int][Math]::Min($hl.Count - 1, [Math]::Floor($aframe)); $hp = $hl[$hix]
        $hx = $cx + $fl * $sc * ($hp[0] - $script:spr.ax); $hy = $cy + $sc * ($hp[1] - $script:spr.ay + 90.0)
        $vx2 = $script:tdx - $script:fx; $vy2 = $script:tdy - $script:fy
        $dl = [Math]::Sqrt($vx2 * $vx2 + $vy2 * $vy2); if ($dl -lt 1.0) { $dl = 1.0 }
        $ux = $vx2 / $dl; $uy = $vy2 / $dl; $len = 0.0
        if ($script:tpPhase -eq 0) { $len = 450.0 * [Math]::Max(0.0, [Math]::Min(1.0, ($script:tpT - 4) / 5.0)) }
        elseif ($script:tpPhase -eq 1) { $len = $dl + 30.0 }
        if ($len -gt 2) { Draw-Web $g $hx $hy ($hx + $ux * $len) ($hy + $uy * $len) 0.0 240 }
        if ($script:tpPhase -eq 0 -and $script:tpT -ge 5 -and $script:tpT -le 8) {
            Reset-Tf $g
            $spl = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(230, 248, 250, 255)), 1.6
            foreach ($q in 0..5) { $an = $q * [Math]::PI / 3 + 0.2; $rr = 5 + ($script:tpT - 5) * 4; $g.DrawLine($spl, [single]($hx + [Math]::Cos($an) * 3), [single]($hy + [Math]::Sin($an) * 3), [single]($hx + [Math]::Cos($an) * $rr), [single]($hy + [Math]::Sin($an) * $rr)) }
            $spl.Dispose()
        }
    }
    if ($fxn -eq 'pushup') {
        $pfr = $t - $script:fxT0
        $prot = $fl * (76.0 + 9.0 * [Math]::Sin($pfr / 3.0))
        Draw-Frame $g $aname $aframe (110.0 - 78.0 * $fl) 222.0 $prot ($fl * $sc) $sc $alpha $bright 90.0
        if (($pfr % 15) -eq 0) { Play-Sfx 'push' }
    } else {
        Draw-Frame $g $aname $aframe $cx $cy $rot ($fl * $sc) $sc $alpha $bright
    }
    Reset-Tf $g
    if ($script:aName -eq 'sleep') {
        $zx = $cx - 50 * $fl
        $zy = $cy - 36 - ([Math]::Abs([Math]::Sin($t / 20.0)) * 10)
        $g.DrawString('z Z', $script:fnt, [Drawing.Brushes]::Black, [single]($zx + 1), [single]($zy + 1))
        $g.DrawString('z Z', $script:fnt, [Drawing.Brushes]::White, [single]$zx, [single]$zy)
    }
    if ($mode -eq 'tp' -and -not $web) {
        $r = 6 + $script:tpT * 4.5
        $al = [int][Math]::Max(0, 230 - $script:tpT * 17)
        $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb($al, 34, 229, 255)), 3
        $g.DrawEllipse($pen, [single]($cx - $r), [single](132 - $r), [single](2 * $r), [single](2 * $r))
        foreach ($i in 0..7) {
            $an = $i * [Math]::PI / 4 + $script:tpT * 0.2
            $g.DrawLine($pen, [single]($cx + [Math]::Cos($an) * $r * 0.5), [single](132 + [Math]::Sin($an) * $r * 0.5), [single]($cx + [Math]::Cos($an) * $r), [single](132 + [Math]::Sin($an) * $r))
        }
        $pen.Dispose()
    }
}

# ---------------- drawing ----------------
function Draw-Pet($g) {
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $t = $script:tk
    $moving = ($script:mode -eq 'roam' -or $script:mode -eq 'dash')
    if ($moving) { $bob = [Math]::Sin($t / 2.5) * 4 } else { $bob = [Math]::Sin($t / 7.0) * 2.5 }
    $jmp = 0
    if ($script:act -eq 'jump') { $jmp = [Math]::Abs([Math]::Sin(($script:actEnd - $t) / 25.0 * [Math]::PI * 2)) * 28 }
    $cx = 110; $cy = 132 + $bob - $jmp
    $peekM = Test-PeekLike
    $flip = ($peekM -and $script:side -eq 'L')
    $sc = [Math]::Max(0.02, $script:scale)
    $sx = if ($flip) { -$sc } else { $sc }
    $bat = ($script:skin -eq 'bat')
    $ol = $script:pOl; $thin = $script:pThin; $blk = $script:bBlk; $white = [Drawing.Brushes]::White
    $bBody = $script:br['body']; $bBelly = $script:br['belly']; $bSkin = $script:br['skin']; $bAcc = $script:br['acc']

    Reset-Tf $g
    $g.TranslateTransform($cx, 132)
    $g.ScaleTransform($sx, $sc)
    $g.TranslateTransform(-$cx, -132)

    $pmRun = ($script:sy -and $script:sy.pm -and $script:sy.pm.run -and $script:sy.pm.mode -eq 'focus')
    $happy = ($script:act -eq 'jump')
    $eh = 1.0
    if ($script:sleepy) { $eh = 0.12 }
    elseif ($happy) { $eh = 0.6 }
    elseif (($t % 110) -lt 4) { $eh = 0.12 }
    elseif ($pmRun) { $eh = 0.8 }

    # cape / ears (behind the head)
    if ($bat) {
        $sw = [Math]::Sin($t / 9.0) * 4
        $cp = [Drawing.PointF[]]@(
            [Drawing.PointF]::new($cx - 50, $cy - 4), [Drawing.PointF]::new($cx - 66 + $sw, $cy + 60), [Drawing.PointF]::new($cx - 20, $cy + 52),
            [Drawing.PointF]::new($cx + 20, $cy + 52), [Drawing.PointF]::new($cx + 66 + $sw, $cy + 60), [Drawing.PointF]::new($cx + 50, $cy - 4))
        $g.FillPolygon($script:br['cape'], $cp); $g.DrawPolygon($ol, $cp)
        foreach ($s in @(-1, 1)) {
            $ep = [Drawing.PointF[]]@([Drawing.PointF]::new($cx + $s * 10, $cy - 26), [Drawing.PointF]::new($cx + $s * 30, $cy - 86), [Drawing.PointF]::new($cx + $s * 42, $cy - 20))
            $g.FillPolygon($bBody, $ep); $g.DrawPolygon($ol, $ep)
        }
    }
    # torso + emblem
    $g.FillEllipse($bBelly, $cx - 27, $cy + 28, 54, 30); $g.DrawEllipse($ol, $cx - 27, $cy + 28, 54, 30)
    if ($bat) {
        $g.FillEllipse($bAcc, $cx - 13, $cy + 34, 26, 15)
        $bp = [Drawing.PointF[]]@([Drawing.PointF]::new($cx - 10, $cy + 39), [Drawing.PointF]::new($cx - 4, $cy + 37), [Drawing.PointF]::new($cx, $cy + 40), [Drawing.PointF]::new($cx + 4, $cy + 37), [Drawing.PointF]::new($cx + 10, $cy + 39), [Drawing.PointF]::new($cx + 4, $cy + 45), [Drawing.PointF]::new($cx, $cy + 42), [Drawing.PointF]::new($cx - 4, $cy + 45))
        $g.FillPolygon($blk, $bp)
    } else {
        $g.FillEllipse($blk, $cx - 4, $cy + 37, 8, 12)
        foreach ($s in @(-1, 1)) { foreach ($i in 0..2) { $g.DrawLine($thin, $cx + $s * 3, $cy + 40 + $i * 3, $cx + $s * (11 + $i * 2), $cy + 37 + $i * 5) } }
    }
    # feet
    $g.FillEllipse($bBody, $cx - 30, $cy + 50, 24, 12); $g.DrawEllipse($ol, $cx - 30, $cy + 50, 24, 12)
    $g.FillEllipse($bBody, $cx + 6, $cy + 50, 24, 12); $g.DrawEllipse($ol, $cx + 6, $cy + 50, 24, 12)
    # head
    $g.FillEllipse($bBody, $cx - 46, $cy - 36, 92, 80)
    $hp = New-Object Drawing.Drawing2D.GraphicsPath
    $hp.AddEllipse($cx - 46, $cy - 36, 92, 80)
    $g.SetClip($hp)
    if ($bat) { $g.FillEllipse($bSkin, $cx - 38, $cy + 6, 76, 50) }
    else {
        $web = $script:pWeb
        $g.DrawLine($web, $cx, $cy - 36, $cx, $cy + 44)
        foreach ($ex in @(-44, -30, 30, 44)) { $g.DrawLine($web, $cx, $cy - 36, $cx + $ex, $cy + 40) }
        foreach ($r in @(22, 40, 58)) { $g.DrawArc($web, $cx - $r, $cy - 36 - $r, 2 * $r, 2 * $r, 40, 100) }
    }
    $g.ResetClip(); $hp.Dispose()
    $g.DrawEllipse($ol, $cx - 46, $cy - 36, 92, 80)
    # eyes follow the mouse
    $cur = Get-Cur
    $lx = [Math]::Max(-4, [Math]::Min(4, ($cur.X - ($script:fx + 110)) / 70.0))
    if ($flip) { $lx = -$lx }
    if ($bat) { $P = @(@(36, -14), @(7, -5), @(9, 5), @(33, -3)); $y0 = -4 }
    else { $P = @(@(42, -10), @(8, -4), @(12, 16), @(38, 8)); $y0 = 3 }
    foreach ($s in @(-1, 1)) {
        $pl = New-Object 'System.Collections.Generic.List[Drawing.PointF]'
        foreach ($q in $P) { $pl.Add([Drawing.PointF]::new($cx + $s * $q[0] + $lx * 0.7, $cy + $y0 + ($q[1] - $y0) * $eh)) }
        $arr = $pl.ToArray()
        $g.FillPolygon($white, $arr); $g.DrawPolygon($ol, $arr)
    }
    if ($bat) {
        if ($script:bShown) { $g.FillEllipse($blk, $cx - 5, $cy + 18, 10, 8) } else { $g.DrawArc($thin, $cx - 9, $cy + 12, 18, 9, 20, 140) }
    }
    # hand gripping the screen edge while peeking
    if ($peekM -and $script:mode -ne 'tp') {
        $xe = 64 + $script:vis
        foreach ($i in 0..2) {
            $fyy = $cy - 8 + $i * 12
            $g.FillEllipse($script:br['glove'], $xe - 38, $fyy, 46, 11); $g.DrawEllipse($ol, $xe - 38, $fyy, 46, 11)
        }
    }
    # overlays (not scaled / flipped)
    Reset-Tf $g
    if ($script:sleepy) {
        $zx = if ($flip) { $cx + 30 } else { $cx - 62 }
        $g.DrawString('z Z', $script:fnt, $blk, $zx, $cy - 78)
    }
    if ($script:mode -eq 'tp') {
        $r = 6 + $script:tpT * 4.5
        $al = [int][Math]::Max(0, 230 - $script:tpT * 17)
        $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb($al, $script:accRGB[0], $script:accRGB[1], $script:accRGB[2])), 3
        $g.DrawEllipse($pen, $cx - $r, 132 - $r, 2 * $r, 2 * $r)
        foreach ($i in 0..7) {
            $an = $i * [Math]::PI / 4 + $script:tpT * 0.2
            $g.DrawLine($pen, $cx + [Math]::Cos($an) * $r * 0.5, 132 + [Math]::Sin($an) * $r * 0.5, $cx + [Math]::Cos($an) * $r, 132 + [Math]::Sin($an) * $r)
        }
        $pen.Dispose()
    }
}

# ---------------- real-image drawing ----------------
# Draw one pose bitmap centred on (tx,ty) with rotation, scale/flip, opacity and brightness.
function Draw-Pose($g, [string]$pose, [double]$tx, [double]$ty, [double]$rot, [double]$sx, [double]$sy, [double]$alpha, [double]$bright) {
    $bm = $script:img[$pose]; if (-not $bm) { return }
    $ps = [double]$script:img.scale
    $w = $bm.Width * $ps; $h = $bm.Height * $ps
    Reset-Tf $g
    $g.TranslateTransform([single]$tx, [single]$ty)
    if ($rot -ne 0) { $g.RotateTransform([single]$rot) }
    $g.ScaleTransform([single]$sx, [single]$sy)
    $ia = New-Object Drawing.Imaging.ImageAttributes
    $cm = New-Object Drawing.Imaging.ColorMatrix
    $a = [single][Math]::Max(0.0, [Math]::Min(1.0, $alpha)); $b = [single]$bright
    $cm.Matrix00 = $b; $cm.Matrix11 = $b; $cm.Matrix22 = $b; $cm.Matrix33 = $a; $cm.Matrix44 = [single]1
    $ia.SetColorMatrix($cm)
    $dest = [Drawing.Rectangle]::new([int](-$w / 2), [int](-$h / 2), [int]$w, [int]$h)
    $g.DrawImage($bm, $dest, 0, 0, $bm.Width, $bm.Height, [Drawing.GraphicsUnit]::Pixel, $ia)
    $ia.Dispose()
}
# Where a point of a pose (fractions hx,hy of the image) ends up in window coordinates.
function Pose-Pt([string]$pose, [double]$hx, [double]$hy, [double]$tx, [double]$ty, [double]$rot, [double]$sx, [double]$sy) {
    $bm = $script:img[$pose]; $ps = [double]$script:img.scale
    $lx = ($hx - 0.5) * $bm.Width * $ps * $sx; $ly = ($hy - 0.5) * $bm.Height * $ps * $sy
    $r = $rot * [Math]::PI / 180.0
    return @(($tx + $lx * [Math]::Cos($r) - $ly * [Math]::Sin($r)), ($ty + $lx * [Math]::Sin($r) + $ly * [Math]::Cos($r)))
}
# A web strand that fades out towards its far end.
function Draw-Web($g, [double]$x1, [double]$y1, [double]$x2, [double]$y2, [double]$sag, [int]$alpha) {
    if ($alpha -le 3) { return }
    if ((($x2 - $x1) * ($x2 - $x1) + ($y2 - $y1) * ($y2 - $y1)) -lt 16) { return }
    Reset-Tf $g
    $p1 = [Drawing.PointF]::new($x1, $y1); $p2 = [Drawing.PointF]::new($x2, $y2)
    $pm = [Drawing.PointF]::new(($x1 + $x2) / 2 + $sag, ($y1 + $y2) / 2)
    $pts = [Drawing.PointF[]]@($p1, $pm, $p2)
    $lb1 = New-Object Drawing.Drawing2D.LinearGradientBrush $p1, $p2, ([Drawing.Color]::FromArgb([int]($alpha * 0.4), 10, 16, 26)), ([Drawing.Color]::FromArgb(0, 10, 16, 26))
    $lb2 = New-Object Drawing.Drawing2D.LinearGradientBrush $p1, $p2, ([Drawing.Color]::FromArgb($alpha, 248, 250, 255)), ([Drawing.Color]::FromArgb(0, 248, 250, 255))
    $pn1 = New-Object Drawing.Pen $lb1, 3.6
    $pn2 = New-Object Drawing.Pen $lb2, 1.7
    $g.DrawCurve($pn1, $pts, 0.5); $g.DrawCurve($pn2, $pts, 0.5)
    $pn1.Dispose(); $pn2.Dispose(); $lb1.Dispose(); $lb2.Dispose()
}

function Draw-PetImg($g) {
    $t = $script:tk; $im = $script:img; $mode = $script:mode
    $spd = [Math]::Sqrt($script:vx * $script:vx + $script:vy * $script:vy)
    $moving = (($mode -eq 'roam') -or ($mode -eq 'dash')) -and ($spd -gt 1.0)
    $jumping = ($script:act -eq 'jump')
    $sleepy = $script:sleepy
    $peekFace = ($mode -eq 'peek') -or ($mode -eq 'tp' -and $script:tpFrom -eq 'peek')
    if ($spd -gt 1.2 -and $mode -ne 'tp') { $script:face = if ($script:vx -ge 0) { 1 } else { -1 } }
    if ($peekFace) { $fl = if ($script:side -eq 'L') { -1.0 } else { 1.0 } } else { $fl = [double]$script:face }

    # which pose: swing while moving / jumping, crouch when settled (smooth crossfade + little pop)
    $want = if ($jumping -or $moving) { 'A' } else { 'B' }
    if ($mode -eq 'tp') { $want = $script:poseTo }
    if ($want -ne $script:poseTo) {
        if ($script:poseMix -ge 0.5) { $script:poseFrom = $script:poseTo }
        $script:poseTo = $want; $script:poseMix = 0.0; $script:pulse = 1.0
    }
    if ($script:poseMix -lt 1.0) { $script:poseMix = [Math]::Min(1.0, $script:poseMix + 0.25) }
    $script:pulse = $script:pulse * 0.84
    $mix = $script:poseMix
    $fromA = 0.0; $toA = 0.0
    if ($script:poseFrom -eq 'A') { $fromA = 1.0 }
    if ($script:poseTo -eq 'A') { $toA = 1.0 }
    $wA = $fromA * (1.0 - $mix) + $toA * $mix

    # procedural motion: breathing, bob, squash & stretch, tilt, flips
    $br = [Math]::Sin($t / 8.0)
    if ($moving) { $bob = [Math]::Sin($t / 2.5) * 5 } elseif ($sleepy) { $bob = [Math]::Sin($t / 14.0) * 2 } else { $bob = [Math]::Sin($t / 8.0) * 2.5 }
    $sqy = 1.0 + $br * 0.014; $sqx = 1.0 - $br * 0.008
    $jmp = 0.0; $rot = 0.0
    if ($jumping) {
        $ph = 1.0 - ([double]($script:actEnd - $t) / 25.0); $ph = [Math]::Max(0.0, [Math]::Min(1.0, $ph))
        $jmp = [Math]::Sin($ph * [Math]::PI) * 36
        $sqy = 1.0 + 0.13 * [Math]::Cos($ph * [Math]::PI); $sqx = 1.0 / $sqy
        if ($script:jflip) { $rot = $ph * 360.0 * $fl }
    } elseif ($moving) {
        $rot = [Math]::Max(-24, [Math]::Min(24, $script:vx * 1.3)) + [Math]::Sin($t / 3.0) * 4
        $sqy = 1.0 + [Math]::Sin($t / 2.5) * 0.03; $sqx = 1.0 / $sqy
    } else {
        $cur = Get-Cur
        $lean = [Math]::Max(-7, [Math]::Min(7, ($cur.X - ($script:fx + 110)) / 60.0))
        $rot = $lean + [Math]::Sin($t / 26.0) * 1.2
    }
    $sc = 1.0 + 0.12 * $script:pulse + 0.045 * $script:hov; $alpha = 1.0; $bright = 1.0
    if ($mode -eq 'tp') {
        $sc = $sc * [Math]::Max(0.02, $script:scale); $alpha = [Math]::Min(1.0, $script:scale * 1.2)
        $rot = $rot + (1.0 - $script:scale) * 300.0 * $fl
    }
    if ($sleepy) { $bright = 0.72; $alpha = $alpha * 0.92 }
    $cx = 110.0; $cy = 132.0 + $bob - $jmp
    $sx = $fl * $sc * $sqx; $sy = $sc * $sqy

    # ground shadow while roaming
    if ($mode -eq 'roam' -or ($mode -eq 'tp' -and $script:tpFrom -eq 'roam')) {
        $k = [Math]::Max(0.35, 1.0 - $jmp / 90.0) * [Math]::Max(0.0, $script:scale)
        $shw = 96.0 * $k; $shh = 14.0 * $k
        Reset-Tf $g
        if ($shw -gt 6 -and $shh -gt 2) {
            $sp = New-Object Drawing.Drawing2D.GraphicsPath
            $sp.AddEllipse([single](110 - $shw / 2), [single](214 - $shh / 2), [single]$shw, [single]$shh)
            $sbr = New-Object Drawing.Drawing2D.PathGradientBrush $sp
            $sbr.CenterColor = [Drawing.Color]::FromArgb(120, 0, 0, 0)
            $sbr.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 0, 0, 0))
            $g.FillPath($sbr, $sp)
            $sbr.Dispose(); $sp.Dispose()
        }
    }
    # soft cyan aura while a focus session is running
    if ($script:focusing -and $mode -ne 'tp') {
        Reset-Tf $g
        $gp = New-Object Drawing.Drawing2D.GraphicsPath
        $gp.AddEllipse([single]18, [single]($cy - 88), [single]184, [single]176)
        $pb = New-Object Drawing.Drawing2D.PathGradientBrush $gp
        $pb.CenterColor = [Drawing.Color]::FromArgb([int](48 + 26 * [Math]::Sin($t / 10.0)), 34, 229, 255)
        $pb.SurroundColors = [Drawing.Color[]]@([Drawing.Color]::FromArgb(0, 34, 229, 255))
        $g.FillPath($pb, $gp)
        $pb.Dispose(); $gp.Dispose()
    }
    # speed ghosts while dashing / roaming fast
    if ($spd -gt 7 -and $mode -ne 'tp' -and $script:trail.Count -gt 1) {
        for ($i = 0; $i -lt $script:trail.Count - 1; $i++) {
            $o = $script:trail[$i]
            Draw-Pose $g $script:poseTo ($cx + $o[0] - $script:fx) ($cy + $o[1] - $script:fy) $rot $sx $sy ((0.06 + 0.05 * $i) * $alpha) $bright
        }
    }
    # web strands (drawn behind the character so the hand overlaps the thread)
    if ($mode -ne 'tp') {
        if ($wA -gt 0.3 -and ($moving -or $jumping)) {
            $hp = Pose-Pt 'A' ($im.aHand[0]) ($im.aHand[1]) $cx $cy $rot $sx $sy
            $swy = [Math]::Sin($t / 5.0) * 10
            $ax = [Math]::Max(0.0, [Math]::Min([double]$script:PW, $hp[0] - $script:vx * 2.0 + $swy * 0.5))
            Draw-Web $g ($hp[0]) ($hp[1]) $ax (-4) $swy ([int](235 * $wA))
        } elseif ($script:thwip -ge 0 -and $wA -lt 0.5) {
            $sp = Pose-Pt 'B' ($im.bShoot[0]) ($im.bShoot[1]) $cx $cy $rot $sx $sy
            $pr = [Math]::Min(1.0, $script:thwip / 6.0)
            if ($script:thwip -le 18) { $wl = 235 } else { $wl = [int](235 * [Math]::Max(0.0, 1.0 - ($script:thwip - 18) / 16.0)) }
            $dirx = -$fl
            $ex = $sp[0] + $dirx * (20 + 80 * $pr); $ey = $sp[1] - (8 + 42 * $pr)
            Draw-Web $g ($sp[0]) ($sp[1]) $ex $ey (-6 * $fl) $wl
            if ($pr -ge 1.0 -and $wl -gt 40) {
                Reset-Tf $g
                $spl = New-Object Drawing.Pen ([Drawing.Color]::FromArgb($wl, 248, 250, 255)), 1.5
                foreach ($q in 0..4) { $an = $q * [Math]::PI * 2 / 5 + 0.3; $g.DrawLine($spl, [single]$ex, [single]$ey, [single]($ex + [Math]::Cos($an) * 7), [single]($ey + [Math]::Sin($an) * 7)) }
                $spl.Dispose()
            }
        }
    }
    # the character itself
    if ($script:poseFrom -ne $script:poseTo -and $mix -lt 1.0) {
        Draw-Pose $g $script:poseFrom $cx $cy $rot $sx $sy $alpha $bright
        Draw-Pose $g $script:poseTo $cx $cy $rot $sx $sy ($alpha * $mix) $bright
    } else {
        Draw-Pose $g $script:poseTo $cx $cy $rot $sx $sy $alpha $bright
    }
    # overlays (not scaled / flipped)
    Reset-Tf $g
    if ($sleepy) {
        $zx = if ($fl -lt 0) { $cx + 34 } else { $cx - 66 }
        $zy = $cy - 84 - ([Math]::Abs([Math]::Sin($t / 20.0)) * 8)
        $g.DrawString('z Z', $script:fnt, [Drawing.Brushes]::Black, [single]($zx + 1), [single]($zy + 1))
        $g.DrawString('z Z', $script:fnt, [Drawing.Brushes]::White, [single]$zx, [single]$zy)
    }
    if ($mode -eq 'tp') {
        $r = 6 + $script:tpT * 4.5
        $al = [int][Math]::Max(0, 230 - $script:tpT * 17)
        $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb($al, $script:accRGB[0], $script:accRGB[1], $script:accRGB[2])), 3
        $g.DrawEllipse($pen, [single]($cx - $r), [single](132 - $r), [single](2 * $r), [single](2 * $r))
        foreach ($i in 0..7) {
            $an = $i * [Math]::PI / 4 + $script:tpT * 0.2
            $g.DrawLine($pen, [single]($cx + [Math]::Cos($an) * $r * 0.5), [single](132 + [Math]::Sin($an) * $r * 0.5), [single]($cx + [Math]::Cos($an) * $r), [single](132 + [Math]::Sin($an) * $r))
        }
        $pen.Dispose()
    }
}

# Render one frame into the ARGB bitmap and push it to the layered pet window at (x,y).
function Render-Pet([int]$x, [int]$y) {
    if (-not $script:pet -or -not $script:pbmp) { return }
    try {
        $g = $script:pg
        Reset-Tf $g; $g.Clear([Drawing.Color]::Transparent)
        if ($script:spr) { Draw-PetSprite $g } elseif ($script:img) { Draw-PetImg $g } else { Draw-Pet $g }
        $script:pet.Push($script:pbmp, [int]($x * $script:ds), [int]($y * $script:ds))
    } catch {}
}

# ---------------- pet window show/hide ----------------
function Show-PetWindow {
    if (-not $script:pet) { return }
    $wa = (Get-Scr).WorkingArea
    $script:mode = 'peek'; $script:scale = 1.0
    $script:vis = 0.0; $script:visT = $script:vis0; $script:nearTicks = 0
    $script:peekY = [Math]::Max($wa.Top + 20, [Math]::Min($wa.Bottom - 190, $wa.Top + $wa.Height * $script:peekFrac - 132))
    $script:fx = Peek-TargetX; $script:fy = $script:peekY
    $script:pet.Location = New-Object Drawing.Point ([int]($script:fx * $script:ds)), ([int]($script:fy * $script:ds))
    $script:lastX = $script:fx; $script:lastY = $script:fy; $script:vx = 0.0; $script:vy = 0.0; $script:trail.Clear()
    Render-Pet ([int]$script:fx) ([int]$script:fy)
    [RioWindowApiV4]::ShowWindow($script:pet.Handle, 4) | Out-Null
    $script:petOn = $true
    if ($script:spr -and -not $script:greeted) { $script:greeted = $true; Play-Event 'wave' }
}
function Hide-PetWindow {
    if ($script:pet) { [RioWindowApiV4]::ShowWindow($script:pet.Handle, 0) | Out-Null }
    Hide-Bubble; $script:bQ.Clear()
    $script:petOn = $false
}
function Update-PetVisibility {
    if ($script:quitting -or -not $script:pet) { return }
    $h = Find-RioWindow
    $vis = ($h -ne [IntPtr]::Zero) -and [RioWindowApiV4]::IsWindowVisible($h) -and -not [RioWindowApiV4]::IsIconic($h) -and ([RioWindowApiV4]::GetForegroundWindow() -eq $h)
    $want = (-not $script:petHidden) -and ((-not $vis) -or $script:petAlways) -and (-not $script:fsHide)
    if ($want -and -not $script:petOn) { Show-PetWindow }
    elseif (-not $want -and $script:petOn) { Hide-PetWindow }
}
function Toggle-Pet {
    $script:petHidden = -not $script:petHidden
    Save-PetCfg
    Update-PetVisibility
}

function Get-PetTitle([string]$id) {
    if ($id -eq 'spider_2') { return 'Spider-Man' }
    $n = ($id -replace '[_\-]\d+$', '') -replace '[_\-]', ' '
    return (Get-Culture).TextInfo.ToTitleCase($n)
}
function Style-MenuItems($items) {
    foreach ($it in $items) {
        $it.ForeColor = [Drawing.Color]::FromArgb(255, 226, 232, 240)
        if ($it -is [Windows.Forms.ToolStripMenuItem] -and $it.DropDownItems.Count -gt 0) {
            $it.DropDown.Renderer = $script:rend
            $it.DropDown.Font = $script:mfont
            Style-MenuItems $it.DropDownItems
        }
    }
}

function Start-Pet {
    if ($script:pet) { return }
    Load-PetCfg
    $script:pOl = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 12, 18, 24)), 3
    $script:pThin = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255, 12, 18, 24)), 2
    $script:pWeb = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(200, 12, 18, 24)), 1.5
    $script:bBlk = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 12, 18, 24))
    $script:bbFill = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 14, 20, 29))
    $script:bbText = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(255, 232, 241, 248))
    $script:fnt = New-Object Drawing.Font 'Segoe UI', 9, ([Drawing.FontStyle]::Bold)
    $script:sf = New-Object Drawing.StringFormat; $script:sf.Alignment = 'Center'; $script:sf.LineAlignment = 'Center'
    $script:sfR = New-Object Drawing.StringFormat; $script:sfR.Alignment = 'Far'; $script:sfR.Trimming = 'EllipsisCharacter'; $script:sfR.FormatFlags = 'NoWrap'
    $script:sfL = New-Object Drawing.StringFormat; $script:sfL.Trimming = 'EllipsisCharacter'; $script:sfL.FormatFlags = 'NoWrap'
    $script:fHead = New-Object Drawing.Font 'Segoe UI', 7.5, ([Drawing.FontStyle]::Bold)
    $script:fBody = New-Object Drawing.Font 'Segoe UI', 9.5
    $script:fTitle = New-Object Drawing.Font 'Segoe UI Semibold', 11
    $script:fBtn = New-Object Drawing.Font 'Segoe UI Semibold', 9
    $script:mfont = New-Object Drawing.Font 'Segoe UI', 9.5
    $script:mbmp = New-Object Drawing.Bitmap 4, 4
    $script:mg = [Drawing.Graphics]::FromImage($script:mbmp); $script:mg.TextRenderingHint = 'AntiAliasGridFit'
    $script:rend = New-Object Windows.Forms.ToolStripProfessionalRenderer (New-Object RioDarkColors)
    $script:rend.RoundedEdges = $false
    Set-Skin $script:skin

    $f = New-Object RioLayerFormV2
    $f.Text = 'RioPet'; $f.FormBorderStyle = 'None'; $f.ShowInTaskbar = $false; $f.TopMost = $true; $f.StartPosition = 'Manual'
    $script:pwP = [int][Math]::Ceiling($script:PW * $script:ds); $script:phP = [int][Math]::Ceiling($script:PH * $script:ds)
    $f.Size = New-Object Drawing.Size $script:pwP, $script:phP
    $null = $f.Handle
    $script:pbmp = New-Object Drawing.Bitmap $script:pwP, $script:phP
    $script:pg = [Drawing.Graphics]::FromImage($script:pbmp)
    $script:pg.SmoothingMode = 'AntiAlias'; $script:pg.InterpolationMode = 'HighQualityBicubic'
    $script:pg.PixelOffsetMode = 'HighQuality'; $script:pg.CompositingQuality = 'HighQuality'; $script:pg.TextRenderingHint = 'AntiAlias'
    $f.add_MouseDown({ param($s, $e)
        $script:lastClick = Get-Date
        if ($e.Button -eq 'Left') { $script:dragging = $true; $script:moved = $false; $script:dragPt = [Windows.Forms.Cursor]::Position; $script:dragLoc = $script:pet.Location }
    })
    $f.add_MouseMove({ param($s, $e)
        if ($script:dragging) {
            $c = [Windows.Forms.Cursor]::Position; $dx = $c.X - $script:dragPt.X; $dy = $c.Y - $script:dragPt.Y
            if ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 4) { $script:moved = $true }
            if ($script:moved) { $script:pet.Location = [Drawing.Point]::new($script:dragLoc.X + $dx, $script:dragLoc.Y + $dy) }
        }
    })
    $f.add_MouseUp({ param($s, $e)
        if ($script:dragging) {
            $script:dragging = $false
            if ($script:moved) {
                $script:fx = [double]$script:pet.Left / $script:ds; $script:fy = [double]$script:pet.Top / $script:ds; $script:gx = $script:fx; $script:gy = $script:fy
                $b = (Get-Scr).Bounds
                if ($script:mode -eq 'peek') { $script:side = if (($script:fx + 110) -gt ($b.Left + $b.Width / 2)) { 'R' } else { 'L' }; $script:peekY = $script:fy; Remember-Peek }
                Pet-Jump
            } else { Pet-Click }
        }
    })
    $f.add_DoubleClick({ Toggle-RioWindow })

    $pm = New-Object Windows.Forms.ContextMenuStrip
    $pm.Font = $script:mfont; $pm.Renderer = $script:rend
    $pm.ShowImageMargin = $false; $pm.ShowCheckMargin = $true
    $hdr = New-Object Windows.Forms.ToolStripLabel 'RIO  |  DESKTOP PET'
    $hdr.Font = $script:fHead
    [void]$pm.Items.Add($hdr)
    [void]$pm.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $pm.Items.Add('Open / hide dashboard').add_Click({ Toggle-RioWindow })
    $pm.Items.Add('What should I do now?').add_Click({ Pet-Click })
    $pm.Items.Add('Start / pause pomodoro').add_Click({ Send-Cmd 'ptoggle'; Pet-Jump })
    $pm.Items.Add('Pushups +10').add_Click({ Send-Cmd 'push' @{ n = 10 }; if ($script:spr) { Play-Fx 'pushup' 90 } else { Pet-Jump } })
    [void]$pm.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $script:miQuiet = New-Object Windows.Forms.ToolStripMenuItem 'Quiet mode (1 hour)'
    $script:miQuiet.add_Click({
        if ((Get-Date) -lt $script:quietUntil) { $script:quietUntil = [DateTime]::MinValue }
        else { $script:quietUntil = (Get-Date).AddHours(1); $script:bQ.Clear(); Hide-Bubble }
    })
    [void]$pm.Items.Add($script:miQuiet)
    $script:miSfx = New-Object Windows.Forms.ToolStripMenuItem 'Sound effects'
    $script:miSfx.add_Click({ $script:sfxOn = -not $script:sfxOn; Save-PetCfg; if ($script:sfxOn) { Play-Sfx 'pop' } })
    [void]$pm.Items.Add($script:miSfx)
    $script:miBreaks = New-Object Windows.Forms.ToolStripMenuItem 'Break reminders'
    $script:miBreaks.add_Click({ $script:breaksOn = -not $script:breaksOn; $script:workSec = 0; Save-PetCfg })
    [void]$pm.Items.Add($script:miBreaks)
    $script:miAlways = New-Object Windows.Forms.ToolStripMenuItem 'Always show (even with dashboard open)'
    $script:miAlways.add_Click({ $script:petAlways = -not $script:petAlways; Save-PetCfg })
    [void]$pm.Items.Add($script:miAlways)
    [void]$pm.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $lookMenu = New-Object Windows.Forms.ToolStripMenuItem 'Character'
    $script:lookItems = @{}
    try {
        foreach ($d in (Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'pets') -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName 'pet.json')) {
                $mi = New-Object Windows.Forms.ToolStripMenuItem (Get-PetTitle $d.Name)
                $mi.Tag = $d.Name
                $mi.add_Click({ param($s, $e) Set-Skin ([string]$s.Tag); Save-PetCfg; Pet-React 'greet' })
                [void]$lookMenu.DropDownItems.Add($mi); $script:lookItems[$d.Name] = $mi
            }
        }
    } catch {}
    if ($script:lookItems.Count -gt 0) { [void]$lookMenu.DropDownItems.Add((New-Object Windows.Forms.ToolStripSeparator)) }
    $script:miSpider = New-Object Windows.Forms.ToolStripMenuItem 'Classic: Spider poses'
    $script:miSpider.add_Click({ Set-Skin 'spider'; Save-PetCfg; Pet-Jump })
    [void]$lookMenu.DropDownItems.Add($script:miSpider)
    $script:miBat = New-Object Windows.Forms.ToolStripMenuItem 'Classic: Bat (drawn)'
    $script:miBat.add_Click({ Set-Skin 'bat'; Save-PetCfg; Pet-Jump })
    [void]$lookMenu.DropDownItems.Add($script:miBat)
    [void]$pm.Items.Add($lookMenu)
    $langMenu = New-Object Windows.Forms.ToolStripMenuItem 'Language'
    $script:miEn = New-Object Windows.Forms.ToolStripMenuItem 'English'
    $script:miEn.add_Click({ $script:lang = 'en'; Save-PetCfg })
    [void]$langMenu.DropDownItems.Add($script:miEn)
    $script:miHi = New-Object Windows.Forms.ToolStripMenuItem 'Hinglish'
    $script:miHi.add_Click({ $script:lang = 'hi'; Save-PetCfg })
    [void]$langMenu.DropDownItems.Add($script:miHi)
    [void]$pm.Items.Add($langMenu)
    $pm.Items.Add('Teleport now').add_Click({ Start-Teleport $true })
    $script:miHide = New-Object Windows.Forms.ToolStripMenuItem 'Hide pet'
    $script:miHide.add_Click({ Toggle-Pet })
    [void]$pm.Items.Add($script:miHide)
    [void]$pm.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $pm.Items.Add('Quit RIO LIFE OS').add_Click({ Stop-Rio })
    Style-MenuItems $pm.Items
    $hdr.ForeColor = [Drawing.Color]::FromArgb(255, 34, 229, 255)
    $pm.add_Opening({
        $script:menuOpen = $true
        $script:miSpider.Checked = ($script:skin -eq 'spider'); $script:miBat.Checked = ($script:skin -eq 'bat')
        foreach ($lk in @($script:lookItems.Keys)) { $script:lookItems[$lk].Checked = ([string]$lk -eq $script:skin) }
        $script:miAlways.Checked = $script:petAlways; $script:miBreaks.Checked = $script:breaksOn; $script:miSfx.Checked = $script:sfxOn
        $script:miQuiet.Checked = ((Get-Date) -lt $script:quietUntil)
        $script:miEn.Checked = ($script:lang -ne 'hi'); $script:miHi.Checked = ($script:lang -eq 'hi')
    })
    $pm.add_Closed({ $script:menuOpen = $false })
    $f.ContextMenuStrip = $pm
    $script:pet = $f

    $b = New-Object RioLayerFormV2
    $b.Text = 'RioBubble'; $b.FormBorderStyle = 'None'; $b.ShowInTaskbar = $false; $b.TopMost = $true; $b.StartPosition = 'Manual'
    $null = $b.Handle
    $b.add_MouseDown({ param($s, $e) $script:bUntil = [DateTime]::MinValue })
    $script:bub = $b

    $script:petTimer = New-Object Windows.Forms.Timer
    $script:petTimer.Interval = 50
    $script:petTimer.add_Tick({ try { Pet-Tick } catch {} })
    $script:petTimer.Start()
}
Start-Pet

# Tray icon and menu.
$script:notify = New-Object Windows.Forms.NotifyIcon
$script:notify.Icon = New-RioIcon
$script:notify.Text = 'RIO LIFE OS | Ctrl+Shift: Q show, P pet, R quit'
$script:menu = New-Object Windows.Forms.ContextMenuStrip
$showItem = $script:menu.Items.Add('Show / Hide  (Ctrl+Shift+Q)')
$showItem.add_Click({ Toggle-RioWindow })
$separator = New-Object Windows.Forms.ToolStripSeparator
$script:menu.Items.Add($separator) | Out-Null
$voiceItem = $script:menu.Items.Add('Replay welcome greeting')
$voiceItem.add_Click({ Speak-RioGreeting })
$petHideItem = $script:menu.Items.Add('Show / hide pet  (Ctrl+Shift+P)')
$petHideItem.add_Click({ Toggle-Pet })
$petSpiderItem = $script:menu.Items.Add('Pet look: Spider-style')
$petSpiderItem.add_Click({ Set-Skin 'spider'; Save-PetCfg })
$petBatItem = $script:menu.Items.Add('Pet look: Bat-style')
$petBatItem.add_Click({ Set-Skin 'bat'; Save-PetCfg })
$petItem = $script:menu.Items.Add('Pet: always show on/off')
$petItem.add_Click({ $script:petAlways = -not $script:petAlways; Save-PetCfg })
$quitItem = $script:menu.Items.Add('Quit RIO LIFE OS  (Ctrl+Shift+R)')
$quitItem.add_Click({ Stop-Rio })
$script:notify.ContextMenuStrip = $script:menu
$script:notify.add_MouseClick({ param($s, $e) if ($e.Button -eq [Windows.Forms.MouseButtons]::Left) { Toggle-RioWindow } })
$script:notify.Visible = $true

# Register global shortcuts.
$script:hotkeys = New-Object RioHotkeyV4
$script:hotkeys.add_Pressed({
    if ($script:hotkeys.LastId -eq 1) { Toggle-RioWindow }
    elseif ($script:hotkeys.LastId -eq 2) { Stop-Rio }
    elseif ($script:hotkeys.LastId -eq 3) { Toggle-Pet }
})
$toggleOK = $script:hotkeys.Register(1, [uint32]$HotMods, [uint32][char]'Q')
$stopOK   = $script:hotkeys.Register(2, [uint32]$HotMods, [uint32][char]'R')
$petOK    = $script:hotkeys.Register(3, [uint32]$HotMods, [uint32][char]'P')
if (-not $toggleOK -or -not $stopOK -or -not $petOK) {
    $msg = 'Hotkey conflict: '
    if (-not $toggleOK) { $msg += 'Ctrl+Shift+Q ' }
    if (-not $stopOK) { $msg += 'Ctrl+Shift+R ' }
    if (-not $petOK) { $msg += 'Ctrl+Shift+P ' }
    $script:notify.ShowBalloonTip(5000, 'RIO LIFE OS', $msg + 'is already used by another app.', [Windows.Forms.ToolTipIcon]::Warning)
}

# Start visible at login. If the Edge app window is closed with X/Alt+F4,
# recreate it silently in the background so the tray controller remains alive.
try { [void](Open-RioWindow) } catch { $script:notify.ShowBalloonTip(5000, 'RIO LIFE OS', $_.Exception.Message, [Windows.Forms.ToolTipIcon]::Error) }
if ($Startup) { Speak-RioGreeting }

$script:watcher = New-Object Windows.Forms.Timer
$script:watcher.Interval = 400
$script:watcher.add_Tick({
    try { Update-PetVisibility } catch {}
    if ($script:quitting) { return }
    $h = Find-RioWindow
    if ($h -ne [IntPtr]::Zero) {
        $script:windowDetected = $true
        return
    }
    if ($script:windowDetected -and ((Get-Date) - $script:lastRelaunch).TotalSeconds -ge 4) {
        $script:lastRelaunch = Get-Date
        try { [void](Open-RioWindow -Hidden) } catch {}
    }
})
$script:watcher.Start()

try { [Windows.Forms.Application]::Run() }
finally {
    $script:quitting = $true
    if ($script:watcher) { $script:watcher.Stop(); $script:watcher.Dispose() }
    if ($script:notify) { $script:notify.Visible = $false; $script:notify.Dispose() }
    if ($script:hotkeys) { $script:hotkeys.Dispose() }
    if ($script:synth) { try { $script:synth.Dispose() } catch {} }
    try { $mutex.ReleaseMutex(); $mutex.Dispose() } catch {}
}
