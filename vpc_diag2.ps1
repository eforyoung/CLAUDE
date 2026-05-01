param()

# Test 1: blocking read on VPC5 port
Write-Host "=== Test 1: Blocking read on port 32773 ===" -ForegroundColor Cyan
$c = New-Object System.Net.Sockets.TcpClient
$c.Connect("192.168.195.129", 32773)
$s = $c.GetStream()
$s.ReadTimeout = 8000
$buf = New-Object byte[] 4096

Write-Host "TCP connected. Attempting blocking Read() with 8s timeout..."
try {
    $n = $s.Read($buf, 0, $buf.Length)
    Write-Host "Got $n bytes"
    Write-Host "Hex: $(($buf[0..($n-1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')"
    $printable = ($buf[0..($n-1)] | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } }) -join ''
    Write-Host "Text: $printable"
} catch {
    Write-Host "Timeout or error: $_"
}

# Send CR and try again
Write-Host "Sending CR..."
$cr = [byte[]](13,10)
$s.Write($cr,0,$cr.Length); $s.Flush()
try {
    $n = $s.Read($buf, 0, $buf.Length)
    Write-Host "After CR - Got $n bytes"
    $printable = ($buf[0..($n-1)] | ForEach-Object { if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' } }) -join ''
    Write-Host "Text: $printable"
} catch {
    Write-Host "Timeout after CR: $_"
}
$c.Close()

# Test 2: plink telnet
Write-Host "`n=== Test 2: plink telnet to VPC5 ===" -ForegroundColor Cyan
$plink = "C:\Program Files\PuTTY\plink.exe"
$cmds = "show ip`r`nping 10.0.12.2`r`n"
$result = $cmds | & $plink -telnet 192.168.195.129 -P 32773 -batch 2>&1
Write-Host $result

Write-Host "`nDone."
