' RIO LIFE OS detached launcher.
' WScript starts PowerShell hidden and does not wait for it, so no blank console
' window is left attached to the tray controller.
Option Explicit
Dim sh, fso, root, psExe, trayScript, command
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
psExe = sh.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
trayScript = fso.BuildPath(root, "tray.ps1")
command = Chr(34) & psExe & Chr(34) & " -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File " & Chr(34) & trayScript & Chr(34) & " -Startup"
sh.Run command, 0, False
