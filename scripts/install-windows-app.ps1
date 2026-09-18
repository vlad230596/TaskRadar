# Installs the TaskRadar Windows client for the current user: copies the build
# out of the build tree, puts a Start-menu shortcut in front of it, and -- on
# request -- starts it with Windows.
#
# Why a script rather than "double-click taskradar.exe":
#
# 1. **The build tree is not an installation.** `flutter clean`, a branch switch
#    or the next `flutter build windows` rewrites
#    `app/build/windows/x64/runner/Release`, and a shortcut or a Startup entry
#    pointing into it breaks silently -- the app simply stops opening one day.
#    So the build is copied to a stable location first and everything else
#    points there.
#
# 2. **The shortcut is load-bearing, not a convenience.** Windows will not show
#    a toast for an *unpackaged* Win32 app unless a shortcut carrying that app's
#    AppUserModelID exists in the Start menu; `flutter build windows` does not
#    create one. The app already declares its AppUserModelID
#    (`com.taskradar.app`, in `app/lib/notifications/local_notification_gateway.dart`),
#    and this script writes the same string into the shortcut's property store,
#    which is the half that was missing. Setting that property is why this is
#    not four lines of WScript.Shell: the scripting object cannot write it, so
#    the shortcut is built through IShellLink + IPropertyStore below.
#
#    That closes the deployment gap described in
#    `app/lib/notifications/notification_gateway.dart`. It does **not** promote
#    desktop toasts into F1's acceptance: F1 is about a phone surviving a night
#    of battery optimisation, and no shortcut on a desktop says anything about
#    that.
#
# Everything is per-user (no elevation, nothing under HKLM, nothing in Program
# Files), because this is a single-user personal tool and asking for an
# administrator to install it would be theatre.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows-app.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows-app.ps1 -Autostart
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows-app.ps1 -Uninstall
[CmdletBinding()]
param(
    # The build to install. Defaults to this repository's release build.
    [string] $Source,

    # Where the app lands. Per-user, and deliberately not Program Files.
    [string] $InstallPath = (Join-Path $env:LOCALAPPDATA 'Programs\TaskRadar'),

    # The Start-menu folder. Overridable so the script can be exercised without
    # touching the real Start menu.
    [string] $StartMenuPath = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),

    # The Startup folder, for the same reason as above.
    [string] $StartupPath = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),

    # Also start TaskRadar when this user signs in. Off by default: an app that
    # installs itself into startup uninvited is a bad neighbour, and the board
    # is a thing you open in the morning, not a thing that opens you.
    [switch] $Autostart,

    # Remove the shortcuts and the installed copy. Leaves no data behind because
    # there is none here -- the token is in Windows' own credential store and
    # the board snapshot is in the app-support directory, both of which belong
    # to the app, not to this installation.
    [switch] $Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Everything in this file stays ASCII, including the shortcut descriptions:
# Windows PowerShell 5.1 reads a .ps1 as the system ANSI codepage unless it
# carries a UTF-8 BOM, and a Cyrillic string in a BOM-less file is not a mangled
# tooltip -- it is a parse error that kills the whole script.
$appName = 'TaskRadar'
$exeName = 'taskradar.exe'

# Must match the `appUserModelId` the app initialises the notification plugin
# with. If these two ever disagree, Windows has no way to connect a toast to
# this app and the toast is dropped with no error anywhere.
$appUserModelId = 'com.taskradar.app'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $Source) {
    # Two layouts, because this script now ships in two places: a developer's
    # checkout, where the build sits in the tree, and the release zip from
    # .github/workflows/app-release.yml, where the script sits next to a
    # TaskRadar folder holding the same files. Each candidate is accepted only
    # if it actually contains the exe, so an empty or half-copied directory
    # falls through to the next one rather than being picked and then failing
    # later with a confusing message.
    $candidates = @(
        (Join-Path $repositoryRoot 'app\build\windows\x64\runner\Release'),
        (Join-Path $PSScriptRoot 'TaskRadar'),
        $PSScriptRoot
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate $exeName)) {
            $Source = $candidate
            break
        }
    }
    if (-not $Source) { $Source = $candidates[0] }
}

$shortcutPath = Join-Path $StartMenuPath "$appName.lnk"
$autostartShortcutPath = Join-Path $StartupPath "$appName.lnk"

# --- the COM half -----------------------------------------------------------
#
# A shortcut with an AppUserModelID has to be created through IShellLink and
# IPropertyStore; `WScript.Shell`'s CreateShortcut has no way to set a property
# on the link. The declarations below are the minimum needed to create one, read
# the property back, and prove it landed.

