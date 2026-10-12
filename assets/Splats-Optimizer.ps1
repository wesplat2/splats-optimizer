<#
    Splat's Optimizer
    ---------------------------------------------------------------
    Launch it with "Splats Optimizer.exe" in the folder above this one.
    (Running this .ps1 directly also works - it asks for admin itself.)

    - What you last applied is saved in Splats-Optimizer-profile.json
      next to this script (the "Last run" button).
    - Every run is logged to the "logs" folder next to this script.
    - To change which apps get removed, edit $Config below.
#>

# =================================================================
#  Admin check - relaunch elevated if needed
# =================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        Start-Process -FilePath powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    } catch {
        Add-Type -AssemblyName PresentationFramework
        [void][Windows.MessageBox]::Show("Splat's Optimizer needs administrator rights to change system settings.", "Splat's Optimizer")
    }
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Add-Type -Namespace Splat -Name Native -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
[DllImport("user32.dll", SetLastError = true)] public static extern bool SystemParametersInfo(uint action, uint param, int[] vparam, uint winIni);
[DllImport("user32.dll", SetLastError = true)] public static extern bool SystemParametersInfo(uint action, uint param, IntPtr vparam, uint winIni);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
'@
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Splat {
    // Reads the hardware-accelerated GPU scheduling state the driver is actually running (what Settings shows).
    public static class Gpu {
        [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
        [StructLayout(LayoutKind.Sequential)] struct ADAPTERINFO { public uint hAdapter; public LUID Luid; public uint NumOfSources; public int PrecisePresent; }
        [StructLayout(LayoutKind.Sequential)] struct ENUMADAPTERS2 { public uint NumAdapters; public IntPtr pAdapters; }
        [StructLayout(LayoutKind.Sequential)] struct QUERYADAPTERINFO { public uint hAdapter; public int Type; public IntPtr pData; public uint DataSize; }
        [DllImport("gdi32.dll")] static extern int D3DKMTEnumAdapters2(ref ENUMADAPTERS2 p);
        [DllImport("gdi32.dll")] static extern int D3DKMTQueryAdapterInfo(ref QUERYADAPTERINFO p);
        [DllImport("gdi32.dll")] static extern int D3DKMTCloseAdapter(ref uint h);
        // -1 = no adapter supports it, 0 = off, 1 = on
        public static int HagsState() {
            var e = new ENUMADAPTERS2();
            if (D3DKMTEnumAdapters2(ref e) != 0 || e.NumAdapters == 0) return -1;
            int size = Marshal.SizeOf(typeof(ADAPTERINFO));
            e.pAdapters = Marshal.AllocHGlobal(size * (int)e.NumAdapters);
            int result = -1;
            try {
                if (D3DKMTEnumAdapters2(ref e) != 0) return -1;
                for (int i = 0; i < e.NumAdapters; i++) {
                    var info = (ADAPTERINFO)Marshal.PtrToStructure(new IntPtr(e.pAdapters.ToInt64() + i * size), typeof(ADAPTERINFO));
                    IntPtr caps = Marshal.AllocHGlobal(4);
                    Marshal.WriteInt32(caps, 0);
                    var q = new QUERYADAPTERINFO { hAdapter = info.hAdapter, Type = 70, pData = caps, DataSize = 4 };   // KMTQAITYPE_WDDM_2_7_CAPS
                    if (D3DKMTQueryAdapterInfo(ref q) == 0) {
                        int v = Marshal.ReadInt32(caps);
                        if ((v & 1) != 0) { if ((v & 2) != 0) result = 1; else if (result < 1) result = 0; }   // bit0 supported, bit1 enabled
                    }
                    Marshal.FreeHGlobal(caps);
                    uint h = info.hAdapter;
                    D3DKMTCloseAdapter(ref h);
                }
            } finally { Marshal.FreeHGlobal(e.pAdapters); }
            return result;
        }
    }
}
'@
$null = [Splat.Native]::ShowWindow([Splat.Native]::GetConsoleWindow(), 0)
$null = [Splat.Native]::SetCurrentProcessExplicitAppUserModelID('Splat.Optimizer')

$ScriptDir   = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path $env:LOCALAPPDATA 'SplatsOptimizer' }
$ProfilePath = Join-Path $ScriptDir 'Splats-Optimizer-profile.json'
$LogDir      = Join-Path $ScriptDir 'logs'
$FontDir     = Join-Path $ScriptDir 'fonts'
$IconDir     = Join-Path $ScriptDir 'icons'
$AppVersion  = '1.0.1'
$UpdateRepo  = 'wesplat2/splats-optimizer'    # github repo to update from - empty means updates are off

# =================================================================
#  Config - edit these lists to change what gets removed
# =================================================================
$Config = @{
    # Exact package names removed by "Remove bloatware apps"
    BloatApps = @(
        'Microsoft.3DBuilder', 'Microsoft.BingFinance', 'Microsoft.BingNews', 'Microsoft.BingSports',
        'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.Messaging',
        'Microsoft.Microsoft3DViewer', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.MixedReality.Portal', 'Microsoft.People', 'Microsoft.Print3D', 'Microsoft.SkypeApp',
        'Microsoft.Wallet', 'Microsoft.Whiteboard', 'microsoft.windowscommunicationsapps',
        'Microsoft.WindowsFeedbackHub', 'Microsoft.WindowsMaps', 'Microsoft.WindowsSoundRecorder',
        'Microsoft.YourPhone', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.Todos',
        'Microsoft.PowerAutomateDesktop', 'MicrosoftTeams', 'Microsoft.Teams', 'Clipchamp.Clipchamp',
        'Microsoft.549981C3F5F10',
        # newer Windows 11 additions
        'MSTeams', 'Microsoft.Copilot', 'Microsoft.Windows.DevHome', 'Microsoft.OutlookForWindows',
        'MicrosoftCorporationII.MicrosoftFamily', '7EE7776C.LinkedInforWindows'
    )
    # Wildcard matches for third-party preinstalled junk
    BloatWildcards = @(
        '*EclipseManager*', '*ActiproSoftwareLLC*', '*AdobePhotoshopExpress*', '*Duolingo*', '*PandoraMediaInc*',
        '*CandyCrush*', '*BubbleWitch3Saga*', '*Wunderlist*', '*Flipboard*', '*Twitter*', '*Facebook*',
        '*Spotify*', '*Disney*', '*McAfee*', '*TikTok*', '*Instagram*'
    )
    XboxApps = @(
        'Microsoft.Xbox.TCUI', 'Microsoft.XboxApp', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay',
        'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.GamingApp'
    )
    TelemetryTasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload'
    )
    AdValues = @(
        'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-353698Enabled',
        'SystemPaneSuggestionsEnabled', 'SilentInstalledAppsEnabled', 'PreInstalledAppsEnabled',
        'OemPreInstalledAppsEnabled', 'RotatingLockScreenOverlayEnabled',
        'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled',
        'SubscribedContent-310093Enabled', 'SoftLandingEnabled'
    )
    AiPolicies = @(
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1),
        @('HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot', 1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableAIDataAnalysis', 1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'AllowRecallEnablement', 0),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableClickToDo', 1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI', 'DisableGenerativeFill', 1),
        @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search', 'EnableDynamicContentInWSB', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Search', 'IsDynamicSearchBoxEnabled', 0),
        @('HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings', 'IsDynamicSearchBoxEnabled', 0),
        @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint', 'DisableGenerativeFill', 1),
        @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint', 'DisableCocreator', 1),
        @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint', 'DisableImageCreator', 1)
    )
    CleanupHandlers = @(
        'Active Setup Temp Folders', 'Downloaded Program Files', 'Internet Cache Files', 'Old ChkDsk Files',
        'Recycle Bin', 'Temporary Files', 'Temporary Setup Files', 'Thumbnail Cache', 'Update Cleanup',
        'Windows Error Reporting Archive Files', 'Windows Error Reporting Queue Files',
        'Windows Error Reporting System Archive Files', 'Windows Error Reporting System Queue Files',
        'Windows Upgrade Log Files'
    )
}

# =================================================================
#  Helpers - shared by the UI (status checks) and the worker thread
# =================================================================
$HelperCode = @'
function Send($Message) { $sync.Queue.Enqueue($Message) }
function Log([string]$Text = '', [string]$Level = 'info') { Send @{ T = 'log'; Text = $Text; L = $Level } }
function Info([string]$Text) { Log "    $Text" 'dim' }
function Ok([string]$Text) { Log "    $([char]0x2713) $Text" 'ok' }
function Warn([string]$Text) { $global:SplatWarnings++; Log "    ! $Text" 'warn' }

function Get-Reg([string]$Path, [string]$Name) {
    try { (Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop).$Name } catch { $null }
}
function Test-Reg([string]$Path, [string]$Name, $Value) {
    $v = Get-Reg $Path $Name
    if ($null -eq $v) { return $false }
    if ($v -is [array]) { return (($v -join ',') -eq (@($Value) -join ',')) }
    return ("$v" -eq "$Value")
}
function Set-Reg([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord') {
    try {
        if (-not (Test-Path -LiteralPath $Path)) { $null = New-Item -Path $Path -Force -ErrorAction Stop }
        $null = New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force -ErrorAction Stop
    } catch { Warn "Couldn't set $Path\$Name ($($_.Exception.Message))" }
}
function Remove-Reg([string]$Path, [string]$Name) {
    Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
}

function Set-Svc([string]$Name, [string]$Start, [switch]$Stop, [switch]$Soft) {
    if (-not (Get-Service -Name $Name -ErrorAction SilentlyContinue)) { return }
    $mode = @{ Disabled = 'disabled'; Manual = 'demand'; Automatic = 'auto'; Delayed = 'delayed-auto' }[$Start]
    if ($Stop) { $null = & sc.exe stop $Name 2>&1 }
    $out = & sc.exe config $Name start= $mode 2>&1
    if ($LASTEXITCODE -ne 0) {
        if ($Soft) { Info "$Name is protected by Windows - left as is." }
        else { Warn "Couldn't set $Name to $Start ($((($out | Out-String).Trim()) -replace '\s+', ' '))" }
    }
}
function Test-Svc([string]$Name, [string]$Start = 'Disabled') {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return $true }
    return ("$($svc.StartType)" -eq $Start)
}
function Set-Task([string]$Path, [switch]$Enable) {
    $flag = if ($Enable) { '/Enable' } else { '/Disable' }
    $null = & schtasks.exe /Change /TN $Path $flag 2>&1
}

# Runs a console program and streams its output into the log.
# Lines that are just progress percentages overwrite each other.
function Invoke-Native([string]$File, [string[]]$Arguments) {
    & $File @Arguments 2>&1 | ForEach-Object {
        $line = "$_" -replace "`0", ''
        $parts = @($line -split "`r" | Where-Object { $_.Trim() })
        if (-not $parts.Count) { return }
        $seg = $parts[-1].Trim()
        if ($seg -match '^[\s\-\\|/]+$' -or $seg -match '[\u2580-\u259F]') { return }
        if ($seg -match '\d+(\.\d+)?\s*%') { Send @{ T = 'logp'; Text = "    $seg" } }
        else { Log "    $seg" 'dim' }
    }
    return $LASTEXITCODE
}

