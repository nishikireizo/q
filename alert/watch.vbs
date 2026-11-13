' Nishiki Reizo - shukko alert starter (Task Scheduler). Runs PowerShell with no black window.
' No argument = watcher (every 2 min). With arguments (e.g. -When 1530) = the daily alert.
Set sh = CreateObject("WScript.Shell")
d = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
a = "-Watch"
If WScript.Arguments.Count > 0 Then
  a = ""
  For i = 0 To WScript.Arguments.Count - 1
    a = a & " " & WScript.Arguments(i)
  Next
End If
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & d & "shukko_alert.ps1"" " & a, 0, False
