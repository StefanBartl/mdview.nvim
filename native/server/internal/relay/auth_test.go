package relay

import "testing"

func TestValidToken(t *testing.T) {
	cases := []struct {
		name     string
		expected string
		got      string
		want     bool
	}{
		{"matching tokens", "s3cret", "s3cret", true},
		{"mismatched tokens", "s3cret", "wrong", false},
		{"empty expected always rejects", "", "", false},
		{"empty got against real expected rejects", "s3cret", "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := ValidToken(tc.expected, tc.got); got != tc.want {
				t.Fatalf("ValidToken(%q, %q) = %v, want %v", tc.expected, tc.got, got, tc.want)
			}
		})
	}
}

func TestIsAllowedOrigin(t *testing.T) {
	const port = 43219
	cases := []struct {
		name   string
		origin string
		want   bool
	}{
		{"exact localhost match", "http://localhost:43219", true},
		{"exact 127.0.0.1 match", "http://127.0.0.1:43219", true},
		{"wrong port rejected", "http://localhost:9999", false},
		{"https scheme rejected", "https://localhost:43219", false},
		{"foreign host rejected", "http://evil.example:43219", false},
		{"missing origin rejected", "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := IsAllowedOrigin(tc.origin, port); got != tc.want {
				t.Fatalf("IsAllowedOrigin(%q, %d) = %v, want %v", tc.origin, port, got, tc.want)
			}
		})
	}
}
