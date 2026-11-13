# ニシキ冷蔵 — 出庫お知らせ の セットアップ（install.txt が 動かす）
#   -Role = この PC の 音の 番（サーバーの ALERT_ORDER の id。無い・other = ポップアップだけ）。
#   毎日 15:30 と 16:15 の お知らせ ＋ テスト送信の 見張り（2分ごと 8:00〜18:00）の タスクを 作る。
param([string]$Role = "other")
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Role = ([string]$Role).Trim().ToLower(); if (-not $Role) { $Role = "other" }
[IO.File]::WriteAllText((Join-Path $Here "role.txt"), $Role)
$pr  = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$ps  = Join-Path $Here "shukko_alert.ps1"
foreach ($w in "1530", "1615") {
  $act = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ("`"" + (Join-Path $Here "watch.vbs") + "`" -When " + $w)   # 黒い 窓 なし
  $trg = New-ScheduledTaskTrigger -Daily -At ($w.Substring(0, 2) + ":" + $w.Substring(2))
  $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  Register-ScheduledTask -TaskName ("Nishiki shukko alert " + $w) -Action $act -Trigger $trg -Settings $set -Principal $pr -Force | Out-Null
}
$act = New-ScheduledTaskAction -Execute "wscript.exe" -Argument ("`"" + (Join-Path $Here "watch.vbs") + "`"")
$trg = New-ScheduledTaskTrigger -Daily -At "08:00"
$trg.Repetition = (New-ScheduledTaskTrigger -Once -At "08:00" -RepetitionInterval (New-TimeSpan -Minutes 2) -RepetitionDuration (New-TimeSpan -Hours 10)).Repetition
$set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "Nishiki shukko alert watch" -Action $act -Trigger $trg -Settings $set -Principal $pr -Force | Out-Null
Write-Host ""
Write-Host ("  できました — 毎日 15:30 と 16:15 ＋ テスト送信の 見張り。この PC の 番 = " + $Role)
