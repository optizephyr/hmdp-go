package config

import "testing"

func TestConfigHasRocketMQShape(t *testing.T) {
	var cfg Config

	_ = cfg.RocketMQ.NameServers
	_ = cfg.RocketMQ.Topic
	_ = cfg.RocketMQ.ProducerGroup
	_ = cfg.RocketMQ.ConsumerGroup

	_ = cfg.BigCache.Shards
	_ = cfg.BigCache.LifeWindow
	_ = cfg.BigCache.CleanWindow
	_ = cfg.BigCache.MaxEntriesInWindow
	_ = cfg.BigCache.MaxEntrySize
	_ = cfg.BigCache.HardMaxCacheSize
	_ = cfg.BigCache.Verbose
}
