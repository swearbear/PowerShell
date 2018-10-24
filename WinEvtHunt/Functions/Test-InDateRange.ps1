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