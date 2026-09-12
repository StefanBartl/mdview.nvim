# Health check

```vim
:checkhealth mdview
```

reports six sections: the environment, the installed assets, the
configuration, the running session, the optional companions, and the
declared tools.

The asset section is the one to read after a failed first start — it says
whether the relay binary and the client bundle actually arrived.

See [installation.md](installation.md) for what the asset section is
verifying, and [companion-plugins.md](companion-plugins.md) for what the
optional-companions section is about.
