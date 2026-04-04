package config

import (
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"time"

	"github.com/spf13/viper"
)

// Config 根配置结构体
type Config struct {
	Server   ServerConfig   `mapstructure:"server"`
	MySQL    MySQLConfig    `mapstructure:"mysql"`
	Redis    RedisConfig    `mapstructure:"redis"`
	BigCache BigCacheConfig `mapstructure:"bigcache"`
	RocketMQ RocketMQConfig `mapstructure:"rocketmq"`
}

// ServerConfig 服务器配置
type ServerConfig struct {
	Port int    `mapstructure:"port"`
	Mode string `mapstructure:"mode"`
}

// MySQLConfig MySQL配置
type MySQLConfig struct {
	Host         string `mapstructure:"host"`
	Port         string `mapstructure:"port"`
	Username     string `mapstructure:"username"`
	Password     string `mapstructure:"password"`
	DbName       string `mapstructure:"dbname"`
	Charset      string `mapstructure:"charset"`
	MaxOpenConns int    `mapstructure:"max_open_conns"`
	MaxIdleConns int    `mapstructure:"max_idle_conns"`
}

// RedisConfig Redis配置
type RedisConfig struct {
	Host     string        `mapstructure:"host"`
	Port     string        `mapstructure:"port"`
	Password string        `mapstructure:"password"`
	Db       int           `mapstructure:"db"`
	Timeout  time.Duration `mapstructure:"timeout"`
}

// BigCacheConfig BigCache配置
type BigCacheConfig struct {
	Shards             int           `mapstructure:"shards"`
	LifeWindow         time.Duration `mapstructure:"life_window"`
	CleanWindow        time.Duration `mapstructure:"clean_window"`
	MaxEntriesInWindow int           `mapstructure:"max_entries_in_window"`
	MaxEntrySize       int           `mapstructure:"max_entry_size"`
	HardMaxCacheSize   int           `mapstructure:"hard_max_cache_size"`
	Verbose            bool          `mapstructure:"verbose"`
}

// RocketMQConfig RocketMQ配置
type RocketMQConfig struct {
	NameServers   []string `mapstructure:"name_servers"`
	Topic         string   `mapstructure:"topic"`
	ProducerGroup string   `mapstructure:"producer_group"`
	ConsumerGroup string   `mapstructure:"consumer_group"`
}

var GlobalConfig *Config

func init() {
	// 设置Viper基础配置
	v := viper.New()
	// 配置文件路径（相对于项目根目录）
	v.SetConfigType("yaml")
	// 这里用绝对路径是为了让test也能加载config
	// --- 获取当前 config.go 文件所在的绝对路径 ---
	_, filename, _, _ := runtime.Caller(0)
	// filename 是绝对路径: /Users/.../hmdp-go/config/config.go
	// filepath.Dir(filename) 就是 config 目录的绝对路径
	configDir := filepath.Dir(filename)

	// 拼接真正的配置文件绝对路径
	configPath := filepath.Join(configDir, "config.yaml")
	v.SetConfigFile(configPath)

	if err := v.ReadInConfig(); err != nil {
		panic(err)
	}

	GlobalConfig = &Config{}

	if err := v.Unmarshal(GlobalConfig); err != nil {
		panic(err)
	}

	applyEnvOverrides(GlobalConfig)
}

func applyEnvOverrides(cfg *Config) {
	if value := os.Getenv("HMDP_MYSQL_HOST"); value != "" {
		cfg.MySQL.Host = value
	}
	if value := os.Getenv("HMDP_MYSQL_PORT"); value != "" {
		cfg.MySQL.Port = value
	}
	if value := os.Getenv("HMDP_MYSQL_USERNAME"); value != "" {
		cfg.MySQL.Username = value
	}
	if value := os.Getenv("HMDP_MYSQL_PASSWORD"); value != "" {
		cfg.MySQL.Password = value
	}
	if value := os.Getenv("HMDP_MYSQL_DBNAME"); value != "" {
		cfg.MySQL.DbName = value
	}
	if value := os.Getenv("HMDP_MYSQL_CHARSET"); value != "" {
		cfg.MySQL.Charset = value
	}

	if value := os.Getenv("HMDP_REDIS_HOST"); value != "" {
		cfg.Redis.Host = value
	}
	if value := os.Getenv("HMDP_REDIS_PORT"); value != "" {
		cfg.Redis.Port = value
	}
	if value := os.Getenv("HMDP_REDIS_PASSWORD"); value != "" {
		cfg.Redis.Password = value
	}
	if value := os.Getenv("HMDP_REDIS_DB"); value != "" {
		if parsed, err := strconv.Atoi(value); err == nil {
			cfg.Redis.Db = parsed
		}
	}
}
