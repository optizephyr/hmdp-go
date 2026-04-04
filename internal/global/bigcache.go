package global

import (
	"context"
	"log/slog"

	"github.com/allegro/bigcache/v3"
	"github.com/amemiya02/hmdp-go/config"
)

var BigCacheClient *bigcache.BigCache

func init() {
	cfg := config.GlobalConfig.BigCache
	cache, err := bigcache.New(context.Background(), bigcache.Config{
		Shards:             cfg.Shards,
		LifeWindow:         cfg.LifeWindow,
		CleanWindow:        cfg.CleanWindow,
		MaxEntriesInWindow: cfg.MaxEntriesInWindow,
		MaxEntrySize:       cfg.MaxEntrySize,
		HardMaxCacheSize:   cfg.HardMaxCacheSize,
		Verbose:            cfg.Verbose,
	})
	if err != nil {
		slog.Error("bigcache init failed, continue without L1 cache", "err", err)
		BigCacheClient = nil
		return
	}

	BigCacheClient = cache
	slog.Info("Connected to BigCache...")
}
