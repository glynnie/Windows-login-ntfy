### 🚨 Windows-login-ntfy
The installer sets up a scheduled task to watch for Remote Desktop (RDP) and SSH logins and send notifications to an ntfy.sh topic when they occur.

---

### ✅ Requirements

- **Windows** with PowerShell and Task Scheduler.
- **Administrator** privileges to run the installer.
- An **ntfy.sh** topic URL. Use a private or obscure topic as a simple secret.
- Optional **OpenSSH server** enabled if you want SSH alerts.

---

### ⚙️ Installation

1. **Save the installer** to a convenient location (for example your Downloads folder).
2. **Run PowerShell as Administrator**  
   Right-click PowerShell and choose **Run as administrator**.
3. **Execute the installer script**  
   If the script file is `Install-RemoteAlerter.ps1`, run:
   
   ```powershell
   .\Install-RemoteAlerter.ps1
   ```
   
5. **Follow prompts**  
   - Enter your full ntfy topic URL when asked (must start with `http://` or `https://`).  
   - The script will create `C:\Scripts\RemoteAccessAlert.ps1`, lock the folder permissions, and register a scheduled task named **Ntfy-RemoteAccessAlert** that triggers on RDP and SSH login events.

---

### 📁 Files created

- **`C:\Scripts\RemoteAccessAlert.ps1`** — the alert logic that reads events and posts to your ntfy topic.  
- **Scheduled Task** — **Ntfy-RemoteAccessAlert** that runs the alert script when relevant events occur.

---

### 🧪 Testing

- **RDP test**  
  Connect to the machine via Remote Desktop from another device. Within a few seconds the scheduled task should run and send a notification to your ntfy topic.
- **SSH test**  
  If OpenSSH is installed and enabled, connect via SSH and check the ntfy topic for the SSH login notification.
- **Verify task**  
  Open Task Scheduler and look for **Ntfy-RemoteAccessAlert** to confirm it exists and is enabled.

---

### 🧹 Uninstall

- If you run the installer again and it detects an existing installation, it will prompt to **uninstall**.
- To manually uninstall:
  1. Run the same installer script as Administrator.
  2. When prompted about an existing installation, choose **Y** to remove.
- **What uninstall does**
  - Removes the scheduled task **Ntfy-RemoteAccessAlert**.
  - Deletes `C:\Scripts\RemoteAccessAlert.ps1` if possible.
  - Attempts to reset permissions on `C:\Scripts` and remove the directory if empty.
- If the directory is not empty the script will leave it in place and report that to you.

---

### 🛠️ Troubleshooting and Security Notes

#### Troubleshooting
- **Task not present**  
  Open Task Scheduler and search for **Ntfy-RemoteAccessAlert**. If missing, re-run the installer.
- **No notifications**  
  Confirm your ntfy topic URL is correct and reachable from the machine. Test with:
  ```powershell
  Invoke-RestMethod -Uri "<your-topic>" -Method Post -Body "test"
  ```
  Run that in an elevated PowerShell session.
- **Script cannot be deleted on uninstall**  
  Check file attributes and permissions; run PowerShell as Administrator and retry uninstall.
- **Event logs not producing alerts**  
  Ensure the relevant event channels exist:
  - RDP events: `Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational`  
  - SSH events: `OpenSSH/Operational` (requires OpenSSH server)

#### Security
- **ntfy topic privacy**  
  Treat your ntfy topic URL as a secret. Use a long, obscure topic name to avoid others posting to or reading your notifications.
- **Permissions**  
  The installer locks `C:\Scripts` so only SYSTEM and Administrators can modify it. If you need to edit the script later, you may need to temporarily adjust permissions.
- **Administrator requirement**  
  The installer must be run elevated to register the scheduled task and set folder ACLs.

---

### 📌 Quick Reference

- **Scheduled Task name**: **Ntfy-RemoteAccessAlert**  
- **Alert script path**: `C:\Scripts\RemoteAccessAlert.ps1`  
- **To reinstall**: Run the installer again; choose to overwrite or uninstall when prompted.  
- **Need help**: Re-run the installer as Administrator and follow on-screen messages.

---
