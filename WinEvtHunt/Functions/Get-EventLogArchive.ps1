function Get-EventLogArchive
{
<#
.SYNOPSIS
   Get the file paths of archived event logs matching a given date criteria.
.DESCRIPTION
   Get the file paths of archived event logs matching a given date criteria
.EXAMPLE
   Get-EventLogArchive -FilePath C:\Windows\System32\WinEvt\Logs -NewerThan (Get-Date).AddDays(-30)
   # Return the last 30 days of archived event log file paths in the Windows default event log directory.
.EXAMPLE
   Get-EventLogArchive -LogName ForwardedEvents -ComputerName WEC01 -NewerThan (Get-Date).AddDays(-7)
   # Return the last 7 days of archived event log file paths from the directory path of the ForwardedEvents log.
.EXAMPLE
   Get-EventLogArchive -LogName ForwardedEvents -OlderThan (Get-Date).AddDays(-30) |% {Compress-Archive $_ D:\ArchivedEvents\}
   # An example of using this function in a scheduled task to compress archived event logs older than 30 days.
.INPUTS
   Directory path or Windows Event Log name.
   By containing directory (e.g. "C:\Windows\System32\winevt\Logs")
   By log name (e.g. "Application")
.OUTPUTS
   Matching file path(s)
.NOTES
   Author: Swearbear
   Version: 1.0
#>
    [cmdletbinding(DefaultParameterSetName='LogName')]
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='LogName')]
        [string] $LogName,

        [Parameter(Mandatory=$true,ParameterSetName='Path')]
        [string] $Path,

        [Parameter(ParameterSetName='LogName')]
        [Alias('Cn')]
        [string] $ComputerName = $env:COMPUTERNAME,

        [Parameter(ParameterSetName='Path')]
        [Parameter(ParameterSetName='LogName')]
        [regex] $Pattern = '(?<=[\\\$\:\w\-_]*\-)\d{4}(\-\d{2}){5}(?=\-\d{3}.(evtx|zip)$)',

        [Parameter(ParameterSetName='Path')]
        [Parameter(ParameterSetName='LogName')]
        [string] $FileExtension = ".evtx",

        [Parameter(ParameterSetName='Path')]
        [Parameter(ParameterSetName='LogName')]
        [Alias('NewerThan')]
        [datetime] $Start,

        [Parameter(ParameterSetName='Path')]
        [Parameter(ParameterSetName='LogName')]
        [Alias('OlderThan')]
        [datetime] $End
    )

    if (($ComputerName -eq $env:COMPUTERNAME) -or (Test-LocalHost -ComputerName $ComputerName -NullOrEmptyAction $true))
    {
        $PSBoundParameters.Remove('ComputerName') > $null
    }

    # ParameterSet 'LogName'
    if ($PSCmdlet.ParameterSetName -eq 'LogName')
    {
        # Create hashtable of parameters for Get-WinEvent to look for a matching event log
        $params = Copy-Hashtable -InputObject $PSBoundParameters -Key LogName,ComputerName,@{Archive={$true}},@{Parent={$true}} -Force

        # Look for matching event log
        $Path = Resolve-EventLogPath @params
    }
    else
    {
        $Path = Resolve-PathSafe -Path
    }

    # Test access to the path
    $Item = Get-Item -Path $Path -ErrorAction Stop


    $Directory = $Item | Where-Object { $_ -is [System.IO.DirectoryInfo] }
    $Files = $Item | Where-Object { ($_ -is [System.IO.FileInfo]) -and ($_.Extension -eq $FileExtension) }
    if ($Directory)
    {
        $Files = Get-ChildItem $Directory -File -Filter "*$FileExtension"
    }
    
    if (-Not $Files)
    {
        $msg = ("Event log archive not found at path: {0}" -f $Path)
        Write-Error -ErrorAction Stop -Message $msg
    }

    # Create hashtable of bound parameters that match
    $daterange = Copy-Hashtable -InputObject $PSBoundParameters -Key Start,End
    
    # Try to parse the filename and create a datetime object
    foreach ($fn in $files.FullName)
    {
        if ($fn -match $Pattern)
        {
            try
            {
                $date = Get-ParsedDate -InputString $Pattern.Match($fn).Value -FormatString "yyyy-MM-dd-HH-mm-ss"
            }
            catch
            {
                Write-Error $_
                continue
            }

            if ($daterange.Count -gt 0)
            {
                if (-Not (Test-InDateRange -InputObject $date @daterange))
                {
                    continue
                }
            }

            [pscustomobject]([ordered]@{Date=$date;Path=$fn})
        }
    }
}