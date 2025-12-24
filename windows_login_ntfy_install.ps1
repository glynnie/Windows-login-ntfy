# 0. Admin Elevation Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: This script must be run as Administrator." -ForegroundColor Red
    Exit
}

# Early definitions for detection/uninstall
$scriptDir = "C:\Scripts"
$alertScriptPath = "$scriptDir\RemoteAccessAlert.ps1"
$taskName = "Ntfy-RemoteAccessAlert"

# Uninstall prompt if previous installation detected
$existingScript = Test-Path $alertScriptPath
$existingTask = $false
try {
    $existingTask = (Get-ScheduledTask -TaskName $taskName -ErrorAction Stop) -ne $null
} catch {
    $existingTask = $false
}

if ($existingScript -or $existingTask) {
    Write-Host "Detected an existing installation of the Remote Access Alerter." -ForegroundColor Yellow
    Write-Host "Found files or scheduled task for '$taskName'." -ForegroundColor Yellow
    $uninstallChoice = Read-Host "Do you want to uninstall/remove the existing installation? (Y/N)"
    if ($uninstallChoice -match '^[Yy]') {
        Write-Host "Uninstalling..." -ForegroundColor Cyan
        try {
            if ($existingTask) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
                Write-Host "Removed scheduled task '$taskName'." -ForegroundColor Green
            }
        } catch {
            Write-Host "Warning: Failed to remove scheduled task or it may not exist." -ForegroundColor Magenta
        }
        try {
            if (Test-Path $alertScriptPath) {
                # Attempt to remove read-only attribute if present
                if ((Get-Item $alertScriptPath).Attributes -band [System.IO.FileAttributes]::ReadOnly) {
                    (Get-Item $alertScriptPath).Attributes = ((Get-Item $alertScriptPath).Attributes -bxor [System.IO.FileAttributes]::ReadOnly)
                }
                Remove-Item -Path $alertScriptPath -Force -ErrorAction Stop
                Write-Host "Removed alert script at $alertScriptPath." -ForegroundColor Green
            }
        } catch {
            Write-Host "Warning: Could not remove alert script file." -ForegroundColor Magenta
        }
        try {
            if (Test-Path $scriptDir) {
                # Reset permissions to allow deletion
                icacls $scriptDir /reset /T | Out-Null
                # Attempt to remove directory if empty
                $children = Get-ChildItem -Path $scriptDir -Force -ErrorAction SilentlyContinue
                if (-not $children) {
                    Remove-Item -Path $scriptDir -Force -Recurse -ErrorAction Stop
                    Write-Host "Removed directory $scriptDir." -ForegroundColor Green
                } else {
                    Write-Host "Directory $scriptDir not empty; left in place." -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Host "Warning: Could not fully remove directory or reset permissions." -ForegroundColor Magenta
        }
        Write-Host "Uninstall complete." -ForegroundColor Green
        Exit
    } else {
        Write-Host "Continuing with installation (existing files/tasks will be overwritten)." -ForegroundColor Cyan
    }
}

# 1. Configuration
Write-Host "--- Windows Remote Access Alerter Setup ---" -ForegroundColor Cyan
Write-Host "This script automates the setup of a notification system that alerts your phone/browser"
Write-Host "whenever someone logs into this PC via Remote Desktop (RDP) or SSH.`n"

Write-Host "[1/5] CONFIGURATION" -ForegroundColor Yellow
Write-Host "Why: We need to know where to send the alerts. Using an obscure topic name on ntfy.sh"
Write-Host "acts as a 'password' for your notifications."
Write-Host "If using the ntfy.sh make sure it is private or obscure!"
Write-Host "e.g. https://ntfy.sh/anexampleofyourlongsubjectname1234)"

$ntfyTopic = Read-Host "Enter your topic url"

# Error Check: Validate URL input
if ([string]::IsNullOrWhiteSpace($ntfyTopic) -or $ntfyTopic -notmatch "^https?://") {
    Write-Host "ERROR: Invalid URL. Please provide a full link starting with http:// or https://" -ForegroundColor Red
    Exit
}

# Ensure script directory exists (this may be redundant if created earlier)
try {
    if (!(Test-Path $scriptDir)) {
        Write-Host "Creating directory $scriptDir to hold the alert logic..."
        New-Item -Path $scriptDir -ItemType Directory -ErrorAction Stop | Out-Null
    }
} catch {
    Write-Host "ERROR: Failed to create $scriptDir. Check permissions." -ForegroundColor Red ; Exit
}

# 2. Security Hardening
Write-Host "`n[2/5] SECURITY HARDENING" -ForegroundColor Yellow
Write-Host "Why: To prevent unauthorized users from disabling alerts or changing the script,"
Write-Host "Locking $scriptDir so only 'System' and 'Administrators' can edit it."
try {
    icacls $scriptDir /inheritance:r /grant:r "SYSTEM:(OI)(CI)F" /grant:r "Administrators:(OI)(CI)F" -ErrorAction Stop | Out-Null
} catch {
    Write-Host "Warning: Could not set directory permissions." -ForegroundColor Magenta
}

# 3. Create the Alert Script
Write-Host "`n[3/5] CREATING ALERT LOGIC" -ForegroundColor Yellow
Write-Host "Why: To read the Windows Event Logs,"
Write-Host "extract the username, and send it to your topic."
# (alertScriptPath already defined above)
$alertScriptContent = @"
# Logic: Find the most recent login events in the last 30 seconds
`$now = [DateTime]::UtcNow

# Check RDP (Event 1149)
try {
    `$rdpEvent = Get-WinEvent -LogName 'Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational' -MaxEvents 5 -ErrorAction SilentlyContinue |
                 Where-Object { `$_.Id -eq 1149 -and `$_.TimeCreated.ToUniversalTime() -gt `$now.AddSeconds(-30) } | Select-Object -First 1

    if (`$rdpEvent) {
        `$user = `$rdpEvent.Properties[0].Value
        Invoke-RestMethod -Method Post -Uri '$ntfyTopic' -Headers @{'prio'='high'; 'tags'='warning'} -Body "RDP Login: `$user"
    }
} catch {}

