function New-FunctionDefinitionSet
{
    param
    (
        [string[]] $FunctionName
    )

    $fd = @{}
    if ($FunctionName.Length -gt 0)
    {
        foreach ($command in $FunctionName)
        {
            $c = Get-Command -Name $command
            $fd[$c.Name] = $c.Definition
        }
    }
    return $fd
}