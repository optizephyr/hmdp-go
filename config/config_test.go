package config

import "testing"

func TestConfigHasRocketMQShape(t *testing.T) {
	var cfg Config

	_ = cfg.RocketMQ.NameServers
	_ = cfg.RocketMQ.Topic
	_ = cfg.RocketMQ.ProducerGroup
	_ = cfg.RocketMQ.ConsumerGroup
}
