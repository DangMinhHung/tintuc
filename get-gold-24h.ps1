# Lấy bảng giá vàng theo thương hiệu + biểu đồ SJC 30 ngày từ 24h.com.vn
# rồi gắn vào gold.table và gold.history của data\YYYY-MM-DD.js và data\latest.js.
# Dùng: powershell -ExecutionPolicy Bypass -File get-gold-24h.ps1 -Date yyyy-MM-dd
param([string]$Date = (Get-Date -Format "yyyy-MM-dd"))
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding($false)
$url = "https://www.24h.com.vn/gia-vang-hom-nay-c425.html"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$html = (Invoke-WebRequest $url -UseBasicParsing -UserAgent "Mozilla/5.0").Content

function Fmt($s) { ($s -replace '[^\d]', '') -replace '\B(?=(\d{3})+(?!\d))', '.' }

# --- Bảng giá ---
$rows = @()
$trs = [regex]::Matches($html, '(?s)<tr data-seach="[^"]*".*?</tr>')
foreach ($tr in $trs) {
  $t = $tr.Value
  $name = [regex]::Match($t, '<h2>\s*(.*?)\s*</h2>').Groups[1].Value.Trim()
  $tds = [regex]::Matches($t, '(?s)<td[^>]*>(.*?)</td>') | ForEach-Object { $_.Groups[1].Value }
  if ($tds.Count -lt 5 -or -not $name) { continue }
  $cell = foreach ($k in 1, 2) {
    $v = [regex]::Match($tds[$k], 'fixW">\s*([\d,\.]+)').Groups[1].Value
    $amt = [regex]::Match($tds[$k], '<span class="color\w+">\s*([\d,\.]+)\s*</span>').Groups[1].Value
    $sign = if ($tds[$k] -match 'btn_down') { "-" } elseif ($tds[$k] -match 'btn_up') { "+" } else { "" }
    $chg = if ($amt) { $sign + (Fmt $amt) } else { "0" }
    , @((Fmt $v), $chg)
  }
  $pb = Fmt ([regex]::Replace($tds[3], '<[^>]+>', ''))
  $ps = Fmt ([regex]::Replace($tds[4], '<[^>]+>', ''))
  $nm = $name -replace 'Qúy', 'Quý' -replace '^BTMH$', 'Bảo Tín Mạnh Hải' -replace '^BTMC VRTL$', 'BTMC Rồng Thăng Long' -replace '^BTMC SJC$', 'BTMC (vàng miếng SJC)' -replace '^DOJI HN$', 'DOJI Hà Nội' -replace '^DOJI SG$', 'DOJI TP.HCM'
  $rows += [pscustomobject]@{ name = $nm; buy = $cell[0][0]; sell = $cell[1][0]; buyChg = $cell[0][1]; sellChg = $cell[1][1]; prevBuy = $pb; prevSell = $ps }
}
$m = [regex]::Match($html, 'Cập nhật lúc\s*(\d{1,2}:\d{2})\s*\((\d{2}/\d{2}/\d{4})\)')
$upd = if ($m.Success) { $m.Groups[1].Value + " " + $m.Groups[2].Value } else { $null }
$hd = [regex]::Matches($html, 'Hôm (?:nay|qua)\s*\((\d{2}/\d{2}/\d{4})\)')
$table = [pscustomobject]@{
  today = if ($hd.Count -ge 1) { $hd[0].Groups[1].Value } else { $null }
  yesterday = if ($hd.Count -ge 2) { $hd[1].Groups[1].Value } else { $null }
  source = "24h.com.vn (giavang.net, pnj.com.vn, baotinmanhhai.vn)"; url = $url; time = $upd; rows = $rows
}

# --- Biểu đồ 30 ngày ---
$cat = [regex]::Match($html, "categories:\s*\[([^\]]+)\]").Groups[1].Value
$dates = @([regex]::Matches($cat, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$series = @([regex]::Matches($html, "data:\s*\[(\d[\d,\s]+)\]") | ForEach-Object { , @($_.Groups[1].Value -split ',' | ForEach-Object { [int]([long]$_.Trim() / 1000) }) })
$history = $null
if ($dates.Count -ge 2 -and $series.Count -ge 2 -and $series[0].Count -eq $dates.Count) {
  $history = [pscustomobject]@{ label = "SJC"; unit = "nghìn đồng/lượng"; dates = $dates; buy = $series[0]; sell = $series[1]
    source = "24h.com.vn"; url = $url; time = $dates[0] + "–" + $dates[-1] }
}

# --- Ghi vào file dữ liệu ---
$file = Join-Path $root "data\$Date.js"
$raw = [IO.File]::ReadAllText($file, $utf8).Trim()
$o = $raw.Substring("window.BANTIN = ".Length).TrimEnd(';') | ConvertFrom-Json
if (-not $o.gold) { $o | Add-Member -NotePropertyName gold -NotePropertyValue ([pscustomobject]@{}) -Force }
if ($rows.Count) { $o.gold | Add-Member -NotePropertyName table -NotePropertyValue $table -Force }
if ($history) { $o.gold | Add-Member -NotePropertyName history -NotePropertyValue $history -Force }
$out = "window.BANTIN = " + ($o | ConvertTo-Json -Depth 12 -Compress) + ";"
[IO.File]::WriteAllText($file, $out, $utf8)
[IO.File]::WriteAllText((Join-Path $root "data\latest.js"), $out, $utf8)
"rows=$($rows.Count) history=$(if($history){$dates.Count}else{0}) updated=$upd"
if ($rows.Count) { $s = $rows[0]; "SJC: $($s.buy)/$($s.sell) ($($s.buyChg)/$($s.sellChg)) hôm qua $($s.prevBuy)/$($s.prevSell)" }
