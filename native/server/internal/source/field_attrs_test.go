package source

import "testing"

// Review round 3, item 23: the value attribute is read as an attribute, not
// searched for as text.

func TestSetFieldValue_DataValueIsAnotherAttribute(t *testing.T) {
	path := writeTemp(t, `<input name="t" data-value="a">`+"\n")
	if err := SetFieldValue(path, "t", "new"); err != nil {
		t.Fatal(err)
	}
	want := `<input name="t" data-value="a" value="new">` + "\n"
	if got := read(t, path); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_ReplacesAValueHoldingAGreaterThan(t *testing.T) {
	path := writeTemp(t, `<input name="t" value="a>b" size="3">`+"\n")
	if err := SetFieldValue(path, "t", "x"); err != nil {
		t.Fatal(err)
	}
	want := `<input name="t" value="x" size="3">` + "\n"
	if got := read(t, path); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_ReadsSingleQuotedValueAndName(t *testing.T) {
	path := writeTemp(t, `<input name='t' value='it "is" here'>`+"\n")
	if err := SetFieldValue(path, "t", "x"); err != nil {
		t.Fatal(err)
	}
	want := `<input name='t' value="x">` + "\n"
	if got := read(t, path); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_ANameInsideAnotherValueIsNotTheField(t *testing.T) {
	path := writeTemp(t, `<input name="other" title='x name="t" y'>`+"\n"+`<input name="t">`+"\n")
	if err := SetFieldValue(path, "t", "v"); err != nil {
		t.Fatal(err)
	}
	want := `<input name="other" title='x name="t" y'>` + "\n" + `<input name="t" value="v">` + "\n"
	if got := read(t, path); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestSetFieldValue_TextareaWithAGreaterThanInItsOpeningTag(t *testing.T) {
	path := writeTemp(t, `<textarea title="a>b" name="n">old</textarea>`+"\n")
	if err := SetFieldValue(path, "n", "new"); err != nil {
		t.Fatal(err)
	}
	want := `<textarea title="a>b" name="n">new</textarea>` + "\n"
	if got := read(t, path); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}
