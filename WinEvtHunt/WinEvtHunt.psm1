
# Load other, perhaps unrelated functions
foreach ($script in (Get-ChildItem -Path "$PSScriptRoot\Functions" -Filter "*.ps1" -File))
{
    . $script.FullName
}


function Get-LocalIPAddress
{
<#
.SYNOPSIS
   TODO
.DESCRIPTION
   TODO
.EXAMPLE
   TODO
.EXAMPLE
   TODO
#>
    [CmdletBinding(DefaultParameterSetName='IP')]
    param
    (
        [Parameter(ParameterSetName='IPv4')]
        [switch] $IPv4,

        [Parameter(ParameterSetName='IPv6')]
        [switch] $IPv6
    )
    #Requires -Version 3.0
    $query = 'SELECT IPEnabled,IPAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = true'
    $ipaddress = Get-CimInstance -Query $query | Select-Object -ExpandProperty IPAddress
    if ($ipaddress)
    {
        if ($IPv4)
        {
            $ipaddress | Where-Object {$_ -match '(\d{1,3}\.){3}\d{1,3}'}
        }
        elseif ($IPv6)
        {
            $ipaddress | Where-Object {$_ -notmatch '(\d{1,3}\.){3}\d{1,3}'}
        }
        else
        {
            $ipaddress
        }
    }
    else
    {
        $msg = ("Failed to identify any local {0} address." -f $PSCmdlet.ParameterSetName)
        Write-Error -Message $msg
    }
}


function Test-LocalHost
{
<#
.SYNOPSIS
   Test if a value represents the local computer by hostname or IP address.
.DESCRIPTION
   Tests if a given input value matches the local hostname or one of its IP addresses.
.EXAMPLE
   Test-LocalHost -ComputerName 10.54.4.11
.EXAMPLE
   Test-LocalHost -ComputerName LondonDC01
#>
    param
    (
        # This parameter is intentionally not mandatory because parameter binding errors cannot be silenced with -ErrorAction.
        [Parameter(ValueFromPipeline=$true)]
        [AllowEmptyString()]
        [string] $ComputerName = $env:COMPUTERNAME,

        [bool] $NullOrEmptyAction
    )

    if ($ComputerName)
    {
        $IPv4Address = Get-LocalIPAddress -IPv4 -ErrorVariable ER -ErrorAction SilentlyContinue
    
        if ($null -ne $IPv4Address)
        {
            Write-Output ($ComputerName -match "$env:COMPUTERNAME|localhost|127.0.0.1|$($IPv4Address -join '|')")
        }
        else
        {
            foreach ($e in $ER)
            {
                Write-Error -ErrorRecord $e
            }

            Write-Output $false
        }
    }
    else
    {
        $msg = "Evaluation aborted.  The -ComputerName parameter was empty."
        Write-Warning -Message $msg
        if ($PSBoundParameters.ContainsKey('NullOrEmptyAction'))
        {
            Write-Output $NullOrEmptyAction
        }
    }
}


function Resolve-PathSafe
{
    param
    (
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true)]
        [string[]] $Path
    )
      
    process
    {
        foreach ($obj in $Path)
        {
            $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($obj)
        }
    }
}


function ConvertTo-NetworkPath
{
<#
.SYNOPSIS
   TODO
.DESCRIPTION
   TODO
.EXAMPLE
   TODO
.EXAMPLE
   TODO
#>
    [OutputType([string])]
    Param
    (
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [Parameter(Mandatory=$true)]
        [string] $ComputerName
    )

    if ([System.IO.Path]::IsPathRooted($Path))
    {
        $drive = (Split-Path $path -Qualifier) -replace '\:','$' # Gets the drive letter without the path
        $newpath = Split-Path $path -NoQualifier # Get the path without the drive letter
        Join-Path "\\$ComputerName\$drive" $newpath # Combine the pieces with the computer name into a network path
    }
    else
    {
        throw "Path must be rooted or have a drive letter"
    }
}


