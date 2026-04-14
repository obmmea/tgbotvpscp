#!/bin/bash
set -e

GIT_BRANCH="main"
AUTO_AGENT_URL=""
AUTO_NODE_TOKEN=""
AUTO_MODE=false
MIGRATE_ARGS=""

for arg in "$@"; do
    case $arg in
        --agent=*) AUTO_AGENT_URL="${arg#*=}"; AUTO_MODE=true ;;
        --token=*) AUTO_NODE_TOKEN="${arg#*=}"; AUTO_MODE=true ;;
        --branch=*) GIT_BRANCH="${arg#*=}" ;;
        main|develop) GIT_BRANCH="$arg" ;;
    esac
done

export DEBIAN_FRONTEND=noninteractive

BOT_INSTALL_PATH="/opt/tg-bot"
SERVICE_NAME="tg-bot"
WATCHDOG_SERVICE_NAME="tg-watchdog"
NODE_SERVICE_NAME="tg-node"
SERVICE_USER="tgbot"

PYTHON_BIN="/usr/bin/python3"
VENV_PATH="${BOT_INSTALL_PATH}/venv"
ENV_FILE="${BOT_INSTALL_PATH}/.env"
README_FILE="${BOT_INSTALL_PATH}/README.md"

GITHUB_REPO_URL="https://github.com/jatixs/tgbotvpscp.git"

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

msg_info(){ echo -e "${C_CYAN}🔵 $1${C_RESET}"; }
msg_success(){ echo -e "${C_GREEN}✅ $1${C_RESET}"; }
msg_error(){ echo -e "${C_RED}❌ $1${C_RESET}"; }

get_dc_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

run_with_spinner() {
    "$@" >/tmp/install.log 2>&1 &
    pid=$!
    while kill -0 $pid 2>/dev/null; do
        echo -ne "\r⏳ running..."
        sleep 0.2
    done
    wait $pid || return 1
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        msg_error "Run as root"
        exit 1
    fi
}

install_base() {
    apt update -y
    apt install -y git curl wget python3 python3-pip python3-venv
}

clone_repo() {
    rm -rf $BOT_INSTALL_PATH
    git clone -b $GIT_BRANCH $GITHUB_REPO_URL $BOT_INSTALL_PATH
}

create_venv() {
    python3 -m venv $VENV_PATH
    $VENV_PATH/bin/pip install --upgrade pip
    $VENV_PATH/bin/pip install -r $BOT_INSTALL_PATH/requirements.txt
}

write_env() {
    cat > $ENV_FILE <<EOF
DEPLOY_MODE="$1"
INSTALL_MODE="$2"
WEB_SERVER_PORT="8080"
EOF
}

create_service() {
    cat > /etc/systemd/system/$SERVICE_NAME.service <<EOF
[Unit]
Description=TG Bot
After=network.target

[Service]
WorkingDirectory=$BOT_INSTALL_PATH
ExecStart=$VENV_PATH/bin/python bot.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    systemctl restart $SERVICE_NAME
}

install_systemd() {
    install_base
    clone_repo
    create_venv
    write_env systemd secure
    create_service
    msg_success "Installed systemd bot"
}

install_node() {
    install_base
    clone_repo
    create_venv
    write_env node client

    cat > /etc/systemd/system/$NODE_SERVICE_NAME.service <<EOF
[Unit]
Description=TG Node
After=network.target

[Service]
WorkingDirectory=$BOT_INSTALL_PATH
ExecStart=$VENV_PATH/bin/python node/node.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable $NODE_SERVICE_NAME
    systemctl restart $NODE_SERVICE_NAME

    msg_success "Node installed"
}

main() {
    check_root
    echo "1) systemd bot"
    echo "2) node"
    read -p "select: " c

    case $c in
        1) install_systemd ;;
        2) install_node ;;
    esac
}

main
