# Quickstart

Open a Markdown file and start a session — the first run downloads the relay
binary and the client bundle, and nothing else is needed:

```vim
:MDView start
```

Then, once the tab is open:

```vim
:MDView cursor        " show the Neovim cursor in the preview
:MDView theme         " switch the preview theme
:MDView overlay       " mount a floating table of contents
:MDView pin           " hold the preview on this document
:MDView standalone    " hand it to the relay's own file watcher; survives :qa
:MDView stop
```

Verify your setup any time with:

```vim
:checkhealth mdview
```

See [commands.md](commands.md) for the full subcommand reference,
[configuration.md](configuration.md) for every `setup()` option, and
[health.md](health.md) for what the health check reports.
