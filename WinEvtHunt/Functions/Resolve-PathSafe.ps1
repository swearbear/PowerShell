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