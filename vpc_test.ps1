param()

$eve_ip = "192.168.195.129"
$buf = New-Object byte[] 16384

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

function RunVPC([int]$port, [string]$label, [string[]]$cmds) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host " $label" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect($eve_ip, $port)
    $s = $c.GetStream(); $s.ReadTimeout = 200

    # Initial banner drain
    $banner = Read-All $s 3000
    Write-Host "[connected, prompt/banner]"
    Write-Host ($banner -replace "`r","")

    foreach ($cmd in $cmds) {
        Write-Host ""
        Write-Host "[$cmd]" -ForegroundColor Yellow
        Send $s $cmd
        $out = Read-All $s 4000
        Write-Host ($out -replace "`r","")
    }

    $c.Close()
}

function RunNXOS([int]$port, [string]$label, [string[]]$cmds) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host " $label" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan

    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect($eve_ip, $port)
    $s = $c.GetStream(); $s.ReadTimeout = 200

    # Login
    Read-All $s 4000 | Out-Null
    Send $s "admin";    Read-All $s 2000 | Out-Null
    Send $s "Cisco123"; Read-All $s 3000 | Out-Null
    Send $s "terminal length 0"; Read-All $s 2000 | Out-Null

    foreach ($cmd in $cmds) {
        Write-Host ""
        Write-Host "[$cmd]" -ForegroundColor Yellow
        Send $s $cmd
        $out = Read-All $s 4000
        # Strip echoed command and trailing prompt
        $lines = ($out -replace "`r","") -split "`n"
        $lines = $lines | Where-Object { $_ -notmatch "^$([regex]::Escape($cmd))" -and $_ -notmatch '^\S+#\s*$' }
        Write-Host ($lines -join "`n").Trim()
    }

    Send $s "exit"
    $c.Close()
}

# VPC5 - connected to LEAF-1 Eth1/2 (VLAN 10)
RunVPC 32773 "VPC5 - LEAF-1 side" @(
    "show ip",
    "ip 10.0.12.1/24 10.0.12.254",
    "show ip",
    "ping 10.0.12.254",
    "ping 10.0.12.2"
)

# VPC6 - connected to LEAF-2 Eth1/2 (VLAN 10)
RunVPC 32774 "VPC6 - LEAF-2 side" @(
    "show ip",
    "ip 10.0.12.2/24 10.0.12.254",
    "show ip",
    "ping 10.0.12.254",
    "ping 10.0.12.1"
)

# LEAF-1 post-ping verification
RunNXOS 32770 "LEAF-1 - Post-ping verification" @(
    "show mac address-table vlan 10",
    "show ip arp suppression-cache detail",
    "show nve peers detail"
)

Write-Host ""
Write-Host "All tests complete." -ForegroundColor Green
