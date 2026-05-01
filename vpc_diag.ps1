param()
$ip = "192.168.195.129"; $port = 32773
$buf = New-Object byte[] 4096

$c = New-Object System.Net.Sockets.TcpClient
$c.Connect($ip, $port)
$s = $c.GetStream()
$s.ReadTimeout = 5000

Write-Host "Connected to VPC5 (port $port). Reading raw bytes for 5 seconds..."

# Read raw bytes and show hex + printable
$deadline = (Get-Date).AddSeconds(8)
$allBytes = @()

while ((Get-Date) -lt $deadline) {
    try {
        if ($s.DataAvailable) {
            $n = $s.Read($buf, 0, $buf.Length)
            $allBytes += $buf[0..($n-1)]
            Write-Host "Got $n bytes: $(($buf[0..($n-1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')"
            $printable = ($buf[0..($n-1)] | ForEach-Object {
                if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' }
            }) -join ''
            Write-Host "Printable: $printable"
        } else {
            Start-Sleep -Milliseconds 200
        }
    } catch { Write-Host "Read error: $_"; break }
}

Write-Host "`nSending CR to trigger prompt..."
$cr = [byte[]](0x0D, 0x0A)
$s.Write($cr, 0, $cr.Length); $s.Flush()

Start-Sleep -Milliseconds 2000
while ($s.DataAvailable) {
    $n = $s.Read($buf, 0, $buf.Length)
    Write-Host "After CR - Got $n bytes: $(($buf[0..($n-1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')"
    $printable = ($buf[0..($n-1)] | ForEach-Object {
        if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' }
    }) -join ''
    Write-Host "Printable: $printable"
}

# Send IAC DO SUPPRESS-GO-AHEAD, IAC DONT ECHO responses
Write-Host "`nSending telnet IAC responses..."
$iac = [byte[]](0xFF, 0xFD, 0x03,   # IAC DO SGA
               0xFF, 0xFC, 0x01,   # IAC WONT ECHO
               0xFF, 0xFC, 0x18,   # IAC WONT TERMINAL-TYPE
               0xFF, 0xFC, 0x1F)   # IAC WONT NAWS
$s.Write($iac, 0, $iac.Length); $s.Flush()

Start-Sleep -Milliseconds 2000
while ($s.DataAvailable) {
    $n = $s.Read($buf, 0, $buf.Length)
    Write-Host "After IAC - Got $n bytes: $(($buf[0..($n-1)] | ForEach-Object { '{0:X2}' -f $_ }) -join ' ')"
    $printable = ($buf[0..($n-1)] | ForEach-Object {
        if ($_ -ge 32 -and $_ -le 126) { [char]$_ } else { '.' }
    }) -join ''
    Write-Host "Printable: $printable"
}

$c.Close()
Write-Host "Done."
