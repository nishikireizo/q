' Nishiki Reizo - shukko alert watcher (Task Scheduler, every 2 min). Runs PowerShell with no black window.
Set sh = CreateObject("WScript.Shell")
d = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & d & "shukko_alert.ps1"" -Watch", 0, False
