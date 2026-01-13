function Get-S3BucketSizeCurrentParallel {
    param([Parameter(Mandatory)][string] $BucketName, [int] $ThrottleLimit = 16)

    $region = (Get-S3BucketLocation -BucketName $BucketName); if (-not $region) { $region = "us-east-1" }

    $topPrefixes = Get-S3Object -BucketName $BucketName -Region $region.ToString() -Delimiter '/' -Select 'CommonPrefixes'
    if (-not $topPrefixes -or $topPrefixes.Count -eq 0) { $topPrefixes = @('') }

    $bag = [System.Collections.Concurrent.ConcurrentBag[long]]::new()

    # Prepare credentials (optional - uses env vars here)
    $awsCreds = @{
      AccessKey   = $env:AWS_ACCESS_KEY_ID
      SecretKey   = $env:AWS_SECRET_ACCESS_KEY
      SessionToken= $env:AWS_SESSION_TOKEN
    }

    $moduleName = 'AWS.Tools.S3'

    $topPrefixes | ForEach-Object -Parallel {
    param($prefix)

    # Import module once per runspace (fast after first import)
    if (-not (Get-Module -Name $using:moduleName)) {
        Import-Module $using:moduleName -ErrorAction Stop
    }

    $bag = $using:bag
    $objs = Get-S3Object -BucketName $using:BucketName -Region $using:region -Prefix $prefix
    $sum  = ($objs | Measure-Object -Property Size -Sum).Sum
    $bag.Add([long]$sum)
} -ThrottleLimit $ThrottleLimit

    $total = ([long[]]$bag.ToArray()) | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    [PSCustomObject]@{
      BucketName  = $BucketName; Region = $region
      Total_Bytes = $total; Total_GB = [Math]::Round($total / 1GB, 2)
      Throttle    = $ThrottleLimit
    }
    return $total
}