if (-not ('TaskRadar.Shortcuts.ShortcutTool' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace TaskRadar.Shortcuts
{
    [ComImport]
    [Guid("00021401-0000-0000-C000-000000000046")]
    internal class ShellLink { }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("000214F9-0000-0000-C000-000000000046")]
    internal interface IShellLinkW
    {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, IntPtr pfd, uint fFlags);
        void GetIDList(out IntPtr ppidl);
        void SetIDList(IntPtr pidl);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxPath);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxPath);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
        void GetHotkey(out short pwHotkey);
        void SetHotkey(short wHotkey);
        void GetShowCmd(out int piShowCmd);
        void SetShowCmd(int iShowCmd);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
        void Resolve(IntPtr hwnd, uint fFlags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("0000010b-0000-0000-C000-000000000046")]
    internal interface IPersistFile
    {
        void GetClassID(out Guid pClassID);
        [PreserveSig] int IsDirty();
        void Load([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, uint dwMode);
        void Save([MarshalAs(UnmanagedType.LPWStr)] string pszFileName, [MarshalAs(UnmanagedType.Bool)] bool fRemember);
        void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string pszFileName);
        void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string ppszFileName);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PropertyKey
    {
        public Guid FormatId;
        public uint PropertyId;

        public PropertyKey(Guid formatId, uint propertyId)
        {
            FormatId = formatId;
            PropertyId = propertyId;
        }
    }

    // Only the one case this script needs: VT_LPWSTR. A general PROPVARIANT
    // marshaller is a small library of its own and nothing here would use it.
    [StructLayout(LayoutKind.Sequential)]
    internal class PropVariant : IDisposable
    {
        private ushort valueType;
        private ushort reserved1;
        private ushort reserved2;
        private ushort reserved3;
        private IntPtr pointerValue;
        private IntPtr padding;

        private const ushort VT_EMPTY = 0;
        private const ushort VT_LPWSTR = 31;

        public static PropVariant FromString(string value)
        {
            return new PropVariant
            {
                valueType = VT_LPWSTR,
                pointerValue = Marshal.StringToCoTaskMemUni(value)
            };
        }

        public string AsString()
        {
            return valueType == VT_LPWSTR ? Marshal.PtrToStringUni(pointerValue) : null;
        }

        public void Dispose()
        {
            if (valueType == VT_LPWSTR && pointerValue != IntPtr.Zero)
            {
                Marshal.FreeCoTaskMem(pointerValue);
                pointerValue = IntPtr.Zero;
            }
            valueType = VT_EMPTY;
            GC.SuppressFinalize(this);
        }
    }

    [ComImport]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    [Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99")]
    internal interface IPropertyStore
    {
        void GetCount(out uint propertyCount);
        void GetAt(uint index, out PropertyKey key);
        void GetValue(ref PropertyKey key, [In, Out] PropVariant value);
        void SetValue(ref PropertyKey key, PropVariant value);
        void Commit();
    }

    public static class ShortcutTool
    {
        // PKEY_AppUserModel_ID. Fixed by Windows; see the shell property schema.
        private static PropertyKey AppUserModelIdKey =
            new PropertyKey(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);

        public static void Create(
            string shortcutPath,
            string targetPath,
            string workingDirectory,
            string description,
            string appUserModelId)
        {
            IShellLinkW link = (IShellLinkW)new ShellLink();
            link.SetPath(targetPath);
            link.SetWorkingDirectory(workingDirectory);
            link.SetDescription(description);
            link.SetIconLocation(targetPath, 0);

            IPropertyStore store = (IPropertyStore)link;
            using (PropVariant value = PropVariant.FromString(appUserModelId))
            {
                PropertyKey key = AppUserModelIdKey;
                store.SetValue(ref key, value);
                store.Commit();
            }

            ((IPersistFile)link).Save(shortcutPath, true);
            Marshal.ReleaseComObject(link);
        }

        // Reads the property back out of a saved shortcut, which is the only
        // way to know the write actually took.
        public static string ReadAppUserModelId(string shortcutPath)
        {
            IShellLinkW link = (IShellLinkW)new ShellLink();
            ((IPersistFile)link).Load(shortcutPath, 0);

            IPropertyStore store = (IPropertyStore)link;
            using (PropVariant value = new PropVariant())
            {
                PropertyKey key = AppUserModelIdKey;
                store.GetValue(ref key, value);
                string result = value.AsString();
                Marshal.ReleaseComObject(link);
                return result;
            }
        }

        public static string ReadTarget(string shortcutPath)
        {
            IShellLinkW link = (IShellLinkW)new ShellLink();
            ((IPersistFile)link).Load(shortcutPath, 0);

            StringBuilder path = new StringBuilder(260);
            link.GetPath(path, path.Capacity, IntPtr.Zero, 0);
            Marshal.ReleaseComObject(link);
            return path.ToString();
        }
    }
}
'@
}

