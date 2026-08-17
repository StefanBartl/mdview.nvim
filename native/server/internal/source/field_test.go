package source

import "testing"

func TestSetFieldValue_InsertsInputValue(t *testing.T) {
	path := writeTemp(t, `# T

<input type="text" name="title">
`)
	if err := SetFieldValue(path, "title", "Hello"); err != nil {
		t.Fatal(err)
	}
	want := `# T

<input type="text" name="title" value="Hello">
`
	if got := read(t, path); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_ReplacesExistingInputValue(t *testing.T) {
	path := writeTemp(t, `<input name="a" type="text" value="old">`)
	if err := SetFieldValue(path, "a", "new"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), `<input name="a" type="text" value="new">`; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_SelfClosingInput(t *testing.T) {
	path := writeTemp(t, `<input type="text" name="x" />`)
	if err := SetFieldValue(path, "x", "v"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), `<input type="text" name="x" value="v"/>`; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_TextareaBody(t *testing.T) {
	path := writeTemp(t, "<textarea name=\"notes\">old body</textarea>\n")
	if err := SetFieldValue(path, "notes", "new body"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "<textarea name=\"notes\">new body</textarea>\n"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_MultilineTextarea(t *testing.T) {
	path := writeTemp(t, "<textarea name=\"n\">a\nb</textarea>")
	if err := SetFieldValue(path, "n", "one\ntwo\nthree"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), "<textarea name=\"n\">one\ntwo\nthree</textarea>"; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_EscapesHTML(t *testing.T) {
	path := writeTemp(t, `<input name="a" type="text">`)
	if err := SetFieldValue(path, "a", `<b> & "q"`); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), `<input name="a" type="text" value="&lt;b&gt; &amp; &quot;q&quot;">`; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_EscapesTextareaContent(t *testing.T) {
	path := writeTemp(t, `<textarea name="a"></textarea>`)
	if err := SetFieldValue(path, "a", "</textarea><script>"); err != nil {
		t.Fatal(err)
	}
	// The injected close/script is escaped, so it can't break out of the field.
	if got, want := read(t, path), `<textarea name="a">&lt;/textarea&gt;&lt;script&gt;</textarea>`; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_ValueWithDollar(t *testing.T) {
	// A `$` in the value must not be treated as a regex capture reference.
	path := writeTemp(t, `<input name="a" type="text">`)
	if err := SetFieldValue(path, "a", "$1 costs $5"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), `<input name="a" type="text" value="$1 costs $5">`; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_DeclinesUnknownName(t *testing.T) {
	path := writeTemp(t, `<input name="a" type="text">`)
	if err := SetFieldValue(path, "nope", "x"); err != nil {
		t.Fatal(err)
	}
	if read(t, path) != `<input name="a" type="text">` {
		t.Fatal("content changed for an unknown field name")
	}
}

func TestSetFieldValue_LeavesOtherFieldsUntouched(t *testing.T) {
	path := writeTemp(t, `<input name="a" type="text"><input name="b" type="text">`)
	if err := SetFieldValue(path, "b", "B"); err != nil {
		t.Fatal(err)
	}
	if got, want := read(t, path), `<input name="a" type="text"><input name="b" type="text" value="B">`; got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}
