param(
  [ValidateSet('deploy','status')]
  [string]$Action = 'deploy',
  [string]$ScriptPath = ''
)

$ErrorActionPreference = 'Stop'
$PackageRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Unit = 'elk-oneclick-install.service'
$ConsoleLog = '/var/log/elk-oneclick-console.log'

function Get-InstallerPath {
  param([string]$Requested)
  if ($Requested) {
    $rp = Resolve-Path -LiteralPath $Requested -ErrorAction SilentlyContinue
    if ($rp) { return $rp.Path }
  }
  $candidates = @(
    (Join-Path $PackageRoot 'elk-oneclick-install-v2.9.3.sh'),
    (Join-Path $PackageRoot 'elk-oneclick-install-v2.9.2.sh'),
    (Join-Path $PackageRoot 'elk-oneclick-install.sh')
  )
  foreach ($c in $candidates) {
    if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
  }
  $latest = Get-ChildItem -LiteralPath $PackageRoot -Filter 'elk-oneclick-install-v*.sh' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($latest) { return $latest.FullName }
  $downloads = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
  $latest = Get-ChildItem -LiteralPath $downloads -Filter 'elk-oneclick-install-v*.sh' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($latest) { return $latest.FullName }
  throw 'elk-oneclick-install-v*.sh was not found. Generate it from Config Wizard first.'
}

function Get-ShellMeta {
  param([string]$Path,[string]$Key)
  $prefix = $Key + '='
  foreach ($line in [IO.File]::ReadLines($Path)) {
    if ($line.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
      $v = $line.Substring($prefix.Length).Trim()
      if ($v.Length -ge 2) {
        $first = $v.Substring(0,1)
        $last = $v.Substring($v.Length-1,1)
        if (($first -eq "'" -and $last -eq "'") -or ($first -eq '"' -and $last -eq '"')) {
          $v = $v.Substring(1,$v.Length-2)
        }
      }
      return $v
    }
  }
  return ''
}

