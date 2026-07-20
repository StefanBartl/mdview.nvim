<#
.SYNOPSIS
  Open a Markdown file in an mdview preview from the terminal, without tying the
  preview to the shell that started it.

.DESCRIPTION
  Runs Neovim headless against scripts/minimal_init.lua, so the preview gets the
  full plugin (live push, scroll sync) while loading none of your own config — a
  background process shouldn't depend on, or keep alive, plugins that have
  nothing to do with the preview.

  `nvim +MDView --background file.md` is NOT valid Neovim syntax (`+cmd` takes no
  trailing flags); this script is the supported spelling of that idea.

.PARAMETER File
  The Markdown file to preview.

.PARAMETER NoBrowser
  Start the relay but don't open a browser tab.

.PARAMETER Foreground
  Stay in the foreground (Ctrl-C to stop) instead of detaching.

.EXAMPLE
  .\mdview-bg.ps1 README.md

.EXAMPLE
  .\mdview-bg.ps1 -NoBrowser notes.md
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true, Position = 0)]
	[string]$File,

	[switch]$NoBrowser,
	[switch]$Foreground
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $env:MDVIEW_PATH) {
	$env:MDVIEW_PATH = Split-Path -Parent $scriptDir
}
$nvim = if ($env:NVIM) { $env:NVIM } else { 'nvim' }

if (-not (Get-Command $nvim -ErrorAction SilentlyContinue)) {
	Write-Error "mdview-bg: '$nvim' not found on PATH (set `$env:NVIM to override)"
	exit 1
}
if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
	Write-Error "mdview-bg: not a readable file: $File"
	exit 1
}

$init = Join-Path $env:MDVIEW_PATH 'scripts/minimal_init.lua'
if (-not (Test-Path -LiteralPath $init -PathType Leaf)) {
	Write-Error "mdview-bg: minimal init not found at $init — set `$env:MDVIEW_PATH to your mdview.nvim checkout"
	exit 1
}

if ($NoBrowser) { $env:MDVIEW_NO_BROWSER = '1' }

# Absolute path: the detached process may not share this shell's location.
$target = (Resolve-Path -LiteralPath $File).Path

$nvimArgs = @('--headless', '-u', $init, '-c', 'MDView start', $target)

if ($Foreground) {
	& $nvim @nvimArgs
	exit $LASTEXITCODE
}

# -WindowStyle Hidden keeps a console window from flashing up; the process is
# not a child of this shell's job object, so closing the terminal leaves it running.
$proc = Start-Process -FilePath $nvim -ArgumentList $nvimArgs -WindowStyle Hidden -PassThru

Write-Host "mdview: previewing $(Split-Path -Leaf $target) in the background (pid $($proc.Id))"
Write-Host "mdview: close the preview tab to stop it, or: Stop-Process -Id $($proc.Id)"