function Copy-Hashtable
{
<#
.SYNOPSIS
   Copy hashtable and filter for key names
.DESCRIPTION
   Copy hashtable and filter for key names.  Optionally allow null values to be copied.  Optionally force null keys to be created for unmatched names.
.EXAMPLE
   Copy-Hashtable -InputObject $PSBoundParameters -Name ComputerName,Path,Destination
.EXAMPLE
   Another example of how to use this cmdlet
#>
    param
    (
        [Parameter(Mandatory)]
        [hashtable] $InputObject,

        [Parameter(ParameterSetName='Key')]
        [object[]] $Key,

        [switch] $AllowNull,

        [Parameter(ParameterSetName='Key')]
        [switch] $Force
    )

    $ht = @{}

    if ($Key)
    {
        # Validate object types. Only int, string, and hashtables are allowed
        $ValidatedKeys = @()
        foreach ($k in $Key)
        {
            if ($null -eq $k)
            {
                # do not add to validatedkeys. drop.
                # This is useful for releiving callers of the need to do null conditional checks
            }
            elseif (($k -isnot [string]) -and ($k -isnot [hashtable]) -and ($k -isnot [int]))
            {
                throw "error in Key object type"
            }
            elseif (($k -is [hashtable]) -and ($k.Count -gt 1))
            {
                throw "function only supports single-key hashtables"
            }
            elseif ($k -is [int])
            {
                $ValidatedKeys += ($k -as [string])
            }
            else
            {
                $ValidatedKeys += $k
            }
        }

        $refObj = [psobject]$InputObject
        foreach ($k in $ValidatedKeys)
        {
            # All of this logic needs work, review, and testing
            if ($k -is [hashtable])
            {
                $name = $k.Keys | Select-Object -First 1
                $value = $refObj | Select-Object -First 1 | ForEach-Object {($k[$name]).Invoke()}
                
                # This logic needs work
                if (($null -ne $value) -or ($AllowNull -or $Force))
                {
                    $ht[$name] = $value
                }
            }
            elseif ($AllowNull)
            {
                if (($InputObject.ContainsKey($k)) -or $Force)
                {
                    $ht[$k] = $InputObject[$k]
                }
            }
            else
            {
                if ((($InputObject.ContainsKey($k)) -and ($null -ne $InputObject[$k])) -or $Force)
                {
                    $ht[$k] = $InputObject[$k]
                }
            }
        }
    }
    else
    {
        foreach ($kv in $InputObject.GetEnumerator())
        {
            if (($AllowNull) -or ($null -ne $kv.Value))
            {
                $ht.Add($kv.Name, $kv.Value)
            }
        }
    }

    Write-Output $ht
}


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


function Get-ParsedDate
{
<#
.SYNOPSIS
   Simplifies the conversion of arbitrary date/time strings to DateTime objects.
.DESCRIPTION
   Simplifies the conversion of arbitrary date/time strings to DateTime objects.  Really just a wrapper around the System.DateTime.TryParseExact method.
.EXAMPLE
   Get-ParsedDate -InputString "Archive-EventLog-2018-10-03-11-03-50-877.evtx" -FormatString "yyyy-MM-dd-HH-mm-ss"
.INPUTS
   String object with a date.
   Custom date string that matches the date substring of the input string.
.OUTPUTS
   DateTime object
.NOTES
   Author: Swearbear
   Version: 1.0
#>
    param
    (
        [Parameter(Mandatory=$true)]
        [string] $InputString,

        [Parameter(Mandatory=$true)]
        [string] $FormatString,

        [System.Globalization.CultureInfo] $Provider = [System.Globalization.CultureInfo]::InvariantCulture,

        [System.Globalization.DateTimeStyles] $DateTimeStyles = [System.Globalization.DateTimeStyles]::None
    )

    # match only two date/time format characters, (yy, MM, dd, HH, hh, mm, ss)
    $d2 = '((?<!y)yy(?!y)|(?<!M)MM(?!M)|(?<!d)dd(?!d)|(?<!H)HH(?!H)|(?<!h)hh(?!h)|(?<!m)mm(?!m)|(?<!s)ss(?!s))'
    # match only four year format characters
    $d4 = '(?<!y)yyyy(?!y)'
    # match only three month format characters (short month name)
    $a3 = '(?<!M)MMM(?!M)'

    [regex]$pattern = $FormatString -replace $d2, '\d\d' -replace $d4, '\d{4}' -replace $a3,'[A-Z]{3}'
    $dateString = $pattern.Match($InputString).Value
    [ref]$parsedDate = Get-Date

    if ([DateTime]::TryParseExact($dateString, $FormatString, $Provider, $DateTimeStyles, $parsedDate))
    {
        Write-Output $parsedDate.Value
    }
    else
    {
        Write-Error -ErrorAction Stop -Message "Failed to parse date from string: ${InputString}."
    }
}
<#
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
#>


