"""远程开机系统 - serverhost 配置"""
import os

# 监听配置
HOST = os.environ.get("WOL_HOST", "0.0.0.0")
PORT = int(os.environ.get("WOL_PORT", "5000"))
DEBUG = os.environ.get("WOL_DEBUG", "false").lower() == "true"

# API 安全
API_TOKEN = os.environ.get(
    "WOL_API_TOKEN",
    "please-change-me-to-a-random-string",
)
TOKEN_HEADER = "X-API-Token"  # 也可以通过查询参数传递

# 数据目录
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
STATE_FILE = os.path.join(DATA_DIR, "state.json")
LOG_FILE = os.path.join(DATA_DIR, "wake.log")

# 限流
RATE_LIMIT = int(os.environ.get("WOL_RATE_LIMIT", "5"))  # 每分钟最大请求数
