<#
.SYNOPSIS
  Open a Markdown file in a standalone mdview preview from the terminal, with no
  long-lived Neovim in the chain.

.DESCRIPTION
  Runs a throwaway headless Neovim just long enough to launch `:MDView
  standalone` — which spawns the relay watching the file on disk and detaches it
  — then quits. The relay keeps running independently, following the file, until
  you kill it or close the preview. Nothing here stays resident.

  `nvim +MDView --background file.md` is NOT valid Neovim syntax (`+cmd` takes no
  trailing flags); this script is the supported spelling of that idea.

  Standalone needs a relay binary with --watch support (v0.3.0+). Until a release
  ships, set $env:MDVIEW_STANDALONE_BIN to a locally built one, e.g.
  E:/repos/mdview.nvim/native/server/mdview-server.exe

.PARAMETER File
  The Markdown file to preview.

.PARAMETER NoBrowser
  Start the relay but don't open a browser tab (its URL is printed instead).

.EXAMPLE
  .\mdview-bg.ps1 README.md

.EXAMPLE
  .\mdview-bg.ps1 -NoBrowser notes.md
#>
[CmdletBinding()]
param(
	[Parameter(Mandatory = $true, Position = 0)]
	[string]$File,

	[switch]$NoBrowser
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

# Absolute path: the relay resolves its room key from it, and its cwd differs
# from this shell's.
$target = (Resolve-Path -LiteralPath $File).Path

$cmd = "MDView standalone $target"
if ($NoBrowser) { $cmd = "$cmd --no-browser" }

# The Neovim launcher is short-lived (it spawns the detached relay and quits),
# so it runs in the foreground — its output carries the standalone notification,
# including the preview URL under -NoBrowser.
& $nvim --headless -u $init -c $cmd -c 'qa!'
