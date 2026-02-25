#!/bin/bash
# OpenClaw Gateway 透過 Windows Clash 代理啟動（供 systemd 使用）
# 自動偵測 WSL 的預設閘道 = Windows 主機 IP

GW=$(ip route show | grep default | awk '{print $3}')
export HTTPS_PROXY="http://${GW}:7890"
export HTTP_PROXY="http://${GW}:7890"
export NODE_OPTIONS="--dns-result-order=ipv4first"

exec openclaw gateway
