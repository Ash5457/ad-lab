# Troubleshooting Log

Every problem I hit while building and migrating this lab, in the order it happened. Each entry records what I saw, what I assumed first (including when that was wrong), what was actually going on, how I fixed it, and how I proved the fix worked.

Raw PowerShell transcripts for each session are in [`evidence/transcripts/`](evidence/transcripts/).

| # | Phase | Problem | Root cause in one line |
|---|---|---|---|
| 1 | Build | `New-ADGroup` "name already in use" | A group can't share a name with an OU in the same container |
| 2 | Build | Fixed scripts threw the identical errors | `Copy-Item` nested the folder, so the VM kept running old copies |
| 3 | Build | Two Task Manager GPOs linked to HR | Built one by hand after the script had already made it |
| 4 | Build | `Remove-Item` "insufficient access rights" | Hidden `manifest.xml` left behind by a wildcard move |
| 5 | Client | `00-prep.ps1` refused to run | Non-elevated window and blocked script files |
| 6 | Client | `nslookup` couldn't find the domain | The only DNS server (DC01) was powered off |
| 7 | DC02 prep | "DNS request timed out / Server: UnKnown" on every lookup | No reverse lookup zone; the real queries were succeeding |
| 8 | Verify | `dcdiag` wall of red after promotion | Mostly VM noise; two real items fixed before moving roles |
| 9 | Scream test | Couldn't elevate on the client with DC01 off | Built-in admin disabled, local admin had no password, domain admin needs a reachable DC |
| 10 | Demotion | `_msdcs` delegation still pointed at DC01 | Delegation never updated when DC02 was promoted |
| 11 | Demotion | DC02 blue screen `0x7A` mid-migration | External USB SSD holding the VMs dropped out |

---

## 1. `New-ADGroup`: "name already in use"

**Symptom.** `03-users-groups.ps1` created the three users, then failed:

```
New-ADGroup : An attempt was made to add an object to the directory with a name that is already in use
CN=HR,DC=deadeye5457,DC=com
```

`05-shares.ps1` then failed with Windows error **1332** ("No mapping between account names and security IDs was done") but still printed `Shared: HR`.

**First thought.** The group already existed from an earlier run.

**Root cause.** The script created groups at the domain root, where `OU=HR` already lives. Active Directory requires names to be unique within a container, even across object types, so a group called HR and an OU called HR can't sit side by side. Because the script stops on the first error, neither group was created. Error 1332 followed from that: the share script asked Windows to grant access to `DEADEYE5457\HR`, and a group that doesn't exist has no SID to grant. The `Shared: HR` line was misleading because the script printed it without checking whether the share had actually been created.

**Fix.**
- Added a `Groups` OU in `02-ou-structure.ps1`.
- Created the security groups there in `03-users-groups.ps1`.
- Made `05-shares.ps1` check `icacls`'s exit code. `icacls` is an external program, so `$ErrorActionPreference = 'Stop'` doesn't apply to it:

```powershell
icacls $s.Path /grant "${netbios}\$($s.Group):(OI)(CI)M" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls grant failed on $($s.Path)" }
```

**Verified.** `Get-ADGroup -SearchBase "OU=Groups,DC=deadeye5457,DC=com"` lists HR and Personal, `Get-ADGroupMember HR` lists areyes, and `icacls C:\Shares\HR` shows `DEADEYE5457\HR:(OI)(CI)(M)`.

**Takeaway.** A success message only means something if the script checked the result before printing it.

---

## 2. Fixed scripts threw the identical errors

**Symptom.** After fixing the scripts on the host and re-copying them into the VM, the same errors came back on **the exact same line numbers** (`03` line 31, `05` line 21).

**First thought.** The fix was wrong, or the edit hadn't been saved on the host.