function Test-InDateRange
{
<#
.SYNOPSIS
   TODO
.DESCRIPTION
   TODO
.EXAMPLE
   TODO
.EXAMPLE
   TODO
#>
    param
    (
        [Parameter(Mandatory,ParameterSetName='Min',Position=0)]
        [Parameter(Mandatory,ParameterSetName='Max',Position=0)]
        [Parameter(Mandatory,ParameterSetName='Min+Max',Position=0)]
        [Parameter(Mandatory,ParameterSetName='Min+TS',Position=0)]
        [Parameter(Mandatory,ParameterSetName='Max+TS',Position=0)]
        [datetime] $InputObject,

        [Parameter(Mandatory,ParameterSetName='Min',Position=1)]
        [Parameter(Mandatory,ParameterSetName='Min+Max',Position=1)]
        [Parameter(Mandatory,ParameterSetName='Min+TS',Position=1)]
        [Alias('Min','LowerBound','NewerThan')]
        [datetime] $Start,

        [Parameter(Mandatory,ParameterSetName='Max',Position=2)]
        [Parameter(Mandatory,ParameterSetName='Min+Max',Position=2)]
        [Parameter(Mandatory,ParameterSetName='Max+TS',Position=2)]
        [Alias('Max','UpperBound','OlderThan')]
        [datetime] $End,

        [Parameter(Mandatory,ParameterSetName='Min+TS')]
        [Parameter(Mandatory,ParameterSetName='Max+TS')]
        [timespan] $Timespan,

        [Parameter()]
        [Alias('Zulu')]
        [switch] $Utc
    )

    (&{switch -Regex ($PSCmdlet.ParameterSetName)
    {
        'Min|Max\+TS' {(&{if($Start){$Start}else{$End-$Timespan}}) -le $InputObject}
        'Max|Min\+TS' {(&{if($End){$End}else{$Start+$Timespan}}) -ge $InputObject}
    }}) -notcontains $false
}


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


