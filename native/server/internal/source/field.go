package source

import (
	"os"
	"regexp"
	"strings"
)

// Raw HTML in Markdown carries no source position (unlike GFM task lists), so
// syncable text fields can't be located by line the way checkboxes are. Instead
// they're located by their `name` attribute: SetFieldValue scans the source for
// the <input>/<textarea> whose name matches and rewrites just its value in
// place. The document is otherwise preserved byte-for-byte.
//
// Only double-quoted `name="…"` is recognized — that's the form the docs tell
// authors to write, and it keeps the matching unambiguous.

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

// SetFieldValue writes `value` into the field named `name` in the file at
// `path`: a <textarea name="…">…</textarea> body, or an <input name="…">'s
// `value` attribute (replaced if present, inserted otherwise). It is a no-op
// (nil error) when no such field exists — a re-render can race an edit, and
// declining is safer than guessing.
func SetFieldValue(path, name, value string) error {
	content, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	s := string(content)
	q := regexp.QuoteMeta(name)

	// textarea first — it has an explicit close, so its body is unambiguous.
	taRe := regexp.MustCompile(`(?s)<textarea\b[^>]*\bname="` + q + `"[^>]*>.*?</textarea>`)
	if loc := taRe.FindStringIndex(s); loc != nil {
		whole := s[loc[0]:loc[1]]
		openEnd := strings.IndexByte(whole, '>') + 1
		closeStart := strings.LastIndex(whole, "</textarea>")
		rebuilt := whole[:openEnd] + escapeText(value) + whole[closeStart:]
		return os.WriteFile(path, []byte(s[:loc[0]]+rebuilt+s[loc[1]:]), 0o644)
	}

	// input: locate the tag by name, then set its value attribute.
	inRe := regexp.MustCompile(`<input\b[^>]*\bname="` + q + `"[^>]*>`)
	if loc := inRe.FindStringIndex(s); loc != nil {
		tag := s[loc[0]:loc[1]]
		newTag := setInputValue(tag, value)
		return os.WriteFile(path, []byte(s[:loc[0]]+newTag+s[loc[1]:]), 0o644)
	}

	return nil // no field with that name; decline
}

var inputValueAttr = regexp.MustCompile(`\bvalue="[^"]*"`)

// setInputValue returns `tag` with its value attribute set to `value`
// (HTML-escaped): replaced in place if it already has one, otherwise inserted
// just before the tag's closing `>` (or `/>`).
func setInputValue(tag, value string) string {
	repl := `value="` + escapeAttr(value) + `"`
	if inputValueAttr.MatchString(tag) {
		// ReplaceAllStringFunc, not ReplaceAllString: the value may contain `$`,
		// which the template form would treat as a capture reference.
		return inputValueAttr.ReplaceAllStringFunc(tag, func(string) string { return repl })
	}
	// Insert before the closing bracket, preserving a self-closing "/>".
	// TrimRight so an existing space before "/>" doesn't become a double space.
	if strings.HasSuffix(tag, "/>") {
		return strings.TrimRight(tag[:len(tag)-2], " ") + " " + repl + "/>"
	}
	return strings.TrimRight(tag[:len(tag)-1], " ") + " " + repl + ">"
}
