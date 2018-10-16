<#
.Synopsis
   Simplify searching of Windows event logs plus archived .evtx files.
.DESCRIPTION
   Simplify searching of Windows event logs plus archived .evtx files.  Attempts to speed up bulk searches from multiple remote hosts aReturns events as serialized objects.
.EXAMPLE
   Get-BulkWinEvent.ps1 -ComputerName DC1,DC2,DC3 -LogName Security -XPath "*[System[EventID=4624]]" -ArchiveNewerThan (Get-Date).AddDays(-7)

   # Returns events matching event id 4624 from the Security log and all archived .evtx files created within the last 7 days.
.EXAMPLE
   Get-BulkWinEvent.ps1 -ComputerName WEC1 -LogName ForwardedEvents -XPath "*[System[EventID=4625]]" -SecondaryFilter "*[EventData[Data[@Name='TargetUserName' and not(contains(text(), '$'))]]]"

   # Returns failed logon events that were forwarded to a Windows Event Collector.  Uses a second xpath filter to exclude computer accounts (ends with '$') before returning results.
   # The second XPath filter supports XPath 2.0, where as the first XPath parameter supports only a subset of XPath 1.0.
.NOTES
   Author: Swearbear
   Version: 2.0
   Release: 16 Oct 18
#>
[cmdletbinding()]
param(
    [Alias('Path')]
    [string] $LogName,
    [Alias('Cn')]
    [string[]] $ComputerName,
    [string] $XPath,
    [string] $SecondaryFilter,
    [datetime] $ArchiveNewerThan,
    [int] $MaxEvents
)

$ScriptBlock = {

#region FUNCTIONS

    # Required function for returning archived event log files
    function Get-EventLogArchive {
        param(
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

        function Get-ParsedDate {
            param(
                [Parameter(Mandatory=$true)]
                [string] $InputString,

                [Parameter(Mandatory=$true)]
                [string] $FormatString,

                [System.Globalization.CultureInfo] $Provider = [System.Globalization.CultureInfo]::InvariantCulture,

                [System.Globalization.DateTimeStyles] $DateTimeStyles = [System.Globalization.DateTimeStyles]::None,

                [switch] $Exact
            )

            [ref]$parsedDate = Get-Date
            if ([DateTime]::TryParseExact($InputString, $FormatString, $Provider, $DateTimeStyles, $parsedDate))
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
                $IPv4Address = Get-WmiObject win32_networkadapterconfiguration |? {$_.IPEnabled -eq $true} |% {$_.IPAddress |? {$_ -match '(\d{1,3}\.){3}\d{1,3}'}}
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
        $Directory = $Item |? { $_ -is [System.IO.DirectoryInfo] }
        $Files = $Item |? { ($_ -is [System.IO.FileInfo]) -and ($_.Extension -eq $FileExtension) }
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

        $FileNameList = $Files |% { $_.FullName }

        $FileNameList |% {
            $dateString = $Pattern.Match($_).Value
            if ($dateString)
            {
                if (($NewerThan) -and ($OlderThan))
                {
                    if (Get-ParsedDate -InputString $dateString -FormatString "yyyy-MM-dd-HH-mm-ss" |? {($_ -gt $NewerThan) -and ($_ -lt $OlderThan)})
                    {
                        $_
                    }
                }
                elseif ($NewerThan)
                {
                    if (Get-ParsedDate -InputString $dateString -FormatString "yyyy-MM-dd-HH-mm-ss" |? {$_ -gt $NewerThan})
                    {
                        $_
                    }
                }
                elseif ($OlderThan)
                {
                    if (Get-ParsedDate -InputString $dateString -FormatString "yyyy-MM-dd-HH-mm-ss" |? {$_ -lt $OlderThan})
                    {
                        $_
                    }
                }
                else
                {
                    $_
                }
            }
        }
    }

    function getWinEvtWhere2($LogName, $FilterXPath, $MaxEvents, $SecondaryFilter) {
        $argslist = @("qe", $LogName, "/f:xml")
        if ($MaxEvents)
        {
            $argslist += "/c:$MaxEvents"
        }
        if (Test-Path $LogName)
        {
            $argslist += "/lf" # Switch tells wevtutil that the path parameter is a file path (.evtx) instead of an event log.
            # Store only the file name -- used for populating the ContainerLog property of the output objects
            $LogNameShort = Split-Path $LogName -Leaf
        }
        if (-Not ([string]::IsNullOrEmpty($FilterXPath)))
        {
            $argslist += "/q:$FilterXPath"
        }
        #Wait-Debugger
        $secondFilter = if (-Not ([string]::IsNullOrEmpty($SecondaryFilter))) {$SecondaryFilter} else {"/Event"}
        wevtutil.exe $argslist |ForEach-Object {
            if ($_ -match '^<Event\s') {
                $e = $_ -replace "\sxmlns='http://schemas.microsoft.com/win/2004/08/events/event'", '' -replace '\<RenderingInfo\s.*', '</Event>'
                $node = ([xml]$e).SelectSingleNode($secondFilter)
                if ($node)
                {
                    $ht = [ordered]@{
                        TimeCreated = $node.System.TimeCreated.SystemTime
                        EventID = $node.System.EventID
                        MachineName = $node.System.Computer
                        LogName = $node.System.Channel
                        ContainerLog = $LogName
                    }
                    $i=1
                    $Datas = if ($node.EventData.Data) {$node.EventData.Data} else {$node.UserData.Data}
                    foreach ($data in $Datas) {
                        if ($data.Name)
                        {
                            $ht["Data_$($data.Name)"] = $data.'#text'
                        }
                        else
                        {
                            $ht["Data_{0:D2}" -f $i] = $data.'#text'
                            $i++
                        }
                    }
                    [pscustomobject]$ht
                }
            }
        }
    }

#endregion

    $st = Get-Date
    # Set up variables for execution local or remote
    try
    {
        if ($using:LogName) {$LogName = $using:LogName}
        if ($using:XPath) {$XPath = $using:XPath}
        if ($using:MaxEvents) {$MaxEvents = $using:MaxEvents}
        if ($using:SecondaryFilter) {$SecondaryFilter = $using:SecondaryFilter}
        if ($using:ArchiveNewerThan) {$ArchiveNewerThan = $using:ArchiveNewerThan}
    }
    catch [System.Management.Automation.RuntimeException]
    {
        # Catch the errors from evaluating $using variable when not remoting
    }

    #$DebugPreference = "Continue"
    Write-Host "Searching live log..." -ForegroundColor Yellow
    getWinEvtWhere2 $LogName $XPath $MaxEvents $SecondaryFilter |
        Select-Object TimeCreated,EventID,MachineName,LogName,ContainerLog,Data_*
    Write-Host "Elapsed: $((Get-Date) - $st)"
    if ($ArchiveNewerThan) {
        $i = 0
        $archives = Get-EventLogArchive -LogName $LogName -NewerThan $ArchiveNewerThan

        foreach ($log in $archives) {
            $i++
            Write-Host "Searching archived log ($i/$($archives.count))... $log" -ForegroundColor Yellow
            getWinEvtWhere2 $LogName $XPath $MaxEvents $SecondaryFilter |
                Select-Object TimeCreated,EventID,MachineName,LogName,ContainerLog,Data_*
            Write-Host "Elapsed: $((Get-Date) - $st)"
        }
    }
}

# Execute the scriptblock locally or remotely per bound parameters
if ($ComputerName) { Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock }
else { Invoke-Command -ScriptBlock $ScriptBlock }
