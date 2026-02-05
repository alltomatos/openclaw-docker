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
    echo -e "${BEGE}[INFO] $1${RESET}" >&2
    log "INFO: $1"
}

log_success() {
    echo -e "${VERDE}[OK] $1${RESET}" >&2
    log "SUCCESS: $1"
}

log_error() {
    echo -e "${VERMELHO}[ERRO] $1${RESET}" >&2
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

detect_swarm_traefik() {
    log_info "Verificando ambiente Swarm e Traefik..."
    
    # 1. Verificar se é Swarm
    if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]; then
        return 1
    fi

    # 2. Procurar serviço Traefik
    # Tenta encontrar um serviço que tenha "traefik" no nome
    local traefik_service=$(docker service ls --format '{{.Name}}' | grep "traefik" | head -n 1)
    
    if [ -z "$traefik_service" ]; then
        return 1
    fi

    # 3. Descobrir a rede do Traefik
    # Inspeciona o serviço para achar a rede
    # O comando retorna algo como [{"Target":"network_id","Aliases":["traefik"]}]
    # Vamos tentar pegar o nome da rede associada
    local network_id=$(docker service inspect "$traefik_service" --format '{{range .Spec.TaskTemplate.Networks}}{{.Target}}{{end}}' | head -n 1)
    
    if [ -n "$network_id" ]; then
        local network_name=$(docker network inspect "$network_id" --format '{{.Name}}')
        log_success "Traefik detectado: Serviço=$traefik_service, Rede=$network_name"
        echo "$network_name"
        return 0
    fi

    return 1
}