function Decode-B64Utf8 {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  try { return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
  catch { throw 'Deployment password metadata is invalid. Regenerate the SH from Config Wizard.' }
}

function Enable-AutoSshPassword {
  param([string]$Password)
  if ([string]::IsNullOrEmpty($Password)) { return $null }
  $askExe = Join-Path $env:TEMP ("elk-ssh-askpass-{0}.exe" -f $PID)
  if (Test-Path -LiteralPath $askExe) { Remove-Item -Force $askExe -ErrorAction SilentlyContinue }
  $source = @'
using System;
public static class ElkSshAskPass {
    public static int Main() {
        Console.Write(Environment.GetEnvironmentVariable("ELK_DEPLOY_SSH_PASSWORD") ?? "");
        return 0;
    }
}
'@
  try {
    Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $askExe -OutputType ConsoleApplication -ErrorAction Stop
  }
  catch {
    Write-Warning 'Could not create the SSH password helper. Falling back to interactive SSH password input.'
    return $null
  }
  $env:ELK_DEPLOY_SSH_PASSWORD = $Password
  $env:SSH_ASKPASS = $askExe
  $env:SSH_ASKPASS_REQUIRE = 'force'
  $env:DISPLAY = 'elk-auto:0'
  return $askExe
}

function Disable-AutoSshPassword {
  param([string]$AskExe)
  Remove-Item Env:ELK_DEPLOY_SSH_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:SSH_ASKPASS -ErrorAction SilentlyContinue
  Remove-Item Env:SSH_ASKPASS_REQUIRE -ErrorAction SilentlyContinue
  Remove-Item Env:DISPLAY -ErrorAction SilentlyContinue
  if ($AskExe -and (Test-Path -LiteralPath $AskExe)) { Remove-Item -Force $AskExe -ErrorAction SilentlyContinue }
}

function ConvertTo-ProcessArgument {
  param([string]$Value)
  if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
  if ($Value -notmatch '[\s"]') { return $Value }
  # CommandLineToArgvW-compatible quoting:
  #  - backslashes directly before a double quote must be doubled
  #  - the double quote itself is escaped with a backslash
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  $bs = 0
  foreach ($ch in $Value.ToCharArray()) {
    if ($ch -eq [char]92) { $bs++; continue }
    if ($ch -eq [char]34) {
      [void]$sb.Append([char]92, ($bs * 2 + 1))
      [void]$sb.Append('"')
    }
    else {
      if ($bs -gt 0) { [void]$sb.Append([char]92, $bs) }
      [void]$sb.Append($ch)
    }
    $bs = 0
  }
  if ($bs -gt 0) { [void]$sb.Append([char]92, ($bs * 2)) }
  [void]$sb.Append('"')
  return $sb.ToString()
}

function Invoke-OpenSshWithInput {
  param(
    [string]$Exe,
    [string[]]$Arguments,
    [string]$InputText,
    [int]$TimeoutSeconds = 0
  )
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $false
  $psi.RedirectStandardError = $false
  # sudo-hotfix5: Process.Start() creates the stdin StreamWriter with the console code page
  # (65001 because of "chcp 65001" in the .cmd) and emits the UTF-8 BOM immediately at start.
  # Writing to BaseStream later does NOT remove that BOM. Force a BOM-less encoding instead
  # (ProcessStartInfo.StandardInputEncoding needs .NET Framework 4.7.1+; the remote side
  # strips a leading BOM as a fallback, see Invoke-SshRoot).
  try { $psi.StandardInputEncoding = (New-Object System.Text.UTF8Encoding($false)) } catch { }
  $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-ProcessArgument ([string]$_) }) -join ' ')

  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  if (-not $proc.Start()) { throw 'Could not start Windows OpenSSH process.' }
  try {
    # sudo-hotfix5: Do NOT use StandardInput.Write().
    # run-remote-deploy.cmd runs "chcp 65001". Windows PowerShell 5.1 / .NET Framework
    # then creates the redirected stdin StreamWriter with a UTF-8 encoding that emits a
    # BOM (EF BB BF). The BOM became the first bytes of the password line, so sudo saw
    # "<BOM>password" -> "Sorry, try again" -> "no password was provided".
    # (hotfix5: the BOM is actually emitted at Process start; see StandardInputEncoding above.)
    if ($null -ne $InputText -and $InputText.Length -gt 0) {
      $inBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($InputText)
      $proc.StandardInput.BaseStream.Write($inBytes, 0, $inBytes.Length)
    }
    $proc.StandardInput.BaseStream.Flush()
    $proc.StandardInput.Close()

    if ($TimeoutSeconds -gt 0) {
      if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
        try { $proc.Kill() } catch { }
        Write-Warning ("SSH command timed out after {0} seconds." -f $TimeoutSeconds)
        return 124
      }
    }
    else {
      $proc.WaitForExit()
    }
    return $proc.ExitCode
  }
  finally {
    if (-not $proc.HasExited) {
      try { $proc.Kill() } catch { }
    }
    $proc.Dispose()
  }
}

