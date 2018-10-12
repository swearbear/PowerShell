<#
.Synopsis
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
function Get-EventLogArchive
{
    param
    (
        [Parameter(Mandatory=$true,ParameterSetName='FilePath')]
        [string] $FilePath,

        [Parameter(Mandatory=$true,ParameterSetName='LogName')]
        [string] $LogName,

        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [Alias('Cn')]
        [string] $ComputerName,

        [Parameter(Mandatory=$false,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [regex] $Pattern = '(?<=[\\\$\:\w\-_]*\-)\d{4}(\-\d{2}){5}(?=\-\d{3}.(evtx|zip)$)',

        [Parameter(Mandatory=$false,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [string] $FileExtension = ".evtx",

        [Parameter(Mandatory=$false,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [datetime] $NewerThan,

        [Parameter(Mandatory=$false,ParameterSetName='FilePath')]
        [Parameter(Mandatory=$false,ParameterSetName='LogName')]
        [datetime] $OlderThan
    )

    # Required function to convert date strings to [DateTime]
    function Get-ParsedDate
    {
        param
        (
            [Parameter(Mandatory=$true)]
            [string] $InputString,
    
            [Parameter(Mandatory=$true)]
            [string] $FormatString,
    
            [System.Globalization.CultureInfo] $Provider = [System.Globalization.CultureInfo]::InvariantCulture,
    
            [System.Globalization.DateTimeStyles] $DateTimeStyles = [System.Globalization.DateTimeStyles]::None,
    
            [switch] $Exact
        )
    
        [ref]$parsedDate = Get-Date
        [regex]$pattern = $FormatString -replace '((?<!y)yy(?!y)|(?<!M)MM(?!M)|(?<!d)dd(?!d)|(?<!H)HH(?!H)|(?<!h)hh(?!h)|(?<!m)mm(?!m)|(?<!s)ss(?!s))','\d\d' -replace '(?<!y)yyyy(?!y)','\d{4}' -replace '(?<!M)MMM(?!M)','[A-Z]{3}'
        $dateString = $pattern.Match($InputString).Value
    
        if ([DateTime]::TryParseExact($dateString, $FormatString, $Provider, $DateTimeStyles, $parsedDate))
        {
            Write-Output $parsedDate.Value
        }
    }


    # ParameterSet 'LogName'
    if ($PSCmdlet.ParameterSetName -eq 'LogName')
    {
        $getWinEventParams = @{ListLog = $LogName}
        if ($PSBoundParameters.ContainsKey('ComputerName'))
        {
            # Get IPv4 addresses from the local computer for comparison with the $ComputerName parameter
            $IPv4Address = Get-WmiObject win32_networkadapterconfiguration |Where-Object {$_.IPEnabled -eq $true} |ForEach-Object {$_.IPAddress |Where-Object {$_ -match '(\d{1,3}\.){3}\d{1,3}'}}
            $localhost = "$env:COMPUTERNAME|localhost|127.0.0.1|$($IPv4Address -join '|')"
            if ($ComputerName -match $localhost)
            {
                $PSBoundParameters.Remove('ComputerName') > $null
            }
            else
            {
                $getWinEventParams.Add('ComputerName', $ComputerName)
            }
        }

        $log = Get-WinEvent @getWinEventParams

        if (($log) -and ($log.LogMode -eq 'AutoBackup'))
        {
            if ($getWinEventParams.ContainsKey('ComputerName'))
            {
                $FilePath = (Split-Path $log.LogFilePath -Parent)
                $drive = (Split-Path $FilePath -Qualifier) -replace '\:','$'
                $path = Split-Path $FilePath -NoQualifier
                $FilePath = Join-Path "\\$ComputerName\$drive" $path
            }
            else
            {
                $FilePath = (Split-Path $log.LogFilePath -Parent)
            }
        }
        else
        {
            Write-Error ("Archived event logs not found for LogName: {0} on computer: {1}" -f $LogName,$ComputerName) -ErrorAction Stop
            exit
        }
    }


    $Item = Get-Item $FilePath -ErrorAction Stop
    $Directory = $Item |Where-Object { $_ -is [System.IO.DirectoryInfo] }
    $Files = $Item |Where-Object { ($_ -is [System.IO.FileInfo]) -and ($_.Extension -eq $FileExtension) }
    if (-Not $Files)
    {
        if (-Not $Directory)
        {
            Write-Error "Event log archive not found at path: $Path" -ErrorAction Stop
            exit
        }
        else
        {
            $Files = Get-ChildItem $Directory -File -Filter "*$FileExtension"
            if (-Not $Files)
            {
                Write-Error "Event log archive not found at path: $Path" -ErrorAction Stop
                exit
            }
        }
    }

    $FileNameList = $Files |ForEach-Object { $_.FullName }

    $FileNameList |ForEach-Object {
        $dateString = $Pattern.Match($_).Value
        if ($dateString)
        {
            $ArchiveDate = Get-ParsedDate -InputString $dateString -FormatString "yyyy-MM-dd-HH-mm-ss"
            if (($NewerThan) -and ($OlderThan))
            {
                if ($ArchiveDate |Where-Object {($_ -gt $NewerThan) -and ($_ -lt $OlderThan)})
                {
                    New-Object pscustomobject -Property ([ordered]@{
                        ArchiveDate = $ArchiveDate
                        Path = $_
                    })
                }
            }
            elseif ($NewerThan)
            {
                if ($ArchiveDate |Where-Object {$_ -gt $NewerThan})
                {
                    New-Object pscustomobject -Property ([ordered]@{
                        ArchiveDate = $ArchiveDate
                        Path = $_
                    })
                }
            }
            elseif ($OlderThan)
            {
                if ($ArchiveDate |Where-Object {$_ -lt $OlderThan})
                {
                    New-Object pscustomobject -Property ([ordered]@{
                        ArchiveDate = $ArchiveDate
                        Path = $_
                    })
                }
            }
            else
            {
                New-Object pscustomobject -Property ([ordered]@{
                    ArchiveDate = $ArchiveDate
                    Path = $_
                })
            }
        }
    }
}

