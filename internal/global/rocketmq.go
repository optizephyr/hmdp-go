package global

import (
	"github.com/amemiya02/hmdp-go/config"
	rocketmq "github.com/apache/rocketmq-client-go/v2"
	"github.com/apache/rocketmq-client-go/v2/consumer"
	"github.com/apache/rocketmq-client-go/v2/producer"
)

var RocketMQProducer rocketmq.Producer
var RocketMQConsumer rocketmq.PushConsumer

func InitRocketMQProducer() error {
	producerClient, err := rocketmq.NewProducer(
		producer.WithNameServer(config.GlobalConfig.RocketMQ.NameServers),
		producer.WithGroupName(config.GlobalConfig.RocketMQ.ProducerGroup),
	)
	if err != nil {
		return err
	}
	if err := producerClient.Start(); err != nil {
		return err
	}
	RocketMQProducer = producerClient
	return nil
}

func InitRocketMQConsumer() error {
	consumerClient, err := rocketmq.NewPushConsumer(
		consumer.WithNameServer(config.GlobalConfig.RocketMQ.NameServers),
		consumer.WithGroupName(config.GlobalConfig.RocketMQ.ConsumerGroup),
	)
	if err != nil {
		return err
	}
	RocketMQConsumer = consumerClient
	return nil
}

func CloseRocketMQProducer() error {
	if RocketMQProducer == nil {
		return nil
	}
	return RocketMQProducer.Shutdown()
}

func CloseRocketMQConsumer() error {
	if RocketMQConsumer == nil {
		return nil
	}
	return RocketMQConsumer.Shutdown()
}
