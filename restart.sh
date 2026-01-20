#!/bin/bash

# Copyright (c) 2024 VocabVictors
# Author: VocabVictors <w93854@gmail.com>
# License: MIT
# Project: clash-for-AutoDL
# Description: Clash proxy service restart script for AutoDL environment

# 定义颜色和样式
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 自定义action函数，实现通用action功能
success() {
  echo -e "${GREEN}[  OK  ]${NC}"
  return 0
}

failure() {
  local rc=$?
  echo -e "${RED}[FAILED]${NC}"
  [ -x /bin/plymouth ] && /bin/plymouth --details
  return $rc
}

action() {
  local STRING=$1
  echo -n "$STRING "
  shift
  "$@" && success || failure
  local rc=$?
  echo
  return $rc
}

# 函数，判断命令是否正常执行
if_success() {
  local message_success=$1
  local message_failure=$2
  local return_status=${3:-0}  # 如果 \$3 未设置或为空，则默认为 0
  
  if [ "$return_status" -eq 0 ]; then
    action "$message_success" /bin/true
  else
    action "$message_failure" /bin/false
    # exit 1
  fi
}

# 定义路径变量
# 根据shell类型获取脚本路径
if [ -n "$ZSH_VERSION" ]; then
    # zsh 环境
    Server_Dir="$(cd "$(dirname "$(readlink -f "${(%):-%x}")")" && pwd)"
elif [ -n "$BASH_VERSION" ]; then
    # bash 环境
    Server_Dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
else
    # 默认使用 bash 语法
    Server_Dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
fi
Conf_Dir="$Server_Dir/conf"
Log_Dir="$Server_Dir/logs"

# 确保目录存在
[[ ! -d "$Conf_Dir" ]] && mkdir -p "$Conf_Dir"
[[ ! -d "$Log_Dir" ]] && mkdir -p "$Log_Dir"
[[ ! -d "$Server_Dir/bin" ]] && mkdir -p "$Server_Dir/bin"

# 关闭clash服务 - 支持mihomo和clash-linux
close_clash_service() {
  local pid_num=0
  local pids
  local return_status=0
  
  # 检查mihomo进程
  pids=$(pgrep -f "mihomo-linux")
  if [ -n "$pids" ]; then
    pid_num=$(echo "$pids" | wc -l)
    echo "找到 $pid_num 个mihomo进程"
    kill $pids &>/dev/null
    return_status=$?
  fi
  
  # 检查clash-linux进程
  pids=$(pgrep -f "clash-linux")
  if [ -n "$pids" ]; then
    local clash_count=$(echo "$pids" | wc -l)
    pid_num=$((pid_num + clash_count))
    echo "找到 $clash_count 个clash-linux进程"
    kill $pids &>/dev/null
    return_status=$((return_status + $?))
  fi
  
  # 等待进程完全关闭
  sleep 2
  
  # 强制杀死顽固进程
  pids=$(pgrep -f "mihomo-linux|clash-linux")
  if [ -n "$pids" ]; then
    echo "强制关闭剩余进程..."
    kill -9 $pids &>/dev/null
  fi
  
  if_success "服务关闭成功！" "服务关闭失败！" "$return_status"
}

# 获取CPU架构
get_cpu_arch() {
  if /bin/arch &>/dev/null; then
    echo $(/bin/arch)
  elif /usr/bin/arch &>/dev/null; then
    echo $(/usr/bin/arch)
  elif /bin/uname -m &>/dev/null; then
    echo $(/bin/uname -m)
  else
    echo -e "${RED}[ERROR] Failed to obtain CPU architecture!${NC}"
    # exit 1
  fi
}

# 启动clash服务 - 优先使用mihomo
start_clash_service() {
  local cpu_arch=$(get_cpu_arch)
  local mihomo_binary
  local clash_binary
  
  case $cpu_arch in
    x86_64|amd64)
      mihomo_binary="mihomo-linux-amd64"
      clash_binary="clash-linux-amd64"
      ;;
    aarch64|arm64)
      mihomo_binary="mihomo-linux-arm64"
      clash_binary="clash-linux-arm64"
      ;;
    armv7)
      mihomo_binary="mihomo-linux-armv7"
      clash_binary="clash-linux-armv7"
      ;;
    *)
      echo -e "${RED}[ERROR] Unsupported CPU Architecture: $cpu_arch${NC}"
      # exit 1
      ;;
  esac
  
  # 检查配置文件是否存在
  if [ ! -f "$Conf_Dir/config.yaml" ]; then
    echo -e "${RED}错误: 配置文件不存在，请先运行 start.sh${NC}"
    # exit 1
  fi
  
  local return_status=1
  
  # 优先使用mihomo
  if [ -f "$Server_Dir/bin/$mihomo_binary" ]; then
    echo "使用 Mihomo 启动服务..."
    nohup "$Server_Dir/bin/$mihomo_binary" -d "$Conf_Dir" > "$Log_Dir/mihomo.log" 2>&1 &
    return_status=$?
    
    # 创建PID文件
    echo $! > "$Server_Dir/clash.pid"
    
  elif [ -f "$Server_Dir/bin/$clash_binary" ]; then
    echo "使用 Clash 启动服务..."
    nohup "$Server_Dir/bin/$clash_binary" -d "$Conf_Dir" > "$Log_Dir/clash.log" 2>&1 &
    return_status=$?
    
    # 创建PID文件
    echo $! > "$Server_Dir/clash.pid"
    
  else
    echo -e "${RED}错误: 找不到可执行的二进制文件${NC}"
    return_status=1
  fi
  
  if_success "服务启动成功！" "服务启动失败！" "$return_status"
}

# 检查服务状态
check_service_status() {
  local pids=$(pgrep -f "mihomo-linux|clash-linux")
  if [ -n "$pids" ]; then
    echo -e "${GREEN}服务运行中 (PID: $pids)${NC}"
    return 0
  else
    echo -e "${RED}服务未运行${NC}"
    return 1
  fi
}

# 显示服务信息
show_service_info() {
  echo "========================================="
  echo "Clash - 服务重启"
  echo "========================================="
  echo "配置目录: $Conf_Dir"
  echo "日志目录: $Log_Dir"
  echo "二进制目录: $Server_Dir/bin"
  echo ""
}

# 主程序
main() {
  show_service_info
  
  echo "正在重启Clash服务..."
  close_clash_service
  
  # 等待服务完全关闭
  sleep 3
  
  # 确保日志目录存在
  [[ ! -d "$Log_Dir" ]] && mkdir -p "$Log_Dir"

  # 启动前清空旧日志，避免无限追加导致文件持续膨胀
  : > "$Log_Dir/mihomo.log"
  
  start_clash_service
  
  # 等待服务启动完成
  sleep 2
  
  echo "\n检查服务状态..."
  check_service_status
  
  if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}服务重启成功！${NC}"
    echo "提示: 使用 'proxy_on' 开启代理"
  else
    echo -e "\n${RED}服务重启失败！${NC}"
    echo "请检查日志文件: $Log_Dir/"
    # exit 1
  fi
}

main