**Root cause.** `Copy-Item` behaves differently when the destination folder already exists. The first copy created `C:\Lab\scripts` and filled it. Every later copy put the whole folder *inside* it, as `C:\Lab\scripts\scripts\`. My edits landed one level down, and I kept running the stale files. The unchanged line numbers were the giveaway: a bad fix would have moved or changed the error, while a fix that never ran leaves it exactly where it was.

**Fix.** Copy the folder's contents instead of the folder itself, so the result is the same every time:

```powershell
New-Item C:\Lab\scripts -ItemType Directory -Force | Out-Null
Copy-Item '\\vmware-host\Shared Folders\scripts\*' C:\Lab\scripts -Recurse -Force
```

**Verified.** `Test-Path C:\Lab\scripts\scripts` returned `True` before the fix. `Select-String C:\Lab\scripts\03-users-groups.ps1 -Pattern 'groupOU'` returned nothing before and a match after. The re-run created both groups with no errors.

**Takeaway.** When a fix changes nothing at all, first prove the fix actually ran.

---

## 3. Duplicate Task Manager GPO

**Symptom.** Two GPOs linked to the HR OU did the same job: `U_Restrict_TaskMgr` and `Task Manager-Restricted`.

**First thought.** Nothing at first. I found it while checking the OU's links during the one manual GPO step.

**Root cause.** `04-gpos.ps1` had already created and linked `U_Restrict_TaskMgr`. I then built `Task Manager-Restricted` by hand in GPMC without checking first. Nothing broke, since both set the same value, but two sources for one setting means a later change to one is silently duplicated or overridden by the other. It also means a rebuild from the scripts would no longer match the running domain.

**Fix.**

```powershell
Remove-GPO -Name 'Task Manager-Restricted'   # removes the GPO and its link
```

**Verified.** `(Get-GPInheritance -Target 'OU=HR,DC=deadeye5457,DC=com').GpoLinks` lists only `U_Restrict_TaskMgr`.

**Takeaway.** Once something is scripted, the script is the only source of truth. Check `Get-GPO -All` before clicking anything.

---

## 4. GPO backup: "insufficient access rights"

**Symptom.** After moving the Default Domain Policy backup out of the transcripts share on the host, `Remove-Item` on the now-supposedly-empty folder said it still had children, then failed with "You do not have sufficient access rights" on `manifest.xml`.

**First thought.** A permissions problem caused by the VMware shared folder.

**Root cause.** `Backup-GPO` writes `manifest.xml` as a **hidden** file. `Move-Item ...\*` skips hidden files, so the `{GUID}` backup folder moved but the manifest stayed behind. `Remove-Item` won't delete a hidden file without `-Force`, and reports that with misleading "access rights" wording. It was never a permissions issue.

**Fix.**

```powershell
Get-ChildItem "$env:ADLAB\evidence\transcripts\gpo-backup" -Force |
  Move-Item -Destination "$env:ADLAB\scripts\gpo-backups\" -Force
```

**Verified.** `Get-ChildItem scripts\gpo-backups -Force` shows both the `{GUID}` folder and `manifest.xml`. The manifest matters, because it's how `Import-GPO -BackupGpoName` finds a backup by name.

**Takeaway.** Error wording is a hint, not a diagnosis. Look at what is actually there (`-Force` shows hidden files).

---

## 5. `00-prep.ps1` refused to run on the client

**Symptom.** Running `.\00-prep.ps1` on CLIENT01 was refused with a permissions error.

**First thought.** I didn't save the exact error text, so the cause below is the most likely one, not a confirmed one.

**Root cause (most likely).** Two problems stacked:
1. The PowerShell window wasn't elevated, and the script changes machine-level settings (`Set-NetIPInterface`, `New-NetIPAddress`, `Rename-Computer`), which need admin rights.
2. The copied scripts still carried their "came from another computer" mark, which execution policy blocks until `Unblock-File` clears it.

**Fix.** Opened PowerShell **as Administrator** and ran the full session-start block instead of skipping parts of it:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem C:\Lab\scripts -Recurse | Unblock-File
```

**Verified.** The script set 10.1.10.5, renamed the machine to CLIENT01, and rebooted.

**Takeaway.** These two errors read differently and have different fixes: "Access is denied" needs elevation, while "running scripts is disabled" or "not digitally signed" means execution policy or a blocked file. Capture the red text before fixing it.

---

## 6. `nslookup` couldn't find the domain

**Symptom.** On CLIENT01, `nslookup deadeye5457.com` failed before the domain join.

**First thought.** The client's DNS setting from `00-prep.ps1` was wrong.

**Root cause.** DC01 was powered off. CLIENT01's only DNS server is 10.1.10.2, so there was nothing to ask.

**Fix.** Booted DC01, waited for it to finish starting, and retried.

