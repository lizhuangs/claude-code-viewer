#!/bin/bash

# Claude Code Viewer 服务管理脚本
# 用法: ./service.sh {start|stop|restart|status}

set -e

# 配置
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_HOST="127.0.0.1"
BACKEND_PORT="8000"
FRONTEND_PORT="5173"

# PID 文件
PID_DIR="$PROJECT_DIR/.pids"
BACKEND_PID_FILE="$PID_DIR/backend.pid"
FRONTEND_PID_FILE="$PID_DIR/frontend.pid"

# 日志文件
LOG_DIR="$PROJECT_DIR/logs"
BACKEND_LOG="$LOG_DIR/backend.log"
FRONTEND_LOG="$LOG_DIR/frontend.log"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 初始化目录
init_dirs() {
    mkdir -p "$PID_DIR"
    mkdir -p "$LOG_DIR"
}

# 检查进程是否运行
is_running() {
    local pid_file="$1"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# 检查端口是否被占用，返回占用进程的PID
get_port_pid() {
    local port="$1"
    lsof -ti :"$port" 2>/dev/null | head -1
}

# 清理占用端口的进程
kill_port_process() {
    local port="$1"
    local pid=$(get_port_pid "$port")
    if [ -n "$pid" ]; then
        log_warn "端口 $port 被进程 $pid 占用，正在清理..."
        kill "$pid" 2>/dev/null || true
        sleep 1
        # 如果还在运行，强制终止
        if ps -p "$pid" > /dev/null 2>&1; then
            kill -9 "$pid" 2>/dev/null || true
        fi
        log_info "端口 $port 已释放"
    fi
}

# 启动后端
start_backend() {
    if is_running "$BACKEND_PID_FILE"; then
        log_warn "后端服务已在运行 (PID: $(cat $BACKEND_PID_FILE))"
        return 0
    fi

    # 检查并清理端口占用
    kill_port_process "$BACKEND_PORT"

    log_info "启动后端服务..."
    cd "$PROJECT_DIR"

    nohup python -m claude_viewer.main serve \
        --host "$BACKEND_HOST" \
        --port "$BACKEND_PORT" \
        > "$BACKEND_LOG" 2>&1 &

    echo $! > "$BACKEND_PID_FILE"
    sleep 2

    if is_running "$BACKEND_PID_FILE"; then
        log_info "后端服务启动成功 (PID: $(cat $BACKEND_PID_FILE))"
        log_info "后端地址: http://$BACKEND_HOST:$BACKEND_PORT"
    else
        log_error "后端服务启动失败，请查看日志: $BACKEND_LOG"
        return 1
    fi
}

# 启动前端
start_frontend() {
    if is_running "$FRONTEND_PID_FILE"; then
        log_warn "前端服务已在运行 (PID: $(cat $FRONTEND_PID_FILE))"
        return 0
    fi

    # 检查并清理端口占用
    kill_port_process "$FRONTEND_PORT"

    log_info "启动前端服务..."
    cd "$PROJECT_DIR/frontend"

    nohup npm run dev > "$FRONTEND_LOG" 2>&1 &

    echo $! > "$FRONTEND_PID_FILE"
    sleep 3

    if is_running "$FRONTEND_PID_FILE"; then
        log_info "前端服务启动成功 (PID: $(cat $FRONTEND_PID_FILE))"
        log_info "前端地址: http://localhost:$FRONTEND_PORT"
    else
        log_error "前端服务启动失败，请查看日志: $FRONTEND_LOG"
        return 1
    fi
}

# 停止后端
stop_backend() {
    if ! is_running "$BACKEND_PID_FILE"; then
        log_warn "后端服务未运行"
        rm -f "$BACKEND_PID_FILE"
        return 0
    fi

    local pid=$(cat "$BACKEND_PID_FILE")
    log_info "停止后端服务 (PID: $pid)..."
    kill "$pid" 2>/dev/null || true

    # 等待进程结束
    local count=0
    while ps -p "$pid" > /dev/null 2>&1 && [ $count -lt 10 ]; do
        sleep 1
        count=$((count + 1))
    done

    if ps -p "$pid" > /dev/null 2>&1; then
        log_warn "进程未响应，强制终止..."
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$BACKEND_PID_FILE"
    log_info "后端服务已停止"
}

# 停止前端
stop_frontend() {
    if ! is_running "$FRONTEND_PID_FILE"; then
        log_warn "前端服务未运行"
        rm -f "$FRONTEND_PID_FILE"
        return 0
    fi

    local pid=$(cat "$FRONTEND_PID_FILE")
    log_info "停止前端服务 (PID: $pid)..."

    # 终止进程组（包括子进程）
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null || true

    # 等待进程结束
    local count=0
    while ps -p "$pid" > /dev/null 2>&1 && [ $count -lt 10 ]; do
        sleep 1
        count=$((count + 1))
    done

    if ps -p "$pid" > /dev/null 2>&1; then
        log_warn "进程未响应，强制终止..."
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$FRONTEND_PID_FILE"
    log_info "前端服务已停止"
}

# 显示状态
show_status() {
    echo "=========================================="
    echo "  Claude Code Viewer 服务状态"
    echo "=========================================="

    if is_running "$BACKEND_PID_FILE"; then
        echo -e "后端服务: ${GREEN}运行中${NC} (PID: $(cat $BACKEND_PID_FILE))"
        echo "         地址: http://$BACKEND_HOST:$BACKEND_PORT"
    else
        echo -e "后端服务: ${RED}已停止${NC}"
    fi

    if is_running "$FRONTEND_PID_FILE"; then
        echo -e "前端服务: ${GREEN}运行中${NC} (PID: $(cat $FRONTEND_PID_FILE))"
        echo "         地址: http://localhost:$FRONTEND_PORT"
    else
        echo -e "前端服务: ${RED}已停止${NC}"
    fi

    echo "=========================================="
}

# 主命令处理
case "$1" in
    start)
        init_dirs
        log_info "启动 Claude Code Viewer..."
        start_backend
        start_frontend
        echo ""
        show_status
        ;;
    stop)
        log_info "停止 Claude Code Viewer..."
        stop_frontend
        stop_backend
        echo ""
        show_status
        ;;
    restart)
        log_info "重启 Claude Code Viewer..."
        stop_frontend
        stop_backend
        sleep 2
        init_dirs
        start_backend
        start_frontend
        echo ""
        show_status
        ;;
    status)
        show_status
        ;;
    start-backend)
        init_dirs
        start_backend
        ;;
    stop-backend)
        stop_backend
        ;;
    start-frontend)
        init_dirs
        start_frontend
        ;;
    stop-frontend)
        stop_frontend
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        echo ""
        echo "命令说明:"
        echo "  start          启动所有服务（后端 + 前端）"
        echo "  stop           停止所有服务"
        echo "  restart        重启所有服务"
        echo "  status         查看服务状态"
        echo ""
        echo "单独控制:"
        echo "  start-backend  仅启动后端"
        echo "  stop-backend   仅停止后端"
        echo "  start-frontend 仅启动前端"
        echo "  stop-frontend  仅停止前端"
        exit 1
        ;;
esac

exit 0
