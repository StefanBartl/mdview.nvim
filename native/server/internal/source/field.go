package source

import (
	"regexp"
	"strings"
)

// Raw HTML in Markdown carries no source position (unlike GFM task lists), so
// syncable text fields can't be located by line the way checkboxes are. Instead
// they're located by their `name` attribute: SetFieldValue scans the source for
// the <input>/<textarea> whose name matches and rewrites just its value in
// place. The document is otherwise preserved byte-for-byte.
//
// The tag is read attribute by attribute (a quoted value may hold a `>`), and a
// field is the tag whose attribute called exactly `name` has the value asked
// for: `data-name="x"` and `username="x"` are other attributes, and `value='x'`
// is read like `value="x"`.

// escapeAttr escapes a value for an HTML double-quoted attribute so it round-
// trips through render+sanitize and can't break out of the attribute.
func escapeAttr(v string) string {
	v = strings.ReplaceAll(v, "&", "&amp;")
	v = strings.ReplaceAll(v, "<", "&lt;")
	v = strings.ReplaceAll(v, ">", "&gt;")
	v = strings.ReplaceAll(v, `"`, "&quot;")
	return v
}

// escapeText escapes a value for use as element text content (a <textarea>
// body). No quote escaping needed there, but `<`/`&` must be escaped so the
// content can't inject a tag (e.g. a stray "</textarea>").
func escapeText(v string) string {
	v = strings.ReplaceAll(v, "&", "&amp;")
	v = strings.ReplaceAll(v, "<", "&lt;")
	v = strings.ReplaceAll(v, ">", "&gt;")
	return v
}

// An opening tag, read so that a quoted attribute value may contain `>`; and
// one attribute (leading whitespace, name, optional value).
var (
	inputTagRe     = regexp.MustCompile(`<input\b(?:[^>"']|"[^"]*"|'[^']*')*>`)
	textareaOpenRe = regexp.MustCompile(`<textarea\b(?:[^>"']|"[^"]*"|'[^']*')*>`)
	attributeRe    = regexp.MustCompile("\\s([^\\s\"'<>/=]+)(?:\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s\"'<>=`]+)?)?")
)

// attribute is one attribute of a tag: where it sits (from its name to the end
// of its value) and what it says.
type attribute struct {
	name       string
	value      string
	start, end int
}

// attributesOf lists the attributes of `tag`, reading after its first `from`
// bytes ("<input", "<textarea").
func attributesOf(tag string, from int) []attribute {
	var out []attribute
	for _, m := range attributeRe.FindAllStringSubmatchIndex(tag[from:], -1) {
		a := attribute{name: strings.ToLower(tag[from+m[2] : from+m[3]]), start: from + m[2], end: from + m[1]}
		if m[4] >= 0 {
			raw := tag[from+m[4] : from+m[5]]
			// Only the quotes around the value, not quotes inside it.
			if len(raw) >= 2 && (raw[0] == '"' || raw[0] == '\'') && raw[len(raw)-1] == raw[0] {
				raw = raw[1 : len(raw)-1]
			}
			a.value = raw
		}
		out = append(out, a)
	}
	return out
}

// isTagStart reports whether the tag at `loc` really is `<name` followed by
// white space, `/` or `>` (and not a custom element such as <input-x>).
func isTagStart(s string, loc []int, open string) bool {
	if loc[0]+len(open) >= loc[1] {
		return true
	}
	switch s[loc[0]+len(open)] {
	case ' ', '\t', '\r', '\n', '\f', '/', '>':
		return true
	}
	return false
}

// tagHasName reports whether the attribute called `name` of `tag` says `want`.
func tagHasName(tag string, from int, want string) bool {
	for _, a := range attributesOf(tag, from) {
		if a.name == "name" {
			return a.value == want
		}
	}
	return false
}

// SetFieldValue writes `value` into the field named `name` in the file at
// `path`: a <textarea name="…">…</textarea> body, or an <input name="…">'s
// `value` attribute (replaced if present, inserted otherwise). It is a no-op
// (nil error) when no such field exists — a re-render can race an edit, and
// declining is safer than guessing.
func SetFieldValue(path, name, value string) error {
	writeMu.Lock()
	defer writeMu.Unlock()

	target, content, perm, err := loadWatched(path)
	if err != nil {
		return err
	}
	s := string(content)

	// textarea first — it has an explicit close, so its body is unambiguous.
	for _, loc := range textareaOpenRe.FindAllStringIndex(s, -1) {
		if !isTagStart(s, loc, "<textarea") || !tagHasName(s[loc[0]:loc[1]], len("<textarea"), name) {
			continue
		}
		closeAt := strings.Index(s[loc[1]:], "</textarea>")
		if closeAt < 0 {
			continue
		}
		rebuilt := s[:loc[1]] + escapeText(value) + s[loc[1]+closeAt:]
		return writeThrough(target, []byte(rebuilt), content, perm)
	}

	// input: locate the tag by name, then set its value attribute.
	for _, loc := range inputTagRe.FindAllStringIndex(s, -1) {
		tag := s[loc[0]:loc[1]]
		if !isTagStart(s, loc, "<input") || !tagHasName(tag, len("<input"), name) {
			continue
		}
		newTag := setInputValue(tag, value)
		return writeThrough(target, []byte(s[:loc[0]]+newTag+s[loc[1]:]), content, perm)
	}

	return nil // no field with that name; decline
}

// setInputValue returns `tag` with its value attribute set to `value`
// (HTML-escaped): replaced in place if it already has one, otherwise inserted
// just before the tag's closing `>` (or `/>`).
func setInputValue(tag, value string) string {
	repl := `value="` + escapeAttr(value) + `"`
	for _, a := range attributesOf(tag, len("<input")) {
		if a.name == "value" {
			return tag[:a.start] + repl + tag[a.end:]
		}
	}
	// Insert before the closing bracket, preserving a self-closing "/>".
	// TrimRight so an existing space before "/>" doesn't become a double space.
	if strings.HasSuffix(tag, "/>") {
		return strings.TrimRight(tag[:len(tag)-2], " \t\r\n\f") + " " + repl + "/>"
	}
	return strings.TrimRight(tag[:len(tag)-1], " \t\r\n\f") + " " + repl + ">"
}