**Verified.** `Test-Connection 10.1.10.2` replied, `nslookup` answered from 10.1.10.2, and the domain join succeeded.

**Takeaway.** On a domain, clients depend on DC DNS for everything. That's why a DC outage looks like "the whole network is down" to users.

---

## 7. "DNS request timed out / Server: UnKnown" on every lookup

**Symptom.** On DC02, every `nslookup` printed "DNS request timed out" and "Server: UnKnown" first. The SRV lookup underneath still correctly returned DC01 on port 389 at 10.1.10.2.

**First thought.** DNS from DC02 to DC01 was broken, just like in entry 6.

**Root cause.** Before running your query, `nslookup` reverse-looks-up the DNS server's own IP so it can print a name on the `Server:` line. There was no reverse lookup zone, so that one side lookup timed out. The real query succeeded every time.

**Fix.** Created an AD-integrated reverse zone on DC01 and registered DC01's PTR record.

```powershell
Add-DnsServerPrimaryZone -NetworkId "10.1.10.0/24" -ReplicationScope Domain
ipconfig /registerdns
```

**Verified.** `nslookup 10.1.10.2` from DC02 returns `dc01.deadeye5457.com`, and lookups print a server name with no timeout.

**Takeaway.** A timeout followed by an answer is cosmetic. A timeout with no answer is an outage. Read the whole output before deciding DNS is broken.

---

## 8. `dcdiag` wall of red after promoting DC02

**Symptom.** `dcdiag /e /q` failed DFSREvent, KccEvent, Services, SystemLog and ObjectsReplicated across both DCs, with a long list of System log errors.

**First thought.** The promotion had gone wrong and replication was broken.

**Root cause.** Mostly noise from running in a VM, with two real issues mixed in. I sorted every failure before touching anything:

| Failure | Verdict | Reason |
|---|---|---|
| DC02 ObjectsReplicated | **Real** | Replication hadn't caught up after promotion |
| DC01 event-log tests: "RPC server is unavailable" (`0x6ba`) | **Real, minor** | DC01's firewall blocked remote event-log reads. Every other DC01 test passed |
| DFSREvent (both DCs) | Noise | SYSVOL's first sync logs warnings, and the test flags any warning from the last 24 hours. Event 4604 proves the sync completed |
| DC01 Services: DnsCache `WIN32_SHARE_PROCESS` | Noise | Server 2016 with 2 GB RAM shares service processes; the 2025 dcdiag expects the newer layout |
| Hypervisor launch failed, VBS, Secure Boot DBX/SBAT | Noise | The VM has no nested virtualization or Secure Boot |
| Group Policy "no connectivity" | Noise | Transient, during DC02's reboot |
| DCOM 10016, Sync Host service | Noise | Harmless, common on any Windows install |
| KDC event `0x25` | Watched | Kerberos hardening during a mixed 2016/2025 period. Logged once, never recurred |

**Fix.**

```powershell
# DC01: allow remote event-log reads
Enable-NetFirewallRule -DisplayGroup "Remote Event Log Management"
# Both DCs: confirm the network profile (DC01 needed a restart of Network Location Awareness)
Get-NetConnectionProfile | Select-Object Name, NetworkCategory   # DomainAuthenticated
Restart-Service NlaSvc -Force
# DC02: force a full sync
repadmin /syncall /AdeP
```

**Verified.**
- `repadmin /replsummary`: 0 / 5 failures in **both** directions.
- `repadmin /showrepl`: all five partitions "was successful".
- `net share`: SYSVOL and NETLOGON published on DC02.
- Event **4604**: "completed initial synchronization of SYSVOL with partner DC01".
- Re-running `dcdiag`: ObjectsReplicated and the RPC errors were gone; only the noise rows remained.
- Schema `objectVersion` went from 87 to **91**, proving adprep ran.

**Takeaway.** "dcdiag reports nothing" is the ideal, not the go/no-go bar. Sort every failure into noise or real, and prove the real ones fixed with `repadmin`, the SYSVOL state and event 4604 before moving FSMO roles.

---

## 9. Couldn't elevate on the client with DC01 off

**Symptom.** During the scream test, signed in as areyes with DC01 powered off, the UAC prompt rejected `administrator`. `Get-LocalGroupMember Administrators` failed with error **1789**.

