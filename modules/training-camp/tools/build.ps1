param(
    [Parameter(Mandatory=$true)][string]$Engine,
    [ValidateSet('Windows','Linux')][string]$Platform='Windows',
    [string]$OutputFolder=(Join-Path $PSScriptRoot '../builds')
)
$ErrorActionPreference='Stop'
$projectPath=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../project'))
$outputPath=[IO.Path]::GetFullPath($OutputFolder)
if (!(Test-Path -LiteralPath $Engine)) { throw 'Godot executable missing' }
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$env:UPGRADE_VERIFY_DIR=Join-Path $outputPath 'verification'
& $Engine --headless --path $projectPath --editor --import --quit
if ($LASTEXITCODE -ne 0) { throw 'Import failed' }
foreach ($test in @('test_upgrade','test_presentation_upgrade','threaded_upgrade')) {
    & $Engine --headless --path $projectPath --script "res://tests/$test.gd"
    if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
$name=if ($Platform -eq 'Windows') { 'CanghuoTraining.exe' } else { 'CanghuoTraining.x86_64' }
$target=Join-Path $outputPath $name
& $Engine --headless --path $projectPath --export-release "Training $Platform" $target
if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $target)) { throw 'Export failed' }
Get-FileHash -LiteralPath $target -Algorithm SHA256
