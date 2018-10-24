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

    #region INTERNAL FUNCTION GET-LOCALIPADDRESS
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
    #endregion INTERNAL FUNCTION GET-LOCALIPADDRESS
    
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