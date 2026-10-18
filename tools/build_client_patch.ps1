param(
    [ValidatePattern('^[A-Za-z]{4}$')]
    [string]$Locale = 'ruRU',
    [string]$DbcArchive,
    [string]$OutputPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$patchSource = Join-Path $repo 'data\client\patch'
$dockerfile = Join-Path $patchSource 'Dockerfile'

if (-not $DbcArchive) {
    $DbcArchive = Join-Path $repo 'optional\client-patch-dbc.7z'
} elseif (-not [System.IO.Path]::IsPathRooted($DbcArchive)) {
    $DbcArchive = Join-Path $repo $DbcArchive
}
$dbcArchiveFull = (Resolve-Path -LiteralPath $DbcArchive).Path
if (-not $dbcArchiveFull.StartsWith(
        $repo.TrimEnd('\') + '\',
        [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'DBC archive must be stored inside this repository so Docker can read it.'
}
$dbcArchiveRelative = [System.IO.Path]::GetRelativePath($repo, $dbcArchiveFull)
$dbcArchiveContainer = '/work/' + $dbcArchiveRelative.Replace('\', '/')

if (-not $OutputPath) {
    $OutputPath = Join-Path $repo "data\client\patch\out\patch-$Locale-Z.MPQ"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $repo $OutputPath
}
$outputDir = [System.IO.Path]::GetFullPath((Split-Path -Parent $OutputPath))
$OutputPath = Join-Path $outputDir (Split-Path -Leaf $OutputPath)
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
if ((Test-Path -LiteralPath $OutputPath -PathType Leaf) -and -not $Force) {
    throw "Output already exists: $OutputPath. Use -Force to replace it after a successful build."
}

$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) { throw 'Docker is required to build the client patch.' }

$image = 'iptalents-client-patch:local'
& docker build -q -t $image -f $dockerfile $patchSource
if ($LASTEXITCODE -ne 0) { throw 'Client patch Docker image build failed.' }

$repoMount = $repo.Replace('\', '/')
$outputMount = $outputDir.Replace('\', '/')
$outputName = [System.IO.Path]::GetFileName($OutputPath)
& docker run --rm `
    --mount "type=bind,source=$repoMount,destination=/work,readonly" `
    --mount "type=bind,source=$outputMount,destination=/output" `
    --env "PATCH_LOCALE=$Locale" `
    --env "PATCH_DBC_ARCHIVE=$dbcArchiveContainer" `
    --env "PATCH_OUTPUT_NAME=$outputName" `
    $image
if ($LASTEXITCODE -ne 0) { throw 'Client patch build container failed.' }

if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw "Docker finished without creating the expected patch: $OutputPath"
}
$sha = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "Built locale-specific client patch: $OutputPath"
Write-Host "DBC source archive: $dbcArchiveFull"
Write-Host "SHA256: $sha"
