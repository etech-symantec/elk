#requires -Version 5.1
param(
    [ValidateSet('upgrade','check','plan','status')][string]$Action = 'upgrade',
    [string]$Version = 'latest',
    [string]$ScriptPath = ''
)
$ErrorActionPreference = 'Stop'
$PackageRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Unit = 'elk-stack-upgrade.service'
$ConsoleLog = '/var/log/elk-stack-upgrade-console.log'

function Info([string]$Text) { Write-Host ('[INFO] ' + $Text) -ForegroundColor Cyan }
function Ok([string]$Text) { Write-Host ('[ OK ] ' + $Text) -ForegroundColor Green }
function Warn([string]$Text) { Write-Host ('[WARN] ' + $Text) -ForegroundColor Yellow }
function Require([bool]$Test,[string]$Message) { if (-not $Test) { throw $Message } }

function Get-InstallerPath([string]$Requested) {
    if ($Requested) {
        Require (Test-Path -LiteralPath $Requested -PathType Leaf) ('Missing installation SH: ' + $Requested)
        return (Resolve-Path -LiteralPath $Requested).Path
    }
    foreach ($folder in @($PackageRoot, (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'))) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        $files = @(Get-ChildItem -LiteralPath $folder -Filter 'elk-oneclick-install-v*.sh' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($files.Count -gt 0) { return $files[0].FullName }
        $fallback = Join-Path $folder 'elk-oneclick-install.sh'
        if (Test-Path -LiteralPath $fallback -PathType Leaf) { return $fallback }
    }
    throw 'No generated elk-oneclick-install-v*.sh file was found. Put the original generated SH beside run-remote-upgrade.cmd (or in Downloads).'
}
function Get-ShellMeta([string]$Path,[string]$Key) {
    $prefix = $Key + '='
    foreach ($line in [IO.File]::ReadLines($Path)) {
        if ($line.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
            $v = $line.Substring($prefix.Length).Trim()
            if ($v.Length -ge 2) {
                if (($v[0] -eq "'" -and $v[$v.Length-1] -eq "'") -or ($v[0] -eq '"' -and $v[$v.Length-1] -eq '"')) {
                    return $v.Substring(1,$v.Length-2)
                }
            }
            return $v
        }
    }
    return ''
}
function Decode-Password([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
    catch { throw 'SSH/sudo credential metadata in the generated SH is invalid.' }
}
function Enable-SshAskpass([string]$Password) {
    if (-not $Password) { return '' }
    $path = Join-Path $env:TEMP ("elk-upgrade-askpass-{0}.exe" -f $PID)
    $source = @'
using System;
public class ElkUpgradeAskPass {
    public static int Main() {
        Console.Write(Environment.GetEnvironmentVariable("ELK_UPGRADE_SSH_PASSWORD") ?? "");
        return 0;
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $path -OutputType ConsoleApplication -ErrorAction Stop
    $env:ELK_UPGRADE_SSH_PASSWORD = $Password
    $env:SSH_ASKPASS = $path
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $env:DISPLAY = 'elk-upgrade:0'
    return $path
}
function Clear-SshAskpass([string]$Exe) {
    Remove-Item Env:ELK_UPGRADE_SSH_PASSWORD -ErrorAction SilentlyContinue
    Remove-Item Env:SSH_ASKPASS -ErrorAction SilentlyContinue
    Remove-Item Env:SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue
    Remove-Item Env:DISPLAY -ErrorAction SilentlyContinue
    if ($Exe) { Remove-Item -LiteralPath $Exe -Force -ErrorAction SilentlyContinue }
}
function Quote-WinArg([string]$Value) {
    if (-not $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $result = '"'; $bs = 0
    foreach ($c in $Value.ToCharArray()) {
        if ($c -eq [char]92) { $bs++; continue }
        if ($c -eq [char]34) { $result += ('\' * ($bs*2+1)) + '"' }
        else { $result += ('\' * $bs) + [string]$c }
        $bs = 0
    }
    return ($result + ('\' * ($bs*2)) + '"')
}
# Streaming SSH output. StandardInputEncoding must be BOM-less for sudo -S.
function Invoke-OpenSshWithInput([string]$Executable,[string[]]$Arguments,[string]$InputText) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $false
    $start.RedirectStandardError = $false
    $start.CreateNoWindow = $false
    try { $start.StandardInputEncoding = (New-Object Text.UTF8Encoding($false)) } catch {}
    $start.Arguments = (($Arguments | ForEach-Object { Quote-WinArg ([string]$_) }) -join ' ')
    $proc = New-Object Diagnostics.Process
    $proc.StartInfo = $start
    if (-not $proc.Start()) { throw 'Failed to launch Windows OpenSSH.' }
    try {
        if ($InputText) {
            $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($InputText)
            $proc.StandardInput.BaseStream.Write($bytes,0,$bytes.Length)
        }
        $proc.StandardInput.BaseStream.Flush()
        $proc.StandardInput.Close()
        $proc.WaitForExit()
        return [int]$proc.ExitCode
    } finally {
        if (-not $proc.HasExited) { try { $proc.Kill() } catch {} }
        $proc.Dispose()
    }
}
function Quote-Bash([string]$Value) {
    $escape = "'" + [char]34 + "'" + [char]34 + "'"
    return "'" + $Value.Replace("'", $escape) + "'"
}

function Invoke-Root([string]$Text) {
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
    $sshOpts = $script:Common
    if ($script:User -eq 'root') {
        $remote = "echo $b64 | base64 -d | /bin/bash"
        & $script:Ssh @sshOpts -T -p $script:Port $script:Target $remote
        return $LASTEXITCODE
    }
    if ($script:SudoPassword) {
        # Stored sudo password is transmitted only via SSH stdin, not via arguments/files.
        $remote = ('IFS= read -r __pw; printf ''%s\n'' "$__pw" | sudo -S -k -p '''' /bin/bash -c ''echo {0} | base64 -d | /bin/bash''; rc=$?; unset __pw; exit $rc' -f $b64)
        $args = @($script:Common) + @('-T','-p',$script:Port,$script:Target,$remote)
        return (Invoke-OpenSshWithInput -Executable $script:Ssh -Arguments $args -InputText ($script:SudoPassword + "`n"))
    }
    # Unattended sudo works only if sudoers explicitly allows NOPASSWD.
    $remote = "sudo -n /bin/bash -c 'echo $b64 | base64 -d | /bin/bash'"
    & $script:Ssh @sshOpts -T -p $script:Port $script:Target $remote
    return $LASTEXITCODE
}
function Remote-StatusScript {
return @'
set -Eeuo pipefail
unit=elk-stack-upgrade.service
logfile=/var/log/elk-stack-upgrade-console.log
if ! systemctl show "$unit" -p LoadState --value 2>/dev/null | grep -qv '^not-found$'; then
  echo '[ERROR] Upgrade task has not been started.'; exit 2
fi
active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
sub="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
if [[ -f "$logfile" ]]; then
  echo '==== Ubuntu upgrade log ===='
  if [[ "$active" != activating && "$sub" != running && "$sub" != start ]]; then
    cat "$logfile"
  else
    tail -n +1 -F "$logfile" & tailpid=$!
    while :; do
      active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
      sub="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
      if [[ "$active" != activating && "$sub" != running && "$sub" != start ]]; then break; fi
      sleep 2
    done
    sleep 2
    kill "$tailpid" 2>/dev/null || true; wait "$tailpid" 2>/dev/null || true
  fi
else
  echo '[WARN] No upgrade log was found.'
fi
status="$(systemctl show "$unit" -p ExecMainStatus --value 2>/dev/null || true)"
[[ "$status" =~ ^[0-9]+$ ]] || status=1
state="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
[[ "$state" != failed ]] || { ((status != 0)) || status=1; }
echo "[REMOTE RESULT] state=$state exit=$status"
exit "$status"
'@
}

$AskpassExe = ''
try {
    Require (($Version -eq 'latest') -or ($Version -match '^\d+\.\d+\.\d+$')) 'Version must be latest or x.y.z.'
    $generated = Get-InstallerPath $ScriptPath
    $script:HostName = Get-ShellMeta $generated 'DEPLOY_HOST'
    $script:User = Get-ShellMeta $generated 'DEPLOY_USER'
    $script:Port = Get-ShellMeta $generated 'DEPLOY_SSH_PORT'
    $remoteDir = Get-ShellMeta $generated 'DEPLOY_REMOTE_DIR'
    $script:SudoPassword = Decode-Password (Get-ShellMeta $generated 'DEPLOY_SUDO_PASSWORD_B64')
    $sshPassword = Decode-Password (Get-ShellMeta $generated 'DEPLOY_SSH_PASSWORD_B64')
    if ((Get-ShellMeta $generated 'DEPLOY_SUDO_SAME_AS_SSH') -eq 'true') { $script:SudoPassword = $sshPassword }
    Require ($script:HostName -match '^[A-Za-z0-9.:-]+$') 'Invalid DEPLOY_HOST.'
    Require ($script:User -match '^[A-Za-z0-9._-]+$') 'Invalid DEPLOY_USER.'
    if (-not $script:Port) { $script:Port = '22' }
    Require (($script:Port -match '^\d{1,5}$') -and ([int]$script:Port -ge 1) -and ([int]$script:Port -le 65535)) 'Invalid DEPLOY_SSH_PORT.'
    if (-not $remoteDir) { $remoteDir = '/home/' + $script:User }
    Require ($remoteDir -match '^/[A-Za-z0-9_./-]+$') 'DEPLOY_REMOTE_DIR contains unsupported characters.'
    $script:Target = $script:User + '@' + $script:HostName
    $script:Ssh = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
    $scp = Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe'
    Require (Test-Path -LiteralPath $script:Ssh) 'Windows OpenSSH ssh.exe is missing.'
    if ($Action -ne 'status') { Require (Test-Path -LiteralPath $scp) 'Windows OpenSSH scp.exe is missing.' }
    # Trust on first use, reject changed known host keys instead of silently disabling verification.
    $script:Common = @('-o','StrictHostKeyChecking=accept-new','-o','LogLevel=ERROR',
        '-o','ServerAliveInterval=15','-o','ServerAliveCountMax=12','-o','ConnectTimeout=15',
        '-o','NumberOfPasswordPrompts=2')
    Write-Host ('='*74) -ForegroundColor DarkCyan
    Info ('ELK Stack Remote Upgrade | action={0} | target={1}' -f $Action,$Version)
    Info ('Ubuntu : {0} (SSH port {1})' -f $script:Target,$script:Port)
    Info ('SSH metadata: ' + $generated)
    Info ('SSH: {0}; sudo: {1}' -f $(if ($sshPassword) { 'stored password' } else { 'SSH key/interactive' }),$(if ($script:SudoPassword) { 'stored password' } else { 'NOPASSWD required' }))
    Write-Host ('='*74) -ForegroundColor DarkCyan
    $sshOpts = $script:Common
    $AskpassExe = Enable-SshAskpass $sshPassword
    Info '[1/5] Checking Ubuntu SSH authentication...'
    & $script:Ssh @sshOpts -T -p $script:Port $script:Target 'printf "[REMOTE] SSH connected\n"'
    Require ($LASTEXITCODE -eq 0) 'SSH authentication failed. Check saved SSH settings or host key.'
    Info '[2/5] Checking sudo authentication...'
    $rc = Invoke-Root 'id -u; command -v systemd-run >/dev/null'
    Require ($rc -eq 0) 'sudo authentication or systemd-run check failed.'
    Ok 'SSH and sudo authentication are ready.'
    if ($Action -eq 'status') {
        Info 'Reconnecting to upgrade log...'
        $rc = Invoke-Root (Remote-StatusScript)
        exit $rc
    }
    $localUpgrade = Join-Path $PackageRoot '_internal\core\elk-stack-upgrade.sh'
    Require (Test-Path -LiteralPath $localUpgrade -PathType Leaf) ('Missing upgrade helper: ' + $localUpgrade)
    $remoteStage = ($remoteDir.TrimEnd('/') + '/.elk-stack-upgrade-' + $PID + '.sh')
    Info '[3/5] Uploading the upgrade helper (no SSH credentials in this file)...'
    & $scp @sshOpts -P $script:Port $localUpgrade ($script:Target + ':' + $remoteStage)
    Require ($LASTEXITCODE -eq 0) 'SCP upload failed. Check permissions and remote folder.'
    Ok 'SCP finished.'
    $installedScript = '/usr/local/lib/elk-oneclick/elk-stack-upgrade.sh'
    $stageQ = Quote-Bash $remoteStage
    $installedQ = Quote-Bash $installedScript
    if ($Action -eq 'check' -or $Action -eq 'plan') {
        Info '[4/5] Read-only version check / APT simulation...'
        $args = if ($Action -eq 'check') { '--check' } else { '--plan ' + (Quote-Bash $Version) }
        $root = @"
set -Eeuo pipefail
install -d -m 755 /usr/local/lib/elk-oneclick
install -m 755 $stageQ $installedQ
rm -f $stageQ
bash -n $installedQ
/bin/bash $installedQ $args
"@
        $rc = Invoke-Root $root
        if ($rc -eq 0) { Ok 'Check/plan completed. No Elastic packages were changed.' }
        exit $rc
    }
    Info '[4/5] Starting detached Ubuntu upgrade job (APT refresh + plan + upgrade)...'
    $versionQ = Quote-Bash $Version
    $start = @"
set -Eeuo pipefail
unit=elk-stack-upgrade.service
state="`$(systemctl show "`$unit" -p ActiveState --value 2>/dev/null || true)"
sub="`$(systemctl show "`$unit" -p SubState --value 2>/dev/null || true)"
if [[ "`$state" == activating || "`$sub" == running ]]; then echo '[ERROR] An upgrade job is already running.'; exit 3; fi
install -d -m 755 /usr/local/lib/elk-oneclick
install -m 755 $stageQ $installedQ
rm -f $stageQ
bash -n $installedQ
systemctl stop "`$unit" 2>/dev/null || true
systemctl reset-failed "`$unit" 2>/dev/null || true
install -m 600 /dev/null '$ConsoleLog'
systemd-run --unit=elk-stack-upgrade --description='Elastic Stack OneClick Upgrade' --no-block --property=Type=oneshot --property=RemainAfterExit=yes --property=TimeoutStartSec=infinity --property=StandardOutput=append:$ConsoleLog --property=StandardError=append:$ConsoleLog /bin/bash $installedQ --upgrade $versionQ --yes --refresh
"@
    $rc = Invoke-Root $start
    Require ($rc -eq 0) ('Remote upgrade task failed to start (exit ' + $rc + ').')
    Ok 'Ubuntu systemd job started. It will continue if SSH disconnects.'
    Info '[5/5] Monitoring upgrade progress (Ctrl+C stops monitoring, not the Ubuntu task)...'
    $rc = Invoke-Root (Remote-StatusScript)
    if ($rc -eq 0) { Ok 'Upgrade completed successfully. Check the package versions and service/API state above.' }
    else { Warn ('Upgrade exited with code ' + $rc + '. Review remote log ' + $ConsoleLog) }
    exit $rc
} catch {
    Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
} finally {
    Clear-SshAskpass $AskpassExe
}
