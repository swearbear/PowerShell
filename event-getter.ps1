param(
    [string] $LogName,
    [string[]] $ComputerName,
    [string] $XPath,
    [datetime] $ArchiveNewerThan
)

$ScriptBlock = {
    Function Get-WinEventData {
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

    if ($using:XPath) {
        if ($using:ArchiveNewerThan) {
            $i = 0
            Write-Host "Searching live log..." -ForegroundColor Yellow
            Get-WinEvent -LogName $using:LogName -FilterXPath $using:XPath |
                Get-WinEventData |select TimeCreated,MachineName,LogName,ContainerLog,Data_*
            $archives = Get-EventLogArchive -LogName $using:LogName -NewerThan $using:ArchiveNewerThan
            foreach ($log in $archives) {
                $i++
                Write-Host "Searching archived log ($i/$($archives.count))... $_" -ForegroundColor Yellow
                Get-WinEvent -Path $log -FilterXPath $using:XPath |
                    Get-WinEventData |select TimeCreated,MachineName,LogName,ContainerLog,Data_*
            }
        }
        else {
            Get-WinEvent -LogName $using:LogName -FilterXPath $using:XPath |
                Get-WinEventData |select TimeCreated,MachineName,LogName,ContainerLog,Data_*
        }
    }
    else {
        if ($using:ArchiveNewerThan) {
            $i = 0
            Write-Host "Searching live log..." -ForegroundColor Yellow
            Get-WinEvent -LogName $using:LogName |
                Get-WinEventData |select TimeCreated,MachineName,LogName,ContainerLog,Data_*
            $archives = Get-EventLogArchive -LogName $using:LogName -NewerThan $using:ArchiveNewerThan
            foreach ($log in $archives) {
                $i++
                Write-Host "Searching archived log ($i/$($archives.count))... $_" -ForegroundColor Yellow
                Get-WinEvent -Path $log |
                    Get-WinEventData |select TimeCreated,MachineName,LogName,ContainerLog,Data_*
            }
        }
        else {
            Get-WinEvent -LogName $using:LogName |
                Get-WinEventData |select TimeCreated,MachineName,LogName,ContainerLog,Data_*
        }
    }
}

Invoke-Command -ComputerName $ComputerName -ScriptBlock $ScriptBlock
