# ニシキ冷蔵 — 出庫お知らせ（PC）  upload 121
#   タスク スケジューラ が 毎日 15:30（-When 1530）と 16:15（-When 1615）に 動かす。
#   サーバー（Apps Script api=alert）に まだ 🚚 出庫済み で ない 伝票を 聞く → あれば 窓（案 B — 残りの 行まで）。
#   窓は ログインしている 全部の PC に 出る。音（チャイム ＋ 声）は 1台だけ — 順番は サーバーの ALERT_ORDER（1番 → 2番 → 3番）。
#   前の PC が 1分 来ない（電源 OFF・ネット なし）・音が 出せない → 次の PC。どこかで OK → 全部の 音が 止まる。
#   この PC の 番 = role.txt（サーバーの ALERT_ORDER の id か other）— install.txt / setup.ps1 -Role で 決める。
#   試す: powershell -ExecutionPolicy Bypass -File shukko_alert.ps1 -Test
param([string]$When = "1615", [switch]$Test, [switch]$Silent, [string]$Role = "", [string]$Tid = "", [string]$Api = "", [switch]$Watch, [switch]$Broadcast)

$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Url     = "https://script.google.com/macros/s/__DEPLOY__/exec"
$Key     = "__KEY__"
$Chime   = Join-Path $Here "chime.wav"
$SoundPs = Join-Path $Here "shukko_sound.ps1"
$Log     = Join-Path $Here "alert.log"
$Repeat  = 60      # 秒ごとに くり返す
$MaxMin  = 30      # 分で あきらめる
$PollSec = 15      # 秒ごとに サーバーに 聞く（音の 番・OK）

function Log($t) { try { Add-Content -Path $Log -Value ((Get-Date -Format "yyyy-MM-dd HH:mm:ss") + "  [" + $Role + "] " + $t) -Encoding UTF8 } catch {} }
if ($Api) { $Url = $Api }
if (-not $Role) { $rf = Join-Path $Here "role.txt"; $Role = if (Test-Path $rf) { ([IO.File]::ReadAllText($rf)).Trim().ToLower() } else { "other" } }
if ($Test -and -not $Tid) { $Tid = "t" + (Get-Date -Format "yyyyMMddHHmm") }
$Base = $Url + "?api=alert&key=" + $Key + "&when=" + $When + "&pcid=" + $Role + $(if ($Tid) { "&tid=" + $Tid } else { "" })

if (-not $Test -and -not $Broadcast -and -not $Watch -and (Get-Date).Hour -ge 18) { Log "skip (late start)"; exit }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
function GetJson($u, $sec) {
  $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec $sec -Uri $u
  $ms = New-Object IO.MemoryStream; $r.RawContentStream.CopyTo($ms)
  [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json
}

# ── 見張り（-Watch・2分ごと 8:00〜18:00 — watch.vbs）— テスト送信が あれば 本物と 同じ お知らせを 出す（upload 122）──
if ($Watch) {
  try { $j = GetJson ($Base + "&act=check") 60 } catch { exit }
  if ($j.ok -and $j.test -and $j.test.tid) {
    $sf = Join-Path $Here "seen_test.txt"; $seen = if (Test-Path $sf) { ([IO.File]::ReadAllText($sf)).Trim() } else { "" }
    if ($seen -ne [string]$j.test.tid) {
      [IO.File]::WriteAllText($sf, [string]$j.test.tid)
      Log ("test alert from " + $j.test.by)
      $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ('"' + $PSCommandPath + '"'), "-When", "1615", "-Broadcast", "-Tid", [string]$j.test.tid, "-Role", $Role)
      if ($Api) { $a += @("-Api", $Api) }; if ($Silent) { $a += "-Silent" }
      Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList $a
    }
  }
  exit
}

