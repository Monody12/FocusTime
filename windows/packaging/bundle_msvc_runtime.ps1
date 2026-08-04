param(
  [Parameter(Mandatory = $true)]
  [string]$Destination
)

$ErrorActionPreference = 'Stop'

function Get-VcRuntimeDirectory {
  $candidates = @()

  if ($env:VCToolsRedistDir) {
    $candidates += Join-Path $env:VCToolsRedistDir 'x64\Microsoft.VC143.CRT'
  }

  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (Test-Path -LiteralPath $vswhere) {
    $installationPath = & $vswhere `
      -latest `
      -products '*' `
      -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
      -property installationPath

    if ($installationPath) {
      $redistRoot = Join-Path $installationPath 'VC\Redist\MSVC'
      if (Test-Path -LiteralPath $redistRoot) {
        $candidates += Get-ChildItem -LiteralPath $redistRoot -Directory |
          Sort-Object Name -Descending |
          ForEach-Object {
            Join-Path $_.FullName 'x64\Microsoft.VC143.CRT'
          }
      }
    }
  }

  return $candidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
}

$runtimeDirectory = Get-VcRuntimeDirectory
if (-not $runtimeDirectory) {
  throw 'Unable to locate the Visual C++ x64 redistributable runtime directory.'
}

New-Item -ItemType Directory -Path $Destination -Force | Out-Null
$runtimeFiles = Get-ChildItem -LiteralPath $runtimeDirectory -Filter '*.dll' -File
if (-not $runtimeFiles) {
  throw "No Visual C++ runtime DLLs were found in $runtimeDirectory."
}

$runtimeFiles | Copy-Item -Destination $Destination -Force

$requiredFiles = @('msvcp140.dll', 'vcruntime140.dll')
foreach ($requiredFile in $requiredFiles) {
  $packagedFile = Join-Path $Destination $requiredFile
  if (-not (Test-Path -LiteralPath $packagedFile)) {
    throw "Required Visual C++ runtime file was not packaged: $requiredFile"
  }
}

Write-Host "Bundled $($runtimeFiles.Count) Visual C++ runtime DLLs from $runtimeDirectory."
