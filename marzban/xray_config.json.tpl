{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": {{XRAY_PORT}},
      "protocol": "vless",
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.cloudflare.com:443",
          "xver": 0,
          "serverNames": [{{XRAY_REALITY_SERVER_NAMES_JSON}}],
          "privateKey": "{{XRAY_REALITY_PRIVATE_KEY}}",
          "shortIds": [{{XRAY_REALITY_SHORT_IDS_JSON}}]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}