function Remove-Apps([string[]]$Patterns) {
    Info 'Scanning installed apps...'
    $installed   = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)
    $removed = 0
    foreach ($pattern in $Patterns) {
        foreach ($pkg in @($installed | Where-Object { $_.Name -like $pattern } | Sort-Object PackageFullName -Unique)) {
            try {
                Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                Ok "Removed $($pkg.Name)"
                $removed++
            } catch { Info "Skipped $($pkg.Name) - $(($_.Exception.Message -split "`n")[0])" }
        }
        foreach ($p in @($provisioned | Where-Object { $_.DisplayName -like $pattern })) {
            try { $null = Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop } catch { }
        }
    }
    if ($removed) { Info "$removed package(s) removed." } else { Info 'Nothing to remove - already clean.' }
}

# Deletes everything inside a folder it can. Never follows junctions/symlinks.
function Clear-Folder([string]$Path) {
    foreach ($item in @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            try { $item.Delete() } catch { }
            continue
        }
        if ($item.PSIsContainer) {
            Clear-Folder $item.FullName
            try { $item.Delete() } catch { }
        } else {
            try {
                $len = $item.Length
                $item.Attributes = 'Normal'
                $item.Delete()
                $global:SplatFreed += $len
            } catch { }
        }
    }
}

function Find-Winget {
    $w = (Get-Command winget.exe -ErrorAction SilentlyContinue).Source
    if (-not $w -and (Test-Path "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe")) { $w = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe" }
    return $w
}

function Send-SettingChange([string]$Area = 'ImmersiveColorSet') {
    $r = [UIntPtr]::Zero
    $null = [Splat.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, $Area, 2, 2000, [ref]$r)
}

function Restart-Explorer {
    Log ''
    Log 'Restarting Explorer to apply interface changes' 'head'
    $session = (Get-Process -Id $PID).SessionId
    Get-Process explorer -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $session } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Milliseconds 500
        if (Get-Process explorer -ErrorAction SilentlyContinue) { break }
    }
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    Ok 'Explorer restarted.'
}
'@
$sync = [hashtable]::Synchronized(@{ Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]' })
. ([scriptblock]::Create($HelperCode))

# =================================================================
#  Categories & tweaks (run top to bottom in this order)
# =================================================================
$Categories = [ordered]@{
    start   = @{ Name = 'Start here';           Glyph = 0xE80F; Desc = 'pick what you want from the tabs on the left, then hit apply. nothing is ticked until you tick it.' }
    debloat = @{ Name = 'Debloat';              Glyph = 0xE74D; Desc = 'gets rid of the stuff windows comes with that nobody asked for.' }
    privacy = @{ Name = 'Privacy & AI';         Glyph = 0xE72E; Desc = 'stop windows from phoning home, showing you ads and shoving AI into everything.' }
    updates = @{ Name = 'Updates & Services';   Glyph = 0xE895; Desc = 'windows update and a few background services you don''t need.' }
    perf    = @{ Name = 'Performance & Feel';   Glyph = 0xE7FC; Desc = 'makes windows feel snappier and games feel better. there''s more in quick toggles too.' }
    cleanup = @{ Name = 'Cleanup & Repair';     Glyph = 0xE90F; Desc = 'cleanup and repair stuff. these run every time you hit apply while they''re ticked.' }
}

$Items = @(
    # ------------------------------------------------------------ Start here
    @{
        Id = 'restore'; Cat = 'start'; Preset = $true
        Name = 'Make a restore point'
        Desc = 'makes a restore point before anything else runs. if something breaks you can roll back from windows recovery. runs first on undo too.'
        Apply = {
            Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' 'SystemRestorePointCreationFrequency' 0
            try { Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop } catch { }
            try {
                Checkpoint-Computer -Description ("Splat's Optimizer " + (Get-Date -Format 'yyyy-MM-dd HH:mm')) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
                Ok 'Restore point created.'
            } catch { Warn "Couldn't create a restore point: $($_.Exception.Message)" }
        }
    }

    # ------------------------------------------------------------ Debloat
    @{
        Id = 'apps'; Cat = 'debloat'; Preset = $true; OneWay = $true
        Name = 'Remove bloatware'
        Desc = 'all the preinstalled junk. bing news, weather, solitaire, clipchamp, teams, mail, maps, phone link, copilot, candy crush, tiktok etc. hover over it for the full list.'
        Apply = { Remove-Apps ($Config.BloatApps + $Config.BloatWildcards) }
    }
    @{
        Id = 'xbox'; Cat = 'debloat'; Preset = $true; Reboot = $true
        Name = 'Remove Xbox stuff'
        Desc = 'removes the xbox app, game bar and the overlays, kills the xbox services, and turns off game dvr (otherwise games keep throwing a "ms-gamingoverlay" popup).'
        Warn = 'game pass / store games and xbox sign in won''t work after this. steam, battle.net, epic etc are fine.'
        Apply = {
            Remove-Apps $Config.XboxApps
            foreach ($s in 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc') { Set-Svc $s Disabled -Stop }
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0
            Ok 'Xbox services disabled.'
        }
        Revert = {
            foreach ($s in 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc') { Set-Svc $s Manual }
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 1
            Remove-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled'
            Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR'
            Ok 'Xbox services are back on Manual.'
            Info 'Reinstall the Xbox app / Game Bar from the Microsoft Store if you want them back.'
        }
        Check = { foreach ($s in 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc') { Test-Svc $s } }
    }
    @{
        Id = 'onedrive'; Cat = 'debloat'; Preset = $true; OneWay = $true
        Name = 'Remove OneDrive'
        Desc = 'uninstalls onedrive and takes it out of startup and the file explorer sidebar. your onedrive folder only gets deleted if it''s empty so you won''t lose anything.'
        Apply = {
            Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            $cmds = New-Object System.Collections.Generic.List[object]
            foreach ($s in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
                if (Test-Path -LiteralPath $s) { $cmds.Add(@($s, '/uninstall')) }
            }
            foreach ($key in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe',
                             'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe',
                             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe') {
                $u = Get-Reg $key 'UninstallString'
                if ($u -match '^\s*"([^"]+)"\s*(.*)$' -or $u -match '^\s*(\S+)\s*(.*)$') {
                    $exe = $Matches[1]; $arg = $Matches[2]
                    if (-not $arg) { $arg = '/uninstall' }
                    if (Test-Path -LiteralPath $exe) { $cmds.Add(@($exe, $arg)) }
                }
            }
            if ($cmds.Count -eq 0) { Info 'OneDrive installer not found - probably already removed.' }
            foreach ($c in $cmds) {
                Info "Running $(Split-Path $c[0] -Leaf) $($c[1])"
                try {
                    $p = Start-Process -FilePath $c[0] -ArgumentList $c[1] -PassThru -WindowStyle Hidden -ErrorAction Stop
                    $null = $p.WaitForExit(180000)
                } catch { Warn $_.Exception.Message }
            }
            Start-Sleep -Seconds 2
            Remove-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDrive'
            foreach ($clsid in 'Registry::HKEY_CLASSES_ROOT\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}',
                               'Registry::HKEY_CLASSES_ROOT\Wow6432Node\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}') {
                if (Test-Path -LiteralPath $clsid) { Set-Reg $clsid 'System.IsPinnedToNameSpaceTree' 0 }
            }
            foreach ($dir in "$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:ProgramData\Microsoft OneDrive", "$env:SystemDrive\OneDriveTemp") {
                if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
            }
            foreach ($userDir in @((Join-Path $env:USERPROFILE 'OneDrive'), $env:OneDrive) | Where-Object { $_ } | Select-Object -Unique) {
                if (-not (Test-Path -LiteralPath $userDir)) { continue }
                $hasFiles = Get-ChildItem -LiteralPath $userDir -Recurse -Force -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($hasFiles) { Warn "Left $userDir alone - it still has files in it. Move anything you want to keep, then delete it yourself." }
                else { Remove-Item -LiteralPath $userDir -Recurse -Force -ErrorAction SilentlyContinue; Info 'Removed the empty OneDrive folder.' }
            }
            $shell = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
            if (@('Desktop', 'Personal', 'My Pictures' | Where-Object { (Get-Reg $shell $_) -like '*OneDrive*' }).Count) {
                Warn 'Your Desktop/Documents/Pictures still point inside the OneDrive folder. They keep working; to move them back, right-click each one > Properties > Location > Restore Default.'
            }
            Ok 'OneDrive removed.'
        }
        Check = {
            -not ((Test-Path "$env:LOCALAPPDATA\Microsoft\OneDrive\OneDrive.exe") -or
                  (Test-Path "$env:ProgramFiles\Microsoft OneDrive\OneDrive.exe") -or
                  (Test-Path "${env:ProgramFiles(x86)}\Microsoft OneDrive\OneDrive.exe"))
        }
    }
    @{
        Id = 'browser'; Cat = 'debloat'; Preset = $true
        Name = 'Install a browser'
        Desc = 'installs one before edge gets removed so you''re not stuck without a browser.'
        Options = @(
            @{ Key = 'firefox'; Label = 'Firefox' }
            @{ Key = 'chrome';  Label = 'Chrome' }
            @{ Key = 'helium';  Label = 'Helium' }
        )
        Default = 'firefox'
        Apply = {
            param($Option)
            $ids = @{ chrome = 'Google.Chrome'; firefox = 'Mozilla.Firefox'; helium = 'ImputNet.Helium' }
            $winget = Find-Winget
            if (-not $winget) { Warn 'winget is not available yet. Open the Microsoft Store, update "App Installer", then run this again.'; return }
            Info "Installing $($ids[$Option]) with winget..."
            $code = Invoke-Native $winget @('install', '--id', $ids[$Option], '--exact', '--source', 'winget', '--silent',
                                            '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
            if ($code -eq 0) { Ok 'Browser installed.' }
            elseif ($code -eq -1978335189 -or $code -eq -1978335135) { Ok 'Already installed and up to date.' }
            else { Warn "winget exited with code $code." }
        }
    }
    @{
        Id = 'edge'; Cat = 'debloat'; Preset = $true; OneWay = $true
        Name = 'Remove Edge'
        Desc = 'tries to uninstall edge. microsoft blocks this on some builds so no promises, and windows update might bring it back. webview2 stays because a lot of apps need it.'
        Apply = {
            $root = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application'
            if (-not (Test-Path -LiteralPath "$root\msedge.exe")) { Info 'Edge is not installed.'; return }
            Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            # Edge's uninstaller refuses to run outside the EU unless these are present
            Set-Reg 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev' 'AllowUninstall' '' 'String'
            $stub = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe\MicrosoftEdge.exe"
            $madeStub = $false
            if (-not (Test-Path -LiteralPath $stub)) {
                try { $null = New-Item -ItemType File -Path $stub -Force -ErrorAction Stop; $madeStub = $true } catch { }
            }
            $setups = @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d' } |
                        ForEach-Object { Join-Path $_.FullName 'Installer\setup.exe' } | Where-Object { Test-Path -LiteralPath $_ })
            foreach ($s in $setups) {
                Info 'Running the Edge uninstaller...'
                $p = Start-Process -FilePath $s -ArgumentList '--uninstall', '--system-level', '--verbose-logging', '--force-uninstall' -PassThru -WindowStyle Hidden
                $null = $p.WaitForExit(300000)
            }
            if ($madeStub) { Remove-Item -LiteralPath $stub -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 2
            if (Test-Path -LiteralPath "$root\msedge.exe") { Warn 'Edge is still installed - Microsoft blocked the uninstall on this build.' }
            else { Ok 'Edge removed.' }
        }
        Check = { -not (Test-Path "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") }
    }

    # ------------------------------------------------------------ Privacy & AI
    @{
        Id = 'telemetry'; Cat = 'privacy'; Preset = $true; Reboot = $true
        Name = 'Disable telemetry'
        Desc = 'turns diagnostic data down as low as windows lets you and disables the services and scheduled tasks that collect it.'
        Apply = {
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
            foreach ($t in $Config.TelemetryTasks) { Set-Task $t }
            Set-Svc DiagTrack Disabled -Stop
            Set-Svc dmwappushservice Disabled -Stop
            Ok 'Telemetry minimized.'
        }
        Revert = {
            Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
            foreach ($t in $Config.TelemetryTasks) { Set-Task $t -Enable }
            Set-Svc DiagTrack Automatic
            Set-Svc dmwappushservice Manual
            Ok 'Telemetry back to Windows defaults.'
        }
        Check = {
            Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
            Test-Svc DiagTrack
        }
    }
    @{
        Id = 'ads'; Cat = 'privacy'; Preset = $true; Explorer = $true
        Name = 'Disable ads & suggestions'
        Desc = 'no more "suggested" apps in start, tips on the lock screen, onedrive ads in explorer, or sponsored apps installing themselves.'
        Apply = {
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
            foreach ($v in $Config.AdValues) { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' $v 0 }
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 0
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 0
            Ok 'Ads, tips and suggestions turned off.'
        }
        Revert = {
            Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures'
            foreach ($v in $Config.AdValues) { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' $v 1 }
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' 1
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 1
            Ok 'Suggestions back on.'
        }
        Check = {
            Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 1
            Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 0
            Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 0
        }
    }
    @{
        Id = 'cortana'; Cat = 'privacy'; Preset = $true; Reboot = $true
        Name = 'Disable Cortana'
        Desc = 'blocks cortana. that''s it.'
        Apply  = { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0; Ok 'Cortana blocked.' }
        Revert = { Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana'; Ok 'Cortana allowed again.' }
        Check  = { Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 0 }
    }
    @{
        Id = 'ai'; Cat = 'privacy'; Preset = $true; Reboot = $true
        Name = 'Disable Copilot & Recall'
        Desc = 'turns off copilot, recall, click to do, the AI search stuff and the AI junk in paint. some of it only exists on copilot+ pcs anyway.'
        Apply  = { foreach ($p in $Config.AiPolicies) { Set-Reg $p[0] $p[1] $p[2] }; Ok 'AI features turned off.' }
        Revert = { foreach ($p in $Config.AiPolicies) { Remove-Reg $p[0] $p[1] }; Ok 'AI policies removed.' }
        Check  = {
            Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
            Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' 0
            Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
        }
    }
    @{
        Id = 'bgapps'; Cat = 'privacy'; Preset = $true
        Name = 'Disable background apps'
        Desc = 'stops store apps from running in the background when you''re not using them.'
        Apply = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppsAllowed' 0
            Ok 'Background apps disabled.'
        }
        Revert = {
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 0
            Remove-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppsAllowed'
            Ok 'Background apps allowed again.'
        }
        Check = {
            Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
            Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppsAllowed' 0
        }
    }
    # ------------------------------------------------------------ Updates & Services
    @{
        Id = 'wu'; Cat = 'updates'; Preset = $true; Reboot = $true
        Name = 'Stop automatic updates'
        Desc = 'stops windows from updating whenever it feels like it.'
        Options = @(
            @{ Key = 'disable'; Label = 'Turn it off'; Hint = 'turns windows update off completely. checking for updates and store downloads won''t work until you undo this.' }
            @{ Key = 'notify';  Label = 'Manual only';        Hint = 'nothing installs unless you go into settings and do it yourself. the store still works.' }
        )
        Default = 'disable'
        Apply = {
            param($Option)
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions' 2
            if ($Option -eq 'notify') {
                Set-Svc wuauserv Manual
                Ok 'Automatic updates off. Update from Settings > Windows Update whenever you want.'
            } else {
                Set-Svc wuauserv Disabled -Stop
                Ok 'Windows Update service disabled.'
                Info 'Windows can quietly re-enable it over time - just run this again if it does.'
            }
        }
        Revert = {
            Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate'
            Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions'
            Set-Svc wuauserv Manual
            Ok 'Windows Update back to normal.'
        }
        Check = { Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' 1 }
    }
    @{
        Id = 'services'; Cat = 'updates'; Preset = $true; Reboot = $true
        Name = 'Disable unneeded services'
        Desc = 'retail demo, the maps downloader and media player network sharing. search indexing stays on so start search isn''t slow.'
        Apply = {
            foreach ($s in 'RetailDemo', 'MapsBroker', 'WMPNetworkSvc') { Set-Svc $s Disabled -Stop }
            Ok 'Services disabled.'
        }
        Revert = {
            Set-Svc RetailDemo Manual
            Set-Svc MapsBroker Delayed
            Set-Svc WMPNetworkSvc Manual
            Ok 'Services back to defaults.'
        }
        Check = { foreach ($s in 'RetailDemo', 'MapsBroker', 'WMPNetworkSvc') { Test-Svc $s } }
    }
    @{
        Id = 'delivery'; Cat = 'updates'; Preset = $true; Reboot = $true
        Name = 'Disable Delivery Optimization'
        Desc = 'stops your pc from sharing windows updates with random other pcs over the internet.'
        Apply = {
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
            Set-Svc DoSvc Disabled -Stop -Soft
            Ok 'Peer-to-peer update sharing is off.'
        }
        Revert = {
            Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode'
            Set-Svc DoSvc Delayed -Soft
            Ok 'Delivery Optimization back to defaults.'
        }
        Check = { Test-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 }
    }
    @{
        Id = 'storagesense'; Cat = 'updates'; Preset = $true
        Name = 'Disable Storage Sense'
        Desc = 'stops windows from deleting stuff out of your downloads and recycle bin on its own.'
        Apply  = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 0; Ok 'Storage Sense off.' }
        Revert = { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 1; Ok 'Storage Sense on.' }
        Check  = { Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy' '01' 0 }
    }

    # ------------------------------------------------------------ Performance & Gaming
    @{
        Id = 'animations'; Cat = 'perf'; Preset = $true; Explorer = $true
        Name = 'Disable animations'
        Desc = 'turns off window animations, fades, aero peek etc. same as "adjust for best performance". kicks in right away.'
        Apply = {
            $null = [Splat.Native]::SystemParametersInfo(0x0049, 8, [int[]]@(8, 0), 3)        # window min/max animation
            $null = [Splat.Native]::SystemParametersInfo(0x1043, 0, [IntPtr]::Zero, 3)        # animations inside windows
            $null = [Splat.Native]::SystemParametersInfo(0x0025, 0, [IntPtr]::Zero, 3)        # drag full windows
            $null = [Splat.Native]::SystemParametersInfo(0x103F, 0, [IntPtr]::Zero, 3)        # menu/tooltip/fade effects
            Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
            Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 0
            Set-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) 'Binary'
            Set-Reg 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '0' 'String'
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
            Ok 'Animations off.'
        }
        Revert = {
            $null = [Splat.Native]::SystemParametersInfo(0x0049, 8, [int[]]@(8, 1), 3)
            $null = [Splat.Native]::SystemParametersInfo(0x1043, 0, [IntPtr]1, 3)
            $null = [Splat.Native]::SystemParametersInfo(0x0025, 1, [IntPtr]::Zero, 3)
            $null = [Splat.Native]::SystemParametersInfo(0x103F, 0, [IntPtr]1, 3)
            Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '1' 'String'
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 1
            Set-Reg 'HKCU:\Software\Microsoft\Windows\DWM' 'EnableAeroPeek' 1
            Set-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x9E, 0x1E, 0x07, 0x80, 0x12, 0x00, 0x00, 0x00)) 'Binary'
            Set-Reg 'HKCU:\Control Panel\Desktop' 'DragFullWindows' '1' 'String'
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 0
            Ok 'Animations back on.'
        }
        Check = {
            Test-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0'
            Test-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
            Test-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00))
        }
    }
    @{
        Id = 'mouseaccel'; Cat = 'perf'; Preset = $true
        Name = 'Disable mouse acceleration'
        Desc = 'turns off "enhance pointer precision" so your aim is 1:1. kicks in right away.'
        Apply = {
            $null = [Splat.Native]::SystemParametersInfo(0x0004, 0, [int[]]@(0, 0, 0), 3)
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
            Ok 'Mouse acceleration off.'
        }
        Revert = {
            $null = [Splat.Native]::SystemParametersInfo(0x0004, 0, [int[]]@(6, 10, 1), 3)
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '1' 'String'
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '6' 'String'
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '10' 'String'
            Ok 'Mouse acceleration back on.'
        }
        Check = {
            Test-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0'
            Test-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0'
            Test-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0'
        }
    }
    @{
        Id = 'fso'; Cat = 'perf'; Preset = $true; Reboot = $true
        Name = 'Disable fullscreen optimizations'
        Desc = 'forces real exclusive fullscreen in games. you can still change it per game in the exe''s compatibility tab.'
        Apply = {
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 1
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1
            Ok 'Fullscreen optimizations off.'
        }
        Revert = {
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 0
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 0
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 0
            Ok 'Fullscreen optimizations back on.'
        }
        Check = {
            Test-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2
            Test-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1
        }
    }
    @{
        Id = 'contextmenu'; Cat = 'perf'; Preset = $true; Explorer = $true
        Name = 'Classic right-click menu'
        Desc = 'brings back the full windows 10 right click menu. no more "show more options".'
        Apply = {
            $key = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
            try {
                if (-not (Test-Path -LiteralPath $key)) { $null = New-Item -Path $key -Force -ErrorAction Stop }
                Set-ItemProperty -LiteralPath $key -Name '(default)' -Value '' -ErrorAction Stop
                Ok 'Classic menu enabled.'
            } catch { Warn $_.Exception.Message }
        }
        Revert = {
            Remove-Item -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force -ErrorAction SilentlyContinue
            Ok 'Windows 11 menu restored.'
        }
        Check = { Test-Path -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' }
    }

    # ------------------------------------------------------------ Cleanup & Repair
    @{
        Id = 'dns'; Cat = 'cleanup'; Preset = $true
        Name = 'Flush DNS cache'
        Desc = 'clears the dns cache. good for when a site won''t load or you just changed your dns.'
        Apply = { $null = Invoke-Native ipconfig.exe @('/flushdns'); Ok 'DNS cache flushed.' }
    }
    @{
        Id = 'dism'; Cat = 'cleanup'
        Name = 'Repair Windows (DISM)'
        Desc = 'downloads fresh copies of any broken windows files. do this one before sfc. turns windows update back on for a bit if you disabled it. takes like 5-15 min.'
        Apply = {
            $svc = Get-Service wuauserv -ErrorAction SilentlyContinue
            $wasDisabled = $svc -and "$($svc.StartType)" -eq 'Disabled'
            if ($wasDisabled) { Info 'Temporarily enabling Windows Update so DISM can download repairs...'; Set-Svc wuauserv Manual }
            $code = Invoke-Native "$env:SystemRoot\System32\Dism.exe" @('/Online', '/Cleanup-Image', '/RestoreHealth')
            if ($wasDisabled) { Set-Svc wuauserv Disabled -Stop; Info 'Windows Update service disabled again.' }
            if ($code -eq 0) { Ok 'DISM finished.' } else { Warn "DISM exited with code $code." }
        }
    }
    @{
        Id = 'sfc'; Cat = 'cleanup'
        Name = 'System file check (SFC)'
        Desc = 'sfc /scannow. checks all the system files and fixes broken ones. takes 10-20 min.'
        Apply = { $null = Invoke-Native "$env:SystemRoot\System32\sfc.exe" @('/scannow'); Ok 'SFC finished - see the result above.' }
    }
    @{
        Id = 'temp'; Cat = 'cleanup'; Preset = $true
        Name = 'Clean temp files'
        Desc = 'empties your temp folder and C:\Windows\Temp. anything in use gets skipped.'
        Apply = {
            $global:SplatFreed = 0
            $targets = @($env:TEMP, "$env:SystemRoot\Temp") | Where-Object { $_ -and (Test-Path -LiteralPath $_) -and (Split-Path $_ -Leaf) -eq 'Temp' } |
                       ForEach-Object { (Resolve-Path -LiteralPath $_).ProviderPath } | Select-Object -Unique
            foreach ($t in $targets) { Info "Cleaning $t"; Clear-Folder $t }
            Ok ("Freed {0:N0} MB." -f ($global:SplatFreed / 1MB))
        }
    }
    @{
        Id = 'diskcleanup'; Cat = 'cleanup'; Preset = $true; OneWay = $true
        Name = 'Run Disk Cleanup'
        Desc = 'runs disk cleanup in the background. thumbnails, error reports, old update files. heads up, it empties the recycle bin too.'
        Apply = {
            $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
            foreach ($h in $Config.CleanupHandlers) {
                if (Test-Path -LiteralPath "$base\$h") { Set-Reg "$base\$h" 'StateFlags0001' 2 }
            }
            Info 'Disk Cleanup is running in its own small window - this can take a few minutes...'
            $p = Start-Process cleanmgr.exe -ArgumentList '/sagerun:1' -PassThru
            if ($p.WaitForExit(1800000)) { Ok 'Disk Cleanup finished.' }
            else { Warn 'Disk Cleanup is still going after 30 minutes - leaving it to finish on its own.' }
        }
    }
)

$ItemById = @{}
foreach ($it in $Items) { $ItemById[$it.Id] = $it }
$ItemById.apps.Tip = 'Removes: ' + (($Config.BloatApps + $Config.BloatWildcards) -join ', ')
$ItemById.xbox.Tip = 'Removes: ' + ($Config.XboxApps -join ', ')

# =================================================================
#  Quick toggles - flip a switch and it applies immediately.
#  ON always means "the Windows feature is on".
#  Restart = needs a PC restart, Explorer = needs Explorer restarted.
# =================================================================
$ExplorerAdv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$Toggles = @(
    # ---------------------------------------------- Security & gaming
    @{
        Id = 'hvci'; Group = 'Security & gaming'; Restart = $true
        Name = 'Memory Integrity (Core isolation)'
        Desc = 'blocks sketchy kernel drivers. turning it off can get you a few more fps in some games and lets old drivers load, but you lose that protection.'
        Get = { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled') -eq 1 }
        Set = { param($On) Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' ([int]$On) }
    }
    @{
        Id = 'driverblock'; Group = 'Security & gaming'; Restart = $true
        Name = 'Vulnerable driver blocklist'
        Desc = 'blocks drivers that are known to be exploitable. some old rgb, fan control and overclocking tools won''t start while it''s on.'
        Get = { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' 'VulnerableDriverBlocklistEnable') -ne 0 }
        Set = { param($On) Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Config' 'VulnerableDriverBlocklistEnable' ([int]$On) }
    }
    @{
        Id = 'gamemode'; Group = 'Security & gaming'
        Name = 'Game Mode'
        Desc = 'windows prioritizes whatever game you''re playing and holds off on updates while you play. just leave it on.'
        Get = { (Get-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -ne 0 }
        Set = { param($On) Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' ([int]$On) }
    }
    @{
        Id = 'hags'; Group = 'Security & gaming'; Restart = $true
        Name = 'GPU scheduling (HAGS)'
        Desc = 'lets your gpu manage its own memory. usually a bit less latency on newer cards, and dlss frame gen needs it.'
        Get = {
            # a saved setting wins (it may be waiting on a restart); otherwise ask the driver what it's running
            $saved = Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
            if ($null -ne $saved) { return ($saved -eq 2) }
            switch ([Splat.Gpu]::HagsState()) { 1 { $true } 0 { $false } default { $null } }
        }
        Set = { param($On) Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' $(if ($On) { 2 } else { 1 }) }
    }
    @{
        Id = 'windowedopt'; Group = 'Security & gaming'
        Name = 'Optimizations for windowed games'
        Desc = 'older dx10/11 games in windowed or borderless get lower latency and can use vrr / auto hdr.'
        Get = {
            $s = [string](Get-Reg 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings')
            if ($s -notmatch 'SwapEffectUpgradeEnable=') { return $null }   # never set - Windows decides
            $s -match 'SwapEffectUpgradeEnable=1'
        }
        Set = {
            param($On)
            $p = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
            $parts = @(([string](Get-Reg $p 'DirectXUserGlobalSettings')) -split ';' | Where-Object { $_ -and $_ -notmatch '^SwapEffectUpgradeEnable=' })
            $parts += "SwapEffectUpgradeEnable=$([int]$On)"
            Set-Reg $p 'DirectXUserGlobalSettings' (($parts -join ';') + ';') 'String'
        }
    }
    @{
        Id = 'gamedvr'; Group = 'Security & gaming'
        Name = 'Game Bar background recording'
        Desc = 'game bar''s always-on recording. costs a bit of performance, turn it off if you clip with something else.'
        Get = {
            ((Get-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled') -ne 0) -and
            ((Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled') -ne 0) -and
            ((Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR') -ne 0)
        }
        Set = {
            param($On)
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' ([int]$On)
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' ([int]$On)
            if ($On) { Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' }
        }
    }
    # ---------------------------------------------- Power
    @{
        Id = 'ultimate'; Group = 'Power'
        Name = 'Ultimate Performance power plan'
        Desc = 'windows'' hidden max performance power plan. off puts you back on balanced. don''t use it on a laptop, it eats battery.'
        Get = { ((& powercfg.exe /getactivescheme) -join ' ') -match 'Ultimate' }
        Set = {
            param($On)
            if (-not $On) { $null = & powercfg.exe /setactive SCHEME_BALANCED; return }
            $list = (& powercfg.exe /list) -join "`n"
            $guid = $null
            if ($list -match '([0-9a-fA-F-]{36})\s+\(Ultimate Performance\)') { $guid = $Matches[1] }
            else {
                $out = (& powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1) -join "`n"
                if ($out -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { $guid = $Matches[1] }
            }
            if ($guid) { $null = & powercfg.exe /setactive $guid }
        }
    }
    @{
        Id = 'powerthrottle'; Group = 'Power'
        Name = 'Power throttling'
        Desc = 'windows slows down stuff it thinks is in the background. off keeps discord, obs, music etc at full speed. fine on a desktop.'
        Get = { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff') -ne 1 }
        Set = {
            param($On)
            if ($On) { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' }
            else { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 1 }
        }
    }
    @{
        Id = 'hibernate'; Group = 'Power'
        Name = 'Hibernation'
        Desc = 'hiberfil.sys can be a few gb. turning this off frees that up (and kills fast startup too).'
        Get = { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled') -eq 1 }
        Set = { param($On) $null = & powercfg.exe /hibernate $(if ($On) { 'on' } else { 'off' }) 2>&1 }
    }
    @{
        Id = 'faststartup'; Group = 'Power'
        Name = 'Fast Startup'
        Desc = 'makes shut down a kind of half hibernate so you boot faster. off = proper fresh boot every time, which avoids a lot of weird driver issues.'
        Get = { (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled') -eq 1 }
        Set = { param($On) Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' ([int]$On) }
    }
    # ---------------------------------------------- Look & feel
    @{
        Id = 'darkmode'; Group = 'Look & feel'
        Name = 'Dark mode'
        Desc = 'dark theme for windows and apps.'
        Get = { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme') -eq 0 }
        Set = {
            param($On)
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'AppsUseLightTheme' ([int](-not $On))
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'SystemUsesLightTheme' ([int](-not $On))
            Send-SettingChange
        }
    }
    @{
        Id = 'transparency'; Group = 'Look & feel'
        Name = 'Transparency effects'
        Desc = 'the blurry see-through look on the taskbar, start and settings.'
        Get = { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency') -ne 0 }
        Set = { param($On) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' ([int]$On); Send-SettingChange }
    }
    @{
        Id = 'contextmenu'; Group = 'Look & feel'; Explorer = $true
        Name = 'Classic right-click menu'
        Desc = 'the full windows 10 right click menu, no "show more options".'
        Get = { Test-Path -LiteralPath 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' }
        Set = {
            param($On)
            $key = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
            if ($On) {
                $null = New-Item -Path "$key\InprocServer32" -Force
                Set-ItemProperty -LiteralPath "$key\InprocServer32" -Name '(default)' -Value ''
            } else { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    @{
        Id = 'fileext'; Group = 'Look & feel'; Explorer = $true
        Name = 'Show file extensions'
        Desc = 'always shows .exe .txt etc in file explorer. way harder to get tricked by a "photo.jpg.exe".'
        Get = { (Get-Reg $ExplorerAdv 'HideFileExt') -eq 0 }
        Set = { param($On) Set-Reg $ExplorerAdv 'HideFileExt' ([int](-not $On)) }
    }
    @{
        Id = 'hidden'; Group = 'Look & feel'; Explorer = $true
        Name = 'Show hidden files'
        Desc = 'shows hidden stuff like the appdata folder.'
        Get = { (Get-Reg $ExplorerAdv 'Hidden') -eq 1 }
        Set = { param($On) Set-Reg $ExplorerAdv 'Hidden' $(if ($On) { 1 } else { 2 }) }
    }
    @{
        Id = 'taskbarleft'; Group = 'Look & feel'; Explorer = $true
        Name = 'Left-aligned taskbar'
        Desc = 'start button back in the corner like windows 10.'
        Get = { (Get-Reg $ExplorerAdv 'TaskbarAl') -eq 0 }
        Set = { param($On) if ($On) { Set-Reg $ExplorerAdv 'TaskbarAl' 0 } else { Remove-Reg $ExplorerAdv 'TaskbarAl' } }
    }
    @{
        Id = 'searchbox'; Group = 'Look & feel'; Explorer = $true
        Name = 'Search on the taskbar'
        Desc = 'the search box next to start. you can still just hit start and type.'
        Get = { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode') -ne 0 }
        Set = { param($On) if ($On) { Remove-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' } else { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 0 } }
    }
    @{
        Id = 'taskview'; Group = 'Look & feel'; Explorer = $true
        Name = 'Task View button'
        Desc = 'the virtual desktops button. win+tab still works without it.'
        Get = { (Get-Reg $ExplorerAdv 'ShowTaskViewButton') -ne 0 }
        Set = { param($On) Set-Reg $ExplorerAdv 'ShowTaskViewButton' ([int]$On) }
    }
    @{
        Id = 'widgets'; Group = 'Look & feel'; Explorer = $true
        Name = 'Widgets'
        Desc = 'the news and weather thing on the taskbar.'
        Get = { (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests') -ne 0 }
        Set = { param($On) if ($On) { Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' } else { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0 } }
    }
    @{
        Id = 'endtask'; Group = 'Look & feel'; Explorer = $true
        Name = '"End task" on taskbar right-click'
        Desc = 'right click a frozen app on the taskbar and kill it. no task manager needed.'
        Get = { (Get-Reg "$ExplorerAdv\TaskbarDeveloperSettings" 'TaskbarEndTask') -eq 1 }
        Set = { param($On) Set-Reg "$ExplorerAdv\TaskbarDeveloperSettings" 'TaskbarEndTask' ([int]$On) }
    }
    @{
        Id = 'seconds'; Group = 'Look & feel'; Explorer = $true
        Name = 'Seconds on the taskbar clock'
        Desc = 'shows seconds on the clock.'
        Get = { (Get-Reg $ExplorerAdv 'ShowSecondsInSystemClock') -eq 1 }
        Set = { param($On) Set-Reg $ExplorerAdv 'ShowSecondsInSystemClock' ([int]$On) }
    }
    # ---------------------------------------------- Privacy & system
    @{
        Id = 'websearch'; Group = 'Privacy & system'; Explorer = $true
        Name = 'Bing results in Start search'
        Desc = 'web results when you search from start. off = start only searches your pc.'
        Get = {
            ((Get-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions') -ne 1) -and
            ((Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled') -ne 0)
        }
        Set = {
            param($On)
            if ($On) {
                Remove-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions'
                Remove-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled'
            } else {
                Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
            }
        }
    }
    @{
        Id = 'notifications'; Group = 'Privacy & system'
        Name = 'Notifications'
        Desc = 'the popups in the bottom corner.'
        Get = { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled') -ne 0 }
        Set = { param($On) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' ([int]$On) }
    }
    @{
        Id = 'clipboard'; Group = 'Privacy & system'
        Name = 'Clipboard history'
        Desc = 'win+v shows everything you copied recently, not just the last thing.'
        Get = { (Get-Reg 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory') -eq 1 }
        Set = { param($On) Set-Reg 'HKCU:\Software\Microsoft\Clipboard' 'EnableClipboardHistory' ([int]$On) }
    }
    @{
        Id = 'location'; Group = 'Privacy & system'
        Name = 'Location services'
        Desc = 'lets windows and apps see where you are (weather, maps, find my device).'
        Get = { (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value') -eq 'Allow' }
        Set = { param($On) Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' $(if ($On) { 'Allow' } else { 'Deny' }) 'String' }
    }
    @{
        Id = 'adid'; Group = 'Privacy & system'
        Name = 'Advertising ID'
        Desc = 'an id apps use to show you personalized ads.'
        Get = { (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled') -eq 1 }
        Set = { param($On) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' ([int]$On) }
    }
    @{
        Id = 'activity'; Group = 'Privacy & system'
        Name = 'Activity history'
        Desc = 'windows keeps a history of the apps, files and sites you used.'
        Get = { (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities') -ne 0 }
        Set = {
            param($On)
            if ($On) {
                Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities'
                Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities'
            } else {
                Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 0
                Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 0
            }
        }
    }
    # ---------------------------------------------- Keyboard & mouse
    @{
        Id = 'mouseaccel'; Group = 'Keyboard & mouse'
        Name = 'Enhance pointer precision'
        Desc = 'mouse acceleration. off = 1:1 aim. kicks in right away.'
        Get = { (Get-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed') -ne '0' }
        Set = {
            param($On)
            $v = if ($On) { @(6, 10, 1) } else { @(0, 0, 0) }
            $null = [Splat.Native]::SystemParametersInfo(0x0004, 0, [int[]]$v, 3)
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' "$($v[0])" 'String'
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' "$($v[1])" 'String'
            Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' "$($v[2])" 'String'
        }
    }
    @{
        Id = 'stickykeys'; Group = 'Keyboard & mouse'; SignOut = $true
        Name = 'Sticky Keys popup'
        Desc = 'the "do you want to turn on sticky keys?" thing when you spam shift mid game.'
        Get = { (Get-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags') -ne '506' }
        Set = {
            param($On)
            Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' $(if ($On) { '510' } else { '506' }) 'String'
            Set-Reg 'HKCU:\Control Panel\Accessibility\Keyboard Response' 'Flags' $(if ($On) { '126' } else { '122' }) 'String'
            Set-Reg 'HKCU:\Control Panel\Accessibility\ToggleKeys' 'Flags' $(if ($On) { '62' } else { '58' }) 'String'
        }
    }
    @{
        Id = 'numlock'; Group = 'Keyboard & mouse'
        Name = 'Num Lock on at startup'
        Desc = 'num lock turns on by itself at the login screen.'
        Get = { @('2', '2147483650') -contains [string](Get-Reg 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard' 'InitialKeyboardIndicators') }
        Set = {
            param($On)
            $v = if ($On) { '2' } else { '0' }
            Set-Reg 'Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard' 'InitialKeyboardIndicators' $v 'String'
            Set-Reg 'HKCU:\Control Panel\Keyboard' 'InitialKeyboardIndicators' $v 'String'
        }
    }
)

# =================================================================
#  App catalog - one-click installs through winget.
#  Format: winget ID, display name, short description
# =================================================================
$AppCatalog = [ordered]@{
    'Browsers' = @(
        @('Mozilla.Firefox', 'Firefox', 'good for privacy, tons of extensions.'),
        @('Google.Chrome', 'Google Chrome', 'the usual.'),
        @('ImputNet.Helium', 'Helium', 'chromium with ublock built in, no google junk.')
    )
    'Gaming' = @(
        @('Valve.Steam', 'Steam', 'you know what steam is.'),
        @('EpicGames.EpicGamesLauncher', 'Epic Games Launcher', 'fortnite + free games every week.'),
        @('Blizzard.BattleNet', 'Battle.net', 'cod, overwatch, diablo, wow.'),
        @('ElectronicArts.EADesktop', 'EA app', 'battlefield, fc, apex, sims.'),
        @('Ubisoft.Connect', 'Ubisoft Connect', 'assassin''s creed, r6, far cry.'),
        @('Guru3D.Afterburner', 'MSI Afterburner', 'gpu overclocking and fan curves.'),
        @('Guru3D.RTSS', 'RivaTuner Statistics Server', 'fps limiter + the stats overlay.'),
        @('ViGEm.ViGEmBus', 'ViGEmBus', 'controller driver a lot of controller tools need.')
    )
    'Chat & media' = @(
        @('Discord.Discord', 'Discord', 'talk to your friends.'),
        @('Telegram.TelegramDesktop', 'Telegram', 'messaging.'),
        @('VideoLAN.VLC', 'VLC', 'plays literally any video file.'),
        @('OBSProject.OBSStudio', 'OBS Studio', 'record or stream your screen.'),
        @('HandBrake.HandBrake', 'HandBrake', 'shrink and convert videos.')
    )
    'Utilities' = @(
        @('7zip.7zip', '7-Zip', 'opens zips, rars, 7z, everything.'),
        @('Rufus.Rufus', 'Rufus', 'make a bootable windows usb.')
    )
    'Hardware & monitoring' = @(
        @('REALiX.HWiNFO', 'HWiNFO', 'every temp and sensor in your pc.'),
        @('CPUID.CPU-Z', 'CPU-Z', 'cpu, ram and motherboard info.'),
        @('TechPowerUp.GPU-Z', 'GPU-Z', 'gpu info and sensors.'),
        @('CrystalDewWorld.CrystalDiskInfo', 'CrystalDiskInfo', 'check if your drives are dying.'),
        @('CrystalDewWorld.CrystalDiskMark', 'CrystalDiskMark', 'test how fast your drives are.'),
        @('Logitech.GHUB', 'Logitech G HUB', 'for logitech stuff.'),
        @('Corsair.iCUE.5', 'Corsair iCUE', 'for corsair stuff.'),
        @('SteelSeries.GG', 'SteelSeries GG', 'for steelseries stuff.')
    )
    'Coding' = @(
        @('Microsoft.VisualStudioCode', 'VS Code', 'code editor.'),
        @('Git.Git', 'Git', 'version control.'),
        @('Python.Python.3.13', 'Python 3.13', 'python + pip.'),
        @('OpenJS.NodeJS.LTS', 'Node.js LTS', 'node + npm.'),
        @('Microsoft.WindowsTerminal', 'Windows Terminal', 'better terminal with tabs.')
    )
    'Runtimes (fixes missing dll errors)' = @(
        @('Microsoft.VCRedist.2015+.x64', 'Visual C++ Redist (x64)', 'most games need this.'),
        @('Microsoft.VCRedist.2015+.x86', 'Visual C++ Redist (x86)', '32 bit one, older games need it.'),
        @('Microsoft.DirectX', 'DirectX End-User Runtime', 'old directx dlls older games want.'),
        @('Microsoft.DotNet.DesktopRuntime.8', '.NET 8 Desktop Runtime', 'a lot of newer apps need it.'),
        @('Oracle.JavaRuntimeEnvironment', 'Java Runtime', 'for java apps.')
    )
}

$ScanCode = @'
param($sync, $HelperCode)
. ([scriptblock]::Create($HelperCode))
$winget = Find-Winget
if (-not $winget) { Send @{ T = 'installed'; Ids = $null; Error = 'nowinget' }; return }
$tmp = Join-Path $env:TEMP ('splat-winget-{0}.json' -f [guid]::NewGuid())
try {
    $null = & $winget export -o $tmp --source winget --accept-source-agreements --disable-interactivity 2>&1
    $ids = @()
    if (Test-Path -LiteralPath $tmp) {
        $j = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
        $ids = @($j.Sources | ForEach-Object { $_.Packages } | ForEach-Object { $_.PackageIdentifier })
    }
    Send @{ T = 'installed'; Ids = $ids }
} catch {
    Send @{ T = 'installed'; Ids = $null; Error = $_.Exception.Message }
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
'@

$AppCode = @'
param($sync, $HelperCode, $job)
. ([scriptblock]::Create($HelperCode))
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
Log ''
Log $job.Title 'head'
$winget = Find-Winget
if (-not $winget) {
    Log '    x winget is not available yet. Open the Microsoft Store, update "App Installer", then try again.' 'error'
    Send @{ T = 'app'; Id = $job.Id; S = 'failed' }
    return
}
if ($job.Id -eq '__upgrade') {
    $code = Invoke-Native $winget @('upgrade', '--all', '--source', 'winget', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if ($code -eq 0) { Ok 'Everything is up to date.' } else { Log "    ! winget exited with code $code - some apps may need updating by hand." 'warn' }
    Send @{ T = 'app'; Id = $job.Id; S = 'done' }
} else {
    $code = Invoke-Native $winget @('install', '--id', $job.Id, '--exact', '--source', 'winget', '--silent', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity')
    if ($code -eq 0 -or $code -eq -1978335189 -or $code -eq -1978335135) {
        Ok "$($job.Name) installed."
        Send @{ T = 'app'; Id = $job.Id; S = 'installed' }
    } else {
        Log "    x winget exited with code $code." 'error'
        Send @{ T = 'app'; Id = $job.Id; S = 'failed' }
    }
}
'@

# =================================================================
#  Background worker - runs the selected tasks off the UI thread
# =================================================================
$WorkerCode = @'
param($sync, $jobs, $HelperCode, $Config)
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'Continue'
try {
    . ([scriptblock]::Create($HelperCode))
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    $needExplorer = $false
    $total = $jobs.Count
    for ($i = 0; $i -lt $total; $i++) {
        $job = $jobs[$i]
        if ($sync.Cancel) {
            Log ''
            Log "Stopped - skipped $($total - $i) remaining task(s)." 'warn'
            break
        }
        Send @{ T = 'step'; Index = $i; Total = $total; Id = $job.Id; Name = $job.Name }
        if ($i -gt 0) { Log '' }
        Log $job.Name 'head'
        $global:SplatWarnings = 0
        $state = 'ok'
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $null = & ([scriptblock]::Create($job.Code)) $job.Option
            if ($global:SplatWarnings -gt 0) { $state = 'warn' }
        } catch {
            Log "    x $($_.Exception.Message)" 'error'
            $state = 'fail'
        }
        if ($sw.Elapsed.TotalSeconds -ge 5) { Info ('took {0:N0}s' -f $sw.Elapsed.TotalSeconds) }
        if ($job.Explorer -and $state -ne 'fail') { $needExplorer = $true }
        Send @{ T = 'done'; Index = $i; Total = $total; Id = $job.Id; State = $state; Reboot = $job.Reboot }
    }
    if ($needExplorer) { Restart-Explorer }
} catch {
    Send @{ T = 'log'; Text = "Unexpected error: $($_.Exception.Message)"; L = 'error' }
} finally {
    $sync.Finished = $true
}
'@

# =================================================================
#  Motion + window material (C#)
#  Springs are described the Apple way: damping (1 = no overshoot,
#  lower = bouncier) and response (roughly how fast, in seconds).
#  Every animation starts from the value currently on screen, so
#  anything can be interrupted and redirected mid-flight.
# =================================================================
Add-Type -ReferencedAssemblies PresentationCore, PresentationFramework, WindowsBase, System.Xaml -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
namespace Splat {
    public class SpringEase : EasingFunctionBase {
        public static readonly DependencyProperty DampingProperty = DependencyProperty.Register("Damping", typeof(double), typeof(SpringEase), new PropertyMetadata(1.0));
        public static readonly DependencyProperty ResponseProperty = DependencyProperty.Register("Response", typeof(double), typeof(SpringEase), new PropertyMetadata(0.35));
        public double Damping { get { return (double)GetValue(DampingProperty); } set { SetValue(DampingProperty, value); } }
        public double Response { get { return (double)GetValue(ResponseProperty); } set { SetValue(ResponseProperty, value); } }
        public SpringEase() { EasingMode = EasingMode.EaseIn; }
        protected override double EaseInCore(double t) {
            if (t >= 1) return 1;
            return Motion.Curve(Damping, Response, t * Motion.Settle(Damping, Response));
        }
        protected override Freezable CreateInstanceCore() { return new SpringEase(); }
    }

    public static class Motion {
        public static bool Enabled = true;

        // time for the spring to settle within 0.1% of its target
        public static double Settle(double damping, double response) {
            double w = 2 * Math.PI / response;
            if (damping >= 1) return 9.3 / w;
            return 6.9 / (damping * w);
        }

        // step response of a spring released from rest
        public static double Curve(double damping, double response, double t) {
            double w = 2 * Math.PI / response;
            if (damping >= 1) return 1 - (1 + w * t) * Math.Exp(-w * t);
            double wd = w * Math.Sqrt(1 - damping * damping);
            return 1 - Math.Exp(-damping * w * t) * (Math.Cos(wd * t) + (damping * w / wd) * Math.Sin(wd * t));
        }

        public static void To(IAnimatable target, DependencyProperty dp, double to, double damping, double response) {
            To(target, dp, to, damping, response, null);
        }
        public static void To(IAnimatable target, DependencyProperty dp, double to, double damping, double response, EventHandler done) {
            if (!Enabled) {
                Snap(target, dp, to);
                if (done != null) done(null, EventArgs.Empty);
                return;
            }
            var a = new DoubleAnimation(to, new Duration(TimeSpan.FromSeconds(Settle(damping, response))));
            var ease = new SpringEase();
            ease.Damping = damping;
            ease.Response = response;
            a.EasingFunction = ease;
            if (done != null) a.Completed += done;
            target.BeginAnimation(dp, a, HandoffBehavior.SnapshotAndReplace);
        }
        public static void Snap(IAnimatable target, DependencyProperty dp, double value) {
            target.BeginAnimation(dp, null);
            ((DependencyObject)target).SetValue(dp, value);
        }

        // Dips the instant the pointer goes down, springs back on release.
        public static void Press(UIElement el, double scale) {
            el.RenderTransformOrigin = new Point(0.5, 0.5);
            var st = new ScaleTransform(1, 1);
            el.RenderTransform = st;
            el.PreviewMouseLeftButtonDown += (s, e) => { To(st, ScaleTransform.ScaleXProperty, scale, 1, 0.15); To(st, ScaleTransform.ScaleYProperty, scale, 1, 0.15); };
            el.PreviewMouseLeftButtonUp += (s, e) => Release(st);
            el.MouseLeave += (s, e) => Release(st);
            el.LostMouseCapture += (s, e) => Release(st);
        }
        static void Release(ScaleTransform st) {
            To(st, ScaleTransform.ScaleXProperty, 1, 1, 0.3);
            To(st, ScaleTransform.ScaleYProperty, 1, 1, 0.3);
        }
    }

    public static class Glass {
        [StructLayout(LayoutKind.Sequential)] struct MARGINS { public int L, R, T, B; }
        [DllImport("dwmapi.dll")] static extern int DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS m);
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        public static void DarkTitleBar(IntPtr hwnd) { int on = 1; DwmSetWindowAttribute(hwnd, 20, ref on, 4); }
        // Windows 11 Mica behind the whole window; content draws its own solid surfaces on top
        public static bool EnableMica(IntPtr hwnd) {
            var m = new MARGINS { L = -1, R = -1, T = -1, B = -1 };
            if (DwmExtendFrameIntoClientArea(hwnd, ref m) != 0) return false;
            int mica = 2;
            return DwmSetWindowAttribute(hwnd, 38, ref mica, 4) == 0;
        }
    }
}
'@

# =================================================================
#  XAML
# =================================================================
$ResXaml = @'
<SolidColorBrush x:Key="Bg" Color="#1C1C1E"/>
<SolidColorBrush x:Key="SideBg" Color="#232326"/>
<SolidColorBrush x:Key="Group" Color="#2C2C2E"/>
<SolidColorBrush x:Key="Hover" Color="#10FFFFFF"/>
<SolidColorBrush x:Key="Press" Color="#1EFFFFFF"/>
<SolidColorBrush x:Key="Sep" Color="#3A3A3C"/>
<SolidColorBrush x:Key="Text" Color="#F5F5F7"/>
<SolidColorBrush x:Key="Text2" Color="#98989D"/>
<SolidColorBrush x:Key="Text3" Color="#6C6C70"/>
<SolidColorBrush x:Key="Accent" Color="#0A84FF"/>
<SolidColorBrush x:Key="AccentHover" Color="#3395FF"/>
<SolidColorBrush x:Key="AccentPress" Color="#0071E3"/>
<SolidColorBrush x:Key="Tint" Color="#2E0A84FF"/>
<SolidColorBrush x:Key="TintHover" Color="#400A84FF"/>
<SolidColorBrush x:Key="TintPress" Color="#550A84FF"/>
<SolidColorBrush x:Key="TintText" Color="#5AAAFF"/>
<SolidColorBrush x:Key="Good" Color="#30D158"/>
<SolidColorBrush x:Key="Warn" Color="#FF9F0A"/>
<SolidColorBrush x:Key="Bad" Color="#FF453A"/>
<SolidColorBrush x:Key="Fill" Color="#3A3A3C"/>
<SolidColorBrush x:Key="Fill2" Color="#48484A"/>
<SolidColorBrush x:Key="Fill3" Color="#545458"/>
<SolidColorBrush x:Key="Sel" Color="#22FFFFFF"/>
<SolidColorBrush x:Key="LogBg" Color="#161618"/>
<SolidColorBrush x:Key="SegTrack" Color="#1E1E20"/>
<SolidColorBrush x:Key="SegThumb" Color="#5A5A5E"/>

<s:SpringEase x:Key="Quick" Damping="1" Response="0.2"/>
<s:SpringEase x:Key="Std" Damping="1" Response="0.32"/>
<s:SpringEase x:Key="Slide" Damping="0.86" Response="0.3"/>
<s:SpringEase x:Key="Pop" Damping="0.7" Response="0.3"/>

<!-- a checklist row: circle check that pops in, hover + press highlight -->
<Style x:Key="RowCheck" TargetType="CheckBox">
  <Setter Property="Foreground" Value="{StaticResource Text}"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="CheckBox">
        <Grid x:Name="Root" Background="Transparent">
          <Border x:Name="Hl" CornerRadius="7" Background="{StaticResource Hover}" Opacity="0"/>
          <Grid Margin="12,11,14,11">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Grid Width="20" Height="20" VerticalAlignment="Top" Margin="0,1,14,0">
              <Ellipse x:Name="Ring" Stroke="{StaticResource Text3}" StrokeThickness="1.5"/>
              <Grid x:Name="On" Opacity="0" RenderTransformOrigin="0.5,0.5">
                <Grid.RenderTransform><ScaleTransform ScaleX="0.5" ScaleY="0.5"/></Grid.RenderTransform>
                <Ellipse Fill="{StaticResource Accent}"/>
                <Path Data="M5.6,10.3 L8.6,13.2 L14.4,7.1" Stroke="White" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
              </Grid>
            </Grid>
            <ContentPresenter Grid.Column="1"/>
          </Grid>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Trigger.EnterActions><BeginStoryboard><Storyboard>
              <DoubleAnimation Storyboard.TargetName="Hl" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.296" EasingFunction="{StaticResource Quick}"/>
            </Storyboard></BeginStoryboard></Trigger.EnterActions>
            <Trigger.ExitActions><BeginStoryboard><Storyboard>
              <DoubleAnimation Storyboard.TargetName="Hl" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.474" EasingFunction="{StaticResource Std}"/>
            </Storyboard></BeginStoryboard></Trigger.ExitActions>
          </Trigger>
          <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="Hl" Property="Background" Value="{StaticResource Press}"/>
          </Trigger>
          <Trigger Property="IsChecked" Value="True">
            <Setter TargetName="Ring" Property="Stroke" Value="{StaticResource Accent}"/>
            <Trigger.EnterActions><BeginStoryboard><Storyboard>
              <DoubleAnimation Storyboard.TargetName="On" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.296" EasingFunction="{StaticResource Quick}"/>
              <DoubleAnimation Storyboard.TargetName="On" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="1" Duration="0:0:0.471" EasingFunction="{StaticResource Pop}"/>
              <DoubleAnimation Storyboard.TargetName="On" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="1" Duration="0:0:0.471" EasingFunction="{StaticResource Pop}"/>
            </Storyboard></BeginStoryboard></Trigger.EnterActions>
            <Trigger.ExitActions><BeginStoryboard><Storyboard>
              <DoubleAnimation Storyboard.TargetName="On" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.296" EasingFunction="{StaticResource Quick}"/>
              <DoubleAnimation Storyboard.TargetName="On" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleX)" To="0.5" Duration="0:0:0.296" EasingFunction="{StaticResource Quick}"/>
              <DoubleAnimation Storyboard.TargetName="On" Storyboard.TargetProperty="(UIElement.RenderTransform).(ScaleTransform.ScaleY)" To="0.5" Duration="0:0:0.296" EasingFunction="{StaticResource Quick}"/>
            </Storyboard></BeginStoryboard></Trigger.ExitActions>
          </Trigger>
          <Trigger Property="IsEnabled" Value="False">
            <Setter TargetName="Root" Property="Opacity" Value="0.5"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style x:Key="NavItem" TargetType="RadioButton">
  <Setter Property="Foreground" Value="{StaticResource Text}"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Margin" Value="0,0,0,1"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="RadioButton">
        <Grid Background="Transparent">
          <Border x:Name="Hl" CornerRadius="7" Background="{StaticResource Hover}" Opacity="0"/>
          <ContentPresenter Margin="8,6,10,6"/>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True">
            <Trigger.EnterActions><BeginStoryboard><Storyboard>
              <DoubleAnimation Storyboard.TargetName="Hl" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.296" EasingFunction="{StaticResource Quick}"/>
            </Storyboard></BeginStoryboard></Trigger.EnterActions>
            <Trigger.ExitActions><BeginStoryboard><Storyboard>
              <DoubleAnimation Storyboard.TargetName="Hl" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.474" EasingFunction="{StaticResource Std}"/>
            </Storyboard></BeginStoryboard></Trigger.ExitActions>
          </Trigger>
          <Trigger Property="IsPressed" Value="True">
            <Setter TargetName="Hl" Property="Background" Value="{StaticResource Press}"/>
          </Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style x:Key="Btn" TargetType="Button">
  <Setter Property="Foreground" Value="{StaticResource Text}"/>
  <Setter Property="Background" Value="{StaticResource Fill}"/>
  <Setter Property="Padding" Value="16,6"/>
  <Setter Property="FontSize" Value="13"/>
  <Setter Property="HorizontalContentAlignment" Value="Center"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.4"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource Fill2}"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{StaticResource Fill3}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="PrimaryBtn" TargetType="Button" BasedOn="{StaticResource Btn}">
  <Setter Property="Background" Value="{StaticResource Accent}"/>
  <Setter Property="Foreground" Value="White"/>
  <Setter Property="FontWeight" Value="Medium"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource AccentHover}"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{StaticResource AccentPress}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="TintBtn" TargetType="Button" BasedOn="{StaticResource Btn}">
  <Setter Property="Background" Value="{StaticResource Tint}"/>
  <Setter Property="Foreground" Value="{StaticResource TintText}"/>
  <Setter Property="FontWeight" Value="Medium"/>
  <Setter Property="Padding" Value="12,8"/>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource TintHover}"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{StaticResource TintPress}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="PlainBtn" TargetType="Button">
  <Setter Property="Foreground" Value="{StaticResource Accent}"/>
  <Setter Property="FontSize" Value="12.5"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="Bd" Background="Transparent" Padding="2,1"><ContentPresenter VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsPressed" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.55"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.35"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{StaticResource AccentHover}"/></Trigger>
  </Style.Triggers>
</Style>

<!-- App Store style capsule -->
<Style x:Key="GetBtn" TargetType="Button">
  <Setter Property="Foreground" Value="{StaticResource Accent}"/>
  <Setter Property="Background" Value="{StaticResource Fill}"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="FontWeight" Value="Bold"/>
  <Setter Property="MinWidth" Value="64"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="13" Padding="14,4">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.5"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="{StaticResource Fill2}"/></Trigger>
    <Trigger Property="IsPressed" Value="True"><Setter Property="Background" Value="{StaticResource Fill3}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="SegItem" TargetType="RadioButton">
  <Setter Property="Foreground" Value="{StaticResource Text2}"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="RadioButton">
        <Border Background="Transparent" Padding="16,4"><ContentPresenter HorizontalAlignment="Center"/></Border>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
  <Style.Triggers>
    <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="{StaticResource Text}"/></Trigger>
    <Trigger Property="IsChecked" Value="True"><Setter Property="Foreground" Value="{StaticResource Text}"/></Trigger>
  </Style.Triggers>
</Style>

<Style x:Key="Switch" TargetType="ToggleButton">
  <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ToggleButton">
        <Grid x:Name="Root" Width="42" Height="24" Background="Transparent">
          <Border x:Name="Track" CornerRadius="12" Background="{StaticResource Fill2}"/>
          <Border x:Name="OnTrack" CornerRadius="12" Background="{StaticResource Accent}" Opacity="0"/>
          <Ellipse x:Name="Knob" Width="20" Height="20" Fill="White" HorizontalAlignment="Left" Margin="2,0,0,0">
            <Ellipse.RenderTransform><TranslateTransform X="0"/></Ellipse.RenderTransform>
            <Ellipse.Effect><DropShadowEffect BlurRadius="4" ShadowDepth="1" Direction="270" Opacity="0.3"/></Ellipse.Effect>
          </Ellipse>
        </Grid>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Track" Property="Background" Value="{StaticResource Fill3}"/></Trigger>
          <Trigger Property="IsPressed" Value="True"><Setter TargetName="Knob" Property="Fill" Value="#E5E5EA"/></Trigger>
          <Trigger Property="IsChecked" Value="True">
            <Trigger.EnterActions><BeginStoryboard><Storyboard>
              <DoubleAnimation Storyboard.TargetName="OnTrack" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.296" EasingFunction="{StaticResource Quick}"/>
              <DoubleAnimation Storyboard.TargetName="Knob" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" To="18" Duration="0:0:0.383" EasingFunction="{StaticResource Slide}"/>
            </Storyboard></BeginStoryboard></Trigger.EnterActions>
            <Trigger.ExitActions><BeginStoryboard><Storyboard>
              <DoubleAnimation Storyboard.TargetName="OnTrack" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.296" EasingFunction="{StaticResource Quick}"/>
              <DoubleAnimation Storyboard.TargetName="Knob" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" To="0" Duration="0:0:0.383" EasingFunction="{StaticResource Slide}"/>
            </Storyboard></BeginStoryboard></Trigger.ExitActions>
          </Trigger>
          <Trigger Property="IsChecked" Value="{x:Null}"><Setter TargetName="Knob" Property="Opacity" Value="0.55"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Root" Property="Opacity" Value="0.4"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style x:Key="SearchBox" TargetType="TextBox">
  <Setter Property="Foreground" Value="{StaticResource Text}"/>
  <Setter Property="CaretBrush" Value="{StaticResource Text}"/>
  <Setter Property="SelectionBrush" Value="{StaticResource Accent}"/>
  <Setter Property="FontSize" Value="13"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="TextBox">
        <Border x:Name="Bd" Background="{StaticResource Group}" BorderBrush="Transparent" BorderThickness="1.5" CornerRadius="8" Padding="9,5">
          <Grid>
            <TextBlock Text="&#xE721;" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="12" Foreground="{StaticResource Text3}" VerticalAlignment="Center"/>
            <TextBlock x:Name="Ph" Text="search" Foreground="{StaticResource Text3}" Margin="24,0,0,0" Visibility="Collapsed" IsHitTestVisible="False" VerticalAlignment="Center"/>
            <ScrollViewer x:Name="PART_ContentHost" Margin="22,0,0,0" VerticalAlignment="Center"/>
          </Grid>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="Text" Value=""><Setter TargetName="Ph" Property="Visibility" Value="Visible"/></Trigger>
          <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style TargetType="ProgressBar">
  <Setter Property="Height" Value="4"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ProgressBar">
        <Grid>
          <Border x:Name="PART_Track" CornerRadius="2" Background="{StaticResource Fill}"/>
          <Border x:Name="PART_Indicator" CornerRadius="2" Background="{StaticResource Accent}" HorizontalAlignment="Left"/>
        </Grid>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style TargetType="ScrollBar">
  <Setter Property="Width" Value="10"/>
  <Setter Property="MinWidth" Value="10"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ScrollBar">
        <Grid Background="Transparent">
          <Track x:Name="PART_Track" IsDirectionReversed="True">
            <Track.Thumb>
              <Thumb>
                <Thumb.Template>
                  <ControlTemplate TargetType="Thumb">
                    <Border CornerRadius="3" Background="#4A4A4E" Margin="3,2"/>
                  </ControlTemplate>
                </Thumb.Template>
              </Thumb>
            </Track.Thumb>
          </Track>
        </Grid>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>

<Style TargetType="ToolTip">
  <Setter Property="Foreground" Value="{StaticResource Text}"/>
  <Setter Property="FontSize" Value="12"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="ToolTip">
        <Border Background="#2C2C2E" BorderBrush="#48484A" BorderThickness="1" CornerRadius="7" Padding="10,7" MaxWidth="440">
          <ContentPresenter/>
        </Border>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
'@

$MainXamlBody = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:s="clr-namespace:Splat;assembly=__SPRINGASM__"
        Title="Splat's Optimizer" Width="1120" Height="780" MinWidth="940" MinHeight="620"
        WindowStartupLocation="CenterScreen" Background="#1C1C1E" Foreground="#F5F5F7"
        FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="13"
        UseLayoutRounding="True" SnapsToDevicePixels="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    __RESOURCES__
  </Window.Resources>
  <Grid x:Name="Root">
    <Grid x:Name="AppRoot" RenderTransformOrigin="0.5,0.5">
      <Grid.RenderTransform><ScaleTransform/></Grid.RenderTransform>
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="248"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Sidebar: Mica shows through here -->
      <Border x:Name="Sidebar" Background="{StaticResource SideBg}">
        <Grid Margin="12,14,12,16">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Orientation="Horizontal" Margin="8,2,0,20">
            <Border x:Name="Logo" Width="38" Height="38" CornerRadius="10" Background="{StaticResource Fill}" VerticalAlignment="Top"/>
            <StackPanel Margin="11,1,0,0" VerticalAlignment="Center">
              <TextBlock Text="Splat's Optimizer" FontWeight="Medium" FontSize="15" TextOptions.TextFormattingMode="Ideal"/>
              <TextBlock Text="we will steal your data and sell it to the black market :)" Foreground="{StaticResource Text2}" FontSize="11" TextWrapping="Wrap" Width="160" Margin="0,2,0,0"/>
            </StackPanel>
          </StackPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
            <Grid>
              <Border x:Name="NavIndicator" VerticalAlignment="Top" CornerRadius="7" Background="{StaticResource Sel}" Height="34" Opacity="0">
                <Border.RenderTransform><TranslateTransform/></Border.RenderTransform>
              </Border>
              <StackPanel x:Name="NavPanel"/>
            </Grid>
          </ScrollViewer>
          <StackPanel Grid.Row="2" Margin="0,14,0,0">
            <Button x:Name="PresetBtn" Style="{StaticResource TintBtn}" Content="Splat's Selection"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10,0,0">
              <Button x:Name="LastBtn" Style="{StaticResource PlainBtn}" Content="Last run"/>
              <TextBlock Text="&#x00B7;" Foreground="{StaticResource Text3}" Margin="9,0" VerticalAlignment="Center"/>
              <Button x:Name="AllBtn" Style="{StaticResource PlainBtn}" Content="All"/>
              <TextBlock Text="&#x00B7;" Foreground="{StaticResource Text3}" Margin="9,0" VerticalAlignment="Center"/>
              <Button x:Name="NoneBtn" Style="{StaticResource PlainBtn}" Content="Clear"/>
            </StackPanel>
          </StackPanel>
        </Grid>
      </Border>

      <!-- Content -->
      <Grid Grid.Column="1" Background="{StaticResource Bg}">
        <Grid.RowDefinitions>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <ScrollViewer x:Name="ContentScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
          <Grid x:Name="ContentHost" Margin="40,30,36,40" MaxWidth="820" HorizontalAlignment="Stretch"/>
        </ScrollViewer>
        <!-- scroll edge: content fades out under the toolbar instead of a hard cut -->
        <Rectangle Height="26" VerticalAlignment="Bottom" IsHitTestVisible="False">
          <Rectangle.Fill>
            <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
              <GradientStop Color="#001C1C1E" Offset="0"/>
              <GradientStop Color="#FF1C1C1E" Offset="1"/>
            </LinearGradientBrush>
          </Rectangle.Fill>
        </Rectangle>

        <!-- Activity log: a sheet that rises from the bottom -->
        <Border x:Name="LogPanel" Grid.Row="1" Height="0" Background="{StaticResource LogBg}" ClipToBounds="True">
          <DockPanel>
            <Border DockPanel.Dock="Top" Height="1" Background="{StaticResource Sep}"/>
            <DockPanel DockPanel.Dock="Top" Margin="24,10,20,6">
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                <Button x:Name="OpenLogsBtn" Style="{StaticResource PlainBtn}" Content="Open logs folder" Margin="0,0,16,0"/>
                <Button x:Name="HideLogBtn" Style="{StaticResource PlainBtn}" Content="Hide"/>
              </StackPanel>
              <TextBlock Text="Activity" FontWeight="Medium" FontSize="12.5" Foreground="{StaticResource Text2}" VerticalAlignment="Center"/>
            </DockPanel>
            <RichTextBox x:Name="LogBox" IsReadOnly="True" Background="Transparent" BorderThickness="0"
                         Foreground="{StaticResource Text}" FontFamily="Cascadia Mono, Consolas" FontSize="11.5"
                         Padding="20,0,20,12" VerticalScrollBarVisibility="Auto">
              <FlowDocument PagePadding="0" FontFamily="Cascadia Mono, Consolas" FontSize="11.5"/>
            </RichTextBox>
          </DockPanel>
        </Border>

        <!-- Toolbar -->
        <Border Grid.Row="2" Background="{StaticResource Bg}" BorderBrush="{StaticResource Sep}" BorderThickness="0,1,0,0" Padding="24,12,20,12">
          <DockPanel>
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
              <Button x:Name="LogToggleBtn" Style="{StaticResource PlainBtn}" Content="Show log" Margin="0,0,18,0" VerticalAlignment="Center"/>
              <Button x:Name="CancelBtn" Style="{StaticResource Btn}" Content="Stop after this one" Visibility="Collapsed" Margin="0,0,8,0"/>
              <Button x:Name="RevertBtn" Style="{StaticResource Btn}" Content="Undo" MinWidth="80" Margin="0,0,8,0"/>
              <Button x:Name="ApplyBtn" Style="{StaticResource PrimaryBtn}" Content="Apply" MinWidth="112"/>
            </StackPanel>
            <Grid VerticalAlignment="Center" Margin="0,0,24,0">
              <StackPanel x:Name="SelectionInfo" Orientation="Horizontal">
                <TextBlock x:Name="SelCount" FontWeight="Medium"/>
                <TextBlock x:Name="SelNote" Foreground="{StaticResource Warn}" Margin="8,0,0,0"/>
              </StackPanel>
              <StackPanel x:Name="ProgressInfo" Visibility="Collapsed">
                <DockPanel>
                  <TextBlock x:Name="ProgressCount" DockPanel.Dock="Right" Foreground="{StaticResource Text2}" FontSize="12" Margin="12,0,0,0"/>
                  <TextBlock x:Name="ProgressText" FontSize="12" TextTrimming="CharacterEllipsis"/>
                </DockPanel>
                <ProgressBar x:Name="Progress" Margin="0,7,0,0" Maximum="100"/>
              </StackPanel>
            </Grid>
          </DockPanel>
        </Border>
      </Grid>
    </Grid>

    <!-- Dialogs live inside the window: the app recedes, the card materializes -->
    <Grid x:Name="DialogLayer" Visibility="Collapsed">
      <Border x:Name="Scrim" Background="#99000000" Opacity="0"/>
      <Border x:Name="DialogCard" Width="460" HorizontalAlignment="Center" VerticalAlignment="Center"
              Background="#2C2C2E" BorderBrush="#3DFFFFFF" BorderThickness="0,1,0,0" CornerRadius="14"
              RenderTransformOrigin="0.5,0.5" Opacity="0">
        <Border.RenderTransform><ScaleTransform ScaleX="0.92" ScaleY="0.92"/></Border.RenderTransform>
        <Border.Effect><DropShadowEffect BlurRadius="44" ShadowDepth="14" Direction="270" Opacity="0.55"/></Border.Effect>
        <StackPanel Margin="24,22,24,20">
          <TextBlock x:Name="DTitle" FontSize="17" FontWeight="Medium" TextWrapping="Wrap" TextOptions.TextFormattingMode="Ideal"/>
          <TextBlock x:Name="DBody" Foreground="{StaticResource Text2}" TextWrapping="Wrap" Margin="0,6,0,0" LineHeight="19"/>
          <Border x:Name="DListWrap" Background="#1C1C1E" CornerRadius="9" Margin="0,14,0,0" Visibility="Collapsed">
            <ScrollViewer MaxHeight="250" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
              <StackPanel x:Name="DList" Margin="14,8"/>
            </ScrollViewer>
          </Border>
          <StackPanel x:Name="DWarn" Margin="0,12,0,0"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
            <Button x:Name="DNo" Style="{StaticResource Btn}" MinWidth="92"/>
            <Button x:Name="DYes" Style="{StaticResource PrimaryBtn}" MinWidth="92" Margin="8,0,0,0"/>
          </StackPanel>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

# =================================================================
#  Build the window
# =================================================================
$SpringAsm = [Splat.SpringEase].Assembly.GetName().Name
try {
    $window = [Windows.Markup.XamlReader]::Parse($MainXamlBody.Replace('__RESOURCES__', $ResXaml).Replace('__SPRINGASM__', $SpringAsm))
} catch {
    [void][Windows.MessageBox]::Show("Couldn't build the window:`n`n$($_.Exception.Message)", "Splat's Optimizer")
    exit 1
}

$ui = @{}
foreach ($m in [regex]::Matches($MainXamlBody, 'x:Name="(\w+)"')) { $ui[$m.Groups[1].Value] = $window.FindName($m.Groups[1].Value) }
$B = @{}
foreach ($k in $window.Resources.Keys) { if ($window.Resources[$k] -is [Windows.Media.SolidColorBrush]) { $B[$k] = $window.Resources[$k] } }
$IconFont    = New-Object Windows.Media.FontFamily 'Segoe Fluent Icons, Segoe MDL2 Assets'
# Google Sans ships in assets\fonts (OFL). Falls back to Segoe if the folder is missing.
$FontBase    = New-Object Uri (($FontDir.TrimEnd('\')) + '\')
$FontUI      = New-Object Windows.Media.FontFamily $FontBase, './#Google Sans, Segoe UI Variable Text, Segoe UI'
$FontDisplay = New-Object Windows.Media.FontFamily $FontBase, './#Google Sans 17pt Text, ./#Google Sans, Segoe UI Variable Display, Segoe UI'
$FontSmall   = $FontUI
$window.FontFamily = $FontUI
$FontMono    = New-Object Windows.Media.FontFamily 'Cascadia Mono, Consolas'
$Dot = [char]0x00B7

# Windows' own "animation effects" setting is off on PCs this tool has optimized, so the
# app keeps its (small, calm) motion on regardless. Flip this to $false to turn it off.
[Splat.Motion]::Enabled = $true

$P = @{
    Opacity = [Windows.UIElement]::OpacityProperty
    X       = [Windows.Media.TranslateTransform]::XProperty
    Y       = [Windows.Media.TranslateTransform]::YProperty
    SX      = [Windows.Media.ScaleTransform]::ScaleXProperty
    SY      = [Windows.Media.ScaleTransform]::ScaleYProperty
    Height  = [Windows.FrameworkElement]::HeightProperty
    Value   = [Windows.Controls.Primitives.RangeBase]::ValueProperty
    Angle   = [Windows.Media.RotateTransform]::AngleProperty
}
function Anim($Target, [string]$Prop, [double]$To, [double]$Damping = 1, [double]$Response = 0.35, [EventHandler]$Done = $null) {
    if ($Done) { [Splat.Motion]::To($Target, $P[$Prop], $To, $Damping, $Response, $Done) }
    else { [Splat.Motion]::To($Target, $P[$Prop], $To, $Damping, $Response) }
}
function Snap($Target, [string]$Prop, [double]$Value) { [Splat.Motion]::Snap($Target, $P[$Prop], $Value) }

function Thk([double]$L, [double]$T = $L, [double]$R = $L, [double]$Bm = $T) { New-Object Windows.Thickness $L, $T, $R, $Bm }

function New-TextBlock {
    param([string]$Text, [double]$Size = 13, [string]$Brush = 'Text', [switch]$Bold, [switch]$Wrap, $Margin, [string]$Font)
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $Text
    $tb.FontSize = $Size
    if ($Brush) { $tb.Foreground = $B[$Brush] }
    if ($Bold) { $tb.FontWeight = [Windows.FontWeights]::Medium }
    if ($Wrap) { $tb.TextWrapping = 'Wrap' }
    if ($Margin) { $tb.Margin = $Margin }
    # set explicitly: tooltips live in their own popup and don't inherit the window font
    switch ($Font) {
        'display' { $tb.FontFamily = $FontDisplay; [Windows.Media.TextOptions]::SetTextFormattingMode($tb, 'Ideal') }
        'small'   { $tb.FontFamily = $FontSmall }
        'mono'    { $tb.FontFamily = $FontMono }
        default   { $tb.FontFamily = $FontUI }
    }
    return $tb
}

function New-TileBrush([string]$Hex) {
    $c = [Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $lift = { param($v) [byte]([math]::Min(255, $v + (255 - $v) * 0.22)) }
    $top = [Windows.Media.Color]::FromRgb((& $lift $c.R), (& $lift $c.G), (& $lift $c.B))
    $brush = New-Object Windows.Media.LinearGradientBrush $top, $c, 90
    $brush.Freeze()
    return $brush
}

function New-Spinner([double]$Size = 14) {
    $g = New-Object Windows.Controls.Grid
    $g.Width = $Size
    $g.Height = $Size
    $ring = New-Object Windows.Shapes.Ellipse
    $ring.Stroke = $B.Fill2
    $ring.StrokeThickness = 2
    $arc = New-Object Windows.Shapes.Path
    $c = $Size / 2
    $arc.Data = [Windows.Media.Geometry]::Parse(('M{0},1 A{1},{1} 0 0 1 {2},{0}' -f $c, ($c - 1), ($Size - 1)))
    $arc.Stroke = $B.Accent
    $arc.StrokeThickness = 2
    $arc.StrokeStartLineCap = 'Round'
    $arc.StrokeEndLineCap = 'Round'
    [void]$g.Children.Add($ring)
    [void]$g.Children.Add($arc)
    $g.RenderTransformOrigin = New-Object Windows.Point 0.5, 0.5
    $g.RenderTransform = New-Object Windows.Media.RotateTransform
    $g.Visibility = 'Collapsed'
    return $g
}
function Start-Spin($Spinner) {
    $Spinner.Visibility = 'Visible'
    $a = New-Object Windows.Media.Animation.DoubleAnimation
    $a.From = 0
    $a.To = 360
    $a.Duration = New-Object Windows.Duration ([TimeSpan]::FromSeconds(0.9))
    $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $Spinner.RenderTransform.BeginAnimation($P.Angle, $a)
}
function Stop-Spin($Spinner) {
    $Spinner.RenderTransform.BeginAnimation($P.Angle, $null)
    $Spinner.Visibility = 'Collapsed'
}

# Grouped list: one rounded container, rows separated by inset hairlines
function New-Group {
    $border = New-Object Windows.Controls.Border
    $border.Background = $B.Group
    $border.CornerRadius = New-Object Windows.CornerRadius 10
    $border.Padding = Thk 4
    $panel = New-Object Windows.Controls.StackPanel
    $border.Child = $panel
    return @{ Border = $border; Panel = $panel }
}
function Add-GroupRow($Grp, $El, [double]$Inset = 12) {
    if ($Grp.Panel.Children.Count) {
        $sep = New-Object Windows.Controls.Border
        $sep.Height = 1
        $sep.Background = $B.Sep
        $sep.Margin = Thk $Inset 0 12 0
        [void]$Grp.Panel.Children.Add($sep)
    }
    [void]$Grp.Panel.Children.Add($El)
}
function New-SectionHeader([string]$Text, [bool]$First = $false) {
    $t = New-TextBlock $Text 12.5 'Text2' -Bold
    $t.Margin = if ($First) { Thk 6 0 0 8 } else { Thk 6 24 0 8 }
    return $t
}

# ---- status text on the right of a checklist row
$StatusStyles = @{
    applied = @('already done', 'Good')
    partial = @('partly done', 'Warn')
    queued  = @('queued', 'Text3')
    running = @('running', 'Accent')
    ok      = @('done', 'Good')
    warn    = @('check log', 'Warn')
    fail    = @('failed', 'Bad')
}
function Set-Pill($it, [string]$State) {
    if ($State -eq 'running') { Start-Spin $it.Spinner } else { Stop-Spin $it.Spinner }
    if (-not $State -or -not $StatusStyles.ContainsKey($State)) { $it.Status.Visibility = 'Collapsed'; return }
    $s = $StatusStyles[$State]
    $it.StatusText.Text = $s[0]
    $it.StatusText.Foreground = $B[$s[1]]
    if ($it.Status.Visibility -ne 'Visible') {
        $it.Status.Visibility = 'Visible'
        Snap $it.Status 'Opacity' 0
        Anim $it.Status 'Opacity' 1 1 0.25
    }
}

# ---- segmented control (browser pick, update mode) with a sliding thumb
function Move-SegThumb($Thumb, $Row, [int]$Index, [int]$Count, [bool]$Instant) {
    $w = $Row.ActualWidth / $Count
    if ($w -le 0) { return }
    $Thumb.Width = $w
    if ($Instant) { Snap $Thumb.RenderTransform 'X' ($w * $Index) }
    else { Anim $Thumb.RenderTransform 'X' ($w * $Index) 1 0.3 }
}
function New-Segmented($it, $Card) {
    $track = New-Object Windows.Controls.Border
    $track.Background = $B.SegTrack
    $track.CornerRadius = New-Object Windows.CornerRadius 8
    $track.Padding = Thk 2
    $track.HorizontalAlignment = 'Left'
    $track.Margin = Thk 0 10 0 0
    $grid = New-Object Windows.Controls.Grid
    $thumb = New-Object Windows.Controls.Border
    $thumb.Background = $B.SegThumb
    $thumb.CornerRadius = New-Object Windows.CornerRadius 6
    $thumb.HorizontalAlignment = 'Left'
    $thumb.RenderTransform = New-Object Windows.Media.TranslateTransform
    $shadow = New-Object Windows.Media.Effects.DropShadowEffect
    $shadow.BlurRadius = 3; $shadow.ShadowDepth = 1; $shadow.Direction = 270; $shadow.Opacity = 0.25
    $thumb.Effect = $shadow
    $row = New-Object Windows.Controls.Primitives.UniformGrid
    $row.Rows = 1
    $row.Columns = $it.Options.Count
    $hint = New-TextBlock '' 12 'Text2' -Wrap -Margin (Thk 0 8 0 0)
    $hint.Visibility = 'Collapsed'
    $it.Chips = @()
    $i = 0
    foreach ($o in $it.Options) {
        $rb = New-Object Windows.Controls.RadioButton
        $rb.Style = $window.FindResource('SegItem')
        $rb.GroupName = "opt_$($it.Id)"
        $rb.Content = $o.Label
        $rb.Tag = @{ Key = $o.Key; Label = $o.Label; Index = $i; Count = $it.Options.Count; Thumb = $thumb; Row = $row; Hint = $hint; HintText = $o.Hint; Card = $Card }
        $rb.Add_Checked({
            $t = $this.Tag
            Move-SegThumb $t.Thumb $t.Row $t.Index $t.Count $false
            $t.Hint.Text = [string]$t.HintText
            $t.Hint.Visibility = if ($t.HintText) { 'Visible' } else { 'Collapsed' }
        })
        $rb.Add_Click({ $this.Tag.Card.IsChecked = $true })
        [void]$row.Children.Add($rb)
        $it.Chips += $rb
        $i++
    }
    $row.Tag = @{ Thumb = $thumb; Chips = $it.Chips }
    $row.Add_SizeChanged({
        $t = $this.Tag
        for ($j = 0; $j -lt $t.Chips.Count; $j++) {
            if ($t.Chips[$j].IsChecked) { Move-SegThumb $t.Thumb $this $j $t.Chips.Count $true }
        }
    })
    [void]$grid.Children.Add($thumb)
    [void]$grid.Children.Add($row)
    $track.Child = $grid
    return @{ Track = $track; Hint = $hint }
}
function Set-ItemOption($it, [string]$Key) {
    foreach ($c in $it.Chips) { if ($c.Tag.Key -eq $Key) { $c.IsChecked = $true } }
}
function Get-ItemOption($it, [switch]$Label) {
    if (-not $it.Chips) { return $null }
    $c = $it.Chips | Where-Object { $_.IsChecked } | Select-Object -First 1
    if (-not $c) { $c = $it.Chips[0] }
    if ($Label) { return $c.Tag.Label } else { return $c.Tag.Key }
}

# ---- one checklist row
function New-ItemRow($it) {
    $cb = New-Object Windows.Controls.CheckBox
    $cb.Style = $window.FindResource('RowCheck')
    $grid = New-Object Windows.Controls.Grid
    foreach ($w in 'Star', 'Auto') {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = if ($w -eq 'Star') { New-Object Windows.GridLength 1, 'Star' } else { [Windows.GridLength]::Auto }
        $grid.ColumnDefinitions.Add($cd)
    }
    $left = New-Object Windows.Controls.StackPanel
    $titleLine = New-Object Windows.Controls.WrapPanel
    [void]$titleLine.Children.Add((New-TextBlock $it.Name 13.5 'Text'))
    if ($it.OneWay) {
        $nu = New-TextBlock 'no undo' 11.5 'Warn' -Margin (Thk 8 0 0 0)
        $nu.VerticalAlignment = 'Center'
        [void]$titleLine.Children.Add($nu)
    }
    [void]$left.Children.Add($titleLine)
    $desc = New-TextBlock $it.Desc 12 'Text2' -Wrap -Margin (Thk 0 2 0 0)
    $desc.LineHeight = 17
    [void]$left.Children.Add($desc)
    if ($it.Warn) { [void]$left.Children.Add((New-TextBlock "$([char]0x26A0)  $($it.Warn)" 12 'Warn' -Wrap -Margin (Thk 0 6 0 0))) }
    if ($it.Options) {
        $seg = New-Segmented $it $cb
        [void]$left.Children.Add($seg.Track)
        [void]$left.Children.Add($seg.Hint)
        Set-ItemOption $it $it.Default
    }
    [void]$grid.Children.Add($left)

    $status = New-Object Windows.Controls.StackPanel
    $status.Orientation = 'Horizontal'
    $status.VerticalAlignment = 'Top'
    $status.Margin = Thk 14 1 0 0
    $status.Visibility = 'Collapsed'
    $spin = New-Spinner 12
    $spin.Margin = Thk 0 0 6 0
    $spin.VerticalAlignment = 'Center'
    $stText = New-TextBlock '' 12 'Text2'
    [void]$status.Children.Add($spin)
    [void]$status.Children.Add($stText)
    [Windows.Controls.Grid]::SetColumn($status, 1)
    [void]$grid.Children.Add($status)

    $cb.Content = $grid
    if ($it.Tip) {
        $cb.ToolTip = New-TextBlock $it.Tip 12 $null -Wrap
        [Windows.Controls.ToolTipService]::SetShowDuration($cb, 60000)
    }
    $cb.Add_Checked({ Update-Selection })
    $cb.Add_Unchecked({ Update-Selection })
    $it.Box = $cb
    $it.Status = $status
    $it.StatusText = $stText
    $it.Spinner = $spin
    return $cb
}

# ---- sidebar + pages
$Pages = [ordered]@{}
$PageOrder = New-Object System.Collections.Generic.List[string]
$NavItems = @{}
$script:CurrentPage = $null
$NavColors = @{ start = '#636366'; debloat = '#FF453A'; privacy = '#0A84FF'; updates = '#32ADE6'; perf = '#FF9F0A'; cleanup = '#30D158'; toggles = '#BF5AF2'; apps = '#5E5CE6' }

function New-NavHeader([string]$Text, [bool]$First = $false) {
    $t = New-TextBlock $Text 11.5 'Text3' -Bold
    $t.Margin = if ($First) { Thk 10 0 0 6 } else { Thk 10 18 0 6 }
    [void]$ui.NavPanel.Children.Add($t)
}

function New-NavItem([string]$Key, [string]$Name, [int]$Glyph, [string]$Color) {
    $nav = New-Object Windows.Controls.RadioButton
    $nav.Style = $window.FindResource('NavItem')
    $nav.GroupName = 'nav'
    $g = New-Object Windows.Controls.Grid
    foreach ($w in 'Auto', 'Star', 'Auto') {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = if ($w -eq 'Star') { New-Object Windows.GridLength 1, 'Star' } else { [Windows.GridLength]::Auto }
        $g.ColumnDefinitions.Add($cd)
    }
    $tile = New-Object Windows.Controls.Border
    $tile.Width = 22
    $tile.Height = 22
    $tile.CornerRadius = New-Object Windows.CornerRadius 6
    $tile.Background = New-TileBrush $Color
    $iconText = New-TextBlock ([string][char]$Glyph) 12 $null
    $iconText.Foreground = [Windows.Media.Brushes]::White
    $iconText.FontFamily = $IconFont
    $iconText.HorizontalAlignment = 'Center'
    $iconText.VerticalAlignment = 'Center'
    $tile.Child = $iconText
    $label = New-TextBlock $Name 13 $null -Margin (Thk 10 0 0 0)
    $label.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($label, 1)
    $count = New-TextBlock '' 12 'Text3'
    $count.VerticalAlignment = 'Center'
    [Windows.Controls.Grid]::SetColumn($count, 2)
    [void]$g.Children.Add($tile)
    [void]$g.Children.Add($label)
    [void]$g.Children.Add($count)
    $nav.Content = $g
    $nav.Tag = $Key
    $nav.Add_Checked({ Show-Category $this.Tag })
    [void]$ui.NavPanel.Children.Add($nav)
    $NavItems[$Key] = $nav
    return @{ Nav = $nav; Count = $count }
}

function Move-NavIndicator([switch]$Instant) {
    $nav = $NavItems[$script:CurrentPage]
    if (-not $nav -or $nav.ActualHeight -le 0) { return }
    $y = $nav.TranslatePoint((New-Object Windows.Point 0, 0), $ui.NavPanel).Y
    $ui.NavIndicator.Height = $nav.ActualHeight
    if ($Instant -or $ui.NavIndicator.Opacity -lt 0.5) {
        Snap $ui.NavIndicator.RenderTransform 'Y' $y
        Anim $ui.NavIndicator 'Opacity' 1 1 0.25
    } else {
        Anim $ui.NavIndicator.RenderTransform 'Y' $y 1 0.32
    }
}

function New-Page([string]$Key, [string]$Title, [string]$Desc, $Right) {
    $page = New-Object Windows.Controls.StackPanel
    $page.Visibility = 'Collapsed'
    $page.RenderTransform = New-Object Windows.Media.TranslateTransform
    $hdr = New-Object Windows.Controls.DockPanel
    $hdr.Margin = Thk 0 0 0 20
    if ($Right) {
        $Right.VerticalAlignment = 'Bottom'
        [Windows.Controls.DockPanel]::SetDock($Right, 'Right')
        [void]$hdr.Children.Add($Right)
    }
    $titles = New-Object Windows.Controls.StackPanel
    [void]$titles.Children.Add((New-TextBlock $Title 26 'Text' -Bold -Font 'display'))
    [void]$titles.Children.Add((New-TextBlock $Desc 13 'Text2' -Wrap -Margin (Thk 0 4 0 0)))
    [void]$hdr.Children.Add($titles)
    [void]$page.Children.Add($hdr)
    [void]$ui.ContentHost.Children.Add($page)
    $Pages[$Key] = $page
    $PageOrder.Add($Key)
    return $page
}

# Pages slide in from the direction you moved in the sidebar
function Show-Category([string]$Key) {
    $prev = $script:CurrentPage
    if ($prev -eq $Key) { return }
    $script:CurrentPage = $Key
    foreach ($k in $Pages.Keys) { if ($k -ne $Key) { $Pages[$k].Visibility = 'Collapsed' } }
    $page = $Pages[$Key]
    $page.Visibility = 'Visible'
    $ui.ContentScroll.ScrollToTop()
    $dir = 1
    if ($prev -and $PageOrder.IndexOf($Key) -lt $PageOrder.IndexOf($prev)) { $dir = -1 }
    Snap $page 'Opacity' 0
    Snap $page.RenderTransform 'Y' (16 * $dir)
    Anim $page 'Opacity' 1 1 0.28
    Anim $page.RenderTransform 'Y' 0 1 0.36
    Move-NavIndicator
    if ($Key -eq 'toggles') { Update-Toggles }
}

function New-LinkPair([string]$Key) {
    $sp = New-Object Windows.Controls.StackPanel
    $sp.Orientation = 'Horizontal'
    $sp.Margin = Thk 24 0 0 3
    $all = New-Object Windows.Controls.Button
    $all.Style = $window.FindResource('PlainBtn')
    $all.Content = 'Select all'
    $all.Tag = $Key
    $all.Add_Click({ Set-Category $this.Tag $true })
    $none = New-Object Windows.Controls.Button
    $none.Style = $window.FindResource('PlainBtn')
    $none.Content = 'Clear'
    $none.Tag = $Key
    $none.Margin = Thk 14 0 0 0
    $none.Add_Click({ Set-Category $this.Tag $false })
    [void]$sp.Children.Add($all)
    [void]$sp.Children.Add($none)
    return @{ Panel = $sp; All = $all; None = $none }
}

function New-InfoRow([string]$Key, [string]$Value) {
    $d = New-Object Windows.Controls.DockPanel
    $d.Margin = Thk 12 10 14 10
    $v = New-TextBlock $Value 13 'Text2'
    [Windows.Controls.DockPanel]::SetDock($v, 'Right')
    [void]$d.Children.Add($v)
    [void]$d.Children.Add((New-TextBlock $Key 13.5 'Text'))
    return $d
}

New-NavHeader 'Optimize' $true

foreach ($key in $Categories.Keys) {
    $cat = $Categories[$key]
    $n = New-NavItem $key $cat.Name $cat.Glyph $NavColors[$key]
    $links = $null
    if ($key -ne 'start') {
        $lp = New-LinkPair $key
        $links = $lp.Panel
        $cat.AllLink = $lp.All
        $cat.NoneLink = $lp.None
    }
    $page = New-Page $key $cat.Name $cat.Desc $links
    $grp = New-Group
    foreach ($it in @($Items | Where-Object { $_.Cat -eq $key })) { Add-GroupRow $grp (New-ItemRow $it) 46 }
    [void]$page.Children.Add($grp.Border)

    if ($key -eq 'start') {
        try {
            $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            $script:WinBuild = [int]$cv.CurrentBuild
            $prod = $cv.ProductName
            if ($script:WinBuild -ge 22000) { $prod = $prod -replace 'Windows 10', 'Windows 11' }
            [void]$page.Children.Add((New-SectionHeader 'This PC'))
            $info = New-Group
            Add-GroupRow $info (New-InfoRow 'Windows' "$prod $($cv.DisplayVersion)")
            Add-GroupRow $info (New-InfoRow 'Build' "$($cv.CurrentBuild).$($cv.UBR)")
            Add-GroupRow $info (New-InfoRow 'Running as' 'admin')
            $verRow = New-InfoRow 'Version' $AppVersion
            $UpdateBtn = New-Object Windows.Controls.Button
            $UpdateBtn.Style = $window.FindResource('PlainBtn')
            $UpdateBtn.Content = 'Check for updates'
            $UpdateBtn.Margin = Thk 16 0 0 0
            $UpdateBtn.Add_Click({ Start-UpdateCheck $true })
            [Windows.Controls.DockPanel]::SetDock($UpdateBtn, 'Right')
            $verRow.Children.Insert(0, $UpdateBtn)
            Add-GroupRow $info $verRow
            [void]$page.Children.Add($info.Border)
        } catch { $script:WinBuild = 0 }
        [void]$page.Children.Add((New-SectionHeader 'How this works'))
        foreach ($line in @(
            'if a row says "already done", that''s already set on your pc.',
            '"no undo" means the undo button can''t put it back, so think before you tick those.',
            'splat''s selection (bottom left) ticks what i''d recommend. last run ticks whatever you did last time.',
            'quick toggles and install apps are under tools. those work instantly, no apply button.'
        )) { [void]$page.Children.Add((New-TextBlock $line 12.5 'Text2' -Wrap -Margin (Thk 6 0 0 6))) }
    }

    $cat.Nav = $n.Nav
    $cat.Page = $page
    $cat.Count = $n.Count
}

New-NavHeader 'Tools'

# ---------------------------------------------------------------- Quick toggles page
$ToggleById = @{}
foreach ($tg in $Toggles) { $ToggleById[$tg.Id] = $tg }
$script:NeedReboot = $false
$script:NeedSignOut = $false
$script:NeedExplorer = $false

$toggleNav = New-NavItem 'toggles' 'Quick toggles' 0xE9E9 $NavColors.toggles
$togglesPage = New-Page 'toggles' 'Quick toggles' 'flip a switch and it happens right away, no apply button. the switches show how your pc is set up right now.'

$banner = New-Object Windows.Controls.Border
$banner.Background = $B.Group
$banner.CornerRadius = New-Object Windows.CornerRadius 10
$banner.Padding = Thk 14 10 10 10
$banner.Margin = Thk 0 0 0 6
$banner.Visibility = 'Collapsed'
$banner.RenderTransform = New-Object Windows.Media.TranslateTransform
$bannerDock = New-Object Windows.Controls.DockPanel
$bannerBtns = New-Object Windows.Controls.StackPanel
$bannerBtns.Orientation = 'Horizontal'
$bannerBtns.VerticalAlignment = 'Center'
[Windows.Controls.DockPanel]::SetDock($bannerBtns, 'Right')
$ExplorerBtn = New-Object Windows.Controls.Button
$ExplorerBtn.Style = $window.FindResource('Btn')
$ExplorerBtn.Content = 'Restart Explorer'
$ExplorerBtn.Padding = Thk 12 5
$ExplorerBtn.Margin = Thk 12 0 0 0
$RebootBtn = New-Object Windows.Controls.Button
$RebootBtn.Style = $window.FindResource('PrimaryBtn')
$RebootBtn.Content = 'Restart PC'
$RebootBtn.Padding = Thk 12 5
$RebootBtn.Margin = Thk 8 0 0 0
[void]$bannerBtns.Children.Add($ExplorerBtn)
[void]$bannerBtns.Children.Add($RebootBtn)
[void]$bannerDock.Children.Add($bannerBtns)
$bannerIcon = New-TextBlock ([string][char]0xE946) 15 'Accent'
$bannerIcon.FontFamily = $IconFont
$bannerIcon.VerticalAlignment = 'Center'
$bannerIcon.Margin = Thk 0 0 10 0
[Windows.Controls.DockPanel]::SetDock($bannerIcon, 'Left')
[void]$bannerDock.Children.Add($bannerIcon)
$BannerText = New-TextBlock '' 12.5 'Text' -Wrap
$BannerText.VerticalAlignment = 'Center'
[void]$bannerDock.Children.Add($BannerText)
$banner.Child = $bannerDock
[void]$togglesPage.Children.Add($banner)

function New-ToggleRow($tg) {
    $row = New-Object Windows.Controls.Grid
    $row.Margin = Thk 12 11 12 11
    foreach ($w in 'Star', 'Auto') {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = if ($w -eq 'Star') { New-Object Windows.GridLength 1, 'Star' } else { [Windows.GridLength]::Auto }
        $row.ColumnDefinitions.Add($cd)
    }
    $left = New-Object Windows.Controls.StackPanel
    $titleLine = New-Object Windows.Controls.WrapPanel
    [void]$titleLine.Children.Add((New-TextBlock $tg.Name 13.5 'Text'))
    foreach ($tag in @(@($tg.Restart, 'restart needed'), @($tg.SignOut, 'sign out needed'))) {
        if ($tag[0]) {
            $t = New-TextBlock $tag[1] 11.5 'Text3' -Margin (Thk 8 0 0 0)
            $t.VerticalAlignment = 'Center'
            [void]$titleLine.Children.Add($t)
        }
    }
    [void]$left.Children.Add($titleLine)
    $desc = New-TextBlock $tg.Desc 12 'Text2' -Wrap -Margin (Thk 0 2 0 0)
    $desc.LineHeight = 17
    [void]$left.Children.Add($desc)
    [void]$row.Children.Add($left)

    $right = New-Object Windows.Controls.StackPanel
    $right.Orientation = 'Horizontal'
    $right.VerticalAlignment = 'Center'
    $right.Margin = Thk 16 0 0 0
    $state = New-TextBlock '' 12 'Text3' -Margin (Thk 0 0 10 0)
    $state.VerticalAlignment = 'Center'
    $state.Visibility = 'Collapsed'
    $sw = New-Object Windows.Controls.Primitives.ToggleButton
    $sw.Style = $window.FindResource('Switch')
    $sw.Tag = $tg.Id
    $sw.Add_Click({ Invoke-Toggle $this.Tag })
    [void]$right.Children.Add($state)
    [void]$right.Children.Add($sw)
    [Windows.Controls.Grid]::SetColumn($right, 1)
    [void]$row.Children.Add($right)

    $tg.Switch = $sw
    $tg.StateText = $state
    return $row
}

$firstGroup = $true
foreach ($grpName in @($Toggles | ForEach-Object { $_.Group } | Select-Object -Unique)) {
    $hdr = New-SectionHeader $grpName $firstGroup
    if ($firstGroup) { $hdr.Margin = Thk 6 10 0 8 }
    [void]$togglesPage.Children.Add($hdr)
    $firstGroup = $false
    $grp = New-Group
    foreach ($tg in @($Toggles | Where-Object { $_.Group -eq $grpName })) { Add-GroupRow $grp (New-ToggleRow $tg) 12 }
    [void]$togglesPage.Children.Add($grp.Border)
}

# $State: $true / $false, 'default' (never set - Windows decides), or 'error' (couldn't read it)
function Set-ToggleVisual($tg, $State) {
    $tg.Broken = $false
    if ('error' -eq $State) {
        $tg.Broken = $true
        $tg.Switch.IsEnabled = $false
        $tg.StateText.Text = 'can''t read'
        $tg.StateText.Visibility = 'Visible'
        return
    }
    if ('default' -eq $State) {
        $tg.Switch.IsChecked = $null
        $tg.StateText.Text = 'default'
        $tg.StateText.Visibility = 'Visible'
        return
    }
    $tg.Switch.IsChecked = [bool]$State
    $tg.StateText.Visibility = 'Collapsed'
}

function Get-ToggleState($tg) {
    try {
        $r = & $tg.Get
        if ($null -eq $r) { return 'default' }
        return [bool]$r
    } catch { return 'error' }
}

function Update-Toggles {
    foreach ($tg in $Toggles) { Set-ToggleVisual $tg (Get-ToggleState $tg) }
}

function Update-ToggleBanner {
    $msgs = @()
    if ($script:NeedReboot) { $msgs += 'restart your pc for some of these to kick in.' }
    elseif ($script:NeedSignOut) { $msgs += 'sign out and back in for some of these to kick in.' }
    if ($script:NeedExplorer) { $msgs += 'restart explorer to see the taskbar / explorer changes.' }
    $BannerText.Text = $msgs -join ' '
    $ExplorerBtn.Visibility = if ($script:NeedExplorer) { 'Visible' } else { 'Collapsed' }
    $RebootBtn.Visibility = if ($script:NeedReboot -or $script:NeedSignOut) { 'Visible' } else { 'Collapsed' }
    if (-not $msgs.Count) { $banner.Visibility = 'Collapsed'; return }
    if ($banner.Visibility -ne 'Visible') {
        $banner.Visibility = 'Visible'
        Snap $banner 'Opacity' 0
        Snap $banner.RenderTransform 'Y' -10
        Anim $banner 'Opacity' 1 1 0.3
        Anim $banner.RenderTransform 'Y' 0 1 0.36
    }
}

function Invoke-Toggle([string]$Id) {
    $tg = $ToggleById[$Id]
    $want = [bool]$tg.Switch.IsChecked
    $err = $null
    try { $null = & $tg.Set $want } catch { $err = $_.Exception.Message }
    $now = Get-ToggleState $tg
    Set-ToggleVisual $tg $now
    if ($now -isnot [bool] -or $now -ne $want) {
        $msg = if ($err) { $err } else { 'windows wouldn''t let me change it. probably a group policy, your hardware, or some other security setting.' }
        [void](Show-Dialog -Title "couldn't change that" -Body $msg)
        return
    }
    Write-ActivityLine ('{0}: {1}' -f $tg.Name, $(if ($now) { 'on' } else { 'off' }))
    if ($tg.Restart) { $script:NeedReboot = $true }
    if ($tg.SignOut) { $script:NeedSignOut = $true }
    if ($tg.Explorer) { $script:NeedExplorer = $true }
    Update-ToggleBanner
}

$ExplorerBtn.Add_Click({
    $script:MiscJobs.Add((Start-Bg 'param($sync, $HelperCode) . ([scriptblock]::Create($HelperCode)); Restart-Explorer' @($sync, $HelperCode)))
    $script:NeedExplorer = $false
    Update-ToggleBanner
})
$RebootBtn.Add_Click({
    if (Show-Dialog -Title 'restart now?' -Body 'save your stuff first, it restarts 5 seconds after you click.' -Yes 'Restart' -No 'Not yet') {
        Start-Process shutdown.exe -ArgumentList '/r', '/t', '5' -WindowStyle Hidden
    }
})

# ---------------------------------------------------------------- Install apps page
$Apps = New-Object System.Collections.Generic.List[object]
$AppById = @{}
foreach ($grpName in $AppCatalog.Keys) {
    foreach ($a in $AppCatalog[$grpName]) {
        $app = @{ Id = $a[0]; Name = $a[1]; Desc = $a[2]; Group = $grpName; State = 'idle' }
        $Apps.Add($app)
        $AppById[$app.Id] = $app
    }
}
$script:AppPending = New-Object System.Collections.Generic.List[object]
$script:AppJob = $null
$script:ScanJob = $null
$script:MiscJobs = New-Object System.Collections.Generic.List[object]
$AppPalette = @('#FF453A', '#FF9F0A', '#FFD60A', '#30D158', '#64D2FF', '#0A84FF', '#5E5CE6', '#BF5AF2', '#FF375F', '#AC8E68')

$appNav = New-NavItem 'apps' 'Install apps' 0xE896 $NavColors.apps
$UpgradeBtn = New-Object Windows.Controls.Button
$UpgradeBtn.Style = $window.FindResource('PlainBtn')
$UpgradeBtn.Content = 'Update everything'
$UpgradeBtn.Margin = Thk 24 0 0 3
$UpgradeBtn.ToolTip = New-TextBlock 'runs winget upgrade --all. updates everything winget knows about, not just what''s on this page.' 12 $null -Wrap
$appsPage = New-Page 'apps' 'Install apps' 'one click installs through winget. queue up as many as you want, they go one at a time.' $UpgradeBtn

$searchRow = New-Object Windows.Controls.DockPanel
$searchRow.Margin = Thk 0 0 0 4
$AppSearch = New-Object Windows.Controls.TextBox
$AppSearch.Style = $window.FindResource('SearchBox')
$AppSearch.Width = 280
[Windows.Controls.DockPanel]::SetDock($AppSearch, 'Left')
[void]$searchRow.Children.Add($AppSearch)
$AppStatus = New-TextBlock 'checking what you already have...' 12 'Text2' -Margin (Thk 14 0 0 0)
$AppStatus.VerticalAlignment = 'Center'
$AppStatus.TextTrimming = 'CharacterEllipsis'
[void]$searchRow.Children.Add($AppStatus)
[void]$appsPage.Children.Add($searchRow)

function New-AppTile($a) {
    $tile = New-Object Windows.Controls.Border
    $tile.Width = 250
    $tile.Height = 60
    $tile.Padding = Thk 8 0 8 0
    $tile.Margin = Thk 1
    $dock = New-Object Windows.Controls.DockPanel
    $icon = New-Object Windows.Controls.Border
    $icon.Width = 36
    $icon.Height = 36
    $icon.CornerRadius = New-Object Windows.CornerRadius 9
    $icon.VerticalAlignment = 'Center'
    $icon.Margin = Thk 0 0 10 0
    # real app icon from assets\icons\<wingetId>.png, or a colored letter tile if there isn't one
    $iconFile = Join-Path $IconDir "$($a.Id).png"
    $img = $null
    if (Test-Path -LiteralPath $iconFile) {
        try {
            $img = New-Object Windows.Media.Imaging.BitmapImage
            $img.BeginInit()
            $img.CacheOption = 'OnLoad'
            $img.DecodePixelWidth = 96
            $img.UriSource = New-Object Uri $iconFile
            $img.EndInit()
            $img.Freeze()
        } catch { $img = $null }
    }
    if ($img) {
        $brush = New-Object Windows.Media.ImageBrush $img
        $brush.Stretch = 'UniformToFill'
        $brush.Freeze()
        $icon.Background = $brush
    } else {
        $hash = 0
        foreach ($ch in $a.Name.ToCharArray()) { $hash += [int]$ch }
        $icon.Background = New-TileBrush $AppPalette[$hash % $AppPalette.Count]
        $letter = New-TextBlock $a.Name.Substring(0, 1).ToUpper() 16 $null -Bold -Font 'display'
        $letter.Foreground = [Windows.Media.Brushes]::White
        $letter.HorizontalAlignment = 'Center'
        $letter.VerticalAlignment = 'Center'
        $icon.Child = $letter
    }
    [Windows.Controls.DockPanel]::SetDock($icon, 'Left')
    [void]$dock.Children.Add($icon)

    $right = New-Object Windows.Controls.Grid
    $right.VerticalAlignment = 'Center'
    $right.Margin = Thk 8 0 0 0
    [Windows.Controls.DockPanel]::SetDock($right, 'Right')
    $btn = New-Object Windows.Controls.Button
    $btn.Style = $window.FindResource('GetBtn')
    $btn.Content = 'Get'
    $btn.Tag = $a.Id
    $btn.Add_Click({ Request-App $this.Tag })
    [Splat.Motion]::Press($btn, 0.93)
    $spin = New-Spinner 18
    $spin.HorizontalAlignment = 'Center'
    $done = New-TextBlock 'Installed' 12 'Text3'
    $done.HorizontalAlignment = 'Center'
    $done.Visibility = 'Collapsed'
    [void]$right.Children.Add($btn)
    [void]$right.Children.Add($spin)
    [void]$right.Children.Add($done)
    [void]$dock.Children.Add($right)

    $left = New-Object Windows.Controls.StackPanel
    $left.VerticalAlignment = 'Center'
    $name = New-TextBlock $a.Name 13 'Text'
    $name.TextTrimming = 'CharacterEllipsis'
    [void]$left.Children.Add($name)
    $desc = New-TextBlock $a.Desc 11.5 'Text2' -Margin (Thk 0 1 0 0)
    $desc.TextTrimming = 'CharacterEllipsis'
    [void]$left.Children.Add($desc)
    [void]$dock.Children.Add($left)
    $tile.Child = $dock
    $tile.ToolTip = New-TextBlock "$($a.Desc)`nwinget: $($a.Id)" 12 $null -Wrap
    $a.Tile = $tile
    $a.Btn = $btn
    $a.Spin = $spin
    $a.Done = $done
    return $tile
}

# every Visual C++ version + DirectX, installed in one go from the Runtimes header
$VcBundle = [ordered]@{}
foreach ($v in '2005', '2008', '2010', '2012', '2013', '2015+') {
    foreach ($arch in 'x86', 'x64') { $VcBundle["Microsoft.VCRedist.$v.$arch"] = "Visual C++ $v ($arch)" }
}
$VcBundle['Microsoft.DirectX'] = 'DirectX End-User Runtime'
$script:BundleBusy = $false
$script:AppJobId = $null
$BundleBtn = New-Object Windows.Controls.Button
$BundleBtn.Style = $window.FindResource('PlainBtn')
$BundleBtn.Content = 'Get all Visual C++ + DirectX'
$BundleBtn.ToolTip = New-TextBlock 'installs every visual c++ version (2005 to 2015+, 32 and 64 bit) plus directx. stuff you already have just gets skipped.' 12 $null -Wrap
$BundleBtn.Add_Click({
    foreach ($id in $VcBundle.Keys) {
        if ($AppById[$id]) {
            if ($AppById[$id].State -ne 'installed') { Request-App $id }
        } elseif (-not @($script:AppPending | Where-Object { $_.Id -eq $id }).Count) {
            $script:AppPending.Add(@{ Id = $id; Name = $VcBundle[$id]; Title = "Installing $($VcBundle[$id])" })
        }
    }
    $script:BundleBusy = $true
    $BundleBtn.IsEnabled = $false
    Update-BundleBtn
})
function Update-BundleBtn {
    if (-not $script:BundleBusy) { return }
    $left = @($script:AppPending | Where-Object { $VcBundle.Contains($_.Id) }).Count
    if ($script:AppJob -and $VcBundle.Contains([string]$script:AppJobId)) { $left++ }
    if ($left) { $BundleBtn.Content = "Installing$([char]0x2026) $left left"; return }
    $script:BundleBusy = $false
    $BundleBtn.IsEnabled = $true
    $BundleBtn.Content = 'Get all Visual C++ + DirectX'
}

$AppGroups = @{}
foreach ($grpName in $AppCatalog.Keys) {
    $hdr = New-SectionHeader $grpName
    if ($grpName -like 'Runtimes*') {
        $hdrRow = New-Object Windows.Controls.DockPanel
        $hdrRow.Margin = $hdr.Margin
        $hdr.Margin = Thk 0
        $BundleBtn.Margin = Thk 12 0 6 0
        [Windows.Controls.DockPanel]::SetDock($BundleBtn, 'Right')
        [void]$hdrRow.Children.Add($BundleBtn)
        [void]$hdrRow.Children.Add($hdr)
        $hdr = $hdrRow
    }
    $grp = New-Object Windows.Controls.Border
    $grp.Background = $B.Group
    $grp.CornerRadius = New-Object Windows.CornerRadius 10
    $grp.Padding = Thk 5
    $wrap = New-Object Windows.Controls.WrapPanel
    foreach ($a in @($Apps | Where-Object { $_.Group -eq $grpName })) { [void]$wrap.Children.Add((New-AppTile $a)) }
    $grp.Child = $wrap
    [void]$appsPage.Children.Add($hdr)
    [void]$appsPage.Children.Add($grp)
    $AppGroups[$grpName] = @{ Label = $hdr; Box = $grp }
}

$AppSearch.Add_TextChanged({
    $q = $AppSearch.Text.Trim()
    foreach ($grpName in $AppCatalog.Keys) {
        $any = $false
        foreach ($a in @($Apps | Where-Object { $_.Group -eq $grpName })) {
            $hit = (-not $q) -or $a.Name -like "*$q*" -or $a.Desc -like "*$q*" -or $a.Id -like "*$q*" -or $grpName -like "*$q*"
            $a.Tile.Visibility = if ($hit) { 'Visible' } else { 'Collapsed' }
            if ($hit) { $any = $true }
        }
        $vis = if ($any) { 'Visible' } else { 'Collapsed' }
        $AppGroups[$grpName].Label.Visibility = $vis
        $AppGroups[$grpName].Box.Visibility = $vis
    }
})

function Set-AppState([string]$Id, [string]$State) {
    if ($Id -eq '__upgrade') {
        $busy = $State -eq 'queued' -or $State -eq 'installing'
        $UpgradeBtn.IsEnabled = -not $busy
        $UpgradeBtn.Content = if ($busy) { "Updating$([char]0x2026)" } else { 'Update everything' }
        if (-not $busy) { Start-AppScan }
        return
    }
    $a = $AppById[$Id]
    if (-not $a) { return }
    $a.State = $State
    Stop-Spin $a.Spin
    $a.Btn.Visibility = 'Visible'
    $a.Done.Visibility = 'Collapsed'
    $a.Btn.IsEnabled = $true
    $a.Btn.Foreground = $B.Accent
    switch ($State) {
        'installed' {
            $a.Btn.Visibility = 'Collapsed'
            $a.Done.Visibility = 'Visible'
            Snap $a.Done 'Opacity' 0
            Anim $a.Done 'Opacity' 1 1 0.3
        }
        'queued'     { $a.Btn.Content = 'Queued'; $a.Btn.IsEnabled = $false }
        'installing' { $a.Btn.Visibility = 'Collapsed'; Start-Spin $a.Spin }
        'failed'     { $a.Btn.Content = 'Retry'; $a.Btn.Foreground = $B.Bad }
        default      { $a.Btn.Content = 'Get' }
    }
}

function Request-App([string]$Id) {
    $a = $AppById[$Id]
    if (-not $a -or $a.State -eq 'queued' -or $a.State -eq 'installing') { return }
    $script:AppPending.Add(@{ Id = $Id; Name = $a.Name; Title = "Installing $($a.Name)" })
    Set-AppState $Id 'queued'
}
$UpgradeBtn.Add_Click({
    $script:AppPending.Add(@{ Id = '__upgrade'; Name = 'all apps'; Title = 'Updating all apps (winget upgrade --all)' })
    Set-AppState '__upgrade' 'queued'
})

function Start-AppScan {
    if ($script:ScanJob) { return }
    $AppStatus.Text = 'checking what you already have...'
    $script:ScanJob = Start-Bg $ScanCode @($sync, $HelperCode)
}

function Start-Bg([string]$Code, [object[]]$Arguments) {
    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($Code)
    foreach ($a in $Arguments) { [void]$ps.AddArgument($a) }
    return @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke() }
}
function Stop-Bg($Job) {
    try { [void]$Job.PS.EndInvoke($Job.Handle) } catch { }
    try { $Job.PS.Dispose(); $Job.RS.Dispose() } catch { }
}

# ---------------------------------------------------------------- selection
function Set-Category([string]$Key, [bool]$On) {
    foreach ($it in @($Items | Where-Object { $_.Cat -eq $Key })) { $it.Box.IsChecked = $On }
}
function Set-Preset {
    foreach ($it in $Items) {
        $it.Box.IsChecked = [bool]$it.Preset
        if ($it.Chips) { Set-ItemOption $it $it.Default }
    }
}

function Update-Selection {
    $sel = @($Items | Where-Object { $_.Box.IsChecked })
    foreach ($k in $Categories.Keys) {
        $c = $Categories[$k]
        if (-not $c.Count) { continue }
        $on = @($Items | Where-Object { $_.Cat -eq $k -and $_.Box.IsChecked }).Count
        $c.Count.Text = if ($on) { "$on" } else { '' }
    }
    $ui.SelCount.Text = if ($sel.Count -eq 0) { 'nothing ticked yet' } else { "$($sel.Count) ticked" }
    $oneway = @($sel | Where-Object { $_.OneWay }).Count
    $ui.SelNote.Text = if ($oneway) { "$Dot  $oneway can't be undone" } else { '' }
    $ui.ApplyBtn.Content = if ($sel.Count) { "Apply ($($sel.Count))" } else { 'Apply' }
}

function Update-Status {
    foreach ($it in $Items) {
        if (-not $it.Check) { continue }
        try {
            $r = @(& $it.Check)
            $on = @($r | Where-Object { $_ }).Count
            if ($r.Count -and $on -eq $r.Count) { Set-Pill $it 'applied' }
            elseif ($on -gt 0) { Set-Pill $it 'partial' }
            else { Set-Pill $it $null }
        } catch { Set-Pill $it $null }
    }
}

# ---- profile (what you last applied)
function Save-Profile {
    $data = [ordered]@{
        selected = @($Items | Where-Object { $_.Box.IsChecked } | ForEach-Object { $_.Id })
        options  = @{}
    }
    foreach ($it in @($Items | Where-Object { $_.Chips })) { $data.options[$it.Id] = Get-ItemOption $it }
    try { $data | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ProfilePath -Encoding UTF8 -ErrorAction Stop } catch { }
}
function Import-SavedProfile {
    if (-not (Test-Path -LiteralPath $ProfilePath)) { return $false }
    try { $p = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction Stop | ConvertFrom-Json } catch { return $false }
    $selected = @($p.selected)
    foreach ($it in $Items) { $it.Box.IsChecked = ($selected -contains $it.Id) }
    foreach ($it in @($Items | Where-Object { $_.Chips })) {
        $key = $p.options.($it.Id)
        if ($key) { Set-ItemOption $it $key }
    }
    return $true
}

# ---------------------------------------------------------------- dialogs
# The app recedes slightly, the card materializes (scale + fade), and closing
# plays the same path in reverse. Modal via a nested dispatcher frame.
$script:DialogFrame = $null
function Set-DialogContent([string]$Title, [string]$Body, [string[]]$Lines, [string[]]$Warnings, [string]$Yes, [string]$No) {
    $ui.DTitle.Text = $Title
    $ui.DBody.Text = $Body
    $ui.DBody.Visibility = if ($Body) { 'Visible' } else { 'Collapsed' }
    $ui.DList.Children.Clear()
    $ui.DListWrap.Visibility = if ($Lines) { 'Visible' } else { 'Collapsed' }
    $n = 0
    foreach ($l in $Lines) {
        $n++
        $row = New-Object Windows.Controls.DockPanel
        $row.Margin = Thk 0 3 0 3
        $num = New-TextBlock ('{0,2}' -f $n) 12 'Text3' -Font 'mono'
        $num.Width = 24
        [void]$row.Children.Add($num)
        [void]$row.Children.Add((New-TextBlock $l 13 'Text' -Wrap))
        [void]$ui.DList.Children.Add($row)
    }
    $ui.DWarn.Children.Clear()
    foreach ($w in $Warnings) { [void]$ui.DWarn.Children.Add((New-TextBlock "$([char]0x26A0)  $w" 12.5 'Warn' -Wrap -Margin (Thk 0 0 0 6))) }
    $ui.DYes.Content = $Yes
    $ui.DNo.Content = $No
    $ui.DNo.Visibility = if ($No) { 'Visible' } else { 'Collapsed' }
}
function Open-DialogLayer {
    $ui.DialogLayer.Visibility = 'Visible'
    $card = $ui.DialogCard
    Snap $ui.Scrim 'Opacity' 0
    Snap $card 'Opacity' 0
    Snap $card.RenderTransform 'SX' 0.92
    Snap $card.RenderTransform 'SY' 0.92
    Anim $ui.Scrim 'Opacity' 1 1 0.25
    Anim $card 'Opacity' 1 1 0.2
    Anim $card.RenderTransform 'SX' 1 0.84 0.32
    Anim $card.RenderTransform 'SY' 1 0.84 0.32
    Anim $ui.AppRoot.RenderTransform 'SX' 0.985 1 0.4
    Anim $ui.AppRoot.RenderTransform 'SY' 0.985 1 0.4
}
function Close-DialogLayer {
    $card = $ui.DialogCard
    Anim $ui.Scrim 'Opacity' 0 1 0.22
    Anim $card.RenderTransform 'SX' 0.95 1 0.22
    Anim $card.RenderTransform 'SY' 0.95 1 0.22
    Anim $ui.AppRoot.RenderTransform 'SX' 1 1 0.4
    Anim $ui.AppRoot.RenderTransform 'SY' 1 1 0.4
    Anim $card 'Opacity' 0 1 0.18 ([EventHandler]{ if (-not $script:DialogFrame) { $ui.DialogLayer.Visibility = 'Collapsed' } })
}
function Show-Dialog {
    param([string]$Title, [string]$Body, [string[]]$Lines, [string[]]$Warnings, [string]$Yes = 'Ok', [string]$No)
    if ($script:DialogFrame) { return $false }
    Set-DialogContent $Title $Body $Lines $Warnings $Yes $No
    Open-DialogLayer
    $script:DialogResult = $false
    $script:DialogFrame = New-Object Windows.Threading.DispatcherFrame
    $null = $ui.DYes.Focus()
    [Windows.Threading.Dispatcher]::PushFrame($script:DialogFrame)
    return $script:DialogResult
}
function Close-Dialog([bool]$Result) {
    if (-not $script:DialogFrame) { return }
    $script:DialogResult = $Result
    $frame = $script:DialogFrame
    $script:DialogFrame = $null
    Close-DialogLayer
    $frame.Continue = $false
}
$ui.DYes.Add_Click({ Close-Dialog $true })
$ui.DNo.Add_Click({ Close-Dialog $false })
$window.Add_PreviewKeyDown({
    if (-not $script:DialogFrame) { return }
    if ($_.Key -eq 'Escape') { Close-Dialog $false; $_.Handled = $true }
    elseif ($_.Key -eq 'Return') { Close-Dialog $true; $_.Handled = $true }
})

# ---------------------------------------------------------------- activity log
$script:LogOpen = $false
function Show-Log([bool]$Show) {
    $script:LogOpen = $Show
    $target = if ($Show) { 230 } else { 0 }
    Anim $ui.LogPanel 'Height' $target 1 0.38
    $ui.LogToggleBtn.Content = if ($Show) { 'Hide log' } else { 'Show log' }
}
function Write-LogFile([string]$Text) {
    if ($script:LogWriter) { try { $script:LogWriter.WriteLine(('[{0:HH:mm:ss}] {1}' -f (Get-Date), $Text)) } catch { } }
}
function Add-LogLine([string]$Text, [string]$Level = 'info', [switch]$Progress) {
    if ($Progress -and $script:LastRun) {
        $script:LastRun.Text = $Text
        $script:PendingProgress = $Text
        return
    }
    if (-not $Progress -and $script:PendingProgress) { Write-LogFile $script:PendingProgress; $script:PendingProgress = $null }
    $brush = switch ($Level) { 'ok' { $B.Good } 'warn' { $B.Warn } 'error' { $B.Bad } 'dim' { $B.Text2 } default { $B.Text } }
    $para = New-Object Windows.Documents.Paragraph
    $para.Margin = Thk 0
    $run = [Windows.Documents.Run]::new($Text)
    $run.Foreground = $brush
    if ($Level -eq 'head') { $run.FontWeight = [Windows.FontWeights]::Medium }
    $para.Inlines.Add($run)
    $ui.LogBox.Document.Blocks.Add($para)
    if ($Progress) { $script:LastRun = $run; $script:PendingProgress = $Text }
    else { $script:LastRun = $null; Write-LogFile $Text }
    $ui.LogBox.ScrollToEnd()
}
function Write-ActivityLine([string]$Text) {
    Add-LogLine ('{0:HH:mm}  {1}' -f (Get-Date), $Text) 'dim'
}

# ---------------------------------------------------------------- running
$script:Running = $false
function Set-Progress([double]$Value) { Anim $ui.Progress 'Value' $Value 1 0.4 }

function Set-Busy([bool]$Busy) {
    $script:Running = $Busy
    foreach ($it in $Items) { $it.Box.IsEnabled = -not $Busy }
    foreach ($el in $ui.PresetBtn, $ui.AllBtn, $ui.NoneBtn, $ui.ApplyBtn, $ui.RevertBtn) { $el.IsEnabled = -not $Busy }
    $ui.LastBtn.IsEnabled = (-not $Busy) -and (Test-Path -LiteralPath $ProfilePath)
    foreach ($c in $Categories.Values) { if ($c.AllLink) { $c.AllLink.IsEnabled = -not $Busy; $c.NoneLink.IsEnabled = -not $Busy } }
    foreach ($tg in $Toggles) { if (-not $tg.Broken) { $tg.Switch.IsEnabled = -not $Busy } }
    $show = if ($Busy) { $ui.ProgressInfo } else { $ui.SelectionInfo }
    $hide = if ($Busy) { $ui.SelectionInfo } else { $ui.ProgressInfo }
    $hide.Visibility = 'Collapsed'
    $show.Visibility = 'Visible'
    Snap $show 'Opacity' 0
    Anim $show 'Opacity' 1 1 0.3
    $ui.CancelBtn.Visibility = if ($Busy) { 'Visible' } else { 'Collapsed' }
    $ui.CancelBtn.IsEnabled = $true
    $ui.CancelBtn.Content = 'Stop after this one'
}

function Test-OtherBrowser {
    foreach ($p in "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                   "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                   "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
                   "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
                   "$env:ProgramFiles\BraveSoftware\Brave-Browser\Application\brave.exe",
                   "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\Application\brave.exe",
                   "$env:LOCALAPPDATA\imput\Helium\Application\chrome.exe",
                   "$env:ProgramFiles\imput\Helium\Application\chrome.exe") {
        if (Test-Path -LiteralPath $p) { return $true }
    }
    return $false
}

function Start-Run([string]$Mode) {
    if ($script:Running) { return }
    if ($script:AppJob -or $script:AppPending.Count) {
        [void](Show-Dialog -Title 'apps are still installing' -Body 'wait for those to finish, then hit apply again.')
        return
    }
    $selected = @($Items | Where-Object { $_.Box.IsChecked })
    if (-not $selected.Count) {
        [void](Show-Dialog -Title 'nothing ticked' -Body 'tick something first, or hit splat''s selection in the bottom left.')
        return
    }

    if ($Mode -eq 'revert') {
        $run  = @($selected | Where-Object { $_.Revert -or $_.Id -eq 'restore' })
        $skip = @($selected | Where-Object { -not $_.Revert -and $_.Id -ne 'restore' })
        $undoCount = @($run | Where-Object { $_.Revert }).Count
        if (-not $undoCount) {
            [void](Show-Dialog -Title 'nothing to undo' -Body 'none of the stuff you ticked can be undone automatically. removed apps can be reinstalled from the microsoft store.')
            return
        }
        $title = if ($undoCount -eq 1) { 'undo this one?' } else { "undo these $undoCount?" }
        $body = 'puts these back to how windows had them.'
        $warn = @()
        if ($skip.Count) { $warn += 'can''t undo these so they get skipped: ' + (($skip | ForEach-Object { $_.Name }) -join ', ') + '.' }
        $yes = 'Undo'
    } else {
        $run = $selected
        $title = if ($run.Count -eq 1) { 'run this?' } else { "run these $($run.Count)?" }
        $body = 'they run in this order. you can keep using your pc while it works, explorer might restart at the end.'
        $warn = @()
        if ($ItemById.edge.Box.IsChecked -and -not $ItemById.browser.Box.IsChecked -and -not (Test-OtherBrowser)) {
            $warn += 'you''re removing edge without installing another browser. you''ll have no browser at all.'
        }
        $warn += @($run | Where-Object { $_.Warn } | ForEach-Object { "$($_.Name): $($_.Warn)" })
        $oneway = @($run | Where-Object { $_.OneWay })
        if ($oneway.Count) { $warn += 'no undo for: ' + (($oneway | ForEach-Object { $_.Name }) -join ', ') + '.' }
        $yes = 'Go'
    }
    $lines = foreach ($it in $run) {
        $opt = Get-ItemOption $it -Label
        $prefix = if ($Mode -eq 'revert' -and $it.Revert) { 'Undo: ' } else { '' }
        if ($opt) { "$prefix$($it.Name)  $Dot  $opt" } else { "$prefix$($it.Name)" }
    }
    if (-not (Show-Dialog -Title $title -Body $body -Lines $lines -Warnings $warn -Yes $yes -No 'Cancel')) { return }

    if ($Mode -eq 'apply') { Save-Profile; $ui.LastBtn.IsEnabled = $true }
    $jobs = foreach ($it in $run) {
        $undo = ($Mode -eq 'revert' -and $it.Revert)
        @{
            Id       = $it.Id
            Name     = if ($undo) { "Undo: $($it.Name)" } else { $it.Name }
            Code     = if ($undo) { $it.Revert.ToString() } else { $it.Apply.ToString() }
            Option   = Get-ItemOption $it
            Explorer = [bool]$it.Explorer
            Reboot   = [bool]$it.Reboot
        }
    }

    $script:RunResults = @{}
    $script:RunNeedsReboot = $false
    foreach ($it in $run) { Set-Pill $it 'queued' }
    $ui.LogBox.Document.Blocks.Clear()
    $script:LastRun = $null
    $script:PendingProgress = $null
    try {
        if (-not (Test-Path -LiteralPath $LogDir)) { $null = New-Item -ItemType Directory -Path $LogDir -Force }
        $script:LogWriter = New-Object IO.StreamWriter (Join-Path $LogDir ('{0:yyyy-MM-dd_HH-mm-ss}_{1}.log' -f (Get-Date), $Mode)), $true, ([Text.Encoding]::UTF8)
        $script:LogWriter.AutoFlush = $true
    } catch { $script:LogWriter = $null }
    Show-Log $true
    Set-Busy $true
    Snap $ui.Progress 'Value' 0
    $ui.ProgressText.Text = 'starting...'
    $ui.ProgressCount.Text = ''

    $sync.Cancel = $false
    $sync.Finished = $false
    $script:MainJob = Start-Bg $WorkerCode @($sync, @($jobs), $HelperCode, $Config)
}

function Complete-Run {
    try { [void]$script:MainJob.PS.EndInvoke($script:MainJob.Handle) } catch { Add-LogLine "Worker error: $($_.Exception.Message)" 'error' }
    foreach ($e in $script:MainJob.PS.Streams.Error) { Add-LogLine "    ! $e" 'warn' }
    try { $script:MainJob.PS.Dispose(); $script:MainJob.RS.Dispose() } catch { }
    $script:MainJob = $null
    if ($script:PendingProgress) { Write-LogFile $script:PendingProgress; $script:PendingProgress = $null }
    if ($script:LogWriter) { try { $script:LogWriter.Dispose() } catch { }; $script:LogWriter = $null }

    Set-Progress 100
    Set-Busy $false
    Update-Status
    Update-Toggles
    if ($ItemById.browser.Box.IsChecked) { Start-AppScan }
    foreach ($id in $script:RunResults.Keys) {
        $state = $script:RunResults[$id]
        $it = $ItemById[$id]
        if ($state -ne 'ok' -or -not $it.Check) { Set-Pill $it $state }
    }

    $vals = @($script:RunResults.Values)
    $ok = @($vals | Where-Object { $_ -eq 'ok' }).Count
    $wn = @($vals | Where-Object { $_ -eq 'warn' }).Count
    $fl = @($vals | Where-Object { $_ -eq 'fail' }).Count
    $title = if ($sync.Cancel) { 'stopped' } elseif ($fl) { 'done, but some stuff failed' } elseif ($wn) { 'done (mostly)' } else { 'all done' }
    $parts = @("$ok worked")
    if ($wn) { $parts += "$wn had warnings" }
    if ($fl) { $parts += "$fl failed" }
    $body = ($parts -join ', ') + '.'
    if ($wn -or $fl) { $body += ' check the log for details.' }
    if ($script:RunNeedsReboot) {
        $body += ' restart your pc for everything to kick in.'
        if (Show-Dialog -Title $title -Body $body -Yes 'Restart' -No 'Later') {
            Start-Process shutdown.exe -ArgumentList '/r', '/t', '5' -WindowStyle Hidden
        }
    } else {
        [void](Show-Dialog -Title $title -Body $body -Yes 'Ok')
    }
}

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(80)
$timer.Add_Tick({
    $m = $null
    $n = 0
    while ($n -lt 400 -and $sync.Queue.TryDequeue([ref]$m)) {
        $n++
        switch ($m.T) {
            'log'  { Add-LogLine $m.Text $m.L }
            'logp' { Add-LogLine $m.Text 'dim' -Progress }
            'step' {
                if ($ItemById[$m.Id]) { Set-Pill $ItemById[$m.Id] 'running' }
                $ui.ProgressText.Text = $m.Name
                $ui.ProgressCount.Text = "$($m.Index + 1) of $($m.Total)"
                Set-Progress (100 * $m.Index / $m.Total)
            }
            'done' {
                $script:RunResults[$m.Id] = $m.State
                if ($ItemById[$m.Id]) { Set-Pill $ItemById[$m.Id] $m.State }
                if ($m.Reboot -and $m.State -ne 'fail') { $script:RunNeedsReboot = $true }
                Set-Progress (100 * ($m.Index + 1) / $m.Total)
            }
            'app' { Set-AppState $m.Id $m.S }
            'update'  { $script:UpdateMsg = $m }
            'updated' { $script:UpdateMsg = $m }
            'installed' {
                if ($null -eq $m.Ids) {
                    $AppStatus.Text = if ($m.Error -eq 'nowinget') { 'winget isn''t ready yet. open the microsoft store, update "app installer", then reopen this.' }
                                      else { "couldn't check what you have installed ($($m.Error)). installing still works though." }
                } else {
                    $have = 0
                    foreach ($a in $Apps) {
                        if ($m.Ids -contains $a.Id) {
                            $have++
                            if ($a.State -ne 'queued' -and $a.State -ne 'installing') { Set-AppState $a.Id 'installed' }
                        }
                    }
                    $AppStatus.Text = "you already have $have of these."
                }
            }
        }
    }
    if ($script:Running -and $sync.Finished -and $sync.Queue.IsEmpty) { Complete-Run }
    if ($script:UpdateMsg -and -not $script:DialogFrame) { Resolve-UpdateMsg }

    # background app installs: one at a time, never during an optimizer run
    if ($script:AppJob -and $script:AppJob.Handle.IsCompleted) { Stop-Bg $script:AppJob; $script:AppJob = $null; $script:AppJobId = $null }
    if (-not $script:AppJob -and -not $script:Running -and $script:AppPending.Count) {
        $job = $script:AppPending[0]
        $script:AppPending.RemoveAt(0)
        Set-AppState $job.Id 'installing'
        Show-Log $true
        $script:AppJobId = $job.Id
        $script:AppJob = Start-Bg $AppCode @($sync, $HelperCode, $job)
    }
    Update-BundleBtn
    if ($script:ScanJob -and $script:ScanJob.Handle.IsCompleted) { Stop-Bg $script:ScanJob; $script:ScanJob = $null }
    for ($i = $script:MiscJobs.Count - 1; $i -ge 0; $i--) {
        if ($script:MiscJobs[$i].Handle.IsCompleted) { Stop-Bg $script:MiscJobs[$i]; $script:MiscJobs.RemoveAt($i) }
    }
})

# ---- wire up buttons
$ui.ApplyBtn.Add_Click({ Start-Run 'apply' })
$ui.RevertBtn.Add_Click({ Start-Run 'revert' })
$ui.CancelBtn.Add_Click({
    $sync.Cancel = $true
    $ui.CancelBtn.IsEnabled = $false
    $ui.CancelBtn.Content = "Stopping$([char]0x2026)"
})
$ui.PresetBtn.Add_Click({ Set-Preset })
$ui.PresetBtn.ToolTip = New-TextBlock 'ticks the stuff i''d recommend. nothing happens until you hit apply.' 12 $null -Wrap
$ui.LastBtn.Add_Click({ [void](Import-SavedProfile) })
$ui.LastBtn.ToolTip = New-TextBlock 'ticks whatever you applied last time.' 12 $null
$ui.AllBtn.Add_Click({ foreach ($it in $Items) { $it.Box.IsChecked = $true } })
$ui.NoneBtn.Add_Click({ foreach ($it in $Items) { $it.Box.IsChecked = $false } })
$ui.LogToggleBtn.Add_Click({ Show-Log (-not $script:LogOpen) })
$ui.HideLogBtn.Add_Click({ Show-Log $false })
$ui.OpenLogsBtn.Add_Click({
    if (-not (Test-Path -LiteralPath $LogDir)) { $null = New-Item -ItemType Directory -Path $LogDir -Force }
    Start-Process explorer.exe "`"$LogDir`""
})
foreach ($el in $ui.ApplyBtn, $ui.RevertBtn, $ui.CancelBtn, $ui.PresetBtn, $ui.DYes, $ui.DNo, $ExplorerBtn, $RebootBtn) { [Splat.Motion]::Press($el, 0.96) }

# ---- window: dark title bar + Mica, icon
$window.Add_SourceInitialized({
    $hwnd = (New-Object Windows.Interop.WindowInteropHelper $window).Handle
    [Splat.Glass]::DarkTitleBar($hwnd)
    if ($script:WinBuild -ge 22621 -and [Splat.Glass]::EnableMica($hwnd)) {
        [Windows.Interop.HwndSource]::FromHwnd($hwnd).CompositionTarget.BackgroundColor = [Windows.Media.Colors]::Transparent
        $window.Background = [Windows.Media.Brushes]::Transparent
        $ui.Sidebar.Background = [Windows.Media.Brushes]::Transparent
    }
})
# App icon (embedded so the script works on its own) - used for the sidebar logo and the taskbar/title bar
$IconB64 = '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAMCAgICAgMCAgIDAwMDBAYEBAQEBAgGBgUGCQgKCgkICQkKDA8MCgsOCwkJDRENDg8QEBEQCgwSExIQEw8QEBD/2wBDAQMDAwQDBAgEBAgQCwkLEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBD/wAARCABkAGQDAREAAhEBAxEB/8QAHQAAAgMBAQEBAQAAAAAAAAAABgcEBQgDAgABCf/EADcQAAIBAwIFAgUCBAYDAQAAAAECAwQFEQAGBxIhMUETYRQiUXGBCDJSkaGxFRZCweHwIyTS8f/EABsBAAIDAQEBAAAAAAAAAAAAAAIDAAEEBQYH/8QAJhEAAgMAAgICAgIDAQAAAAAAAAECAxEhMQQSE0EFUSIyBhRhI//aAAwDAQACEQMRAD8AY1RfLJwl2waq/VMD8i5GYwCcnzjOMf21zI9HYkhBbx/XRSU800W3qGd0JIZlYBCPsf740Xo/oB+sewGm/VTS7z5rbfYWQSMDGZOvK3XyD7+dVZF9hwcd4JlruzVbuaScyIwwMHx40hmiK0Ltt0VwrqqNIiw6jJPgapdhzxLDT/DewziCKSOTDL5z505dGSTHrtuSehKepJzeO2tFfBhtjvQaQVUFdzAuFk5ex86N9CcYvt97fs1Tcaa4XWqRJKQER5YKFz376yTWs0U6osCatuH94qGppr9bqiqU8rQQTqWTxggecaKMYvgKU5RTaRMWlETpTw4MSDCsBgEeMddba2ZJJvkCt12SOXnBQZGfprQZpSaZQ2fbaVdCuY8mFmiPQeDkf0I1MGqXBlP9WG7TWubYKphRUQ5qgI3Vuvyr+Sf765UP5Pg7VnC0ydS1dOatZJeSPuQMZA1qSSMc22e7rTW+vtUF5s0bUs7TNFJA5GG6ZDL1z7Hp41bSfAEJy9sHb+numuM9FVVNxEoiBCIH8Y//AH+msNsUnwdCubZoqzVtNQtF6XKAOrHsTpa4HPZDo2fvVKYxxxrlMBuYaYmsEyg+hu23eNPVRKVZeYYOj9xTqwmJuxIZhK8gUA4PXU92D8P/AAX36g+GdVxm2o8u2NwVFJd6MGSOESH0qj6o49x51Jr2egx/8+DDEmyd/bAuNlrtxRz217vLOtvmNUjsWhk9NyyKxdVD9AWAyc4zg6a/Hco8F/MuUzcex5rzPtW3SXiSVpJKeNmBYnBIB1K24P0fZntaktiJ7id+pOzcPd81m0dw2WteCHkPxsDK/KGQN8ydCO/jOtsHqMM4sLNn7+sd+scN6s9f6lHWkyxMylSR26gjp209poqLWGIOPN3ut/l3HQPbUi55aeqpGSLCyRJkMgYdCRkHHfvrk0NctnZ8neEjPlJZ7xcZjFS2yslkY45IoWYn8Af9xpzlH9mf1m+kNvh7+nzcF2mp7nulGt9HG3MKdj/5XH4/bn+ekTuXSH10fcjQ1FZaO0USUtHGI4owAB/vrPrfZsgvoiRVslRUiNW6L8nTQs1wghvbIpXFEreoT9OuqWhOtdjBoZKyhiEgLZ/20fJXxJn7/mKreWSFweU9/bQuT6D/ANbAlsN6raFknjkbGBq4yafIqfjJoz7+sHYMklzoOKNiXkjrDHBWpGDkzg4Rhjye33xrf41jckjk+RV8aY8+H9xqNybfrrdb0D3Db/pJPHzfLKzRhyqnsCCSpz0BGp5U3C5tGWmLda0zB+ojhzbL7X3jiDc4qsVTxRxiFHx6LqAuT9e2lRtbYFleAbwu3Xc7HtSO0/4kwFNM6qAhOAcED+uuxVKLitMnq4l/suxwfBrPWxAyyD5xjlzn215xts9JGPt2E0lHQUceIIEjx/CNUXmPgitOZPlQDGokR9E2eyVUtslq4U5mVCQo89NMUQYSxi4s14ignnE45XEueVu+lzT06NLUhl7X4nWe11MFvrqlIzIwABOhjLDXKrUPS1XKC4wRvEysjgdRrQmmL+Lng+npYIK0ocYIydBJI11wTjpPW5UFFAPXkCr1RQfJ0GxXZmsrk+Yh7w7ttp3RRVdNc7bT11MkiOI54g68w6g4Ixka10HC/Jp1yS/YxKfh/tqloXp7DbobOZcszUUaxczHuSFGCdOsh7bI5EbGmkZs44cL7hFRXCy3NfiqauhkeOdYgjF16jLZ7+5741inFpmpSUjNXC7bT3GxVbzWSXmgr5IASn7gqJ1/rrqePU3WnpislsuiVHXR0w+U6456KGnGouRn6A/8ahUm9PNDNyyDnPY56nVoBrBgbZr6f01jkcEN0xnTEA+DpuPgjt7eC/GW5vhKvPNzx9Ax9xqNaSu1wkZi438Gt87SqRcmqJZY4mzG6HGP5apZHs6sLvkQ7f0wb8vN72XBBe2f4mldoct3YA4B0tySliOr41TlD+Q44bnLU3WSMkkrjz7ar22RtdajVwBtfLuvdPEL/D6GNkttEwjU9cM3k6RbCUpcGF3V01vTXfC6yix2tYQMu6guT5bXT8dZE8Z59vy2aMuhkDAowx9NaDmgXxUoUqbeshhMjjIXlzk/y0m4bU8Z/P8A3Tc+Jex9zXSzbfuNppaJ6lqhI5YGLgvjJP8ALQxvcViY34XLkEkrkcdVPX31kO30eXq1iBbGdQVKXJwp7gwZnZseQNWgd0vrRenWUEMQv30aKGNtbeEtO6j1SRnwdW5YTMDbcUdo3pYno6uJJWaM9x2Ogk/boOqThMT/AA1sf+Wq2ptixFQtQxHT30iEW58nr6J+9YzbRmW+sFBPzDt9tTP54jVY0qG2M3h9teOetkq3gCnnypI1ojHWeM863G0h42um+GjRUx2663RWI4FklJl+ob0+Zehx30QgDt+VoipP/YqHUKCSQucaTa0htXZjHeO59lVu4auc3O4k83KTHTx8uR9+p1mUdOgpSS6EXJWiPoiHGlnQbOc9zQpy8jZOrRnfZFStaRiOTH30RCZSXJImGXwc9tEiBVaLvHEByv1PXOqZBg7T3DIswWRzyHA76nqWF0lkp3rkuVIOkh+fA/vqeh1vE8jFyWe3KRY631kXmkkl5Rge+oo4zZf5mV+o/tn2kU9DllAkXGfvjWiFe8nkPLv2YZ0kuFXA69iPpp//AA58v2W8buU6g9dQoBeIiepEaYVAhkkRgrFWI+5wD/bSrehtZnus4VbWNVK9bc9vPK7FicwqfyFZRn8A6Qmh/u0ZNqatFJzGqD7ZOk4dLWVss0UrZXvoijljHYatIh45CWzoiF3QI+UAbooydWgX2F1lu8Ubxx83XI86jQUXyNvad9FTSyRSsO3TRZo9Np8BBsioPxAlZ8uHyAfHXvooRTYzyJpxHZt3cEwKCRgFcYOtCWLDiXQTeh3a6mEYmMisCevtqGSWl7JVw+jzL2Hkav6BM5cc+KW37bfEsF1qkjYYYepG0kfXP7uRgw/GsVs9fqbKILNYsZd1Tu3NS2vblXF/pkW4MPxhpcj86QaMijOdSKJyVkyxHhe2fc6M0lXLSEuWjUKvgDVohHeF1OfGdEQ+ZSvU9ABqZpNw9UdbO59FDhSME+caJAtl5bCwqF5G7anZcexk2O7JRUBeSQKWGMA6ZGLHRehps69wK3qyyKCoBHX36aOMHEl3PQ69v3GmeNW5g3y/Xtphz5xbYwbZWQ+iW5gWHy4B7nV4Y5xekTcu+odv2h2WaMSt0jDnoGPbP50EpJICEdkZB4hC07nvU8169K0XR3Z1+JfmpqgfxB8fIfxj86xZvLNf9VwL24Cptk4o63b9Vzoo5WjQyI6+GV1yGHuCdWkT3TBqCjLHnlJHXOProNN5K+FDghV7D6ashX1SrA551OfHvolyQGb1eUpULAke2jSJmlDHu000atnq5OPtqx9dHv2XFn3hM5Eg7seXOjjg+Hi/8GJaL768SrMwzgYB06LNMPFehpaq4IFaOU5fAP8AP/nVSkl0dCr8epdoP7Du2rpWjQyEYbPU+NJdr3B0/wATBpvB519/S12qiKFhPVQesBg9fGdSc/U8L5Ffra0J/ce8JZp5KirZhg8soOeVlz1yO4+47d9IcylH9AZfrbbb9Qmjqpz6TDngkUAmM/xL4x9V7YPYdgUeSuUxPV8O+Nt1s1ro9w1NLCjcypDWNEhz/qC5840xAOPJ9YKqO5UcUvqhnZeZsaS4OPZ0VJMIIKFpPkRc9NUW2j1cdstNTgtGwLHC4XOTq46gXNIVu7duzpO8LoQAOn00fZcZJvQIvFiqaWlSVEYrGMN+T31Z0fEuTljOdikdJkRiQMjOouDsQh7Pgb+3o4ZLdNM2WlVIfSKn9uc82f6Dt/LTVPDXVU3LA924kpaJiw6YOSe3TSJM7FdWLkY+2bQlfPFRxMZKirkCoB3Yn/YDqfbQpazN5XkRoqlKXSGTva6vSVEFHQVUg+HiWABXI7Dv9fqdVZyz5hKfzSdj+2Li4Sz1E4lkRZhMuHBAyfBGdAWnhWQW6Ki9SnqoXWBm8DKg+GX6H/p0Ueyn+xjWDhxRV9qgq2jgq1kGUlwM8v0OexByMa0KTQltswhtncE1qZYZZAI4hyv7uey/gd9Psh7jFZg+9m3K23FYVZ05mXJzpHxDVYmhtWnbtDc6MsnKwKlRjpolBdCp24DO4eD8d4/ZAFYDPMUJyPtolVpFdgJ3HghLBAY6yk5kmBWTK5AX6H6aL4l9jK/I9ZeyYD1/6VN0ioWs2nUw1kEilxBNIIpE9sn5SPckeOmhdL+ju+J+apg8uRcWPgnxHpnWjqNo3Tn6ANHCXQ9P4lyP66B1z/R6Gn8p4n9nNIYNo4McR5UAawvSRRY5pKqZYQo+pDEE/YAnSvik++B9n+QeBWv7DZ2ZsiLaNM0k9XHX3KVOUygHkjU91jz3z5boT2wOuWeiS4PF/mPzk/yMvSCyBxuVmq6irYCJmZupI65OlODbOQrF9nazcN625VCQCnIGepI7atUtlStSCO6cFvirLUUyzCGodCInPhh2JHnrpipwpWa0hVWHf952vT1FhakqpHoqqSF3pnJjZlOMjp7aNUto6H+ss0wNXSPHFTqrHqnqH3Ynqda30c2bDnbd/udHKkFPPyqAEz5wNChfs8H1wy3lfae/0tGKhXhmIDo4yD1A+vudLtWJYRPTW9ostBV06SyowLd+U48DRRBlwUm56GnjlkhUHkjAABP1zqMkXjBGG5VFDuEUNOEEbB2OR1+SMMB9ssc6W5NPgPd7L+57hudDbzUU0oRlUMOnnCf/AEdKlZLeyJIHLzuu+zOHeub9nYdBjp0+3/GhcmyNLSHw03Bca8zNUMh5ah0AAIGAxGcZ76Orkpj3sdvo5oDUSQKXVcg486diKLixxok7sqgEDA1f0RLSbOi1tTHTzfsJOQvTOqRF2UN1sNlp66RI7ZCATzHGVyfJPKRk+566L2Ybumvs/9k='
try {
    $iconStream = New-Object IO.MemoryStream (, [Convert]::FromBase64String($IconB64))
    $iconImg = New-Object Windows.Media.Imaging.BitmapImage
    $iconImg.BeginInit()
    $iconImg.CacheOption = 'OnLoad'
    $iconImg.StreamSource = $iconStream
    $iconImg.EndInit()
    $iconImg.Freeze()
    $window.Icon = $iconImg
    $logoBrush = New-Object Windows.Media.ImageBrush $iconImg
    $logoBrush.Stretch = 'UniformToFill'
    $ui.Logo.Background = $logoBrush
} catch { }

$wa = [Windows.SystemParameters]::WorkArea
if ($window.Height -gt $wa.Height - 30) { $window.Height = [math]::Max($window.MinHeight, $wa.Height - 30) }
if ($window.Width -gt $wa.Width - 30) { $window.Width = [math]::Max($window.MinWidth, $wa.Width - 30) }

# ---------------------------------------------------------------- updates (from GitHub)
# version.json on the repo's main branch says what's current; updating downloads the
# repo zip and swaps in every changed file (logs and your saved picks are left alone).
$UpdateCheckCode = @'
param($sync, $repo)
try {
    $v = Invoke-RestMethod -Uri "https://raw.githubusercontent.com/$repo/main/version.json" -UseBasicParsing -TimeoutSec 15 -Headers @{ 'Cache-Control' = 'no-cache' }
    $sync.Queue.Enqueue(@{ T = 'update'; Version = [string]$v.version; Notes = [string]$v.notes })
} catch { $sync.Queue.Enqueue(@{ T = 'update'; Error = $_.Exception.Message }) }
'@

$UpdateApplyCode = @'
param($sync, $repo, $appRoot)
$ProgressPreference = 'SilentlyContinue'
$tmp = Join-Path $env:TEMP ('splat-update-' + [guid]::NewGuid())
try {
    $null = New-Item -ItemType Directory -Path $tmp -Force
    $zip = Join-Path $tmp 'update.zip'
    Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing -TimeoutSec 180
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $tmp 'x') -Force
    $src = Get-ChildItem -LiteralPath (Join-Path $tmp 'x') -Directory | Select-Object -First 1
    if (-not $src -or -not (Test-Path -LiteralPath (Join-Path $src.FullName 'assets\Splats-Optimizer.ps1'))) { throw 'the download doesn''t look like splat''s optimizer, nothing was changed.' }
    $changed = 0
    $failed = @()
    foreach ($f in Get-ChildItem -LiteralPath $src.FullName -Recurse -File) {
        $rel = $f.FullName.Substring($src.FullName.Length + 1)
        if ($rel -like 'assets\logs\*' -or $rel -eq 'assets\Splats-Optimizer-profile.json' -or $rel -like '.git*') { continue }
        $dest = Join-Path $appRoot $rel
        if ((Test-Path -LiteralPath $dest) -and (Get-FileHash -LiteralPath $dest).Hash -eq (Get-FileHash -LiteralPath $f.FullName).Hash) { continue }
        try {
            $null = New-Item -ItemType Directory -Path (Split-Path $dest) -Force
            Copy-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction Stop
            $changed++
        } catch { $failed += $rel }
    }
    $sync.Queue.Enqueue(@{ T = 'updated'; Changed = $changed; Failed = $failed })
} catch {
    $sync.Queue.Enqueue(@{ T = 'updated'; Error = $_.Exception.Message })
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
'@

$script:UpdateMsg = $null
$script:UpdateManual = $false
function Start-UpdateCheck([bool]$Manual) {
    if (-not $UpdateRepo) {
        if ($Manual) { [void](Show-Dialog -Title 'updates aren''t set up yet' -Body 'there''s no github repo linked in the script yet.') }
        return
    }
    $script:UpdateManual = $Manual
    if ($Manual) { $UpdateBtn.IsEnabled = $false; $UpdateBtn.Content = "Checking$([char]0x2026)" }
    $script:MiscJobs.Add((Start-Bg $UpdateCheckCode @($sync, $UpdateRepo)))
}
function Resolve-UpdateMsg {
    $m = $script:UpdateMsg
    $script:UpdateMsg = $null
    $UpdateBtn.IsEnabled = $true
    $UpdateBtn.Content = 'Check for updates'
    if ($m.T -eq 'update') {
        $newer = $false
        try { $newer = [version]$m.Version -gt [version]$AppVersion } catch { }
        if ($m.Error -or -not $newer) {
            if ($script:UpdateManual) {
                if ($m.Error) { [void](Show-Dialog -Title 'couldn''t check for updates' -Body $m.Error) }
                else { [void](Show-Dialog -Title 'you''re up to date' -Body "you're on $AppVersion, that's the latest.") }
            }
            return
        }
        $body = "version $($m.Version) is out, you have $AppVersion."
        if ($m.Notes) { $body += "`n`n$($m.Notes)" }
        if (-not (Show-Dialog -Title 'update available' -Body $body -Yes 'Update' -No 'Later')) { return }
        if ($script:Running -or $script:AppJob) {
            [void](Show-Dialog -Title 'not right now' -Body 'wait for whatever''s running to finish, then hit check for updates on the start page.')
            return
        }
        $UpdateBtn.IsEnabled = $false
        $UpdateBtn.Content = "Updating$([char]0x2026)"
        $script:MiscJobs.Add((Start-Bg $UpdateApplyCode @($sync, $UpdateRepo, (Split-Path $ScriptDir))))
    } elseif ($m.T -eq 'updated') {
        if ($m.Error) { [void](Show-Dialog -Title 'update failed' -Body $m.Error); return }
        $body = "updated $($m.Changed) file(s)."
        if (@($m.Failed).Count) { $body += " couldn't replace $(@($m.Failed) -join ', ') right now, those get picked up next time." }
        if (Show-Dialog -Title 'updated' -Body "$body restart to use the new version." -Yes 'Restart' -No 'Later') {
            Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$(Join-Path $ScriptDir 'Splats-Optimizer.ps1')`"")
            [Environment]::Exit(0)
        }
    }
}

$window.Add_ContentRendered({
    Move-NavIndicator -Instant
    Update-Status
    Update-Toggles
    Start-AppScan
    $timer.Start()
})
$window.Add_Closing({
    if ($script:DialogFrame) { $_.Cancel = $true; return }
    if ($script:Running -or $script:AppJob) {
        if (-not (Show-Dialog -Title 'still running' -Body 'something''s still going. if you close now it gets cut off halfway.' -Yes 'Close anyway' -No 'Keep going')) {
            $_.Cancel = $true
            return
        }
    }
})

# ---- initial state: nothing ticked - the user decides
$ui.LastBtn.IsEnabled = Test-Path -LiteralPath $ProfilePath
Update-Selection
$NavItems['start'].IsChecked = $true

[void]$window.ShowDialog()
[Environment]::Exit(0)