# ── 聞く（hello — 伝票 ＋ 音の 番）──
$data = $null; $err = ""; $st0 = $null
for ($i = 0; $i -lt 3 -and -not $data; $i++) {
  try { $j = GetJson ($Base + "&act=hello") 90; if ($j.ok) { $data = $j; $st0 = $j.st } else { $err = [string]$j.error } }
  catch { $err = $_.Exception.Message; if ($i -lt 2) { Start-Sleep -Seconds 20 } }
}
if ($Test) {
  function It($l, $i, $n, $q, $o) { [pscustomobject]@{ loc = $l; id = $i; name = $n; qty = $q; ok = $o } }
  $data = [pscustomobject]@{ ok = $true; when = $When; st = $st0; slips = @(
    [pscustomobject]@{ time = "09:30"; client = "99. サンプル冷凍"; hikitori = "本社"; tantou = "佐藤"; unso = "西濃"; state = "積み込み待ち"; lines = 3; done = 3; items = @() },
    [pscustomobject]@{ time = "11:00"; client = "99. サンプル冷凍"; hikitori = "サンプル物流"; tantou = "山田"; unso = "ヤマト"; state = "ピッキング中"; lines = 3; done = 1; items = @(
      (It "5-12" "10001" "冷凍えび 30尾 1kg" 8 $true), (It "6-21" "10003" "さば フィレ 10kg" 3 $false), (It "7-03" "10002" "いか リング 500g" 5 $false)) }) }
}
if (-not $data) { Log ("error: " + $err) }
elseif (-not $data.slips -or @($data.slips).Count -eq 0) { Log ($When + " none"); exit }

# ── 言う こと — 「サンプル冷凍様、担当者、佐藤様、本社、積み込み待ち。」（引取先 は 言葉を 言わず 名前だけ・会社なら 様）──
$slips = @(); if ($data) { $slips = @($data.slips) }
function Sama($n) { $n = ([string]$n -replace '^\s*\d+\.\s*', '').Trim(); if (-not $n) { "" } elseif ($n -match '様$') { $n } else { $n + "様" } }
function Place($h) { $h = ([string]$h).Trim(); if (-not $h) { "" } elseif ($h -match '(本社|本店|支店|営業所|センター|倉庫|工場|直送|自社|当社|店)$') { $h } else { Sama $h } }
function SayState($s) { if ($s.state -eq "未") { "ピッキング前" } else { $s.state } }
if ($data) {
  $msg = "出庫お知らせです。まだ 出庫済みに なって いない 伝票が " + $slips.Count + "件 あります。"
  $k = 0
  foreach ($s in $slips) {
    if ($k -ge 6) { break }
    $parts = @(Sama $s.client)
    if ($s.tantou) { $parts += "担当者"; $parts += (Sama $s.tantou) }
    if ($s.hikitori) { $parts += (Place $s.hikitori) }
    $parts += (SayState $s)
    $msg += ($parts -join "、") + "。"; $k++
  }
  if ($slips.Count -gt 6) { $msg += "ほか " + ($slips.Count - 6) + "件。" }
} else { $msg = "出庫お知らせを 読めませんでした。出庫一覧を 確かめて ください。" }
if ($Broadcast) { $msg = "これは テストです。" + $msg }

