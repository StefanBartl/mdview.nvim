# Fixture for the any_file checklist in TESTS/CHECK.md.
#
# The point of this file is case 3: every `#` below is a COMMENT marker, not
# an ATX heading. core/breadcrumbs.lua only scans for headings when the
# filetype is markdown/md; here every breadcrumb entry must read "(top)".
#
# The three lines that follow are deliberately shaped like headings — they
# are the ones that would show up as fake outline entries if the filetype
# gate ever stopped working.

# Setup
# ## Helper functions
# ### Deeply nested section


def double(n):
    """Return n doubled."""
    return n * 2


# Another comment that looks like a heading:
# Configuration
DEFAULTS = {
    "verbose": False,
    "retries": 3,
}


def join(items):
    """Join items with a comma."""
    return ", ".join(items)


# Padding, so the buffer is taller than one screen and case 2 has room.
PADDING = [
    "line 01", "line 02", "line 03", "line 04", "line 05",
    "line 06", "line 07", "line 08", "line 09", "line 10",
    "line 11", "line 12", "line 13", "line 14", "line 15",
    "line 16", "line 17", "line 18", "line 19", "line 20",
    "line 21", "line 22", "line 23", "line 24", "line 25",
    "line 26", "line 27", "line 28", "line 29", "line 30",
]

# The last line of the file.
