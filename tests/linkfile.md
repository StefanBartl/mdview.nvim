# Dies der Beginn der Linkfile `tests/linkfile.md`...

..für das Nvim-Plugin `mdview`.

---

## Table of content

- [Lorem Ipsum](#lorem-ipsum)
- [Codetesting](#codetesting)

---

## Lorem Ipsum

Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum.

<figure style="text-align:center;" id="#fig-nvimlogo">
  <img src="./ressources/neovim-logo.png" alt="Testfigure nvim-Logo">
  <figcaption>Testfigure nvim-Logo</figcaption>
</figure>

---

## Codetesting

**Inline:**

```sh
PS C:\configs> powershell
PS C:\configs>
```

_HTML:_\*

<figure id="#code-html">
  <pre><code class="">
local M = {}

---@param opts table|nil
---@return nil
function M.setup(opts)
opts = opts or {}
for k, v in pairs(opts) do
M.config[k] = v
end
end
</code>

</pre>

<figcaption><strong>Testcode via HTML</strong> </figcaption>
</figure>

---

----LINKFILE ENDE------------LINKFILE ENDE------------LINKFILE ENDE------------LINKFILE ENDE--------