# Check SSH (Event 4)
try {
    `$sshEvent = Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 5 -ErrorAction SilentlyContinue |
                 Where-Object { `$_.Id -eq 4 -and `$_.TimeCreated.ToUniversalTime() -gt `$now.AddSeconds(-30) } | Select-Object -First 1

    if (`$sshEvent -and `$sshEvent.Message -match 'Accepted \w+ for (\S+)') {
        `$user = `$Matches[1]
        Invoke-RestMethod -Method Post -Uri '$ntfyTopic' -Headers @{'prio'='high'; 'tags'='key'} -Body "SSH Login: `$user"
    }
} catch {}
"@

try {
    Set-Content -Path $alertScriptPath -Value $alertScriptContent -ErrorAction Stop
} catch {
    Write-Host "ERROR: Could not write alert script to disk." -ForegroundColor Red ; Exit
}

# 4. Automate with Task Scheduler
Write-Host "`n[4/5] REGISTERING SYSTEM TRIGGER" -ForegroundColor Yellow
Write-Host "Why: Windows Task Scheduler will 'watch' the system logs. The moment a login event"
Write-Host "appears, it will wake up and run the alert script automatically."

$xml = @"
<Task version='1.2' xmlns='schemas.microsoft.com'>
  <Triggers>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id='0' Path='Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'&gt;&lt;Select Path='Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational'&gt;*[System[(EventID=1149)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id='0' Path='OpenSSH/Operational'&gt;&lt;Select Path='OpenSSH/Operational'&gt;*[System[(EventID=4)]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals><Principal id='Author'><UserId>S-1-5-18</UserId><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <StartWhenAvailable>true</StartWhenAvailable>
  </Settings>
  <Actions Context='Author'>
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-ExecutionPolicy Bypass -WindowStyle Hidden -File "$alertScriptPath"</Arguments>
    </Exec>
  </Actions>
</Task>
"@

try {
    $tempFile = [System.IO.Path]::GetTempFileName()
    $xml | Out-File $tempFile -Encoding utf8
    Register-ScheduledTask -TaskName $taskName -Xml (Get-Content $tempFile -Raw) -Force -ErrorAction Stop
    Remove-Item $tempFile -ErrorAction SilentlyContinue
} catch {
    Write-Host "ERROR: Failed to register Scheduled Task. Ensure you are running as Administrator." -ForegroundColor Red
    Exit
}

# 5. Final Confirmation
Write-Host "`n[5/5] DONE!" -ForegroundColor Green
Write-Host "The system is now active. You can manage this task in 'Task Scheduler' under the name '$taskName'"
Write-Host "To test: Open an RDP or SSH session to this machine and check your ntfy topic on the website or app."
Write-Host "$ntfyTopic"
