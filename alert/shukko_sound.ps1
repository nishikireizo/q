# ニシキ冷蔵 — 出庫お知らせの 音だけ（shukko_alert.ps1 が 動かす・止める時は この プロセスを 終わらせる）
#   チャイム → 声 → チャイム → 「繰り返します。」→ 声。$Repeat 秒ごと、$MaxMin 分まで。
#   音が 出せない → exit 3（お知らせの 窓が サーバーに 言って 次の PC へ）。親の 窓が 無くなったら 終わる。
param([string]$MsgFile, [string]$Chime = "", [int]$Parent = 0, [int]$Repeat = 60, [int]$MaxMin = 30, [switch]$Silent)
try {
  Add-Type -AssemblyName System.Speech
  $msg = [IO.File]::ReadAllText($MsgFile, [Text.Encoding]::UTF8)
  $v = New-Object System.Speech.Synthesis.SpeechSynthesizer
  # 日本語の 声（Haruka が 一番）。無い PC → チャイムだけ
  $ja = @($v.GetInstalledVoices() | Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -eq "ja-JP" })
  $pick = @($ja | Where-Object { $_.VoiceInfo.Name -match "Haruka" }) + $ja | Select-Object -First 1
  if ($pick) { $v.SelectVoice($pick.VoiceInfo.Name) }
  $jaOk = [bool]$pick
  if (-not $jaOk -and -not ($Chime -and (Test-Path $Chime))) { exit 3 }
  $v.Rate = -1; $v.Volume = $(if ($Silent) { 0 } else { 100 })
  $v.SetOutputToDefaultAudioDevice()
} catch { exit 3 }
$start = Get-Date
while ($true) {
  if ($Parent -and -not (Get-Process -Id $Parent -ErrorAction SilentlyContinue)) { exit 0 }
  $t0 = Get-Date
  try {
    if ($jaOk) {
      $pb = New-Object System.Speech.Synthesis.PromptBuilder ([System.Globalization.CultureInfo]::GetCultureInfo("ja-JP"))
      if ($Chime -and (Test-Path $Chime)) { $pb.AppendAudio($Chime) }
      $pb.AppendText($msg); $pb.AppendBreak([TimeSpan]::FromMilliseconds(700))
      if ($Chime -and (Test-Path $Chime)) { $pb.AppendAudio($Chime) }
      $pb.AppendText("繰り返します。"); $pb.AppendText($msg)
    } else {
      $pb = New-Object System.Speech.Synthesis.PromptBuilder
      $pb.AppendAudio($Chime); $pb.AppendBreak([TimeSpan]::FromMilliseconds(700)); $pb.AppendAudio($Chime); $pb.AppendBreak([TimeSpan]::FromMilliseconds(700)); $pb.AppendAudio($Chime)
    }
    $v.Speak($pb)
  } catch { exit 3 }
  if (((Get-Date) - $start).TotalMinutes -ge $MaxMin) { exit 0 }
  while (((Get-Date) - $t0).TotalSeconds -lt $Repeat) {
    Start-Sleep -Milliseconds 500
    if ($Parent -and -not (Get-Process -Id $Parent -ErrorAction SilentlyContinue)) { exit 0 }
  }
}