function Invoke-SshRoot {
  param(
    [string]$SshExe,
    [string[]]$Common,
    [string]$Port,
    [string]$Target,
    [string]$RootScript,
    [string]$SudoPassword,
    [int]$TimeoutSeconds = 0
  )

  # sudo-hotfix2:
  # Avoid -tt for automatic sudo password input. With redirected stdin, the
  # pseudo-terminal can consume the stream and leave sudo waiting for another
  # attempt even when the configured SSH/sudo password is the same.
  #
  # The remote login shell now reads exactly one password line. It then pipes
  # that value into sudo -S. The actual root payload is Base64 encoded in the
  # remote command, so it does not share stdin with sudo. The password is not
  # placed on the process command line and is not written to disk.
  $bytes = [Text.Encoding]::UTF8.GetBytes($RootScript)
  $b64 = [Convert]::ToBase64String($bytes)

  if (-not [string]::IsNullOrEmpty($SudoPassword)) {
    $stdin = $SudoPassword + "`n"
    $remote = ('IFS= read -r __elk_sudo_pw; __elk_sudo_pw=$(printf ''%s'' "$__elk_sudo_pw" | LC_ALL=C sed -e ''s/^\xef\xbb\xbf//'' -e ''s/\r$//''); printf ''%s\n'' "$__elk_sudo_pw" | sudo -S -k -p '''' /bin/bash -c ''echo {0} | base64 -d | /bin/bash''; __rc=$?; unset __elk_sudo_pw; exit $__rc' -f $b64)
    $args = @()
    $args += $Common
    $args += @('-T','-p',$Port,$Target,$remote)
    return Invoke-OpenSshWithInput -Exe $SshExe -Arguments $args -InputText $stdin -TimeoutSeconds $TimeoutSeconds
  }

  # No stored sudo password: preserve interactive/NOPASSWD behavior.
  $remote = "sudo /bin/bash -c 'echo $b64 | base64 -d | /bin/bash'"
  & $SshExe @Common -tt -p $Port $Target $remote
  return $LASTEXITCODE
}
function Show-SudoDiagnostics {
  param(
    [string]$SshExe,
    [string[]]$Common,
    [string]$Port,
    [string]$Target,
    [string]$SshPassword,
    [string]$SudoPassword
  )
  # Password values are never printed here - only lengths / yes-no results.
  $enc = New-Object System.Text.UTF8Encoding($false)
  Write-Host
  Write-Host '[DIAG] sudo authentication failed. Running diagnostics (password values are never printed).'
  Write-Host ('[DIAG] Local sudo password length : {0} chars / {1} bytes (UTF-8)' -f $SudoPassword.Length, $enc.GetByteCount($SudoPassword))

  # 1) Is the stored SSH password really accepted? Key auth would hide a wrong password.
  if (-not [string]::IsNullOrEmpty($SshPassword)) {
    & $SshExe @Common -o PreferredAuthentications=password -o PubkeyAuthentication=no -T -p $Port $Target 'true'
    if ($LASTEXITCODE -eq 0) { Write-Host '[DIAG] 1) SSH password-only login : OK (stored SSH password is valid)' }
    else { Write-Host '[DIAG] 1) SSH password-only login : FAILED (stored password is NOT accepted; the earlier SSH OK probably came from a key)' }
  }

  # 2) What does the remote shell actually receive on stdin?
  Write-Host '[DIAG] 2) Password as received by the remote shell (length only):'
  $probe = 'IFS= read -r p; case "$p" in *[![:print:]]*) np=yes;; *) np=no;; esac; echo "       remote_len=${#p} nonprintable=$np shell=$SHELL groups=$(id -nG)"'
  $probeArgs = @()
  $probeArgs += $Common
  $probeArgs += @('-T','-p',$Port,$Target,$probe)
  $null = Invoke-OpenSshWithInput -Exe $SshExe -Arguments $probeArgs -InputText ($SudoPassword + "`n") -TimeoutSeconds 20

  Write-Host '[DIAG] How to read this:'
  Write-Host '       - remote_len != local length, or nonprintable=yes  -> password is altered in transit'
  Write-Host '       - password-only login FAILED                        -> the password stored in the SH is wrong'
  Write-Host '       - both fine, groups has sudo/admin                  -> Ubuntu sudo password really differs (or sudoers uses rootpw/targetpw)'
  Write-Host '       - groups has no sudo/admin                          -> this user is not allowed to use sudo'
  Write-Host
}

function Test-RemoteCredentials {
  param(
    [string]$SshExe,
    [string[]]$Common,
    [string]$Port,
    [string]$Target,
    [string]$SshPassword,
    [string]$SudoPassword
  )

  Write-Host '[0/3] Checking SSH / sudo credentials...'
  & $SshExe @Common -T -p $Port $Target 'printf __ELK_SSH_OK__'
  $sshRc = $LASTEXITCODE
  if ($sshRc -ne 0) {
    throw "SSH authentication/connection test failed. Exit code: $sshRc"
  }
  Write-Host '[OK] SSH authentication succeeded.'

  if (-not [string]::IsNullOrEmpty($SudoPassword)) {
    $sudoRc = Invoke-SshRoot -SshExe $SshExe -Common $Common -Port $Port -Target $Target -RootScript "printf '__ELK_SUDO_OK__\n'" -SudoPassword $SudoPassword -TimeoutSeconds 20
    if ($sudoRc -ne 0) {
      Show-SudoDiagnostics -SshExe $SshExe -Common $Common -Port $Port -Target $Target -SshPassword $SshPassword -SudoPassword $SudoPassword
      throw 'SSH login succeeded, but sudo password authentication failed. In Config Wizard, verify "sudo password = SSH password". If sudo uses a different password, turn that option off and enter the separate sudo password.'
    }
    Write-Host '[OK] sudo password authentication succeeded.'
  }
  else {
    # Do not force an interactive prompt during preflight. NOPASSWD is enough to pass silently.
    & $SshExe @Common -T -p $Port $Target 'sudo -n true >/dev/null 2>&1'
    if ($LASTEXITCODE -eq 0) {
      Write-Host '[OK] sudo NOPASSWD authentication is available.'
    }
    else {
      Write-Host '[INFO] No stored sudo password/NOPASSWD detected. sudo may prompt during deployment.'
    }
  }
  Write-Host
}

$Script = Get-InstallerPath $ScriptPath
$sshExe = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
$scpExe = Join-Path $env:WINDIR 'System32\OpenSSH\scp.exe'
if (-not (Test-Path -LiteralPath $sshExe)) { throw 'Windows OpenSSH ssh.exe is not installed.' }
if (-not (Test-Path -LiteralPath $scpExe)) { throw 'Windows OpenSSH scp.exe is not installed.' }

$HostName = Get-ShellMeta $Script 'DEPLOY_HOST'
$User = Get-ShellMeta $Script 'DEPLOY_USER'
$Port = Get-ShellMeta $Script 'DEPLOY_SSH_PORT'
$RemoteDir = Get-ShellMeta $Script 'DEPLOY_REMOTE_DIR'
$AutoInstall = Get-ShellMeta $Script 'DEPLOY_AUTO_INSTALL'
$RemoveAfter = Get-ShellMeta $Script 'DEPLOY_REMOVE_REMOTE_INSTALLER_AFTER'
$Payload = Get-ShellMeta $Script 'ONECLICK_PAYLOAD_VERSION'
$Resolver = Get-ShellMeta $Script 'ELK_PACKAGE_RESOLVER'
$SshPassword = Decode-B64Utf8 (Get-ShellMeta $Script 'DEPLOY_SSH_PASSWORD_B64')
$SudoSame = Get-ShellMeta $Script 'DEPLOY_SUDO_SAME_AS_SSH'
$SudoPassword = Decode-B64Utf8 (Get-ShellMeta $Script 'DEPLOY_SUDO_PASSWORD_B64')
if ($SudoSame -eq 'true') { $SudoPassword = $SshPassword }

if (-not $HostName) { throw 'DEPLOY_HOST is empty.' }
if (-not $User) { throw 'DEPLOY_USER is empty.' }
if (-not $Port) { $Port = '22' }
if (-not $RemoteDir) { $RemoteDir = '/home/' + $User }
if ($Resolver -ne 'v2') { throw 'Old One-Click SH detected. Import it into Config Wizard v2.9.3 and save a new SH.' }

$BaseName = [IO.Path]::GetFileName($Script)
$RemoteDir = $RemoteDir.TrimEnd('/')
$RemoteFile = $RemoteDir + '/' + $BaseName
$Target = $User + '@' + $HostName
$Common = @(
  '-o','StrictHostKeyChecking=no',
  '-o','UserKnownHostsFile=NUL',
  '-o','GlobalKnownHostsFile=NUL',
  '-o','LogLevel=ERROR',
  '-o','ServerAliveInterval=15',
  '-o','ServerAliveCountMax=12',
  '-o','TCPKeepAlive=yes',
  '-o','ConnectTimeout=15',
  '-o','NumberOfPasswordPrompts=3'
)

Write-Host '=============================================================================='
Write-Host ' ELK Remote Auto Deploy - Windows OpenSSH v2.9.3 sudo-hotfix5'
Write-Host '=============================================================================='
Write-Host ("[INFO] Local file  : {0}" -f $Script)
Write-Host ("[INFO] Target      : {0}" -f $Target)
Write-Host ("[INFO] SSH port    : {0}" -f $Port)
Write-Host ("[INFO] Remote file : {0}" -f $RemoteFile)
Write-Host ("[INFO] Payload     : {0} / APT resolver {1}" -f $Payload,$Resolver)
Write-Host ("[INFO] SSH auth    : {0}" -f $(if($SshPassword){'password auto-input'}else{'interactive / SSH key'}))
Write-Host ("[INFO] sudo auth   : {0}" -f $(if($SudoPassword){'password auto-input'}else{'interactive / NOPASSWD'}))
Write-Host '[INFO] Host key    : verification disabled'
Write-Host

$askExe = $null
$tempUpload = $null
try {
  $askExe = Enable-AutoSshPassword $SshPassword

  Test-RemoteCredentials -SshExe $sshExe -Common $Common -Port $Port -Target $Target -SshPassword $SshPassword -SudoPassword $SudoPassword

  if ($Action -eq 'deploy') {
    # SSH/sudo deployment passwords are local-only. Upload a sanitized copy to Ubuntu.
    $raw = [IO.File]::ReadAllText($Script)
    $raw = [Regex]::Replace($raw,'(?m)^DEPLOY_SSH_PASSWORD_B64=.*$',"DEPLOY_SSH_PASSWORD_B64=''")
    $raw = [Regex]::Replace($raw,'(?m)^DEPLOY_SUDO_PASSWORD_B64=.*$',"DEPLOY_SUDO_PASSWORD_B64=''")
    $raw = [Regex]::Replace($raw,'(?m)^DEPLOY_SUDO_SAME_AS_SSH=.*$',"DEPLOY_SUDO_SAME_AS_SSH='false'")
    $tempUpload = Join-Path $env:TEMP ("elk-oneclick-upload-{0}.sh" -f ([Guid]::NewGuid().ToString('N')))
    [IO.File]::WriteAllText($tempUpload,$raw,(New-Object Text.UTF8Encoding($false)))

    Write-Host '[1/3] Uploading sanitized installer with SCP...'
    if ($SshPassword) { Write-Host '      SSH password: automatic' } else { Write-Host '      SSH password may be requested.' }
    & $scpExe @Common -P $Port $tempUpload ($Target + ':' + $RemoteFile)
    $rc = $LASTEXITCODE
    if ($rc -ne 0) { throw "SCP upload failed. Exit code: $rc" }
    Write-Host '[OK] SCP upload completed. Deployment passwords were not copied to Ubuntu.'

    if ($AutoInstall -ne 'true') { Write-Host '[OK] Upload completed. Auto-install is disabled.'; exit 0 }

    Write-Host
    Write-Host '[2/3] Starting detached install job on Ubuntu...'
    if ($SudoPassword) { Write-Host '      SSH/sudo passwords: automatic' } else { Write-Host '      sudo password may be requested.' }
    $inner = "systemctl stop $Unit 2>/dev/null || true; systemctl reset-failed $Unit 2>/dev/null || true; rm -f $ConsoleLog; install -o root -g root -m 600 /dev/null $ConsoleLog; systemd-run --unit=elk-oneclick-install --description='ELK One-Click Installer' --property=Type=oneshot --property=RemainAfterExit=yes --property=TimeoutStartSec=infinity --property=StandardOutput=append:$ConsoleLog --property=StandardError=append:$ConsoleLog --no-block /bin/bash '$RemoteFile' --local-install"
    $rc = Invoke-SshRoot $sshExe $Common $Port $Target $inner $SudoPassword
    if ($rc -eq 255) {
      Write-Warning 'SSH disconnected while starting the job. The detached job may still be running. Use run-remote-deploy.cmd --status.'
      exit 255
    }
    if ($rc -ne 0) { throw "Could not start detached install job. Exit code: $rc" }
    Write-Host ("[OK] Detached install job started: {0}" -f $Unit)
  }

  Write-Host
  Write-Host '[3/3] Monitoring remote install progress...'
  Write-Host '      The install job continues independently from this SSH session.'
  $monitor = 'LOG=' + "'$ConsoleLog'" + '; UNIT=' + "'$Unit'" + '; touch "$LOG"; tail -n +1 -F "$LOG" & TPID=$!; while :; do STATE=$(systemctl show -p ActiveState --value "$UNIT" 2>/dev/null || echo unknown); SUB=$(systemctl show -p SubState --value "$UNIT" 2>/dev/null || echo unknown); if [ "$STATE" = failed ] || [ "$SUB" = exited ] || [ "$STATE" = inactive ] || [ "$STATE" = unknown ]; then break; fi; sleep 2; done; kill "$TPID" 2>/dev/null || true; wait "$TPID" 2>/dev/null || true; RC=$(systemctl show -p ExecMainStatus --value "$UNIT" 2>/dev/null || echo 1); echo; echo "[REMOTE] state=$STATE/$SUB exit=$RC"; exit ${RC:-1}'
  $rc = Invoke-SshRoot $sshExe $Common $Port $Target $monitor $SudoPassword
  Write-Host
  if ($rc -eq 0) {
    if ($RemoveAfter -eq 'true') {
      Write-Host '[INFO] Removing remote installer after successful health check...'
      & $sshExe @Common -T -p $Port $Target ("rm -f '" + $RemoteFile.Replace("'","") + "'")
      if ($LASTEXITCODE -eq 0) { Write-Host '[OK] Remote installer removed.' }
      else { Write-Warning 'Remote installer cleanup failed. Installation itself succeeded.' }
    }
    Write-Host '=============================================================================='
    Write-Host '[OK] ELK installation and post-install health check completed successfully.'
    Write-Host '[INFO] Logs:'
    Write-Host ('       ' + $ConsoleLog)
    Write-Host '       /var/log/elk-auto-install.log'
    Write-Host '       /var/log/elk-post-install-check.log'
    Write-Host '=============================================================================='
    exit 0
  }
  if ($rc -eq 255) {
    Write-Warning 'Monitoring SSH disconnected. The Ubuntu install may still be running. Run run-remote-deploy.cmd --status later.'
    exit 0
  }
  Write-Host '=============================================================================='
  Write-Host ("[ERROR] ELK installation finished with an error. Remote exit code: {0}" -f $rc)
  Write-Host ('        ' + $ConsoleLog)
  Write-Host '        /var/log/elk-auto-install.log'
  Write-Host '        /var/log/elk-post-install-check.log'
  Write-Host '=============================================================================='
  exit $rc
}
catch {
  Write-Host ('[ERROR] ' + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
finally {
  if ($tempUpload -and (Test-Path -LiteralPath $tempUpload)) { Remove-Item -Force $tempUpload -ErrorAction SilentlyContinue }
  Disable-AutoSshPassword $askExe
}