function New-TaskRadarShortcut {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Target,
        [Parameter(Mandatory = $true)][string] $Description
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    [TaskRadar.Shortcuts.ShortcutTool]::Create(
        $Path,
        $Target,
        (Split-Path -Parent $Target),
        $Description,
        $appUserModelId)

    # Proving it rather than assuming it: a shortcut whose AppUserModelID did
    # not stick looks exactly like one that worked, right up until a reminder
    # does not appear.
    $written = [TaskRadar.Shortcuts.ShortcutTool]::ReadAppUserModelId($Path)
    if ($written -ne $appUserModelId) {
        throw "Shortcut '$Path' was created without its AppUserModelID (got '$written', expected '$appUserModelId')."
    }
}

# --- uninstall --------------------------------------------------------------

if ($Uninstall) {
    foreach ($path in @($shortcutPath, $autostartShortcutPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
            Write-Host "Removed $path"
        }
    }

    if (Test-Path -LiteralPath $InstallPath) {
        Remove-Item -LiteralPath $InstallPath -Recurse -Force
        Write-Host "Removed $InstallPath"
    }

    Write-Host 'TaskRadar is uninstalled. The signed-in session and the cached board are untouched.'
    return
}

# --- install ----------------------------------------------------------------

$sourceExe = Join-Path $Source $exeName
if (-not (Test-Path -LiteralPath $sourceExe)) {
    throw @"
No build at '$Source'.

From the release zip, run this script from the folder it was unpacked into --
it expects a 'TaskRadar' folder beside it -- or pass -Source explicitly.

From a checkout, build it first:
    cd app
    flutter build windows --release --dart-define=TASKRADAR_API_URL=https://<your-host>

The API base URL is baked in at build time; a build without it talks to
http://localhost:3001, which is only right when the backend runs on this machine.
"@
}

# A running instance holds its own exe open, and the copy below would fail
# halfway through with a locked-file error -- leaving an installation that is
# half one version and half another.
$running = Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($exeName)) -ErrorAction SilentlyContinue
if ($running) {
    throw "$appName is running (PID $($running.Id -join ', ')). Close it and run this again."
}

if (-not (Test-Path -LiteralPath $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
}

# Mirror, not merge: a file that a previous version shipped and this one does
# not (a renamed plugin DLL, say) has to disappear, or it stays on disk forever
# and may even be loaded.
$robocopy = Start-Process -FilePath 'robocopy.exe' `
    -ArgumentList @($Source, $InstallPath, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP') `
    -NoNewWindow -Wait -PassThru

# Robocopy's exit codes are a bit field: < 8 means it did its job (0 = nothing
# to copy, 1 = files copied, 2 = extras removed, and combinations). 8 and above
# are real failures.
if ($robocopy.ExitCode -ge 8) {
    throw "Copying the build failed (robocopy exit code $($robocopy.ExitCode))."
}

$installedExe = Join-Path $InstallPath $exeName

New-TaskRadarShortcut -Path $shortcutPath -Target $installedExe `
    -Description 'TaskRadar project board'

Write-Host "Installed to $InstallPath"
Write-Host "Start-menu shortcut: $shortcutPath (AppUserModelID $appUserModelId)"

if ($Autostart) {
    New-TaskRadarShortcut -Path $autostartShortcutPath -Target $installedExe `
        -Description 'TaskRadar project board (autostart)'
    Write-Host "Autostart shortcut: $autostartShortcutPath"
} elseif (Test-Path -LiteralPath $autostartShortcutPath) {
    # Without this, re-running the script without -Autostart would leave an
    # older autostart shortcut pointing at the old install path -- the exact
    # stale-shortcut failure this script exists to prevent.
    New-TaskRadarShortcut -Path $autostartShortcutPath -Target $installedExe `
        -Description 'TaskRadar project board (autostart)'
    Write-Host "Autostart shortcut refreshed: $autostartShortcutPath (use -Uninstall to remove it)"
}

Write-Host ''
Write-Host 'Toasts on Windows: the shortcut is the part Windows requires and the'
Write-Host 'part the Flutter build does not create. It is still not F1 acceptance --'
Write-Host 'that is a phone question (app/NOTIFICATIONS-CHECKLIST.md).'
