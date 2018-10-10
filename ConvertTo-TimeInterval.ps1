function ConvertTo-TimeInterval
{
<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   ConvertTo-TimeInterval (Get-Date) 
.EXAMPLE
   $Events = Get-EventLog -LogName Security
   $TS = New-TimeSpan -Minutes 15
   $Events | Group-Object {ConvertTo-TimeInterval $_.TimeGenerated -TimeSpan $TS}
.EXAMPLE
   Another example of how to use this cmdlet
.NOTES
   Adapted logic from https://mjolinor.wordpress.com/2012/01/22/counting-and-grouping-log-entries-by-arbitrary-time-spans-with-powershell/
#>

    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName='TimeSpan')]
        [Alias('interval','span','ti','ts')]
        [timespan] $TimeSpan, #9000000000, # 15 min default

        [Parameter(ParameterSetName='Units')]
        [AllowNull()]
        [int] $Days,

        [Parameter(ParameterSetName='Units')]
        [AllowNull()]
        [Alias('hrs')]
        [int] $Hours,

        [Parameter(ParameterSetName='Units')]
        [AllowNull()]
        [int] $Minutes,

        [Parameter(ParameterSetName='Units')]
        [AllowNull()]
        [int] $Seconds,

        [Parameter(ParameterSetName='Units')]
        [AllowNull()]
        [Alias('ms')]
        [int] $Milliseconds,

        [Parameter(Position=0,
                   ValueFromPipeline=$true)]
        [datetime[]] $InputObject,

        [Parameter()]
        [datetime] $StartDate
    )

    begin
    {
        if ('Units' -eq $PSCmdlet.ParameterSetName)
        {
            $TimeSpan = [timespan]::new($Days, $Hours, $Minutes, $Seconds, $Milliseconds)
        }
        elseif ('TimeSpan' -ne $PSCmdlet.ParameterSetName)
        {
            $erMsg = "TimeSpan not specified."
            $excpt = New-Object System.Management.Automation.ParameterBindingException $erMsg
            Write-Error -Exception $excpt -ErrorAction Stop
        }
        $SpanTicks = $TimeSpan.Ticks
        $TimeBase = [DateTime]::MinValue
    }

    process
    {
        foreach ($obj in $InputObject)
        {
            $Time_Slice = [int][math]::truncate($obj.Ticks / $SpanTicks)
            Write-OutPut ($TimeBase + [TimeSpan]::FromTicks($SpanTicks * $Time_Slice))
        }
    }
}
