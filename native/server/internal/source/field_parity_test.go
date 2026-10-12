package source

import "testing"

// The same cases as TESTS/nvim/field_parity_spec.lua: Go and Lua must write
// byte-identical output for them.
func TestSetFieldValue_ParityCases(t *testing.T) {
	cases := []struct {
		name, src, field, value, want string
	}{
		{"unquoted name and value", `<input name=t value=abc>`, "t", "x", `<input name=t value="x">`},
		{"value without a value", `<input name="t" value= >`, "t", "x", `<input name="t" value="x">`},
		{"attribute names in capitals", `<input NAME="t" VALUE="a">`, "t", "x", `<input NAME="t" value="x">`},
		{"a custom element is no input", "<input-x name=\"t\">\n<input name=\"t\">", "t", "x", "<input-x name=\"t\">\n<input name=\"t\" value=\"x\">"},
		{"quotes inside a quoted name stay", `<input name="'t'">`, "'t'", "x", `<input name="'t'" value="x">`},
		{"an unclosed quote hides only its own tag", "<input name=a value=\"x>\n<input name=\"t\">", "t", "v", "<input name=a value=\"x>\n<input name=\"t\" value=\"v\">"},
		{"a bare attribute is kept", `<input disabled name="t">`, "t", "x", `<input disabled name="t" value="x">`},
		{"white space before the closing bracket goes", "<input\n  name=\"t\"\n>", "t", "x", "<input\n  name=\"t\" value=\"x\">"},
		{"a tab before a self closing bracket goes", "<input name=\"t\"\t/>", "t", "x", "<input name=\"t\" value=\"x\"/>"},
		{"a custom element hides what its values hold", "<input-x title='<input name=\"t\">'>", "t", "x", "<input-x title='<input name=\"t\">'>"},
		{"a form feed separates attributes", "<input\fname=\"t\">", "t", "x", "<input\fname=\"t\" value=\"x\">"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			path := writeTemp(t, c.src+"\n")
			if err := SetFieldValue(path, c.field, c.value); err != nil {
				t.Fatal(err)
			}
			if got, want := read(t, path), c.want+"\n"; got != want {
				t.Fatalf("got %q want %q", got, want)
			}
		})
	}
}
