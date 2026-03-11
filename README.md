# Docker 日志清理工具

一键限制 Docker 容器日志大小，防止磁盘爆满。

## 功能特点

- 🔧 自动配置 Docker 日志轮转（max-size、max-file）
- 💾 自动备份现有配置
- 🧹 可选：清理现有大日志文件
- 🔍 支持 dry-run 模式预览
- ✅ 安全的 JSON 处理
- 📊 日志占用空间检查
- 🎯 批量清理指定容器日志

## 快速开始

### 1. 检查日志占用

```bash
sudo ./check-docker-logs.sh
```

### 2. 配置日志轮转（默认：10MB × 3 个文件）

```bash
sudo ./limit-docker-logs.sh
```

### 3. 清理现有日志

```bash
# 清理指定容器
sudo ./clean-container-logs.sh nginx mysql

# 清理所有容器
sudo ./clean-container-logs.sh --all
```

## 脚本说明

### limit-docker-logs.sh - 配置日志轮转

```bash
# 自定义大小
sudo ./limit-docker-logs.sh --max-size 20m --max-file 5

# 配置并清理现有日志
sudo ./limit-docker-logs.sh --apply-truncate

# 预览模式
sudo ./limit-docker-logs.sh --dry-run
```

### check-docker-logs.sh - 检查日志占用

显示：
- 前 10 大日志文件
- 总占用空间
- 当前配置

### clean-container-logs.sh - 批量清理日志

```bash
# 清理指定容器
sudo ./clean-container-logs.sh container1 container2

# 清理所有容器
sudo ./clean-container-logs.sh --all

# 预览模式
sudo ./clean-container-logs.sh --all --dry-run
```

## 参数说明

### limit-docker-logs.sh

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `--max-size` | 单个日志文件最大大小 | 10m |
| `--max-file` | 保留的日志文件数量 | 3 |
| `--apply-truncate` | 清空现有容器日志 | 否 |
| `--dry-run` | 预览模式，不实际修改 | 否 |

## 工作原理

脚本会修改 `/etc/docker/daemon.json`，添加日志轮转配置：

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

## 注意事项

- ⚠️ 需要 root 权限
- ⚠️ limit-docker-logs.sh 会重启 Docker 服务
- ⚠️ 只对新容器和重启后的容器生效
- ⚠️ 清理日志会丢失历史日志，谨慎使用

## 常见问题

**Q: 现有容器的日志会自动清理吗？**  
A: 不会。需要重启容器或使用清理脚本。

**Q: 支持哪些日志驱动？**  
A: 目前只支持 `json-file`（Docker 默认）。

**Q: 如何恢复原配置？**  
A: 备份文件在 `/etc/docker/backup-daemon-json/`。

**Q: 如何定期自动清理？**  
A: 可以添加 cron 任务：
```bash
# 每周日凌晨 3 点清理
0 3 * * 0 /path/to/clean-container-logs.sh --all
```

## 许可证

MIT
