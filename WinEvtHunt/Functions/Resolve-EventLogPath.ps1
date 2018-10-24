function Resolve-EventLogPath
{
<#
.SYNOPSIS
   Resolve the file or directory path of a given event log from its Event Log or Channel name.
.DESCRIPTION
   Resolve the file or directory path of a given event log from its Event Log or Channel name.  If remoting, optionally return as a network path.
.EXAMPLE
   Resolve-EventLogPath -LogName System

   Returns the rooted (qualified) filesystem path to the System log file.
.EXAMPLE
   Resolve-EventLogPath -LogName Microsoft-Windows-Sysmon/Operational -Parent

   Returns the rooted (qualified) filesystem path to the directory containing the Microsoft-Windows-Sysmon/Operational log.
.EXAMPLE
   Resolve-EventLogPath -LogName ForwardedEvents -Parent -AsNetworkPath -ComputerName EastWEC01

   Returns a network path to the directory containing the ForwardedEvents.evtx file on the remote host "EastWEC01"
#>
    param
    (
        [Parameter(Mandatory)]
        [string] $LogName,

        [switch] $Parent,

        [switch] $Archive,

        [Parameter(ParameterSetName='Remote')]
        [Alias('Cn')]
        [string] $ComputerName = $env:COMPUTERNAME,

        [Parameter(ParameterSetName='Remote')]
        [switch] $AsNetworkPath
    )

    if (($ComputerName -eq $env:COMPUTERNAME) -or (Test-LocalHost -ComputerName $ComputerName -NullOrEmptyAction $true))
    {
        $PSBoundParameters.Remove('ComputerName') > $null
    }

    $params = Copy-Hashtable -InputObject $PSBoundParameters -Key @{ListLog={$_.LogName}},ComputerName

    $log = Get-WinEvent @params
    #Wait-Debugger
    # Log found and is configured for archiving ("AutoBackup")
    if ($log)
    {
        # Replace any environment variables with the PowerShell $env: equivalent. Then resolve it.
        $path = $ExecutionContext.InvokeCommand.ExpandString(($log.LogFilePath -replace '%(.*)%', '$env:$1'))
        if ($Archive -and ($log.LogMode -eq 'AutoBackup'))
        {
            # Use the LogFilePath property to know where archived files are written
            if ($Parent)
            {
                $path = Split-Path $path -Parent # Get the parent directory path
            }

        }
        else
        {
            $msg = ("LogName: {0} on computer: {1} is not configured for archiving." -f $LogName,$ComputerName)
            Write-Warning -Message $msg
        }

        if ($PSBoundParameters.ContainsKey('ComputerName')) # Remote computer
        {
            $path = ConvertTo-NetworkPath -Path $path -ComputerName $ComputerName
        }

        Write-Output (Resolve-PathSafe -Path $path)
    }
    else
    {
        $msg = ("Failed to resolve LogName: {0} on computer: {1}." -f $LogName,$ComputerName)
        Write-Error -ErrorAction Stop -Message $msg
    }
}