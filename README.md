# Docker 日志清理工具

限制 + 清理 Docker 容器日志，防止磁盘爆满。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/lucifer988/docker-clear/main/install.sh | sudo bash
```

安装后脚本在 `/opt/docker-clear/`。

## 使用方法

### 1. 检查日志占用

```bash
sudo /opt/docker-clear/check-docker-logs.sh
```

### 2. 限制日志大小（新容器立即生效，已有容器重启后生效）

```bash
# 默认 10MB × 3 个文件
sudo /opt/docker-clear/limit-docker-logs.sh

# 自定义
sudo /opt/docker-clear/limit-docker-logs.sh --max-size 20m --max-file 5

# 限制 + 清空现有日志（谨慎）
sudo /opt/docker-clear/limit-docker-logs.sh --apply-truncate

# 预览，不实际修改
sudo /opt/docker-clear/limit-docker-logs.sh --dry-run
```

### 3. 清理已有日志

```bash
# 清理指定容器
sudo /opt/docker-clear/clean-container-logs.sh nginx mysql

# 清理所有容器
sudo /opt/docker-clear/clean-container-logs.sh --all
```

## 自动定时清理（可选）

```bash
# 每周日凌晨 3 点清理
echo '0 3 * * 0 root /opt/docker-clear/clean-container-logs.sh --all' >> /etc/crontab
```

## 注意事项

- 需要 root 权限
- `limit-docker-logs.sh` 会重启 Docker，已有容器需手动 restart
- 清理日志会丢失历史记录，请确认后再操作
- 修改前自动备份配置到 `/etc/docker/backup-daemon-json/`

## License

MIT
