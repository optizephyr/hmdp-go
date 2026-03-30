package test

import (
	"testing"
)

func TestResolveTokenExportCount(t *testing.T) {
	t.Setenv("K6_TOKEN_COUNT", "2000")
	if got := resolveTokenExportCount(); got != 2000 {
		t.Fatalf("expected 2000 token export count, got %d", got)
	}

	t.Setenv("K6_TOKEN_COUNT", "0")
	if got := resolveTokenExportCount(); got != 1000 {
		t.Fatalf("expected default token export count 1000, got %d", got)
	}

	t.Setenv("K6_TOKEN_COUNT", "5000")
	if got := resolveTokenExportCount(); got != 5000 {
		t.Fatalf("expected 5000 token export count, got %d", got)
	}
}
