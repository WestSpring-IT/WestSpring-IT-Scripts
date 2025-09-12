$FormFactors = @{
    0  = "Unknown"
    1  = "Other"
    2  = "SIP"
    3  = "DIP"
    4  = "ZIP"
    5  = "SOJ"
    6  = "Proprietary"
    7  = "SIMM"
    8  = "DIMM"
    9  = "TSOP"
    10 = "PGA"
    11 = "RIMM"
    12 = "SODIMM"
    13 = "SRIMM"
    14 = "FB-DIMM"
}

$SMBIOSMemoryTypes = @{
    0  = "Unknown"
    1  = "Other"
    2  = "DRAM"
    3  = "Synchronous DRAM"
    4  = "Cache DRAM"
    5  = "EDO"
    6  = "EDRAM"
    7  = "VRAM"
    8  = "SRAM"
    9  = "RAM"
    10 = "ROM"
    11 = "Flash"
    12 = "EEPROM"
    13 = "FEPROM"
    14 = "EPROM"
    15 = "CDRAM"
    16 = "3DRAM"
    17 = "SDRAM"
    18 = "SGRAM"
    19 = "RDRAM"
    20 = "DDR"
    21 = "DDR2"
    22 = "DDR2 FB-DIMM"
    24 = "DDR3"
    25 = "FBD2"
    26 = "DDR4"
    27 = "LPDDR"
    28 = "LPDDR2"
    29 = "LPDDR3"
    30 = "LPDDR4"
    31 = "Logical non-volatile device"
    32 = "HBM"
    33 = "HBM2"
    34 = "DDR5"
    35 = "LPDDR5"
    36 = "DDR5 with ECC"
    37 = "LPDDR5 with ECC"
    38 = "DDR5 with ECC and CRC"
    39 = "LPDDR5 with ECC and CRC"
    40 = "DDR5 with CRC"
    41 = "LPDDR5 with CRC"
}

Get-WmiObject -class win32_bios | Select-Object @{Name = "Serial Number"; Expression = { $_.SerialNumber }} | Format-List
Get-WmiObject Win32_PhysicalMemory | Select-Object BankLabel, `
@{Name = "Capacity, GB"; Expression = {$_.Capacity / 1GB}}, `
@{Name = 'ConfiguredClockSpeed (MHz)'; Expression = {$_.ConfiguredClockSpeed}}, `
@{Name = 'ConfiguredVoltage (mV)'; Expression = {$_.ConfiguredVoltage}}, `
@{Name = 'SMBIOSMemoryType'; Expression = { 
    if ($_.SMBIOSMemoryType -ne $null -and $SMBIOSMemoryTypes.ContainsKey([int]$_.SMBIOSMemoryType)) { 
        $SMBIOSMemoryTypes[[int]$_.SMBIOSMemoryType] 
    } else { 
        "Unknown" 
    }
}}, `
Manufacturer, `
DeviceLocator, `
@{Name = 'FormFactor'; Expression = { 
    if ($_.FormFactor -ne $null -and $FormFactors.ContainsKey([int]$_.FormFactor)) { 
        $FormFactors[[int]$_.FormFactor] 
    } else { 
        "Unknown" 
    }
}}
Get-WmiObject -Class Win32_PhysicalMemoryArray | Select-Object @{Name = "Max Capacity (GB)"; Expression = {($_.MaxCapacity / 1MB ) }}, @{Name = "Max Memory Devices"; Expression = { $_.MemoryDevices }} | Format-List




