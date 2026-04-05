package test

import (
	"os"
	"strconv"
)

func resolveTokenExportCount() int {
	raw := os.Getenv("K6_TOKEN_COUNT")
	if raw == "" {
		return 1000
	}

	count, err := strconv.Atoi(raw)
	if err != nil || count <= 0 {
		return 1000
	}

	return count
}
