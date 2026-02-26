# Deploy bingobingo_bot to EC2. Run: cd c:\src\anya_trade_app; .\bingobingo_bot\deploy-to-ec2.ps1

$EC2_HOST = "3.106.232.238"
$EC2_USER = "ubuntu"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$KEY_PATH = $null
foreach ($p in @(
    (Join-Path $ProjectRoot "openclaw.pem"),
    (Join-Path $env:USERPROFILE "openclaw.pem"),
    (Join-Path $env:USERPROFILE ".ssh\openclaw.pem"),
    "openclaw.pem"
)) {
    if (Test-Path $p) { $KEY_PATH = $p; break }
}
if (-not $KEY_PATH) {
    Write-Host "ERROR: openclaw.pem not found. Put it in one of:" -ForegroundColor Yellow
    Write-Host "  " $ProjectRoot\openclaw.pem
    Write-Host "  " $env:USERPROFILE\openclaw.pem
    exit 1
}

Write-Host "Key: $KEY_PATH"
# Fix .pem permissions so SSH accepts it (required on Windows)
icacls $KEY_PATH /inheritance:r /grant:r "${env:USERNAME}:R" | Out-Null

Write-Host "Creating remote directory..."
ssh -i $KEY_PATH -o StrictHostKeyChecking=accept-new "${EC2_USER}@${EC2_HOST}" "mkdir -p bingobingo_bot"
if ($LASTEXITCODE -ne 0) {
    Write-Host "SSH failed. Check network and EC2 port 22." -ForegroundColor Red
    exit 1
}

Write-Host "Uploading bingobingo_bot to $EC2_USER@${EC2_HOST} ..."
$RemoteDest = "${EC2_USER}@${EC2_HOST}:bingobingo_bot"
Push-Location "$ProjectRoot\bingobingo_bot"
Get-ChildItem -Force | ForEach-Object {
    $name = $_.Name
    if ($name -eq "." -or $name -eq "..") { return }
    scp -i $KEY_PATH -o StrictHostKeyChecking=accept-new -r $_.FullName "${RemoteDest}/"
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
Pop-Location

Write-Host "Done. SSH: ssh -i `"$KEY_PATH`" ${EC2_USER}@${EC2_HOST}" -ForegroundColor Green
Write-Host "Then run: cd bingobingo_bot"
