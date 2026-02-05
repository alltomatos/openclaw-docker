#!/bin/bash

## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##
##                                         SETUP OPENCLAW                                      ##
## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##

# Configurações
REPO_URL="https://github.com/alltomatos/openclaw-docker.git"
INSTALL_DIR="/opt/openclaw"
LOG_FILE="/var/log/setup_openclaw.log"

# Cores
VERDE="\e[32m"
AMARELO="\e[33m"
VERMELHO="\e[91m"
BRANCO="\e[97m"
BEGE="\e[93m"
AZUL="\e[34m"
RESET="\e[0m"

# --- Funções Visuais e Logs ---

header() {
    clear
    echo -e "${AZUL}## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##${RESET}"
    echo -e "${AZUL}##                                         SETUP OPENCLAW                                      ##${RESET}"
    echo -e "${AZUL}## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##${RESET}"
    echo ""
    echo -e "                                   ${BRANCO}Versão do Instalador: ${VERDE}v1.0.0${RESET}                "
    echo -e "${VERDE}                ${BRANCO}<----- Desenvolvido por AllTomatos ----->     ${VERDE}github.com/alltomatos/openclaw-docker${RESET}"
    echo ""
}

log() {
    local msg="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $msg" >> "$LOG_FILE"
}

log_info() {
    echo -e "${BEGE}[INFO] $1${RESET}"
    log "INFO: $1"
}

log_success() {
    echo -e "${VERDE}[OK] $1${RESET}"
    log "SUCCESS: $1"
}

log_error() {
    echo -e "${VERMELHO}[ERRO] $1${RESET}"
    log "ERROR: $1"
}

# --- Verificações ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script precisa ser executado como root (sudo)."
        exit 1
    fi
}

check_deps() {
    log_info "Verificando dependências básicas..."
    local deps=("curl" "git" "jq")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_info "Instalando $dep..."
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y -qq "$dep" >/dev/null 2>&1 || log_error "Falha ao instalar $dep"
        fi
    done
}

# --- Infraestrutura ---

install_docker() {
    if ! command -v docker &> /dev/null; then
        log_info "Instalando Docker Engine..."
        
        # Método via script oficial (mais compatível)
        if curl -fsSL https://get.docker.com | bash; then
            log_success "Docker instalado com sucesso."
        else
            log_error "Falha ao instalar Docker via script. Tentando apt..."
            apt-get update -qq
            apt-get install -y docker.io docker-compose-v2
        fi
        
        systemctl enable docker >/dev/null 2>&1
        systemctl start docker >/dev/null 2>&1
    else
        log_info "Docker já instalado."
    fi
}

# --- Instalação do OpenClaw ---

setup_openclaw() {
    log_info "Iniciando configuração do OpenClaw..."

    # 1. Preparar Diretório
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Diretório $INSTALL_DIR já existe. Atualizando repositório..."
        cd "$INSTALL_DIR" || exit
        git pull
    else
        log_info "Clonando repositório em $INSTALL_DIR..."
        git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR" || exit
    fi

    # 2. Configurar Permissões
    chmod +x *.sh
    mkdir -p skills
    chmod 777 skills # Permite escrita fácil pelo usuário e container

    # 3. Build & Deploy
    log_info "Construindo e iniciando containers..."
    docker compose up -d --build

    if [ $? -eq 0 ]; then
        log_success "OpenClaw iniciado com sucesso!"
        echo ""
        echo -e "${BRANCO}Comandos úteis:${RESET}"
        echo -e "  - Ver logs: ${VERDE}docker compose logs -f${RESET}"
        echo -e "  - Adicionar Skill: ${VERDE}./add_skill.sh <url_git>${RESET}"
        echo -e "  - Scan Manual: ${VERDE}docker compose exec openclaw /usr/local/bin/scan_skills.sh${RESET}"
    else
        log_error "Falha ao iniciar o OpenClaw."
    fi
}

# --- Menu Principal ---

menu() {
    while true; do
        header
        echo -e "${BRANCO}Selecione uma opção:${RESET}"
        echo ""
        echo -e "${VERDE}1${BRANCO} - Instalar/Atualizar OpenClaw (Completo)${RESET}"
        echo -e "${VERDE}2${BRANCO} - Apenas Instalar Docker${RESET}"
        echo -e "${VERDE}3${BRANCO} - Ver Logs do OpenClaw${RESET}"
        echo -e "${VERDE}0${BRANCO} - Sair${RESET}"
        echo ""
        echo -en "${AMARELO}Opção: ${RESET}"
        read -r OPCAO

        case $OPCAO in
            1)
                check_root
                check_deps
                install_docker
                setup_openclaw
                read -p "Pressione ENTER para continuar..."
                ;;
            2)
                check_root
                check_deps
                install_docker
                read -p "Pressione ENTER para continuar..."
                ;;
            3)
                if [ -d "$INSTALL_DIR" ]; then
                    cd "$INSTALL_DIR" || exit
                    docker compose logs -f --tail 50
                else
                    log_error "OpenClaw não parece estar instalado em $INSTALL_DIR"
                    read -p "Pressione ENTER para continuar..."
                fi
                ;;
            0)
                exit 0
                ;;
            *)
                echo "Opção inválida."
                sleep 1
                ;;
        esac
    done
}

# Execução
menu