function Get-WevtutilEvent
{
<#
.SYNOPSIS
   Get and search Windows Events using WEVTUTIL.EXE, which is much faster than Get-WinEvent.
.DESCRIPTION
   Get and search Windows Events using WEVTUTIL.EXE, which is much faster than Get-WinEvent.
   The function acts as a wrapper for WEVTUTIL.EXE's query command ('qe').
   It only supports Xml formatted output from the command, but it converts it to a custom PSObject that suites simple property searches and and simple export (CSV) well.
   The currently supported WEVTUTIL.EXE options are:
   '/{lf | logfile}:[true|false]'  -  dynamic,
   '/{q | query}:VALUE'  -  '-FilterXPath',
   '/{f | format}:[XML|Text|RenderedXml]'  -  dynamic (There are no plans to support "Text"),
   '/{c | count}:<n>'  -  '-MaxEvents'

   For more information about what WEVTUTIL supports for event queries, execute "WEVTUTIL QE /?"
.EXAMPLE
   WEVTUTIL.EXE QE Application /f:Xml | ConvertFrom-Wevtutil
.EXAMPLE
   wevtutil qe System /f:Xml > SystemEventsXml.txt
   Get-Content SystemEventsXml.txt | ConvertFrom-Wevtutil
#>
    param
    (
        [Parameter(Mandatory=$true,Position=0)]
        [string] $LogName,

        [Parameter(Position=1)]
        [string] $FilterXPath,

        [Parameter(Position=2)]
        [string] $FilterXPath2,

        [Parameter(Position=3)]
        [int] $MaxEvents
    )

    #region INTERNAL FUNCTION CONVERTFROM-WEVTUTIL
    <#
    .Synopsis
        Converts the XML formatted output of WEVTUTIL.EXE to objects.
    .DESCRIPTION
        Converts the XML formatted output of WEVTUTIL.EXE to objects.  Strips the 'RenderingInfo' element, which includes the message.
    .EXAMPLE
        WEVTUTIL.EXE QE Application /f:Xml | ConvertFrom-Wevtutil
    .EXAMPLE
        wevtutil qe System /f:Xml > SystemEventsXml.txt
        Get-Content SystemEventsXml.txt | ConvertFrom-Wevtutil
    #>
    function ConvertFrom-Wevtutil
    {
        param
        (
            [Parameter(Position=0,ValueFromPipeline=$true)]
            [string[]] $InputObject,

            [Parameter(Position=1)]
            [string] $FilterXPath,

            [string] $RootElement,

            [string] $ContainerLog
        )
    
        begin
        {
            # Remove any carrots around the RootElement parameter
            if ($RootElement)
            {
                $RootElement = $RootElement.Trim() -replace '<|>', ''
            }

            # Matches the default first element of a Windows Event xml string
            $eventxmlns = "^<Event\sxmlns='http://schemas.microsoft.com/win/2004/08/events/event'>"

            # Identifies the first processed object as such
            $firstobj = $true
        }
        process
        {
            # ignore any strings that don't start with the "Event" xml node
            if ($_ -match $eventxmlns)
            {
                if (($firstobj) -and ($RootElement -eq "Event"))
                {
                    $msg = "The '-RootElement' parameter should only be used to identify an element encapsulating ",
                            "the default `"<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>`", ",
                            "such as when using the '/e:' parameter of wevtutil.exe to specify the root element tags." -join ''
                    Write-Warning $msg
                }

                # create a simple, searchable xml string
                # 1. Remove the xml namespace attribute to simplify searching
                # 2. Remove the RenderingInfo element because its generally unnecessary (I may want to add this as an option)
                # 3. Remove double closing 'Event' tags if someone used '/e:Event' with wevtutil.exe and replace with the correct tag
                # ...Add correct closing tag if it doesn't precede the end of string.
                $eventxmlstr = $_ -replace $eventxmlns, '<Event>' -replace '\<RenderingInfo\s.*', '' -replace '(</Event></Event>$)|(?<!</Event>)$', '</Event>'

                if (-Not $FilterXPath)
                {
                    $FilterXPath = "/Event"
                }
            
                $node = ([xml]$eventxmlstr).SelectSingleNode($FilterXPath)

                if ($node)
                {
                    # populate custom object properties
                    $ht = [ordered]@{
                        TimeCreated = $node.System.TimeCreated.SystemTime
                        EventID = $node.System.EventID
                        MachineName = $node.System.Computer
                        LogName = $node.System.Channel
                        ContainerLog = $ContainerLog
                    }

                    # add dynamic properties from the "EventData" or "UserData" child elements
                    $i=1
                    $data = if ($node.EventData.Data) {$node.EventData.Data} else {$node.UserData.Data}
                    foreach ($dn in $data)
                    {
                        if ($dn.Name)
                        {
                            $ht["Data_$($dn.Name)"] = $dn.'#text'
                        }
                        else
                        {
                            # use two-digit numbers in property names when the "Data" node doesn't have a "Name" attribute
                            $ht["Data_{0:D2}" -f $i] = $dn.'#text'
                            $i++
                        }
                    }
                    Write-Output ([pscustomobject]$ht)
                }
            }
            elseif ($firstobj)
            {
                if ($_ -match '^Event\[\d+\]:$')
                {
                    $msg = "ConvertFrom-Wevtutil doesn't support text-formatted wevtutil.exe output ('/f:Text').  ",
                            "The only supported formats are '/f:Xml' or '/f:RenderedXml'." -join ''
                    Write-Error -ErrorAction Stop -Message $msg
                }
                elseif (-Not $RootElement)
                {
                    $msg = "Expected first element string to start with `"<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>`".  ",
                            "If the input has another root element, use the '-RootElement' parameter to identify it." -join ''
                    Write-Error -ErrorAction Stop -Message $msg
                }
                elseif ($_ -inotmatch "<$RootElement>")
                {
                    $msg = "Expected first element string to start with `"<$RootElement>`".  ",
                            "Verify that the root element name matches the '-RootElement' parameter." -join ''
                    Write-Error -ErrorAction Stop -Message $msg
                }
            }
            $firstobj = $false
        }
    }
    #endregion INTERNAL FUNCTION CONVERTFROM-WEVTUTIL

    $argslist = @("qe", $LogName, "/f:xml")

    if ($FilterXPath)
    {
        $argslist += "/q:$FilterXPath"
    }

    # The count parameter "/c:" of wevtutil.exe can't be used because the following filter may block some of the objects
    #if ($MaxEvents)
    #{
    #    $argslist += "/c:$MaxEvents"
    #}

    if (Test-Path $LogName)
    {
        $argslist += "/lf" # Switch tells wevtutil that the path parameter is a file path (.evtx) instead of an event log.
        # Store only the file name -- used for populating the ContainerLog property of the output objects
        $ContainerLog = Split-Path $LogName -Leaf
    }
    else
    {
        $ContainerLog = $LogName
    }

    if (-Not ($FilterXPath2))
    {
        $FilterXPath2 = "/Event"
    }

    # Initialize event counter to compare against the -MaxEvents parameter
    $count = 0
    #Wait-Debugger
    try
    {
        wevtutil.exe $argslist | ConvertFrom-Wevtutil -FilterXPath $FilterXPath2 | ForEach-Object {
            if ($count -lt $MaxEvents)
            {
                $_.ContainerLog = $ContainerLog  # set the ContainerLog property to the file name
                Write-Output $_
                $count ++  # increment event counter
            }
            else
            {
                continue
            }
        }
    }
    catch [System.Management.Automation.ContinueException]
    {
        if ($_.FullyQualifiedErrorId -ne "NativeCommandFailed")
        {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}


function Get-BulkWinEvent
{
<#
.SYNOPSIS
   Simplify searching of Windows event logs plus archived .evtx files.
.DESCRIPTION
   Simplify searching of Windows event logs plus archived .evtx files.  Attempts to speed up bulk searches from multiple remote hosts aReturns events as serialized objects.
.EXAMPLE
   Get-BulkWinEvent.ps1 -ComputerName DC1,DC2,DC3 -LogName Security -FilterXPath "*[System[EventID=4624]]" -ArchiveNewerThan (Get-Date).AddDays(-7)

   # Returns events matching event id 4624 from the Security log and all archived .evtx files created within the last 7 days.
.EXAMPLE
   Get-BulkWinEvent.ps1 -ComputerName WEC1 -LogName ForwardedEvents -FilterXPath "*[System[EventID=4625]]" -FilterXPath2 "*[EventData[Data[@Name='TargetUserName' and not(contains(text(), '$'))]]]"

   # Returns failed logon events that were forwarded to a Windows Event Collector.  Uses a second xpath filter to exclude computer accounts (ends with '$') before returning results.
   # The second XPath filter supports XPath 2.0, where as the first XPath parameter supports only a subset of XPath 1.0.
.NOTES
   Author: Swearbear
   Version: 2.0
   Release: 17 Oct 18
#>
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [Alias('Path')]
        [string] $LogName,

        [Alias('Cn')]
        [string[]] $ComputerName,

        [Parameter()]
        [string] $FilterXPath,

        [Parameter()]
        [string] $FilterXPath2,

        [datetime] $ArchiveNewerThan,

        [int] $MaxEvents
    )
    
    $RequiredModuleFunctions = @('Get-WevtutilEvent', 'Get-EventLogArchive', 'Copy-Hashtable', 'Resolve-EventLogPath', 'Test-LocalHost', 'ConvertTo-NetworkPath', 'Resolve-PathSafe', 'Get-ParsedDate', 'Test-InDateRange')
    $ExportedFunctions = Get-Module WinEvtHunt |select -exp ExportedFunctions
    $func = @{}
    if ($RequiredModuleFunctions)
    {
        foreach ($rmf in $RequiredModuleFunctions)
        {
            $func[$rmf] = $ExportedFunctions[$rmf].Definition
        }
    }
    $IsVerbose = $PSCmdlet.MyInvocation.BoundParameters.ContainsKey('Verbose')

    #Wait-Debugger
    $ScriptBlock = {

        # Set up variables for execution local or remote
        try
        {
            if ($using:LogName) {$LogName = $using:LogName}
            if ($using:FilterXPath) {$FilterXPath = $using:FilterXPath}
            if ($using:MaxEvents) {$MaxEvents = $using:MaxEvents}
            if ($using:FilterXPath2) {$FilterXPath2 = $using:FilterXPath2}
            if ($using:ArchiveNewerThan) {$ArchiveNewerThan = $using:ArchiveNewerThan}
            if ($using:ComputerName)
            {
                $remote = $true
                if ($using:RequiredModuleFunctions -and $using:func)
                {
                    foreach ($f in ($using:func).GetEnumerator())
                    {
                        New-Item -Path Function:\ -Name $f.Name -Value $f.Value > $null
                    }
                }
            }

        }
        catch [System.Management.Automation.RuntimeException]
        {
            # Catch the errors from evaluating $using variable when not remoting
        }

        if ($using:IsVerbose) { $VerbosePreference = "Continue" }
        #$DebugPreference = "Continue"
        #Wait-Debugger
        $count = 0
        # Start of search
        $st = Get-Date
        Write-Verbose ("Searching {0} log..." -f $LogName) 4>&1 #-ForegroundColor Yellow
        Get-WevtutilEvent $LogName $FilterXPath $FilterXPath2 $MaxEvents |ForEach-Object {$count++; $_}
        Write-Verbose "Elapsed: $((Get-Date) - $st)" 4>&1

        # if max event count has not been met
        if ($count -lt $MaxEvents)
        {
            if ($ArchiveNewerThan)
            {            
                $i = 0
                $archives = Get-EventLogArchive -LogName $LogName -NewerThan $ArchiveNewerThan

                foreach ($log in $archives)
                {
                    if ($count -lt $MaxEvents)
                    {
                        $i++
                        Write-Verbose "Searching archived log ($i/$($archives.count))... $($log.Path)" 4>&1 #-ForegroundColor Yellow
                        Get-WevtutilEvent $log.Path $FilterXPath $FilterXPath2 ($MaxEvents - $count) |ForEach-Object {$count++; $_}
                        Write-Verbose "Elapsed: $((Get-Date) - $st)" 4>&1
                    }
                    else
                    {
                        break  # break foreach ($log in $archives)
                    }
                }
            }
        }
    }

    # Execute the scriptblock locally or remotely per bound parameters
    if ($ComputerName)
    {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock | ForEach-Object {
            if ($_ -is [System.Management.Automation.VerboseRecord])
            {
                Write-Verbose $_.Message
            }
            else
            {
                $_
            }
        }
    }
    else { Invoke-Command -ScriptBlock $ScriptBlock }
}


function Get-WinEventData
{
<#
.SYNOPSIS
    Get custom event data from an event log record

.DESCRIPTION
    Get custom event data from an event log record

    Takes in Event Log entries from Get-WinEvent, converts each to XML, extracts all properties from Event.EventData.Data

    Notes:
        To avoid overwriting existing properties or skipping event data properties, we append 'EventData' to these extracted properties
        Some events store custom data in other XML nodes.  For example, AppLocker uses Event.UserData.RuleAndFileData

.PARAMETER Event
    One or more event.
    
    Accepts data from Get-WinEvent or any System.Diagnostics.Eventing.Reader.EventLogRecord object

.INPUTS
    System.Diagnostics.Eventing.Reader.EventLogRecord

.OUTPUTS
    System.Diagnostics.Eventing.Reader.EventLogRecord

.EXAMPLE
    Get-WinEvent -LogName system -max 1 | Get-WinEventData | Select -Property MachineName, TimeCreated, EventData*

    #  Simple example showing the computer an event was generated on, the time, and any custom event data

.EXAMPLE
    Get-WinEvent -ComputerName DomainController1 -FilterHashtable @{Logname='security';id=4740} -MaxEvents 10 | Get-WinEventData | Select TimeCreated, EventDataTargetUserName, EventDataTargetDomainName

    #  Find lockout events on a domain controller
    #    ideally you have log forwarding, audit collection services, or a product from a t-shirt company for this...

.NOTES
    Concept and most code borrowed from Ashley McGlone
        http://blogs.technet.com/b/ashleymcglone/archive/2013/08/28/powershell-get-winevent-xml-madness-getting-details-from-event-logs.aspx

.FUNCTIONALITY
    Computers
#>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, 
                    ValueFromPipeline=$true,
                    ValueFromPipelineByPropertyName=$true, 
                    ValueFromRemainingArguments=$false, 
                    Position=0 )]
        [System.Diagnostics.Eventing.Reader.EventLogRecord[]]
        $event
    )

    Process
    {
        #Loop through provided events
        foreach($entry in $event)
        {
            #Get the XML...
            $XML = [xml]$entry.ToXml()
        
            #Some events use other nodes, like 'UserData' on Applocker events...
            $XMLData = $null
            if( $XMLData = @( $XML.Event.EventData.Data ) )
            {
                For( $i=0; $i -lt $XMLData.count; $i++ )
                {
                    #We don't want to overwrite properties that might be on the original object, or in another event node.
                    Add-Member -InputObject $entry -MemberType NoteProperty -name "Data_$($XMLData[$i].name)" -Value $XMLData[$i].'#text' -Force
                }
            }
            elseif( $XMLData = @( $XML.Event.UserData.Data ) )
            {
                For( $i=0; $i -lt $XMLData.count; $i++ )
                {
                    #We don't want to overwrite properties that might be on the original object, or in another event node.
                    Add-Member -InputObject $entry -MemberType NoteProperty -name "Data_$($XMLData[$i].name)" -Value $XMLData[$i].'#text' -Force
                }
            }

            $entry
        }
    }
}