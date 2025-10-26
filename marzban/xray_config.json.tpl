{
  "api": {
    "services": ["HandlerService", "LoggerService", "StatsService"],
    "tag": "api"
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_PORT:-2083},
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${XRAY_REALITY_SERVER_NAMES%%,*}:443",
          "xver": 0,
          "serverNames": ["${XRAY_REALITY_SERVER_NAMES//,/\", \"}"],
          "privateKey": "${XRAY_REALITY_PRIVATE_KEY}",
          "shortIds": ["${XRAY_REALITY_SHORT_IDS//,/\", \"}"]
        },
        "grpcSettings": {
          "serviceName": "grpc"
        }
      },
      "tag": "vless-reality"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ]
}