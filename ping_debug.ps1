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

function RunCmds([int]$port, [string]$label, [string[]]$cmds) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host " $label" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect($eve_ip, $port)
    $s = $c.GetStream(); $s.ReadTimeout = 200

    Read-All $s 4000 | Out-Null
    Send $s "admin";    Read-All $s 2000 | Out-Null
    Send $s "Cisco123"; Read-All $s 3000 | Out-Null
    Send $s "terminal length 0"; Read-All $s 2000 | Out-Null

    foreach ($cmd in $cmds) {
        Write-Host ""
        Write-Host "[$cmd]" -ForegroundColor Yellow
        Send $s $cmd
        $out = Read-All $s 4000
        $lines = ($out -replace "`r","") -split "`n"
        $lines = $lines | Where-Object { $_ -notmatch "^$([regex]::Escape($cmd))\s*$" -and $_ -notmatch '^\S+[#>]\s*$' }
        Write-Host ($lines -join "`n").Trim()
    }

    Send $s "exit"
    $c.Close()
}

$leaf1Cmds = @(
    "show interface Ethernet1/2",
    "show interface Vlan10",
    "show mac address-table vlan 10",
    "show ip arp vlan 10",
    "show nve peers",
    "show nve vni",
    "show bgp l2vpn evpn",
    "show vlan id 10"
)

$leaf2Cmds = @(
    "show interface Ethernet1/2",
    "show interface Vlan10",
    "show mac address-table vlan 10",
    "show ip arp vlan 10",
    "show nve peers",
    "show nve vni",
    "show bgp l2vpn evpn",
    "show vlan id 10"
)

RunCmds 32770 "LEAF-1 (port 32770)" $leaf1Cmds
RunCmds 32771 "LEAF-2 (port 32771)" $leaf2Cmds

Write-Host ""
Write-Host "Debug complete." -ForegroundColor Green
