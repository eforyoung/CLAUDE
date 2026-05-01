param()
$eve_ip = "192.168.195.129"
$buf = New-Object byte[] 32768

function Read-All($stream, [int]$waitMs = 3000) {
    Start-Sleep -Milliseconds $waitMs
    $out = ""
    $ext = (Get-Date).AddMilliseconds(500)
    while ((Get-Date) -lt $ext) {
        if ($stream.DataAvailable) {
            $n = $stream.Read($buf, 0, $buf.Length)
            $raw = $buf[0..($n-1)]; $i = 0
            while ($i -lt $raw.Count) {
                if ($raw[$i] -eq 0xFF) { $i += 3; continue }
                $out += [char]$raw[$i]; $i++
            }
            $ext = (Get-Date).AddMilliseconds(500)
        } else { Start-Sleep -Milliseconds 50 }
    }
    return $out
}
function Send($stream, [string]$cmd) {
    $bytes = [System.Text.Encoding]::ASCII.GetBytes("$cmd`r`n")
    $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
}
function RunCmds([int]$port, [string]$label, [string[]]$cmds, [int]$longWait = 4000) {
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
        # pings need longer wait
        $wait = if ($cmd -match '^ping') { 10000 } else { $longWait }
        $out = Read-All $s $wait
        $lines = ($out -replace "`r","") -split "`n"
        $lines = $lines | Where-Object { $_ -notmatch "^$([regex]::Escape($cmd))\s*$" -and $_ -notmatch '^\S+[#>]\s*$' }
        Write-Host ($lines -join "`n").Trim()
    }
    Send $s "exit"; $c.Close()
}

# LEAF-1: ping underlay + clear counters + check ARP for VPC IPs
RunCmds 32770 "LEAF-1 - Underlay ping and ARP" @(
    "ping 10.22.255.252 count 5",
    "show ip arp vlan 10",
    "show mac address-table dynamic vlan 10",
    "clear ip arp vlan 10 force-delete",
    "clear mac address-table dynamic vlan 10",
    "show interface nve1 counters"
)

# LEAF-2: same
RunCmds 32771 "LEAF-2 - Underlay ping and ARP" @(
    "ping 10.22.255.253 count 5",
    "show ip arp vlan 10",
    "show mac address-table dynamic vlan 10",
    "clear ip arp vlan 10 force-delete",
    "clear mac address-table dynamic vlan 10",
    "show interface nve1 counters"
)

Write-Host ""
Write-Host "Tables cleared. Now go to the VPC console and run:" -ForegroundColor Green
Write-Host "  VPC5: ip 10.0.12.1/24 10.0.12.254" -ForegroundColor Yellow
Write-Host "        ping 10.0.12.2" -ForegroundColor Yellow
Write-Host "  VPC6: ip 10.0.12.2/24 10.0.12.254" -ForegroundColor Yellow
Write-Host "        ping 10.0.12.1" -ForegroundColor Yellow
Write-Host ""
Write-Host "Waiting 30 seconds for you to run pings, then checking counters..." -ForegroundColor Green
Start-Sleep -Seconds 30

# Post-ping check
RunCmds 32770 "LEAF-1 - Post-ping state" @(
    "show ip arp vlan 10",
    "show mac address-table dynamic vlan 10",
    "show interface nve1 counters"
)

RunCmds 32771 "LEAF-2 - Post-ping state" @(
    "show ip arp vlan 10",
    "show mac address-table dynamic vlan 10",
    "show interface nve1 counters"
)

Write-Host ""
Write-Host "Done." -ForegroundColor Green
