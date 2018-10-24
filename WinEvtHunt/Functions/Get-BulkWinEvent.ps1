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