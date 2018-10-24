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
        [Parameter(Mandatory=$true)]
        [Alias('Path')]
        [string] $LogName,

        [Parameter()]
        [string] $FilterXPath,

        [Parameter()]
        [string] $FilterXPath2,

        [Alias('Cn')]
        [string[]] $ComputerName,

        [Parameter()]
        [int] $MaxEvents,

        [datetime] $Start,

        [datetime] $End,

        [switch] $AsJob,

        [switch] $Archive,

        [string] $ArchiveHint
    )

    $requiredfunctions = @('WinEvtHunt\Test-LocalHost')

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
                        PSTypeName = $node.System.Provider.Name + "." + $node.System.EventID
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

    #$MyInvocation.MyCommand |select *
    #return
    $argslist = @("qe", $LogName, "/f:xml")

    if ($FilterXPath)
    {
        $argslist += "/q:$FilterXPath"
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

    # if running against localhost
    if (($ComputerName.Count -eq 0) -or (Test-LocalHost -ComputerName $ComputerName[0] -NullOrEmptyAction $true))
    {
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
    else
    {
        try
        {
            $functiondefinitions = @{}
            foreach ($command in $requiredfunctions)
            {
                $c = Get-Command -Name $command
                $functiondefinitions[$c.Name] = $c.Definition
            }
            $functiondefinitions[$MyInvocation.MyCommand.Name] = $MyInvocation.MyCommand.Definition

            Invoke-Command -ComputerName $ComputerName {
                $funcdefs = $using:functiondefinitions
                foreach ($fn in $funcdefs.Keys)
                {
                    #Write-Host "Creating function $fn..."
                    New-Item -Path Function:\ -Name $fn -Value $funcdefs[$fn] > $null
                }
                
                Get-WevtutilEvent @using:PSBoundParameters
            }
        }
        catch
        {
            $PSCmdlet.ThrowTerminatingError($_)
        }
        finally
        {
            #Remove-PSSession -Session $Session
        }
    }
}