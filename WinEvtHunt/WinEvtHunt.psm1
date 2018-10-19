# Compares IPv4 addresses and hostnames against the local host
function Test-LocalHost {
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [string] $ComputerName
    )

    $query = 'SELECT IPEnabled,IPAddress FROM Win32_NetworkAdapterConfiguration WHERE IPEnabled = true'
    $IPv4Address = Get-CimInstance -Query $query |ForEach-Object {$_.IPAddress |Where-Object {$_ -match '(\d{1,3}\.){3}\d{1,3}'}}
    
    if ($null -ne $IPv4Address)
    {
        $ComputerName -match "$env:COMPUTERNAME|localhost|127.0.0.1|$($IPv4Address -join '|')"
    }
    else
    {
        Write-Error "Failed to identifying a local IPv4 addresses."
        $false
    }
}


function Get-ParsedDate {
<#
.Synopsis
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
.Notes
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


function Get-WinEventData {
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


function Get-EventLogArchive {
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
    [cmdletbinding(DefaultParameterSetName='LogName')]
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

    # ParameterSet 'LogName'
    if ($PSCmdlet.ParameterSetName -eq 'LogName')
    {
        $getWinEventParams = @{ListLog = $LogName}
        if ($PSBoundParameters.ContainsKey('ComputerName'))
        {
            # Get IPv4 addresses from the local computer for comparison with the $ComputerName parameter
            $IPv4Address = Get-WmiObject Win32_NetworkAdapterConfiguration |Where-Object {$_.IPEnabled -eq $true} |ForEach-Object {$_.IPAddress |Where-Object {$_ -match '(\d{1,3}\.){3}\d{1,3}'}}
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


function ConvertFrom-Wevtutil {
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
    param(
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [string[]] $InputObject,

        [Parameter(Position=1)]
        [string] $FilterXPath,

        [string] $RootElement
    )

    begin
    {
        # Remove any carrots around the RootElement parameter
        if ($RootElement)
        {
            $RootElement = $RootElement.Trim() -replace '<|>', ''
        }

        # Try to determine the containing log name by parsing this command invocation
        $cmdline = "(?<=wevtutil(?:\.exe)?\s+qe\s+)", # matches a wevtutil query command
                   "((?:`")(?<Path>[^`"]*)(?:`")",    # matches the third wevtutil query argument -- Path/LogName (double quoted)
                   "|(?:')(?<Path>[^`"]*)(?:')",      # '' (single quoted)
                   "|(?<Path>[^\s]*))",               # '' (unquoted)
                   "(?:\s[^$]*)(?<LF>/lf)" -join ''   # matches the '/lf' parameter
        if ($MyInvocation.Line -match $cmdline)
        {
            if ($Matches['LF'])
            {
                $ContainerLog = Split-Path (Resolve-Path $Matches['Path']).Path -Leaf
            }
            else
            {
                $ContainerLog = $Matches['Path']
            }
        }
        else
        {
            $ContainerLog = "-"
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


function Get-WevtutilEvent {
<#
.Synopsis
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
    param(
        [Parameter(Mandatory=$true,Position=0)]
        [string] $LogName,

        [Parameter(Position=1)]
        [string] $FilterXPath,

        [Parameter(Position=2)]
        [string] $FilterXPath2,

        [Parameter(Position=3)]
        [int] $MaxEvents
    )

    $argslist = @("qe", $LogName, "/f:xml")

    if ($FilterXPath)
    {
        $argslist += "/q:$FilterXPath"
    }

    if ($MaxEvents)
    {
        $argslist += "/c:$MaxEvents"
    }

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

    #Wait-Debugger
    try
    {
        wevtutil.exe $argslist | ConvertFrom-Wevtutil -FilterXPath $FilterXPath2
    }
    catch [System.Management.Automation.ContinueException]
    {
        if ($_.FullyQualifiedErrorId -ne "NativeCommandFailed")
        {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}


function Get-BulkWinEvent {
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
   Release: 17 Oct 18
#>
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Alias('Path')]
        [string] $LogName,

        [Alias('Cn')]
        [string[]] $ComputerName,

        [Parameter(HelpMessage="")]
        [string] $FilterXPath,

        [Parameter(HelpMessage="")]
        [string] $FilterXPath2,

        [datetime] $ArchiveNewerThan,

        [int] $MaxEvents
    )

    $ScriptBlock = {

        $st = Get-Date
        # Set up variables for execution local or remote
        try
        {
            if ($using:LogName) {$LogName = $using:LogName}
            if ($using:FilterXPath) {$FilterXPath = $using:FilterXPath}
            if ($using:MaxEvents) {$MaxEvents = $using:MaxEvents}
            if ($using:FilterXPath2) {$FilterXPath2 = $using:FilterXPath2}
            if ($using:ArchiveNewerThan) {$ArchiveNewerThan = $using:ArchiveNewerThan}
        }
        catch [System.Management.Automation.RuntimeException]
        {
            # Catch the errors from evaluating $using variable when not remoting
        }

        #$DebugPreference = "Continue"
        $count = 0
        Write-Host "Searching live log..." -ForegroundColor Yellow
        Get-WevtutilEvent $LogName $FilterXPath $FilterXPath2 $MaxEvents |ForEach-Object {$count++; $_}
        Write-Host "Elapsed: $((Get-Date) - $st)"

        if ($MaxEvents -le $count)
        {
            # if max event count has been met
            return
        }

        if ($ArchiveNewerThan) {
            $i = 0
            $archives = Get-EventLogArchive -LogName $LogName -NewerThan $ArchiveNewerThan

            foreach ($log in $archives) {
                $i++
                Write-Host "Searching archived log ($i/$($archives.count))... $log" -ForegroundColor Yellow
                Get-WevtutilEvent $LogName $FilterXPath $FilterXPath2 ($MaxEvents - $count) |ForEach-Object {$count++; $_}
                Write-Host "Elapsed: $((Get-Date) - $st)"
            }
        }
    }

    # Execute the scriptblock locally or remotely per bound parameters
    if ($ComputerName) { Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock }
    else { Invoke-Command -ScriptBlock $ScriptBlock }

}


function Test-InSubnet {
    param
    (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='Address')]
        [ipaddress[]]$Address,

        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ParameterSetName='RRInstance')]
        [ciminstance[]]$RRInstance,

        [Parameter(Mandatory=$true)]
        [string[]]$Network
    )

    begin
    {   
        $IPv4Regex = '(?:(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)\.){3}(?:0?0?\d|0?[1-9]\d|1\d\d|2[0-5][0-5]|2[0-4]\d)'

        #$network, [int]$subnetlen = $cidr.Split('/')

        $Subnets = @()
        foreach ($Subnet in $Network)
        {
            if (($Subnet -match "\A(?<IP>${IPv4Regex})\s*/\s*(?<NetworkLength>\d{1,2})\z") -or ("\A(?<IP>${IPv4Regex})[\s/]+(?<SubnetMask>${IPv4Regex})\z"))
            {
                #Wait-Debugger
                $a = [uint32[]]$Matches['IP'].Split('.')
                [uint32] $unetwork = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]
                if ($Matches['SubnetMask'])
                {
                    $mask = [uint32[]]$Matches['SubnetMask'].Split('.')
                }
                else
                {
                    $mask = (-bnot [uint32]0) -shl (32 - [int]$Matches['NetworkLength'])
                }
            }
            else
            {
                Write-Error "Invalid subnet notation." -ErrorAction Stop
                return
            }

            $Subnets += @{uNetwork=$unetwork;Mask=$mask}
        }
    }

    process
    {
        try
        {
            if ($PSCmdlet.ParameterSetName -eq 'RRInstance')
            {
                $ip = $_.RecordData.IPv4Address.IPAddressToString
            }
            else
            {
                $ip = $Address.IPAddressToString
            }

            $a = [uint32[]]$ip.split('.')
            [uint32] $uip = ($a[0] -shl 24) + ($a[1] -shl 16) + ($a[2] -shl 8) + $a[3]

            foreach ($sn in $Subnets)
            {
                if ($unetwork -eq ($mask -band $uip))
                {
                    Write-Output $_
                    break
                }
            }
        }
        catch
        {
            $_
            break
        }
    }
}


function Get-TerrainOU {
    param(
        [string]$SiteName,
        [string]$Server,
        [string]$ZoneName
    )

    $Site = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Sites |? Name -eq $SiteName

    $OUs = @()
    #$Site.Subnets
    #Wait-Debugger
    foreach ($net in $Site.Subnets) {
        Get-DnsServerResourceRecord -ComputerName $Server -ZoneName $ZoneName -RRType A |
            ? HostName -ne "@" | Test-InSubnet -Network $net.Name |Select -ExpandProperty HostName |
                Get-ADComputer -ea SilentlyContinue |% {$_.DistinguishedName.Split(',', 2) |Select -Last 1} |
                    Get-ADOrganizationalUnit |Select Name,DistinguishedName |
                        % {if ($OUs -notcontains $_.DistinguishedName) {$OUs += $_.DistinguishedName; $_.DistinguishedName}}
    }

}
