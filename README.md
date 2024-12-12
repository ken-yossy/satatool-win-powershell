# satatool-win-powershell: Sample script for accessing SATA drive via ATA Pass-Through with powershell in Windows

## Abstract
This repository provides some sample powershell scripts that demonstrate accessing SATA drive using ATA Pass-Through feature in Windows.

You can easily extend, customize these scripts and integrate them into your environment.

## List of scripts

Scripts are stored in the directory `scripts`.
Please check each script for further information (e.g. parameters).

Table 1. List of scripts

|         script name | Description                 | Note |
| ------------------: | :---------------------------|:-----|
| `sata-get-basic-information.ps1` | Retrieve "Model Number", "Serial Number", and "Firmware Revision" via IDENTIFY DEVICE command | |
| `sata-get-smart-attributes.ps1`  | Getting S.M.A.R.T. attributes | |
| `sata-read-sector.ps1`           | Read one sector | LBA can be specified, but should be within 24-bit. |

## Note

Privileged access is required to run these scripts.

## Environment

Confirmed on the following environment:

```powershell
PS C:\temp> $PSVersionTable

Name                           Value
----                           -----
PSVersion                      5.1.19041.5247
PSEdition                      Desktop
PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0...}
BuildVersion                   10.0.19041.5247
CLRVersion                     4.0.30319.42000
WSManStackVersion              3.0
PSRemotingProtocolVersion      2.3
SerializationVersion           1.1.0.1
```

* Tested operating system
  * Windows 10 Pro 64bit (Version 22H2, Build 19045.5247)

## Limitations

Only tested with the SATA drive directly attached to PC.

it may not work over protocol translations such as usb-sata.

## To run scripts

Most of scripts can be run as follows:

```powershell
PS C:\> ./<script name> <PhysicalDriveNo>
```

You can find `PhysicalDriveNo` in "Disk Management" utility.

See comments in each script for further information.

## License
Scripts are released under the MIT License, see LICENSE.

## References
[1] T13, _"Information technology - ATA Command Set - 4 (ACS-4)"_, Working Draft, Revision 14, October 2016

[2] Microsoft, _"(ATA_PASS_THROUGH_EX structure)[https://learn.microsoft.com/en-us/windows-hardware/drivers/ddi/ntddscsi/ns-ntddscsi-_ata_pass_through_ex]"_, Retrieved in December 2024

[2] _"(Sending ATA commands directly to device in Windows?)[https://stackoverflow.com/questions/5070987/sending-ata-commands-directly-to-device-in-windows]"_, Retrieved in December 2024
