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

            [string] $ContainerLog,

            [hashtable] $hash
        )
    
        begin
        {
            Write-Verbose "CONVERTFROM-WEVTUTIL: BEGIN {}"
            $hash.scriptblock = {
                param([string]$obj)
                # ignore any strings that don't start with the "Event" xml node
                if ($obj -match $hash.eventxmlns)
                {
                    if (($hash.firstobj) -and ($RootElement -eq "Event"))
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
                    $eventxmlstr = $obj -replace $hash.eventxmlns, '<Event>' -replace '\<RenderingInfo\s.*', '' -replace '(</Event></Event>$)|(?<!</Event>)$', '</Event>'

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
                        [pscustomobject]$ht
                    }
                }
                elseif ($hash.firstobj)
                {
                    if ($obj -match '^Event\[\d+\]:$')
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
                    elseif ($obj -inotmatch "<$RootElement>")
                    {
                        $msg = "Expected first element string to start with `"<$RootElement>`".  ",
                                "Verify that the root element name matches the '-RootElement' parameter." -join ''
                        Write-Error -ErrorAction Stop -Message $msg
                    }
                }
                #$hash.firstobj = $false
            }


            # Remove any carrots around the RootElement parameter
            if ($RootElement)
            {
                $hash['rootelement'] = $RootElement.Trim() -replace '<|>', ''
            }
            $hash['eventxmlns'] = "^<Event\sxmlns='http://schemas.microsoft.com/win/2004/08/events/event'>"
            $hash['firstobj'] = $true
        
        }
        process
        {
            foreach ($obj in $InputObject)
            {
                if ($obj.StartsWith('<'))
                {
                    if ($hash.objcounter -ge $hash.maxevents)
                    {
                        break
                    }
                    #Write-Verbose -Message "CONVERTFROM-WEVTUTIL: PROCESS { InputObject = $obj }"
                    Write-Verbose -Message "CONVERTFROM-WEVTUTIL: PROCESS {}"
                    #Write-Host "test" -fore Yellow
                    #sleep -Milliseconds 10
                    #Create the powershell instance and supply the scriptblock with the other parameters 
                    $ps = [powershell]::Create().AddScript($hash.scriptblock).AddArgument($obj)
           
                    #Add the runspace into the powershell instance
                    $ps.RunspacePool = $hash.runspacepool
    
                    #Save the handle output when calling BeginInvoke() that will be used later to end the runspace
                    $temp = @{
                        PowerShell = $ps
                        Result = $ps.BeginInvoke()
                    }

                    $null = $hash.runspaces.Add($temp)
                    # Register event subscription in the host runspace
                    $null = $hash.Host.Runspace.Events.SubscribeEvent($ps, "InvocationStateChanged", $null, $temp, $null, $false, $false)

                    $hash.firstobj = $false
                }
            }
            if ($hash.objcounter -ge $hash.maxevents)
            {
                return 1
            }
        }
    }
    #endregion INTERNAL FUNCTION CONVERTFROM-WEVTUTIL

    $hash = [hashtable]::Synchronized(@{
        wevtutilargslist = @("qe", $LogName, "/f:xml")
        filterxpath2 = $FilterXPath2
        containerlog = $null
        objcounter = 0
        maxevents = $MaxEvents
        host = $Host
        runspaces = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
        runspacepool = $null
        pipecompleted = $false
        scriptblock = $null
    })

    #$MyInvocation.MyCommand |select *
    #return
    #$argslist = @("qe", $LogName, "/f:xml")

    if ($FilterXPath)
    {
        #$argslist += "/q:$FilterXPath"
        $hash.wevtutilargslist += "/q:$FilterXPath"
    }

    if (Test-Path $LogName)
    {
        #$argslist += "/lf" # Switch tells wevtutil that the path parameter is a file path (.evtx) instead of an event log.
        $hash.wevtutilargslist += "/lf"
        # Store only the file name -- used for populating the ContainerLog property of the output objects
        #$ContainerLog = Split-Path $LogName -Leaf
        $hash.containerlog = Split-Path $LogName -Leaf
    }
    else
    {
        #$ContainerLog = $LogName
        $hash.containerlog = $LogName
    }

    if (-Not ($FilterXPath2))
    {
        #$FilterXPath2 = "/Event"
        $hash.filterxpath2 = "/Event"
    }

    # if running against localhost
    if (($ComputerName.Count -eq 0) -or (Test-LocalHost -ComputerName $ComputerName[0] -NullOrEmptyAction $true))
    {
        # Create initial session state of runspaces
        $InitialSessionState = [system.management.automation.runspaces.initialsessionstate]::CreateDefault()
        #$InitialSessionState.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'InputObject', $InputObject))
        $InitialSessionState.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'hash', $hash, ''))
        $InitialSessionState.Commands.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList (Get-Command ConvertFrom-Wevtutil).Name, (Get-Command ConvertFrom-Wevtutil).Definition))
        # Create runspace pool
        $hash.runspacepool = [runspacefactory]::CreateRunspacePool(1, 6, $InitialSessionState, $Host)
        # Open the runspace pool for work
        $hash.runspacepool.Open()
        
        $sb = {
            try
            {
                wevtutil.exe $hash.wevtutilargslist | ConvertFrom-Wevtutil -hash ([ref]$hash) -FilterXPath $hash.filterxpath2 | ForEach-Object {
                    if ($_ -eq 1)
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
           
        $pipeline = [powershell]::Create().AddScript($sb)
        $pipeline.RunspacePool = $hash.runspacepool
        $temp = @{
            PowerShell = $pipeline
            Result = $pipeline.BeginInvoke()
        }

        $null = $hash.runspaces.Add($temp)
        # Register what should be the final event
        $null = $hash.Host.Runspace.Events.SubscribeEvent($pipeline, "InvocationStateChanged", $null, $temp, $null, $false, $false)

        ##############################
        #
        # Process events and runspaces
        #
        ##############################
        while ($hash.runspaces)
        {
            "runspaces count = {0}" -f $hash.runspaces.Count
            $events = Wait-Event -Timeout 1
            if ((-Not $hash.maxevents) -or ($hash.objcounter -lt $hash.maxevents))
            {
                foreach ($e in $events)
                {
                    $output = $e.MessageData.powershell.EndInvoke($e.MessageData.result)
                    $e.MessageData.powershell.Dispose()
                    $hash.runspaces.Remove($e.MessageData)
                    Remove-Event -EventIdentifier $e.EventIdentifier
                    if ($output) {
                        $output
                        $hash.objcounter++
                    }
                }
            }
            else
            {
                foreach ($e in $events)
                {
                    $e.MessageData.powershell.Dispose()
                }
                $events | Remove-Event
                $hash.runspaces.Clear()
                #$hash.runspaces = $null
                #foreach ($e in $events)
                #{
                #    $null = $e.MessageData.powershell.EndInvoke($e.MessageData.result)
                #    $e.MessageData.powershell.Dispose()
                #    $hash.runspaces.Remove($e.MessageData)
                #    Remove-Event -EventIdentifier $e.EventIdentifier
                #}
            }
        }

        # Final cleanup
        $hash.runspacepool.Dispose()
        Remove-Variable InitialSessionState
        Remove-Variable sb
        Remove-Variable pipeline
        Remove-Variable hash


    }
    #else
    #{
    #    try
    #    {
    #        #$fds = New-FunctionDefinitionSet -FunctionName $requiredfunctions
    #        $functiondefinitions = @{}
    #        foreach ($command in $requiredfunctions)
    #        {
    #            $c = Get-Command -Name $command
    #            $functiondefinitions[$c.Name] = $c.Definition
    #        }
    #        $functiondefinitions[$MyInvocation.MyCommand.Name] = $MyInvocation.MyCommand.Definition
    #
    #        Invoke-Command -ComputerName $ComputerName {
    #            $funcdefs = $using:functiondefinitions
    #            foreach ($fn in $funcdefs.Keys)
    #            {
    #                #Write-Host "Creating function $fn..."
    #                New-Item -Path Function:\ -Name $fn -Value $funcdefs[$fn] > $null
    #            }
    #            
    #            Get-WevtutilEvent @using:PSBoundParameters
    #        }
    #    }
    #    catch
    #    {
    #        $PSCmdlet.ThrowTerminatingError($_)
    #    }
    #    finally
    #    {
    #        #Remove-PSSession -Session $Session
    #    }
    #}
}