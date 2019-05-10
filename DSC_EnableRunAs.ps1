Start-Transcript -Path '.\DSC_EnableRunAs_log.txt' -Append

# Build the LCM configuation object
[DSCLocalConfigurationManager()]
configuration LCMConfig
{
    Settings
    {
        AllowModuleOverWrite = $true
        ConfigurationMode = 'ApplyAndAutoCorrect'
        ConfigurationModeFrequencyMins = 15
        RebootNodeIfNeeded = $false
        RefreshFrequencyMins = 30
        RefreshMode = 'Push'
    }
}

# Build DSC configuration object
Configuration EnableRunAs
{
    Import-DscResource –ModuleName ’PSDesiredStateConfiguration’

    Registry ConsentPromptBehaviorUser
    {
        Ensure = "Present"
        Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\system"
        ValueName = "ConsentPromptBehaviorUser"
        ValueType = "Dword"
        ValueData = "1"
    }

    Registry batfile
    {
        Ensure = "Absent"
        Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\batfile\shell\runasuser"
        ValueName = "SuppressionPolicy"
    }

    Registry cmdfile
    {
        Ensure = "Absent"
        Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\cmdfile\shell\runasuser"
        ValueName = "SuppressionPolicy"
    }

    Registry exefile
    {
        Ensure = "Absent"
        Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\exefile\shell\runasuser"
        ValueName = "SuppressionPolicy"
    }

    Registry mscfile
    {
        Ensure = "Absent"
        Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Classes\mscfile\shell\runasuser"
        ValueName = "SuppressionPolicy"
    }
}

# Execute the LCM configuration object to generate .MOF file
LCMConfig
# Apply LCM configuration
Set-DscLocalConfigurationManager -Path '.\LCMConfig\' -Verbose -Debug

# Execute the DSC configuration object to generate .MOF file
EnableRunAs
# Apply DSC configuration
Start-DscConfiguration -Path '.\EnableRunAs\' -Force -Wait -Verbose -Debug

# Cleanup
Remove-Item '.\LCMConfig','.\EnableRunAs' -Recurse
Stop-Transcript