generate_swarm_config() {
    local network_name="$1"
    local domain="$2"
    local auth_hash="$3"
    
    log_info "Gerando configuração para Swarm (Traefik na rede $network_name)..."
    
    local middleware_config=""
    if [ -n "$auth_hash" ]; then
        log_info "Configurando autenticação para o usuário: $(echo $auth_hash | cut -d: -f1)"
        middleware_config="
        - \"traefik.http.middlewares.openclaw-auth.basicauth.users=$auth_hash\"
        - \"traefik.http.routers.openclaw.middlewares=openclaw-auth\""
    fi

    cat > docker-compose.swarm.yml <<EOF
services:
  openclaw:
    image: watink/openclaw:latest
    networks:
      - $network_name
    deploy:
      mode: replicated
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.openclaw.rule=Host(\`$domain\`)"
        - "traefik.http.routers.openclaw.entrypoints=web"
        - "traefik.http.services.openclaw.loadbalancer.server.port=18789"
$middleware_config
        # Opcional: Se usar HTTPS/TLS
        # - "traefik.http.routers.openclaw.entrypoints=websecure"
        # - "traefik.http.routers.openclaw.tls=true"
    volumes:
      - openclaw_config:/home/openclaw/.openclaw
      - openclaw_workspace:/home/openclaw/workspace
      - openclaw_home:/home/openclaw
      - ./skills:/home/openclaw/workspace/skills

networks:
  $network_name:
    external: true

volumes:
  openclaw_config:
  openclaw_workspace:
  openclaw_home:
EOF
}

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
    
    # Tenta detectar Traefik/Swarm
    TRAEFIK_NET=$(detect_swarm_traefik)
    
    if [ -n "$TRAEFIK_NET" ]; then
        echo ""
        echo -e "${AMARELO}Ambiente Docker Swarm com Traefik detectado na rede: ${VERDE}$TRAEFIK_NET${RESET}"
        echo -e "Deseja instalar o OpenClaw no modo Cluster (Swarm) integrado ao Traefik?"
        echo -en "${BRANCO}[Y/n]: ${RESET}"
        read -r USE_SWARM
        
        if [[ "$USE_SWARM" =~ ^[Yy]$ || -z "$USE_SWARM" ]]; then
            echo -en "${BRANCO}Digite o domínio para o OpenClaw (ex: openclaw.app.localhost): ${RESET}"
            read -r DOMAIN
            [ -z "$DOMAIN" ] && DOMAIN="openclaw.app.localhost"
            
            # --- Autenticação ---
            local AUTH_HASH=""
            echo ""
            echo -e "Deseja proteger o acesso com senha (Basic Auth)?"
            echo -en "${BRANCO}[Y/n]: ${RESET}"
            read -r ENABLE_AUTH
            
            if [[ "$ENABLE_AUTH" =~ ^[Yy]$ || -z "$ENABLE_AUTH" ]]; then
                echo -en "${BRANCO}Usuário (default: admin): ${RESET}"
                read -r AUTH_USER
                [ -z "$AUTH_USER" ] && AUTH_USER="admin"
                
                echo -en "${BRANCO}Senha: ${RESET}"
                read -rs AUTH_PASS
                echo ""
                
                log_info "Gerando hash de senha..."
                # Tenta usar htpasswd via docker (httpd:alpine) - imagem leve ~5MB
                # Se falhar (ex: sem internet para pull), tenta python ou avisa
                AUTH_HASH=$(docker run --rm --entrypoint htpasswd httpd:alpine -nb "$AUTH_USER" "$AUTH_PASS" 2>/dev/null)
                
                if [ -z "$AUTH_HASH" ]; then
                     # Fallback para Python (se disponível no host)
                     if command -v python3 &>/dev/null; then
                         # Gera MD5 crypt (comum em linux)
                         local pass_hash=$(python3 -c "import crypt; print(crypt.crypt('$AUTH_PASS', crypt.mksalt(crypt.METHOD_MD5)))" 2>/dev/null)
                         if [ -n "$pass_hash" ]; then
                            AUTH_HASH="$AUTH_USER:$pass_hash"
                         fi
                     fi
                fi

                if [ -n "$AUTH_HASH" ]; then
                    log_success "Hash gerado com sucesso!"
                    echo -e "Credenciais: ${VERDE}$AUTH_USER${RESET} / ${VERDE}******${RESET}"
                else
                    log_error "Não foi possível gerar o hash (requer internet para baixar httpd:alpine ou python3 local)."
                    echo -e "${AMARELO}A instalação continuará sem autenticação.${RESET}"
                fi
            fi

            generate_swarm_config "$TRAEFIK_NET" "$DOMAIN" "$AUTH_HASH"
            
            log_info "Baixando imagem oficial..."
            docker pull watink/openclaw:latest
            
            log_info "Realizando deploy da Stack..."
            docker stack deploy -c docker-compose.yml -c docker-compose.swarm.yml openclaw
            
            if [ $? -eq 0 ]; then
                log_success "OpenClaw implantado no Swarm!"
                echo -e "Acesse em: ${VERDE}http://$DOMAIN${RESET}"
            else
                log_error "Falha no deploy Swarm."
            fi
            return
        fi
    fi

    # Modo Standalone (Padrão)
    log_info "Baixando imagem oficial e iniciando containers (Standalone)..."
    docker compose pull
    docker compose up -d
    
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

# --- Acesso ao Shell ---

enter_shell() {
    log_info "Tentando acessar o shell do container OpenClaw..."
    
    # Tenta encontrar container local (funciona para Standalone e Swarm se estiver no node atual)
    # Filtra por nome que contenha 'openclaw' (ex: openclaw-openclaw-1 ou openclaw_openclaw.1.xxx)
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    
    if [ -n "$container_id" ]; then
        log_info "Container encontrado: $container_id"
        
        echo ""
        echo -e "${BRANCO}Comandos internos disponíveis no OpenClaw:${RESET}"
        echo -e "  - ${VERDE}openclaw onboard --install-daemon${RESET} : Instala o daemon do sistema"
        echo -e "  - ${VERDE}openclaw channels login --channel whatsapp${RESET} : Gera QRCode do WhatsApp"
        echo -e "  - ${VERDE}/usr/local/bin/scan_skills.sh${RESET}     : Escaneia e instala novas skills"
        echo -e "  - ${VERDE}openclaw --help${RESET}                   : Ajuda geral do CLI"
        echo -e "  - ${VERDE}exit${RESET}                              : Sair do terminal"
        echo ""
        echo -e "${VERDE}Acessando container...${RESET}"
        
        # Tenta bash, se falhar tenta sh
        docker exec -it "$container_id" /bin/bash || docker exec -it "$container_id" /bin/sh
    else
        log_error "Nenhum container do OpenClaw encontrado em execução neste nó."
        echo -e "${AMARELO}Se estiver usando Swarm em múltiplos nós, o container pode estar em outro servidor.${RESET}"
    fi
}

# --- Limpeza ---

cleanup_vps() {
    log_info "Iniciando processo de remoção do OpenClaw..."
    echo ""
    echo -e "${VERMELHO}!!! ATENÇÃO !!!${RESET}"
    echo -e "Esta ação irá remover:"
    echo -e "  - Todos os containers e stacks do OpenClaw"
    echo -e "  - Todos os volumes de dados (configurações, workspace, histórico)"
    echo -e "  - O diretório de instalação ($INSTALL_DIR)"
    echo -e ""
    echo -e "${AMARELO}O Docker Engine NÃO será removido.${RESET}"
    echo ""
    echo -en "${BRANCO}Tem certeza absoluta que deseja continuar? (digite 'sim' para confirmar): ${RESET}"
    read -r CONFIRM

    if [ "$CONFIRM" != "sim" ]; then
        log_info "Operação cancelada pelo usuário."
        return
    fi

    # 1. Remover Stack Swarm (se existir)
    if docker stack ls | grep -q "openclaw"; then
        log_info "Removendo stack 'openclaw' do Swarm..."
        docker stack rm openclaw
        # Aguarda um pouco para garantir que os containers terminem
        log_info "Aguardando encerramento dos serviços (10s)..."
        sleep 10
    fi

    # 2. Remover Containers Standalone (se existirem)
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR" || return
        if docker compose ls | grep -q "openclaw"; then
             log_info "Parando e removendo containers Standalone..."
             docker compose down -v --remove-orphans
        fi
    fi

    # 3. Remover Volumes (Forçar limpeza)
    log_info "Removendo volumes persistentes..."
    docker volume rm openclaw_config openclaw_workspace openclaw_home 2>/dev/null || true

    # 4. Remover Diretório
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Removendo diretório de instalação: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi

    log_success "Limpeza concluída! O OpenClaw foi removido deste servidor."
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
        echo -e "${VERDE}4${BRANCO} - Acessar Terminal do Container${RESET}"
        echo -e "${VERMELHO}5${BRANCO} - Limpar VPS (Remover OpenClaw)${RESET}"
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
            4)
                enter_shell
                read -p "Pressione ENTER para continuar..."
                ;;
            5)
                check_root
                cleanup_vps
                read -p "Pressione ENTER para continuar..."
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