**First thought.** The client had fallen off the domain. Error 1789 is "the trust relationship between this workstation and the primary domain failed."

**Root cause.** Four things, none of them a broken trust:
- On its own, `administrator` means CLIENT01's built-in local Administrator, which Windows 11 disables by default.
- The local admin account I created during setup (`Computer1`) had no password, and Windows wouldn't accept it at the elevation prompt with a blank one.
- Elevating with the domain admin account needs a reachable DC. DNS still pointed only at DC01, which was off, so the client couldn't find DC02.
- `Get-LocalGroupMember` tries to resolve every domain account in the group. With no DC reachable it fails with 1789, even though the trust is fine.

**Fix.** `net localgroup administrators`, which doesn't need a DC to answer, showed the local admin account. I set a password on `Computer1`, elevated as `.\Computer1`, and repointed DNS to DC02.

**Verified.** After repointing, `nltest /dsgetdc:deadeye5457.com` named DC02, and `DEADEYE5457\Domain Admins` reappeared in the local Administrators group.

**Takeaway.** Error 1789 here was a lookup failure, not a broken trust. Confirm with a tool that doesn't depend on the thing that's down before you rejoin a machine to the domain. Separately, a local admin account with a blank password is a real security finding on any workstation, and it's exactly the problem LAPS exists to solve.

---

## 10. Stale `_msdcs` delegation pointing at DC01

**Symptom.** After demotion, `Get-ADDomainController -Filter *` listed only DC02. But in the `deadeye5457.com` zone, the `_msdcs` NS (delegation) record still said `dc01.deadeye5457.com`.

**First thought.** A leftover the demotion should have cleaned up.

**Root cause.** The delegation was created together with the forest on DC01, and nothing updated it when DC02 was promoted. Its only listed name server was therefore a machine that was no longer a DC. The `_msdcs` zone itself was fine: its own NS record already said dc02.

**Fix (on DC02).**

```powershell
Add-DnsServerZoneDelegation -Name deadeye5457.com -ChildZoneName _msdcs -NameServer dc02.deadeye5457.com -IPAddress 10.1.10.3
Remove-DnsServerResourceRecord -ZoneName deadeye5457.com -Name _msdcs -RRType NS -RecordData dc01.deadeye5457.com. -Force
```

**Verified.** Every NS record in both zones says dc02, and no SRV records reference dc01. See [`evidence/11-only-dc02.png`](evidence/11-only-dc02.png).

**Takeaway.** A clean demotion doesn't guarantee clean DNS. Always check the NS and SRV records for the old DC.

---

## 11. DC02 blue screen `0x7A` mid-migration

**Symptom.** `dcdiag`'s SystemLog test showed DC02 had rebooted from a bugcheck:

```
The bugcheck was: 0x0000007a (0xffffeccc841c3488, 0xffffffffc0000185, ...)
The previous system shutdown at 3:50:56 PM was unexpected.
```

**First thought.** I decoded the codes before guessing. `0x7A` is `KERNEL_DATA_INPAGE_ERROR`: Windows couldn't read paged-out memory back from disk. The second parameter, `0xc0000185`, is `STATUS_IO_DEVICE_ERROR`: the disk itself failed the read. In a VM, that points at the host's storage, not at Windows.

**Root cause.** The VM files live on an external SSD connected over USB. The drive dropped out for a moment, DC02's virtual disk disappeared mid-read, and the guest crashed.

**Fix.**
- Disabled USB selective suspend (Power Options > Advanced > USB settings) so Windows stops power-managing the port.
- In Device Manager, turned off "Allow the computer to turn off this device to save power" on the SSD's USB controller.
- Connected the SSD directly to the laptop, with no hub.

**Verified.**
- Host storage had plenty of free space, which ruled out a full disk and left the USB dropout as the cause.
- The Directory Service log's only errors were two event **2087**s (15:34 and 15:52), both saying DC02 couldn't resolve DC01's GUID record (`9cabd6e2-...._msdcs.deadeye5457.com`). That fits DC01's demotion removing its DNS records while DC02 still had a replication link to it, and none have appeared since.
- No database corruption events (IDs 467 or 474), so the AD database came through the crash intact.

**Takeaway.** This is why the migration had a system state backup and coordinated snapshots. A DC crashing mid-migration is a real risk, and the bugcheck parameters said "storage" before I had touched anything.
