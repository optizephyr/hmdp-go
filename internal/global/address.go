package global

func joinHostPort(host, port string) string {
	if len(port) > 0 && port[0] == ':' {
		port = port[1:]
	}
	return host + ":" + port
}