# ── 窓（案 B）— システムと 同じ 色と 形（空色の 背景・白い カード・深い 緑・からし・さんご色）──
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
function X($t) { [Security.SecurityElement]::Escape([string]$t) }
$font = "Noto Sans JP, Yu Gothic UI, Meiryo"
$rows = ""; $i = 0
foreach ($s in $slips) {
  $pill = if ($s.state -eq "積み込み待ち") { "#E3F0FA|#1D5F8A|#9CC6E6|積み込み待ち" } elseif ($s.state -eq "ピッキング中") { "#FBF1D4|#7A5A00|#E0B038|ピッキング中 " + $s.done + "/" + $s.lines } else { "#F1F8FC|#6E8A84|#CFE3EC|ピッキング前" }
  $p = $pill.Split("|")
  $who = @(); if ($s.tantou) { $who += "担当者 " + (Sama $s.tantou) }; if ($s.hikitori) { $who += (Place $s.hikitori) }; if ($s.unso) { $who += [string]$s.unso }
  $line = if ($i -gt 0) { "0,1,0,0" } else { "0" }
  if ($s.state -eq "積み込み待ち") {
    $body = "<Border Margin=`"64,0,0,0`" Background=`"#E3F0FA`" BorderBrush=`"#9CC6E6`" BorderThickness=`"1`" CornerRadius=`"10`" Padding=`"12,7`"><TextBlock Text=`"$(X ('全部 ✓（' + $s.lines + ' 行）— トラックに 積んだら スキャン画面で 出庫 確定'))`" FontSize=`"13.5`" FontWeight=`"Bold`" Foreground=`"#1D5F8A`" TextWrapping=`"Wrap`"/></Border>"
  } else {
    $ln = ""; $n = 0
    foreach ($l in @($s.items)) {
      $c1 = if ($l.ok) { "#9AB0AA" } else { "#2F6B57" }; $c2 = if ($l.ok) { "#9AB0AA" } else { "#4F6D66" }; $c3 = if ($l.ok) { "#9AB0AA" } else { "#23403A" }
      $mark = if ($l.ok) { "<TextBlock Grid.Column=`"4`" Text=`"✓`" FontSize=`"15`" FontWeight=`"Bold`" Foreground=`"#2F6B57`" HorizontalAlignment=`"Center`"/>" } else { "<TextBlock Grid.Column=`"4`" Text=`"まだ`" FontSize=`"12`" FontWeight=`"Bold`" Foreground=`"#A9563F`" HorizontalAlignment=`"Center`" VerticalAlignment=`"Center`"/>" }
      $bt = if ($n -gt 0) { "0,1,0,0" } else { "0" }
      $ln += "<Border BorderBrush=`"#EDF3F6`" BorderThickness=`"$bt`" Padding=`"10,5`"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width=`"62`"/><ColumnDefinition Width=`"58`"/><ColumnDefinition Width=`"*`"/><ColumnDefinition Width=`"56`"/><ColumnDefinition Width=`"46`"/></Grid.ColumnDefinitions>" +
        "<TextBlock Text=`"$(X $l.loc)`" FontFamily=`"Consolas`" FontWeight=`"Bold`" FontSize=`"13.5`" Foreground=`"$c1`" VerticalAlignment=`"Center`"/>" +
        "<TextBlock Grid.Column=`"1`" Text=`"$(X $l.id)`" FontFamily=`"Consolas`" FontSize=`"13.5`" Foreground=`"$c2`" VerticalAlignment=`"Center`"/>" +
        "<TextBlock Grid.Column=`"2`" Text=`"$(X $l.name)`" FontSize=`"13.5`" Foreground=`"$c3`" TextTrimming=`"CharacterEllipsis`" VerticalAlignment=`"Center`"/>" +
        "<TextBlock Grid.Column=`"3`" Text=`"$(X $l.qty)`" FontSize=`"13.5`" FontWeight=`"Bold`" Foreground=`"$c3`" HorizontalAlignment=`"Right`" VerticalAlignment=`"Center`"/>$mark</Grid></Border>"
      $n++
    }
    $body = "<Border Margin=`"64,0,0,0`" BorderBrush=`"#EDF3F6`" BorderThickness=`"1`" CornerRadius=`"10`"><StackPanel>$ln</StackPanel></Border>"
  }
  $rows += @"
<Border BorderBrush="#EDF3F6" BorderThickness="$line" Padding="16,12"><StackPanel>
 <Grid><Grid.ColumnDefinitions><ColumnDefinition Width="64"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
  <TextBlock Text="$(X $s.time)" FontFamily="Consolas" FontSize="17" Foreground="#4F6D66" VerticalAlignment="Center"/>
  <TextBlock Grid.Column="1" Text="$(X $s.client)" FontSize="17" FontWeight="Bold" Foreground="#23403A" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
  <Border Grid.Column="2" Background="$($p[0])" BorderBrush="$($p[2])" BorderThickness="1" CornerRadius="10" Padding="10,2,10,3" VerticalAlignment="Center" Margin="10,0,0,0">
   <TextBlock Text="$(X $p[3])" FontSize="13" FontWeight="Bold" Foreground="$($p[1])"/></Border>
 </Grid>
 <TextBlock Text="$(X ($who -join '  ·  '))" FontSize="13" Foreground="#4F6D66" Margin="64,2,0,8"/>
 $body
</StackPanel></Border>
"@
  $i++
}
if (-not $data) { $rows = "<TextBlock Margin=`"16`" Text=`"$(X ('読めませんでした: ' + $err))`" FontSize=`"15`" Foreground=`"#A9563F`" TextWrapping=`"Wrap`"/>" }
$title = if ($Broadcast) { "出庫お知らせ（テスト）" } else { "出庫お知らせ" }
$when2 = if ($Broadcast) { "テスト" } elseif ($When -eq "1530") { "15:30" } else { "16:15" }
$why = if ($Broadcast) { "テスト送信 — " + $(if ($data -and $data.test) { [string]$data.test.by + " " + (Get-Date -Format "HH:mm") } else { "" }) } elseif ($When -eq "1530") { "2時間 以上 前の 伝票" } else { "締めの 前 — 全部の 伝票" }
$maxH = [int]([System.Windows.SystemParameters]::WorkArea.Height - 330); if ($maxH -lt 200) { $maxH = 200 }
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
  Title="出庫お知らせ" Width="800" SizeToContent="Height" WindowStartupLocation="CenterScreen" Topmost="True"
  WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="NoResize" FontFamily="$font">
 <Border Background="#D7EDFB" CornerRadius="22" Padding="18" Margin="14" BorderBrush="#B9DCD2" BorderThickness="1">
  <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="4" Opacity="0.28"/></Border.Effect>
  <StackPanel>
   <Border Background="White" CornerRadius="14" BorderBrush="#CFE3EC" BorderThickness="1" Padding="18,12">
    <DockPanel>
     <Border DockPanel.Dock="Right" Background="#FBF1D4" BorderBrush="#E0B038" BorderThickness="1" CornerRadius="12" Padding="12,3" VerticalAlignment="Center">
      <TextBlock Text="$when2" FontFamily="Consolas" FontSize="18" FontWeight="Bold" Foreground="#7A5A00"/></Border>
     <StackPanel><TextBlock Text="$title" FontSize="24" FontWeight="Bold" Foreground="#2F6B57"/>
      <TextBlock Text="ニシキ冷蔵 · 出庫一覧" FontSize="12" Foreground="#6E8A84"/></StackPanel>
    </DockPanel></Border>
   <Border Background="#F9EBE5" BorderBrush="#E6B8A8" BorderThickness="1" CornerRadius="14" Padding="16,12" Margin="0,10,0,0">
    <TextBlock FontSize="17" FontWeight="Bold" Foreground="#A9563F" TextWrapping="Wrap">⚠ まだ 出庫済みに なって いない 伝票 $($slips.Count) 件<Run FontSize="13" FontWeight="Normal" Text="　（$why）"/></TextBlock></Border>
   <Border Background="White" CornerRadius="14" BorderBrush="#CFE3EC" BorderThickness="1" Margin="0,10,0,0">
    <ScrollViewer MaxHeight="$maxH" VerticalScrollBarVisibility="Auto"><StackPanel>$rows</StackPanel></ScrollViewer></Border>
   <Button x:Name="OkBtn" Height="58" Margin="0,14,0,0" Cursor="Hand">
    <Button.Template><ControlTemplate TargetType="Button"><Border x:Name="b" Background="#2F6B57" CornerRadius="14">
      <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
     <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#24574A"/></Trigger></ControlTemplate.Triggers>
    </ControlTemplate></Button.Template>
    <TextBlock x:Name="OkTxt" Text="OK（止める）" FontSize="20" FontWeight="Bold" Foreground="White"/></Button>
   <TextBlock x:Name="Foot" Text="音: 順番を 確かめて います…" FontSize="12" Foreground="#6E8A84" HorizontalAlignment="Center" Margin="0,8,0,0"/>
  </StackPanel></Border></Window>
"@
$f = [Windows.Markup.XamlReader]::Parse($xaml)
$ok = $f.FindName("OkBtn"); $okTxt = $f.FindName("OkTxt"); $foot = $f.FindName("Foot")
$f.Add_MouseLeftButtonDown({ try { $f.DragMove() } catch {} })

# ── 音 — 別の 小さな プロセス（shukko_sound.ps1）。止める = そのプロセスを 終わらせる（すぐ 静かに なる）──
$MsgFile = Join-Path $env:TEMP ("nishiki_alert_" + $When + "_" + $PID + ".txt")
[IO.File]::WriteAllText($MsgFile, $msg, (New-Object Text.UTF8Encoding $true))
$script:child = $null; $script:soundDone = $false; $script:failed = $false; $script:acked = $false
function StartSound {
  if ($script:child -or $script:soundDone -or $script:failed -or -not (Test-Path $SoundPs)) { return }
  $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ('"' + $SoundPs + '"'), "-MsgFile", ('"' + $MsgFile + '"'),
         "-Chime", ('"' + $Chime + '"'), "-Parent", $PID, "-Repeat", $Repeat, "-MaxMin", $MaxMin)
  if ($Silent) { $a += "-Silent" }
  $script:child = Start-Process -FilePath powershell.exe -ArgumentList $a -WindowStyle Hidden -PassThru
  $null = $script:child.Handle
  Log ($When + " sound start")
}
function StopSound {
  if ($script:child) { try { if (-not $script:child.HasExited) { $script:child.Kill() } } catch {}; $script:child = $null; Log ($When + " sound stop") }
}
function HmOf($ms) { try { [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$ms).ToLocalTime().ToString("HH:mm") } catch { "" } }
function Apply($st) {
  if (-not $st) { return }
  if ($st.ack) { $script:acked = $true; StopSound; $okTxt.Text = "閉じる"; $foot.Text = "OK 済み — " + $st.ack.by + " " + (HmOf $st.ack.at) + "（音は 止まりました）"; return }
  if ($st.play) { StartSound } elseif ($script:child) { StopSound }
  $foot.Text = if ($st.sound) { "音: " + $st.sound + " の PC" + $(if ($st.play) { "（この PC）" } else { "" }) + " — OK を 押すまで 1分ごとに チャイムと 声" } else { "音: 順番を 待っています" }
}
function NewWc { $w = New-Object Net.WebClient; $w.Encoding = [Text.Encoding]::UTF8; $w }
function SendAsync($act) { try { $null = (NewWc).DownloadStringTaskAsync($Base + "&act=" + $act) } catch {} }

$started = Get-Date; $script:pend = $null; $script:lastPoll = Get-Date; $script:lastOk = Get-Date
$tick = New-Object System.Windows.Threading.DispatcherTimer; $tick.Interval = [TimeSpan]::FromSeconds(1)
$tick.Add_Tick({
  try {
    if ($script:child -and $script:child.HasExited) {
      $code = $script:child.ExitCode; $script:child = $null
      if ($code -eq 3) { $script:failed = $true; Log ($When + " sound failed, next PC"); SendAsync "fail"; $foot.Text = "この PC は 音が 出せません — 次の PC に まかせます" }
      else { $script:soundDone = $true }
    }
    if ($script:pend -and $script:pend.IsCompleted) {
      $t = $script:pend; $script:pend = $null
      if (-not $t.IsFaulted) { $script:lastOk = Get-Date; $j = $t.Result | ConvertFrom-Json; if ($j.ok) { Apply $j.st } }
    }
    if (-not $script:pend -and -not $script:acked -and ((Get-Date) - $script:lastPoll).TotalSeconds -ge $PollSec) {
      $script:lastPoll = Get-Date; $script:pend = (NewWc).DownloadStringTaskAsync($Base + "&act=poll")
    }
    if ($script:child -and ((Get-Date) - $script:lastOk).TotalSeconds -gt 60) { StopSound }   # サーバーに 届かない → 次の PC に まかせる
    if (((Get-Date) - $started).TotalMinutes -ge $MaxMin + 1) { $tick.Stop() }
  } catch { Log ("tick error: " + $_.Exception.Message) }
})
$ok.Add_Click({
  StopSound
  try { Log ($When + " OK pressed after " + [int](((Get-Date) - $started).TotalSeconds) + "s") } catch {}
  if ($data -and -not $script:acked) { $f.Hide(); try { $null = GetJson ($Base + "&act=ok") 25; Log ($When + " OK shared") } catch { Log ("OK send failed: " + $_.Exception.Message) } }
  try { Remove-Item $MsgFile -ErrorAction SilentlyContinue } catch {}
  [System.Diagnostics.Process]::GetCurrentProcess().Kill()
})
$f.Add_ContentRendered({ $f.Activate() | Out-Null; if ($data) { Apply $st0; $tick.Start() } })
$f.Add_Closed({ StopSound; [System.Diagnostics.Process]::GetCurrentProcess().Kill() })
Log ($When + " alert: " + $slips.Count + " slips" + $(if ($Test) { " (test " + $Tid + ")" } else { "" }))
[void]$f.ShowDialog()
