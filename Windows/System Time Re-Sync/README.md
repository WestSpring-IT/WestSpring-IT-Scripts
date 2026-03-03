# SystemTimeReSync

PowerShell script to enable automatic time zone detection and
resynchronise Windows Time (`w32time`) using a defined NTP server.

Designed for managed environments such as Intune, RMM platforms,
scheduled tasks, or manual administrative execution.

------------------------------------------------------------------------

## Overview

`SystemTimeReSync` performs the following actions:

1.  Enables **"Set time zone automatically"**
2.  Ensures required location permissions are enabled
3.  Configures Windows Time (`w32time`) to use a specified NTP server
4.  Restarts and validates the Windows Time service
5.  Logs detailed operational output for auditing and troubleshooting

The script is safe to run repeatedly and is suitable for
enterprise-managed devices.

------------------------------------------------------------------------

## Features

### Automatic Time Zone Configuration

-   Enables the `tzautoupdate` service
-   Sets required location capability permissions
-   Attempts to start supporting services (`tzautoupdate`, `lfsvc`)
-   Logs verification of registry settings

Equivalent to enabling:

Settings → Time & Language → Date & Time → **Set time zone
automatically**

If controlled by Group Policy or MDM, the script logs a warning and
continues.

------------------------------------------------------------------------

### Windows Time (w32time) Configuration

-   Sets a manual NTP peer (default: `time.windows.com`)
-   Restarts the `w32time` service
-   Waits until the service reaches `Running` state
-   Forces rediscovery and resynchronisation
-   Logs:
    -   `w32tm /query /status`
    -   `w32tm /query /peers`

------------------------------------------------------------------------

### Logging

Logs are written to:

C:`\WestSpring `{=tex}IT`\LogFiles`{=tex}\

Log file format:

YYYY-MM-DD-SystemTimeReSync.log

Log entry format:

HH:MM:SS \| LEVEL \| Message

Log levels:

-   INFO\
-   SUCCESS\
-   WARN\
-   ERROR

Console output is colour-coded.

------------------------------------------------------------------------

## Requirements

-   Windows 10 or Windows 11\
-   PowerShell 5.1+\
-   Administrator privileges

------------------------------------------------------------------------

## Usage

### Manual Execution

``` powershell
.\SystemTimeReSync.ps1
```

### Recommended for RMM / Intune

``` powershell
powershell.exe -ExecutionPolicy Bypass -File .\SystemTimeReSync.ps1
```

------------------------------------------------------------------------

## Customisation

### Change NTP Server

Edit the following line in the script:

``` powershell
$NtpServer = "time.windows.com"
```

Example:

``` powershell
$NtpServer = "pool.ntp.org"
```

------------------------------------------------------------------------

## Exit Codes

  Code   Meaning
  ------ ---------
  0      Success
  1      Failure

------------------------------------------------------------------------

## Behaviour Notes

-   If automatic time zone is disabled by policy, the script logs a
    warning and continues.
-   The script does not override enforced Group Policy or MDM
    restrictions.
-   Designed to be idempotent and safe for repeated execution.
-   No external modules or dependencies required.

------------------------------------------------------------------------

## Security Considerations

-   Modifies registry keys under `HKLM`
-   Adjusts Windows service configuration
-   Requires elevated privileges
-   Does not transmit or collect data
-   No external network calls beyond NTP synchronisation

------------------------------------------------------------------------

## Author

Thomas Samuel\
WestSpring IT Limited\
thomassamuel@westspring-it.co.uk

------------------------------------------------------------------------

## License

Copyright © WestSpring IT Limited.\
Usage and redistribution subject to company policy.
