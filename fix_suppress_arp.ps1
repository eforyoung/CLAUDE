param()
$eve_ip = "192.168.195.129"
$buf = New-Object byte[] 32768

function Read-All($stream, [int]$waitMs = 3000) {
    Start-Sleep -Milliseconds $waitMs
    $out = ""
    $ext = (Get-Date).AddMilliseconds(800)
    while ((Get-Date) -lt $ext) {
        if ($stream.DataAvailable) {
            $n = $stream.Read($buf, 0, $buf.Length)
            $raw = $buf[0..($n-1)]; $i = 0
            while ($i -lt $raw.Count) {
                if ($raw[$i] -eq 0xFF) { $i += 3; continue }
                $out += [char]$raw[$i]; $i++
            }
            $ext = (Get-Date).AddMilliseconds(800)
        } else { Start-Sleep -Milliseconds 50 }
    }
    return $out
}
function Send($stream, [string]$cmd) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("$cmd`r`n")
    $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
}
function Configure([int]$port, [string]$label, [string[]]$cmds) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host " $label" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect($eve_ip, $port); $s = $c.GetStream(); $s.ReadTimeout = 200
    Read-All $s 4000 | Out-Null
    Send $s "admin";    Read-All $s 2000 | Out-Null
    Send $s "Cisco123"; Read-All $s 3000 | Out-Null
    Send $s "terminal length 0"; Read-All $s 2000 | Out-Null
    foreach ($cmd in $cmds) {
        Write-Host "  $cmd" -ForegroundColor Yellow
        Send $s $cmd
        Read-All $s 3000 | Out-Null
    }
    Send $s "exit"; $c.Close()
}
function Check([int]$port, [string]$label, [string[]]$cmds) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host " $label" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect($eve_ip, $port); $s = $c.GetStream(); $s.ReadTimeout = 200
    Read-All $s 4000 | Out-Null
    Send $s "admin";    Read-All $s 2000 | Out-Null
    Send $s "Cisco123"; Read-All $s 3000 | Out-Null
    Send $s "terminal length 0"; Read-All $s 2000 | Out-Null
    foreach ($cmd in $cmds) {
        Write-Host ""; Write-Host "[$cmd]" -ForegroundColor Yellow
        Send $s $cmd
        $wait = if ($cmd -match '^ping') { 12000 } else { 4000 }
        $out = Read-All $s $wait
        $lines = ($out -replace "`r","") -split "`n"
        $lines = $lines | Where-Object { $_ -notmatch "^$([regex]::Escape($cmd))\s*$" -and $_ -notmatch '^\S+[#>]\s*$' }
        Write-Host ($lines -join "`n").Trim()
    }
    Send $s "exit"; $c.Close()
}

Write-Host ""
Write-Host "Applying suppress-arp to VNI 10010 on both leafs..." -ForegroundColor Magenta

Configure 32770 "LEAF-1 - Add suppress-arp" @(
    "configure terminal",
    "interface nve1",
    "member vni 10010",
    "suppress-arp",
    "end",
    "copy running-config startup-config"
)

Configure 32771 "LEAF-2 - Add suppress-arp" @(
    "configure terminal",
    "interface nve1",
    "member vni 10010",
    "suppress-arp",
    "end",
    "copy running-config startup-config"
)

Write-Host ""
Write-Host "Waiting 5 seconds for ARP suppression cache to populate from BGP..." -ForegroundColor Green
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "Verifying ARP suppression cache and NVE VNI state..." -ForegroundColor Magenta

Check 32770 "LEAF-1 - Post-fix verification" @(
    "show nve vni 10010",
    "show ip arp suppression-cache detail",
    "ping 10.0.12.2 vrf default count 3"
)

Check 32771 "LEAF-2 - Post-fix verification" @(
    "show nve vni 10010",
    "show ip arp suppression-cache detail",
    "ping 10.0.12.1 vrf default count 3"
)

Write-Host ""
Write-Host "Fix applied. Now test VPC1->VPC2 ping from the VPC consoles." -ForegroundColor Green
Write-Host "  VPC5: ping 10.0.12.2" -ForegroundColor Yellow
Write-Host "  VPC6: ping 10.0.12.1" -ForegroundColor Yellow
