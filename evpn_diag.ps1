param()
$eve_ip = "192.168.195.129"
$buf = New-Object byte[] 65536

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
function RunCmds([int]$port, [string]$label, [string[]]$cmds) {
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
        $wait = if ($cmd -match '^ping') { 12000 } else { 5000 }
        $out = Read-All $s $wait
        $lines = ($out -replace "`r","") -split "`n"
        $lines = $lines | Where-Object { $_ -notmatch "^$([regex]::Escape($cmd))\s*$" -and $_ -notmatch '^\S+[#>]\s*$' }
        Write-Host ($lines -join "`n").Trim()
    }
    Send $s "exit"; $c.Close()
}

Write-Host ""
Write-Host "Step 1: Check BGP EVPN routes and ARP suppression state" -ForegroundColor Magenta

RunCmds 32770 "LEAF-1 - BGP EVPN + ARP state" @(
    "show bgp l2vpn evpn summary",
    "show bgp l2vpn evpn",
    "show ip arp vlan 10",
    "show ip arp suppression-cache detail",
    "show nve vni 10010"
)

RunCmds 32771 "LEAF-2 - BGP EVPN + ARP state" @(
    "show bgp l2vpn evpn summary",
    "show bgp l2vpn evpn",
    "show ip arp vlan 10",
    "show ip arp suppression-cache detail",
    "show nve vni 10010"
)

Write-Host ""
Write-Host "Step 2: Ping VPC2 (10.0.12.2) from LEAF-1 SVI to test reachability" -ForegroundColor Magenta

RunCmds 32770 "LEAF-1 - SVI ping test to VPC2" @(
    "ping 10.0.12.2 vrf default count 3",
    "show ip arp vlan 10",
    "show ip arp suppression-cache detail"
)

Write-Host ""
Write-Host "Step 3: Check what VPC2 looks like from LEAF-2 after SVI ping" -ForegroundColor Magenta

RunCmds 32771 "LEAF-2 - State after LEAF-1 SVI ping" @(
    "show ip arp vlan 10",
    "show mac address-table dynamic vlan 10",
    "show bgp l2vpn evpn"
)

Write-Host ""
Write-Host "Done." -ForegroundColor Green
