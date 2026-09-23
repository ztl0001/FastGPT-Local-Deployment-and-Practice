$ErrorActionPreference = 'Stop'

$repoName = Split-Path -Leaf (Get-Location)
$owner = (git credential-manager github list | Select-Object -First 1)
if (-not $owner) {
    throw 'No GitHub account found in Git Credential Manager.'
}
$owner = $owner.Trim()

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'git'
$psi.Arguments = 'credential fill'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::Start($psi)
$process.StandardInput.Write("protocol=https`nhost=github.com`n`n")
$process.StandardInput.Close()
$credentialOutput = $process.StandardOutput.ReadToEnd()
$credentialError = $process.StandardError.ReadToEnd()
$process.WaitForExit()

if ($process.ExitCode -ne 0) {
    throw "git credential fill failed with exit code $($process.ExitCode): $credentialError"
}

$token = ($credentialOutput -split "`r?`n" | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
if (-not $token) {
    throw 'No GitHub token returned by Git Credential Manager.'
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{
    Authorization = "Bearer $token"
    'User-Agent' = 'codex-agent'
    Accept = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
}

$encodedOwner = [Uri]::EscapeDataString($owner)
$encodedRepo = [Uri]::EscapeDataString($repoName)
$repoUrl = "https://api.github.com/repos/$encodedOwner/$encodedRepo"

$existingRepo = $null
try {
    $existingRepo = Invoke-RestMethod -Uri $repoUrl -Headers $headers -Method Get
    Write-Output "Repository already exists: $($existingRepo.html_url)"
} catch {
    $statusCode = $null
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }
    if ($statusCode -ne 404) {
        throw
    }
}

if (-not $existingRepo) {
    $body = @{
        name = $repoName
        private = $false
        auto_init = $false
        description = 'FastGPT 本地部署与智能投顾助手实战教程'
    } | ConvertTo-Json

    $createdRepo = Invoke-RestMethod -Uri 'https://api.github.com/user/repos' -Headers $headers -Method Post -Body $body -ContentType 'application/json; charset=utf-8'
    Write-Output "Created repository: $($createdRepo.html_url)"
}

if (-not (Test-Path .git)) {
    git init -b main | Out-Host
}

git config user.name $owner
git config user.email "$owner@users.noreply.github.com"

if (-not (git remote get-url origin 2>$null)) {
    $remoteUrl = "https://github.com/$owner/$repoName.git"
    git remote add origin $remoteUrl
}

git add .
git commit -m 'Add FastGPT deployment and investment assistant tutorials'
git push -u origin main
