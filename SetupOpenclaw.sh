#!/bin/bash

## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##
##                                         SETUP OPENCLAW                                      ##
## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##

# Configurações
# REPO_URL removida (instalação self-contained)
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

# Variáveis Globais de Armazenamento

VOLUME_NAME="openclaw_data"

# --- Helpers de Armazenamento ---



# Garante que o volume exista (se modo volume)
# Garante que o volume exista
ensure_volume_exists() {
    if ! docker volume ls -q | grep -q "^${VOLUME_NAME}$"; then
        log_info "Criando volume Docker: $VOLUME_NAME"
        docker volume create "$VOLUME_NAME"
    fi
}

# --- Funções Visuais e Logs ---

header() {
    clear
    echo -e "${AZUL}## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##${RESET}"
    echo -e "${AZUL}##                                         SETUP OPENCLAW                                      ##${RESET}"
    echo -e "${AZUL}## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##${RESET}"
    echo ""
    echo -e "                           ${BRANCO}Versão do Instalador: ${VERDE}v2.1.0${RESET}                "
    echo -e "${VERDE}     ${BRANCO}<- Desenvolvido por AllTomatos ->     ${VERDE}github.com/alltomatos/openclaw-docker${RESET}"
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

log_warning() {
    echo -e "${AMARELO}[AVISO] $1${RESET}" >&2
    log "WARNING: $1"
}

log_warn() {
    log_warning "$1"
}

# --- Verificações ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script precisa ser executado como root (sudo)."
        exit 1
    fi
    
    # SetupOrion Logic: Garante execução a partir do /root para evitar problemas de permissão/path
    if [ "$PWD" != "/root" ]; then
        log_info "Mudando para o diretório /root/ para garantir estabilidade..."
        cd /root || exit
    fi
}

# Adiciona o usuário atual ao grupo docker se necessário
ensure_docker_permission() {
    # Verifica GID do grupo docker no host
    DOCKER_GID=$(getent group docker | cut -d: -f3)
    if [ -n "$DOCKER_GID" ]; then
        # Exporta GID para ser usado no build/run se necessário
        export DOCKER_GID_HOST=$DOCKER_GID
    fi
}

check_deps() {
    log_info "Verificando dependências essenciais..."
    # Lista expandida baseada no SetupOrion-init.sh
    local deps=("curl" "git" "jq" "apache2-utils" "apt-utils" "dialog" "python3" "neofetch")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_info "Instalando $dep..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$dep" >/dev/null 2>&1 || log_error "Falha ao instalar $dep"
        fi
    done
    
    log_success "Dependências verificadas."
}

setup_hostname() {
    local force_setup="$1"
    
    # Se já configurado e não forçado, retorna silenciosamente
    if [ -f "/root/dados_vps/.hostname_configured" ] && [ "$force_setup" != "force" ]; then
        return
    fi

    header
    echo -e "${AZUL}=== Preparação do Sistema (Ubuntu 24 LTS) ===${RESET}"
    echo ""
    
    log_info "Atualizando index de repositórios e pacotes do sistema..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq || log_warn "Aviso: Algumas atualizações de sistema foram ignoradas ou falharam."
    
    echo ""
    current_hostname=$(hostname)
    echo -e "${BRANCO}Hostname atual: ${VERDE}$current_hostname${RESET}"
    echo ""
    
    # Se já configurado, pergunta diferente
    if [ -f "/root/dados_vps/.hostname_configured" ]; then
        echo -e "${AMARELO}O hostname já foi configurado anteriormente.${RESET}"
    fi
    
    echo -en "${BRANCO}Deseja alterar o hostname? [y/N]: ${RESET}"
    read -r CHANGE_HOST
    
    if [[ "$CHANGE_HOST" =~ ^[Yy]$ ]]; then
        echo -en "${BRANCO}Digite o novo hostname: ${RESET}"
        read -r NEW_HOSTNAME
        if [ -n "$NEW_HOSTNAME" ]; then
            hostnamectl set-hostname "$NEW_HOSTNAME"
            # Atualiza hosts
            if grep -q "127.0.0.1" /etc/hosts; then
                 sed -i "s/127.0.0.1.*/127.0.0.1 localhost $NEW_HOSTNAME/" /etc/hosts
            else
                 echo "127.0.0.1 $NEW_HOSTNAME" >> /etc/hosts
            fi
            log_success "Hostname alterado para $NEW_HOSTNAME"
        else
            log_error "Hostname inválido."
        fi
    fi
    
    # Garante diretório de persistência central
    if [ ! -d "/root/dados_vps" ]; then
        log_info "Criando diretório de persistência /root/dados_vps..."
        mkdir -p /root/dados_vps
    fi
    
    # Marca como configurado
    touch /root/dados_vps/.hostname_configured
}

install_portainer_standalone() {
    log_error "Modo Standalone foi removido. Use o modo Swarm."
    return 1
}

generate_infra_config() {
    local network_name="$1"
    local email_ssl="$2"
    
    # Garante que a rede externa exista
    docker network create --driver overlay --attachable "$network_name" 2>/dev/null || true
    
    cat <<EOF > docker-compose.infra.yml
version: '3.8'

networks:
  $network_name:
    external: true

volumes:
  portainer_data:
  letsencrypt_data:

services:
  traefik:
    image: traefik:v2.10
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.email=$email_ssl"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "letsencrypt_data:/letsencrypt"
    networks:
      - $network_name
    deploy:
      mode: global
      placement:
        constraints:
          - node.role == manager

  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "portainer_data:/data"
    networks:
      - $network_name
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`portainer.localhost\`)"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
EOF
}

# --- Infraestrutura ---

prepare_persistence() {
    log_info "Preparando diretório de persistência em /root/openclaw..."
    mkdir -p /root/openclaw/workspace/skills /root/openclaw/config
    # 994:994 é o UID:GID do usuário openclaw na imagem oficial
    chown -R 994:994 /root/openclaw
    chmod -R 775 /root/openclaw
    log_success "Diretório /root/openclaw pronto."
}

update_dashboard_link() {
    local domain="$1"
    local info_file="/root/dados_vps/openclaw.txt"
    
    if [ -f "$info_file" ]; then
        log_info "Atualizando link do dashboard para usar domínio $domain..."
        # Substitui a URL com IP pela URL com domínio (preservando o token)
        sed -i "s|http://.*:18789/|https://$domain/|g" "$info_file"
    fi
}

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
    local gateway_token="$4"
    local canvas_domain="$5"
    
    log_info "Gerando configuração para Swarm (Traefik na rede $network_name)..."
    
    local middleware_config=""
    if [ -n "$auth_hash" ]; then
        log_info "Configurando autenticação para o usuário: $(echo "$auth_hash" | cut -d: -f1)"
        # Escape $ for docker-compose interpolation
        local escaped_hash=$(echo "$auth_hash" | sed 's/\$/$$/g')
        middleware_config="
        - \"traefik.http.middlewares.openclaw-auth.basicauth.users=$escaped_hash\"
        - \"traefik.http.routers.openclaw.middlewares=openclaw-auth\""
    fi

    # Configuração COMPLETA para Swarm (evita dependência do docker-compose.yml e erro de 'profiles')
    cat > /root/openclaw.yaml <<EOF
version: "3.7"
services:
  openclaw:
    image: watink/openclaw:latest
    networks:
      - $network_name
    environment:
      - OPENCLAW_DISABLE_BONJOUR=1
      # Bind LAN (necessário para Traefik alcançar o container)
      - OPENCLAW_GATEWAY_BIND=lan
      # Token de Gateway para automação
      - OPENCLAW_GATEWAY_TOKEN=${gateway_token:-admin-token-123}
      # Configurações Adicionais (OpenClaw Best Practices)
      - TZ=America/Fortaleza
      - NODE_ENV=production
      # Aponta para o serviço de sandbox
      - OPENCLAW_SANDBOX_HOST=sandbox
    # Permite iniciar sem config para rodar o onboard depois
    command: ["openclaw", "gateway", "--allow-unconfigured"]
    # Healthcheck desabilitado para evitar loops de reinício durante o setup inicial no Swarm
    # healthcheck:
    #   test: ["CMD", "node", "dist/index.js", "health", "--json"]
    #   interval: 30s
    #   timeout: 10s
    #   retries: 3
    deploy:
      mode: replicated
      replicas: 1
      resources:
        limits:
          cpus: '2.0'
          memory: 2048M
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.openclaw.rule=Host(\`$domain\`)"
        - "traefik.http.routers.openclaw.service=openclaw"
        - "traefik.http.routers.openclaw.entrypoints=web"
        - "traefik.http.routers.openclaw.entrypoints=websecure"
        - "traefik.http.routers.openclaw.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.openclaw.loadbalancer.server.port=18789"
        # Canvas Host (Porta 18793)
        - "traefik.http.routers.openclaw-canvas.rule=Host(\`$canvas_domain\`)"
        - "traefik.http.routers.openclaw-canvas.service=openclaw-canvas"
        - "traefik.http.routers.openclaw-canvas.entrypoints=web"
        - "traefik.http.routers.openclaw-canvas.entrypoints=websecure"
        - "traefik.http.routers.openclaw-canvas.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.openclaw-canvas.loadbalancer.server.port=18793"
$middleware_config
    volumes:
      - /root/openclaw:/home/openclaw/.openclaw
      - /var/run/docker.sock:/var/run/docker.sock

  sandbox:
    image: watink/openclaw-sandbox:bookworm-slim
    command: ["sleep", "infinity"]
    networks:
      - $network_name
    deploy:
      mode: replicated
      replicas: 1
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

# Removido volumes nomeados para garantir persistência direta no bind mount
networks:
  $network_name:
    external: true
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

    # FIX: Traefik Client Version 1.24 Error (SetupOrion Logic)
    # Força o Daemon a aceitar API 1.24, evitando erro "client version 1.24 is too old"
    log_info "Verificando e aplicando patch de compatibilidade API Docker..."
    
    mkdir -p /etc/systemd/system/docker.service.d
    
    # Cria/Atualiza override
    cat > /etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
Environment=DOCKER_MIN_API_VERSION=1.24
EOF

    # Recarrega daemon e reinicia docker para aplicar
    # Apenas reinicia se a configuração mudou ou se necessário, mas para garantir fazemos sempre no setup
    systemctl daemon-reload >/dev/null 2>&1
    systemctl restart docker >/dev/null 2>&1
    
    if systemctl show --property=Environment docker | grep -q "DOCKER_MIN_API_VERSION=1.24"; then
        log_success "Patch de API Docker aplicado com sucesso."
    else
        log_warning "Atenção: Não foi possível confirmar o Patch de API Docker."
    fi
    
    sleep 5
}

setup_security_config() {
    local gen_token="$1"
    local domain_override="$2"
    log_info "Verificando configuração de segurança..."
    
    # Aguarda o container subir (tentativa simples)
    sleep 5
    
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    
    if [ -z "$container_id" ]; then
        log_error "Container não encontrado. Não foi possível ler a configuração."
        return
    fi

    # Tenta ler configuração diretamente do container (Volume Nomeado)
    local config_content=""
    # Ler configuração atual diretamente do container
    config_content=$(docker exec "$container_id" cat /home/openclaw/.openclaw/openclaw.json 2>/dev/null)
    
    # Se falhar ou não existir no host, tenta via container (fallback)
    if [ -z "$config_content" ]; then
        # Ler configuração atual diretamente do container
        # Usamos cat para ler sem copiar o arquivo para o host
        config_content=$(docker exec "$container_id" cat /home/openclaw/.openclaw/openclaw.json 2>/dev/null)
    fi
    
    # Se não conseguir ler, assume vazio
    if [ -z "$config_content" ]; then
         log_warn "Arquivo de configuração não encontrado ou vazio (Host/Container)."
    fi

    # Verificar se tem token configurado pelo Wizard
    local auth_token=""
    if [ -n "$config_content" ]; then
        auth_token=$(echo "$config_content" | jq -r '.gateway.auth.token // empty')
    fi
    
    # Se não achou no JSON, mas temos um gerado via Env Var, usa o gerado
    if [ -z "$auth_token" ] && [ -n "$gen_token" ]; then
        auth_token="$gen_token"
    fi
    
    if [ -n "$auth_token" ]; then
        log_info "Token de segurança detectado."
        
        local BASE_URL=""
        if [ -n "$domain_override" ]; then
             # Modo Swarm/Domínio: Não usa IP/Porta direta
             BASE_URL="https://$domain_override"
        else
            # Modo Standalone: Detectar IP Externo para facilitar o acesso
            local PUBLIC_IP="LOCALHOST"
            if command -v curl &> /dev/null; then
                PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me || echo "LOCALHOST")
            fi
            BASE_URL="http://$PUBLIC_IP:18789"
        fi
        
        # Salvar info para o usuário (apenas leitura/display)
        mkdir -p /root/dados_vps
        
        # Se o arquivo já existir e contiver "URL: ", preservamos o modo Swarm e apenas atualizamos o token
        if grep -q "URL: " /root/dados_vps/openclaw.txt 2>/dev/null; then
            log_info "Atualizando token no arquivo de informações existente..."
            # Remove linhas antigas de token se existirem para evitar duplicidade
            sed -i '/TOKEN_ACESSO:/d' /root/dados_vps/openclaw.txt
            echo "TOKEN_ACESSO: $auth_token" >> /root/dados_vps/openclaw.txt
        else
            # Modo Standalone ou arquivo novo
            echo "================================================================" > /root/dados_vps/openclaw.txt
            echo " DATA DE INSTALAÇÃO: $(date)" >> /root/dados_vps/openclaw.txt
            echo "================================================================" >> /root/dados_vps/openclaw.txt
            echo " TOKEN DE ACESSO (GATEWAY):" >> /root/dados_vps/openclaw.txt
            echo " $auth_token" >> /root/dados_vps/openclaw.txt
            echo "----------------------------------------------------------------" >> /root/dados_vps/openclaw.txt
            echo " LINK DIRETO DO DASHBOARD:" >> /root/dados_vps/openclaw.txt
            echo " $BASE_URL/?token=$auth_token" >> /root/dados_vps/openclaw.txt
            echo "================================================================" >> /root/dados_vps/openclaw.txt
        fi
        
        chmod 600 /root/dados_vps/openclaw.txt

        echo ""
        echo -e "${AZUL}================================================================${RESET}"
        echo -e "${VERDE} TOKEN DE ACESSO (GATEWAY):${RESET}"
        echo -e "${BRANCO} $auth_token ${RESET}"
        echo -e "${AZUL}================================================================${RESET}"
        echo -e "Uma cópia foi salva em: ${VERDE}/root/dados_vps/openclaw.txt${RESET}"
        echo ""
    else
        log_info "Nenhum token detectado na configuração atual."
        echo ""
        echo -e "${AMARELO}NOTA: O OpenClaw ainda não está configurado com um token de acesso.${RESET}"
        echo -e "${BRANCO}Utilize o 'Setup Wizard' (Opção 4) para gerar a configuração inicial.${RESET}"
        echo ""
    fi
}

sync_official_skills() {
    log_info "Sincronizando skills oficiais do repositório (Pasta /skills)..."
    
    # Garante que estamos na raiz do projeto
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR" || return
        
        # Se for um repositório git, tenta atualizar apenas a pasta skills
        if [ -d ".git" ]; then
            # Faz fetch do remote para garantir que temos as referências mais novas
            git fetch origin main >/dev/null 2>&1 || true
            
            # Força o checkout da pasta skills do branch main
            # Isso garante que temos os arquivos exatos do repositório oficial
            # -- no-overlay não é suportado em git muito antigo, então usamos checkout simples pathspec
            if git checkout origin/main -- skills/ >/dev/null 2>&1; then
                log_success "Skills oficiais sincronizadas com sucesso."
            else
                log_error "Falha ao sincronizar skills oficiais. Verifique a conexão com o Git."
            fi
        else
            log_info "Não é um repositório git completo. Pulando sincronização de skills oficiais."
        fi
    fi
}

install_initial_skills() {
    log_info "Verificando e instalando skills iniciais..."
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    
    if [ -n "$container_id" ]; then
        # Executa o scan em background para não travar se demorar muito, ou foreground?
        # Melhor foreground para garantir que o usuário veja o output
        log_info "Executando varredura de skills dentro do container..."
        docker exec "$container_id" /usr/local/bin/scan_skills.sh
        log_success "Skills processadas."
    else
        log_error "Container não encontrado. Pulei a instalação de skills."
    fi
}

# Variáveis de Ambiente (Padrão Oficial)
# OPENCLAW_DOCKER_APT_PACKAGES: Pacotes apt extras para instalar no build
OPENCLAW_DOCKER_APT_PACKAGES="${OPENCLAW_DOCKER_APT_PACKAGES:-}"

# Função para build da imagem
build_image() {
    log_info "Construindo imagem Docker ($IMAGE_NAME)..."
    if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then
        log_info "Pacotes extras detectados: $OPENCLAW_DOCKER_APT_PACKAGES"
    fi
    
    if docker build \
        --build-arg OPENCLAW_DOCKER_APT_PACKAGES="$OPENCLAW_DOCKER_APT_PACKAGES" \
        -t "$IMAGE_NAME" .; then
        log_success "Imagem construída com sucesso."
    else
        log_error "Falha ao construir imagem."
        exit 1
    fi
}

# --- Helpers ---

wait_stack() {
    log_info "Aguardando serviços... (Se demorar > 5min, algo deu errado)"
    declare -A services_status

    # Inicializa o status de todos os serviços como "pendente"
    for service in "$@"; do
        services_status["$service"]="pendente"
    done

    while true; do
        all_active=true

        for service in "${!services_status[@]}"; do
            # Verifica se tem réplica 1/1 (ativo)
            if docker service ls --filter "name=$service" | grep -q "1/1"; then
                if [ "${services_status["$service"]}" != "ativo" ]; then
                    log_success "O serviço $service está online."
                    services_status["$service"]="ativo"
                fi
            else
                if [ "${services_status["$service"]}" != "pendente" ]; then
                    services_status["$service"]="pendente"
                fi
                all_active=false
            fi
        done

        # Sai do loop quando todos os serviços estiverem ativos
        if $all_active; then
            sleep 1
            break
        fi
        sleep 30
        echo -n "."
    done
}

check_service_health() {
    local service_name="$1"
    local desired_replicas="${2:-1}"
    local timeout="${3:-300}" # 5 minutes default
    local interval=10
    local elapsed=0

    log_info "Monitorando saúde do serviço $service_name (Meta: $desired_replicas/$desired_replicas)..."

    while [ $elapsed -lt $timeout ]; do
        # Verifica réplicas (Running / Desired)
        # Formato {{.Replicas}} retorna algo como "1/1"
        local replicas=$(docker service ls --filter "name=$service_name" --format "{{.Replicas}}")
        
        if [[ "$replicas" == "$desired_replicas/$desired_replicas" ]]; then
            echo ""
            log_success "Serviço $service_name estabilizado em $replicas!"
            return 0
        fi
        
        # Verifica se falhou (0/1 por muito tempo)
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done

    echo ""
    log_error "Timeout aguardando serviço $service_name ficar saudável."
    log_info "Logs recentes do serviço:"
    docker service logs --tail 20 "$service_name"
    return 1
}

deploy_stack_via_api() {
    local stack_name="$1"
    local compose_file="$2"
    
    # Tenta recuperar credenciais/configuração do Portainer se não estiverem no escopo
    local p_domain="$PORTAINER_DOMAIN"
    local p_user="$PORTAINER_USER"
    local p_pass="$PORTAINER_PASS"
    local token=""
    
    if [ -f "/root/dados_vps/dados_portainer.txt" ]; then
        local p_url_file=$(grep "URL: " /root/dados_vps/dados_portainer.txt | awk '{print $2}')
        if [ -n "$p_url_file" ]; then
            p_domain=$(echo "$p_url_file" | sed 's|https://||' | sed 's|http://||')
        fi
        
        # Tenta pegar token do arquivo
        local token_file=$(grep "Token: " /root/dados_vps/dados_portainer.txt | awk '{print $2}')
        if [ -n "$token_file" ]; then
            token="$token_file"
        fi
        
        # Se não tem user/pass no escopo, tenta pegar do arquivo
        if [ -z "$p_user" ]; then
            p_user=$(grep "User: " /root/dados_vps/dados_portainer.txt | awk '{print $2}')
        fi
        if [ -z "$p_pass" ]; then
            p_pass=$(grep "Pass: " /root/dados_vps/dados_portainer.txt | awk '{print $2}')
        fi
    fi
    
    # Se ainda não temos domínio, falha
    if [ -z "$p_domain" ]; then
        log_warn "Domínio do Portainer não identificado. Usando deploy via CLI (Stack NÃO EDITÁVEL no Portainer)."
        docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
        return
    fi
    
    local portainer_url="https://$p_domain"
    
    # Com Automação de DNS (/etc/hosts), não precisamos mais de Truques de Resolve complexos
    
    # Se não temos token, tenta gerar
    
    # Se não temos token, tenta gerar
    if [ -z "$token" ] && [ -n "$p_user" ] && [ -n "$p_pass" ]; then
         log_info "Gerando token temporário para deploy via API..."
         token=$(curl -k -s $resolve_arg -X POST "$portainer_url/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"$p_user\",\"password\":\"$p_pass\"}" | jq -r .jwt)
    fi

    if [ -z "$token" ] || [ "$token" == "null" ]; then
        log_warn "Não foi possível autenticar na API do Portainer. Usando deploy via CLI (Stack NÃO EDITÁVEL)."
        docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
        return
    fi

    # Obter Endpoint ID (com retry e fallback)
    local endpoint_id=""
    local max_retries=15
    local count=0
    
    while [ $count -lt $max_retries ]; do
        # Tenta pegar lista de endpoints
        local response=$(curl -k -s -H "Authorization: Bearer $token" "$portainer_url/api/endpoints")

        # Verifica se o token é inválido ou expirado
        if echo "$response" | grep -qE "Invalid JWT token|Unauthorized"; then
             log_warn "Token Portainer expirado ou inválido. Tentando gerar novo token..."
             if [ -n "$p_user" ] && [ -n "$p_pass" ]; then
                 local new_token=$(curl -k -s -X POST "$portainer_url/api/auth" \
                    -H "Content-Type: application/json" \
                    -d "{\"username\":\"$p_user\",\"password\":\"$p_pass\"}" | jq -r .jwt)
                 
                 if [ -n "$new_token" ] && [ "$new_token" != "null" ]; then
                     token="$new_token"
                     log_success "Novo token gerado com sucesso."
                     
                     # Atualiza arquivo se existir
                     if [ -f "/root/dados_vps/dados_portainer.txt" ]; then
                         sed -i "s|^Token: .*|Token: $token|" /root/dados_vps/dados_portainer.txt
                     fi
                     
                     sleep 1
                     continue
                 else
                     log_error "Falha ao regenerar token."
                 fi
             fi
        fi
        
        # Estratégia 1: Primeiro ID da lista
        endpoint_id=$(echo "$response" | jq -r 'if type=="array" then .[0].Id else empty end')
        
        # Estratégia 2: Fallback estilo Orion (busca por nome "primary" ou "local")
        if [ -z "$endpoint_id" ] || [ "$endpoint_id" == "null" ]; then
             endpoint_id=$(echo "$response" | jq -r 'if type=="array" then .[] | select(.Name == "primary" or .Name == "local") | .Id else empty end' | head -n 1)
        fi

        if [ -n "$endpoint_id" ] && [ "$endpoint_id" != "null" ]; then
            break
        fi
        
        sleep 2
        count=$((count+1))
    done
    
    if [ -z "$endpoint_id" ] || [ "$endpoint_id" == "null" ]; then
         log_warn "Falha ao obter Endpoint ID após $max_retries tentativas. Usando deploy via CLI (Stack NÃO EDITÁVEL)."
         log_info "Response debug: $response"
         docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
         return
    fi
    
    # Arquivos temporários para capturar saída
    local response_output=$(mktemp)
    local error_output=$(mktemp)
    local file_content=$(cat "$compose_file")
    
    log_info "Tentando deploy via Portainer API (Stack Editável)..."

    # Verificar se a stack já existe
    local stack_id=$(curl -k -s -H "Authorization: Bearer $token" "$portainer_url/api/stacks" | jq -r --arg name "$stack_name" '.[] | select(.Name == $name) | .Id')

    if [ -n "$stack_id" ] && [ "$stack_id" != "null" ]; then
         log_info "Stack '$stack_name' encontrada (ID: $stack_id). Atualizando via API..."
         
         # Preparar payload JSON seguro usando jq
         local payload=$(jq -n --arg content "$file_content" --argjson prune true '{StackFileContent: $content, Prune: $prune}')
         
         local http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X PUT \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            "$portainer_url/api/stacks/$stack_id?endpointId=$endpoint_id" 2> "$error_output")
            
         if [ "$http_code" -eq 200 ]; then
            log_success "Stack '$stack_name' atualizada com SUCESSO via Portainer API!"
         else
            log_error "Erro ao atualizar stack via API (HTTP $http_code)."
            log_info "Tentando fallback via CLI..."
            docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
         fi
    else
        # API Request para CRIAR stack
        local http_code=0
        
        # SWARM DEPLOY
        # Obter Swarm ID
        local swarm_id=$(curl -k -s -H "Authorization: Bearer $token" "$portainer_url/api/endpoints/$endpoint_id/docker/swarm" | jq -r .ID)
        
        http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
        -H "Authorization: Bearer $token" \
        -F "Name=$stack_name" \
        -F "file=@$compose_file" \
        -F "SwarmID=$swarm_id" \
        -F "endpointId=$endpoint_id" \
        "$portainer_url/api/stacks/create/swarm/file" 2> "$error_output")
        
        if [ "$http_code" -eq 200 ]; then
            log_success "Deploy da stack '$stack_name' realizado com SUCESSO via Portainer API!"
            log_info "A stack agora deve aparecer como 'Total Control' no Portainer."
            return 0
        elif [ "$http_code" -eq 409 ]; then
            log_warn "Stack '$stack_name' já existe no Portainer (Conflito detectado tardiamente). Atualizando via CLI..."
            docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
            return 0
        else
            log_error "Erro no deploy via API (HTTP $http_code)."
            log_info "Tentando fallback via CLI..."
            if docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"; then
                return 0
            else
                return 1
            fi
        fi
    fi
    
    rm -f "$response_output" "$error_output"
}

# --- Instalação Completa (Swarm + Portainer + Traefik) ---

install_infrastructure() {
    log_info "Iniciando Setup de Infraestrutura (Docker Swarm + Portainer + Traefik)..."
    
    # 1. Instalar Docker
    install_docker
    
    # 2. Iniciar Swarm se necessário
    if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" != "active" ]; then
        log_info "Iniciando Docker Swarm..."
        # Tenta init simples primeiro
        if ! docker swarm init >/dev/null 2>&1; then
            log_warning "Falha no init automático. Tentando detectar IP principal..."
            
            # Tenta detectar IP
            local ADVERTISE_ADDR=""
            # Tenta via hostname
            ADVERTISE_ADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
            
            # Se falhar, tenta via ip route (mais confiável para gateway default)
            if [ -z "$ADVERTISE_ADDR" ]; then
                ADVERTISE_ADDR=$(ip route get 1 2>/dev/null | awk '{print $7;exit}')
            fi
            
            if [ -n "$ADVERTISE_ADDR" ]; then
                log_info "Usando IP detectado: $ADVERTISE_ADDR"
                docker swarm init --advertise-addr "$ADVERTISE_ADDR" || log_error "Falha crítica ao iniciar Swarm."
            else
                log_error "Não foi possível detectar IP. Tentando iniciar Swarm sem advertise-addr explícito..."
                docker swarm init || log_error "Falha crítica ao iniciar Swarm. Tente rodar manualmente: docker swarm init --advertise-addr <SEU_IP>"
            fi
        fi
    fi
    
    # 3. Coletar Informações
    echo ""
    echo -e "${AZUL}=== Configuração de Infraestrutura ===${RESET}"
    
    echo -en "${BRANCO}Nome da Rede Interna (ex: public_net): ${RESET}"
    read -r NETWORK_NAME
    [ -z "$NETWORK_NAME" ] && NETWORK_NAME="public_net"
    
    echo -en "${BRANCO}Email para SSL/Let's Encrypt (ex: admin@exemplo.com): ${RESET}"
    read -r EMAIL_SSL
    [ -z "$EMAIL_SSL" ] && EMAIL_SSL="admin@openclaw.local"
    
    echo -en "${BRANCO}Domínio do Portainer (ex: portainer.seu-dominio.com): ${RESET}"
    read -r PORTAINER_DOMAIN
    
    # Automação de DNS: Adicionar ao /etc/hosts para acesso interno via API
    if [ -n "$PORTAINER_DOMAIN" ]; then
        log_info "Configurando resolução local para $PORTAINER_DOMAIN..."
        
        # Detectar IP Real
        local REAL_IP=$(detect_public_ip)
        
        # Remove entrada antiga se existir
        sed -i "/$PORTAINER_DOMAIN/d" /etc/hosts
        echo "$REAL_IP $PORTAINER_DOMAIN" >> /etc/hosts
        log_success "Domínio $PORTAINER_DOMAIN mapeado para $REAL_IP em /etc/hosts"
    fi
    
    echo -en "${BRANCO}Usuário Admin do Portainer (ex: admin): ${RESET}"
    read -r PORTAINER_USER
    [ -z "$PORTAINER_USER" ] && PORTAINER_USER="admin"
    
    echo -en "${BRANCO}Senha do Portainer (min 12 chars): ${RESET}"
    read -r PORTAINER_PASS
    
    # 4. Criar Rede e Volumes
    log_info "Criando rede $NETWORK_NAME..."
    docker network create --driver overlay --attachable "$NETWORK_NAME" >/dev/null 2>&1 || true
    
    docker volume create volume_swarm_certificates >/dev/null 2>&1
    docker volume create portainer_data >/dev/null 2>&1
    
    # Garantir diretório de configuração em /root
    local SETUP_DIR="/root"
    # mkdir -p "$SETUP_DIR" # Já deve existir
    local CURRENT_DIR=$(pwd)
    cd "$SETUP_DIR" || exit

    # 5. Deploy Traefik
    log_info "Preparando Traefik em $SETUP_DIR..."
    cat > traefik.yml <<EOF
version: "3.7"
services:
  traefik:
    image: ghcr.io/traefik/traefik:v3.4.0
    command:
      - "--api.dashboard=true"
      - "--providers.swarm=true"
      - "--providers.docker.endpoint=unix:///var/run/docker.sock"
      - "--providers.docker.exposedbydefault=false"
      - "--providers.docker.network=$NETWORK_NAME"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencryptresolver.acme.email=$EMAIL_SSL"
      - "--log.level=DEBUG"
      - "--log.format=common"
      - "--accesslog=true"
    volumes:
      - vol_certificates:/etc/traefik/letsencrypt
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - $NETWORK_NAME
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
        - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
        - "traefik.http.routers.http-catchall.rule=Host(\`{host:.+}\`)"
        - "traefik.http.routers.http-catchall.entrypoints=web"
        - "traefik.http.routers.http-catchall.middlewares=redirect-https@docker"
        - "traefik.http.routers.http-catchall.priority=1"

volumes:
  vol_certificates:
    external: true
    name: volume_swarm_certificates

networks:
  $NETWORK_NAME:
    external: true
    attachable: true
    name: $NETWORK_NAME
EOF

    log_info "Implantando Traefik..."
    sleep 2
    if [ ! -f "traefik.yml" ]; then
        log_error "Arquivo traefik.yml não encontrado! Tentando criar novamente..."
        sleep 1
    fi
    docker stack deploy --prune --resolve-image always -c traefik.yml traefik
    wait_stack "traefik"
    
    # 6. Deploy Portainer
    log_info "Preparando Portainer..."
    sleep 2
    cat > portainer.yml <<EOF
version: "3.7"
services:
  agent:
    image: portainer/agent:latest
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - $NETWORK_NAME
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:latest
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - $NETWORK_NAME
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`$PORTAINER_DOMAIN\`)"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.docker.network=$NETWORK_NAME"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.priority=1"

volumes:
  portainer_data:
    external: true
    name: portainer_data

networks:
  $NETWORK_NAME:
    external: true
    attachable: true
    name: $NETWORK_NAME
EOF
    
    log_info "Implantando Portainer..."
    sleep 2
    if [ ! -f "portainer.yml" ]; then
        log_error "Arquivo portainer.yml não encontrado! Tentando criar novamente..."
        sleep 1
    fi
    docker stack deploy --prune --resolve-image always -c portainer.yml portainer
    
    log_info "Aguardando Portainer inicializar completamente..."
    wait_stack "portainer"
    sleep 5
    
    # 7. Criar Admin Portainer
    log_info "Preparando para criar conta admin no Portainer (30s)..."
    sleep 30

    log_info "Configurando usuário admin do Portainer..."
    local MAX_RETRIES=4
    local DELAY=15
    local CONTA_CRIADA=false
    
    for i in $(seq 1 $MAX_RETRIES); do
        # Tenta criar o usuário admin
        # Adicionado --resolve para garantir conexão local com o Traefik (evita erro 404 se DNS não propagou)
        RESPONSE=$(curl -k -s --resolve "$PORTAINER_DOMAIN:443:127.0.0.1" -X POST "https://$PORTAINER_DOMAIN/api/users/admin/init" \
            -H "Content-Type: application/json" \
            -d "{\"Username\": \"$PORTAINER_USER\", \"Password\": \"$PORTAINER_PASS\"}")
        
        # Verifica sucesso (JSON com Username)
        if echo "$RESPONSE" | grep -q "\"Username\":\"$PORTAINER_USER\""; then
            log_success "Admin Portainer criado com sucesso!"
            CONTA_CRIADA=true
            break
        elif echo "$RESPONSE" | grep -q "Users already exists"; then
            log_info "Usuário admin já existe no Portainer."
            CONTA_CRIADA=true
            break
        else
            log_info "Tentativa $i/$MAX_RETRIES falhou. Retentando em ${DELAY}s..."
            # Se for a última tentativa, exibe erro
            if [ $i -eq $MAX_RETRIES ]; then
                 log_error "Não foi possível criar a conta de administrador após $MAX_RETRIES tentativas."
                 log_error "Erro retornado: $RESPONSE"
            fi
            sleep $DELAY
        fi
    done

    if [ "$CONTA_CRIADA" = false ]; then
        log_error "Não foi possível configurar o admin do Portainer automaticamente."
        echo -e "${AMARELO}Por favor, acesse https://$PORTAINER_DOMAIN e crie a conta manualmente assim que possível.${RESET}"
    fi
    
    local TOKEN=""
    if [ "$CONTA_CRIADA" = true ]; then
        # Gerar Token JWT
        log_info "Gerando token de acesso..."
        sleep 5
        TOKEN=$(curl -k -s --resolve "$PORTAINER_DOMAIN:443:127.0.0.1" -X POST "https://$PORTAINER_DOMAIN/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"$PORTAINER_USER\",\"password\":\"$PORTAINER_PASS\"}" | jq -r .jwt)
            
        # Salvar dados Portainer
        mkdir -p /root/dados_vps
        cat > /root/dados_vps/dados_portainer.txt <<EOF
[ PORTAINER ]
URL: https://$PORTAINER_DOMAIN
User: $PORTAINER_USER
Pass: $PORTAINER_PASS
Token: $TOKEN
EOF
        chmod 600 /root/dados_vps/dados_portainer.txt
        log_success "Dados de acesso salvos em /root/dados_vps/dados_portainer.txt"
    fi
    
    # 8. Finalização da Infraestrutura
    echo ""
    log_success "Infraestrutura Swarm configurada com sucesso!"
    echo -e "${BRANCO}O ambiente está pronto para receber o OpenClaw.${RESET}"
    echo -e "${AMARELO}Retorne ao menu e selecione a Opção 2 para realizar o Deploy da Aplicação.${RESET}"
    
    # Limpeza do diretório temporário (Não remover arquivos gerados em /root)
    cd "$CURRENT_DIR" || true
    # rm -rf "$TEMP_SETUP_DIR"
}

# --- Instalação do OpenClaw (Smart Deploy) ---

setup_openclaw() {
    log_info "Iniciando Smart Deploy do OpenClaw (Swarm Mode)..."
    
    # Criar diretório de instalação se não existir
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR" || return
    
    log_success "Diretório de instalação preparado: $INSTALL_DIR"
    
    # Configurar permissões básicas
    prepare_persistence

    # --- Passo C: Deploy SWARM ---
    
    # Recuperar Rede Traefik
    local TRAEFIK_NET=$(detect_swarm_traefik)
    if [ -z "$TRAEFIK_NET" ]; then
        log_error "Swarm ativo, mas Traefik não detectado. Execute a Opção 1 (Swarm) novamente."
        return
    fi
    
    echo -en "${BRANCO}Digite o domínio para o OpenClaw (ex: openclaw.watink.com.br): ${RESET}"
    read -r DOMAIN
    [ -z "$DOMAIN" ] && DOMAIN="openclaw.watink.com.br"
    
    # Sugere domínio do canvas
    local default_canvas_domain=""
    if [[ "$DOMAIN" == openclaw.* ]]; then
        default_canvas_domain="${DOMAIN/openclaw./canvas.}"
    else
        default_canvas_domain="canvas.$DOMAIN"
    fi
    
    echo -en "${BRANCO}Digite o domínio para o Canvas (ex: $default_canvas_domain): ${RESET}"
    read -r CANVAS_DOMAIN
    [ -z "$CANVAS_DOMAIN" ] && CANVAS_DOMAIN="$default_canvas_domain"
    
    # Autenticação Opcional (Basic Auth no Traefik)
    local AUTH_HASH=""
    echo ""
    echo -e "Deseja proteger o acesso com senha (Basic Auth)?"
    echo -en "${BRANCO}[Y/n]: ${RESET}"
    read -r ENABLE_AUTH
    
    local AUTH_USER=""
    local AUTH_PASS=""
    
    if [[ "$ENABLE_AUTH" =~ ^[Yy]$ || -z "$ENABLE_AUTH" ]]; then
        echo -en "${BRANCO}Usuário (default: admin): ${RESET}"
        read -r AUTH_USER
        [ -z "$AUTH_USER" ] && AUTH_USER="admin"
        
        echo -en "${BRANCO}Senha: ${RESET}"
        read -rs AUTH_PASS
        echo ""
        
        log_info "Gerando hash de senha..."
        AUTH_HASH=$(docker run --rm --entrypoint htpasswd httpd:alpine -nb "$AUTH_USER" "$AUTH_PASS" 2>/dev/null)
        
        if [ -z "$AUTH_HASH" ] && command -v python3 &>/dev/null; then
             local pass_hash=$(python3 -c "import crypt; print(crypt.crypt('$AUTH_PASS', crypt.mksalt(crypt.METHOD_MD5)))" 2>/dev/null)
             [ -n "$pass_hash" ] && AUTH_HASH="$AUTH_USER:$pass_hash"
        fi
        
        if [ -n "$AUTH_HASH" ]; then
            # Salvar credenciais
            mkdir -p /root/dados_vps
            echo "URL: https://$DOMAIN" > /root/dados_vps/openclaw.txt
            echo "CANVAS URL: https://$CANVAS_DOMAIN" >> /root/dados_vps/openclaw.txt
            echo "USER: $AUTH_USER" >> /root/dados_vps/openclaw.txt
            echo "PASS: $AUTH_PASS" >> /root/dados_vps/openclaw.txt
            echo "NETWORK: $TRAEFIK_NET" >> /root/dados_vps/openclaw.txt
            chmod 600 /root/dados_vps/openclaw.txt
        fi
    fi
    
    # Gerar config Swarm (Passamos um token temporário)
    generate_swarm_config "$TRAEFIK_NET" "$DOMAIN" "$AUTH_HASH" "admin-token-123" "$CANVAS_DOMAIN"
    
    log_info "Baixando imagem oficial..."
    docker pull watink/openclaw:latest
    
    log_info "Realizando deploy da Stack via Portainer API (Modo Editável)..."
    if ! deploy_stack_via_api "openclaw" "/root/openclaw.yaml"; then
        log_error "Ocorreu um problema no deploy. Abortando processos automáticos."
        return 1
    fi
    
    # --- Automação de Onboarding ---
    log_info "Iniciando Onboarding Automático (Aguarde)..."
    sleep 5
    
    local random_token=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24 ; echo '')
    
    docker run --rm \
      -v /root/openclaw:/home/openclaw/.openclaw \
      watink/openclaw:latest \
      openclaw onboard --non-interactive --accept-risk --token "$random_token" >/dev/null 2>&1

    # Ajuste fino do openclaw.json para Swarm/Traefik (Solicitado pelo usuário)
    local json_file="/root/openclaw/openclaw.json"
    if [ -f "$json_file" ]; then
        log_info "Atualizando openclaw.json com configurações de DNS e Rede..."
        
        # Backup preventivo
        cp "$json_file" "${json_file}.bak"
        
        # Atualiza bind para 'lan' e configura trustedProxies para Traefik
        local tmp_json=$(mktemp)
        if jq --arg bind "lan" \
           '.gateway.bind = $bind | .gateway.trustedProxies = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]' \
           "$json_file" > "$tmp_json"; then
           
           mv "$tmp_json" "$json_file"
           # Garante permissões corretas (994 é o uid do usuário node/openclaw na imagem)
           chown -R 994:994 "/root/openclaw"
           chmod -R 700 "/root/openclaw"
           log_success "openclaw.json atualizado: Bind=lan, TrustedProxies=Configured"
        else
           log_warn "Falha ao atualizar openclaw.json com jq."
        fi
    fi

    # Forçar restart para carregar nova config
    docker service update --force openclaw_openclaw >/dev/null 2>&1
    
    log_success "Deploy e Configuração inicial concluídos!"
    show_openclaw_access
}

# --- Acesso ao Shell ---

enter_shell() {
    log_info "Tentando acessar o shell do container OpenClaw..."
    sync_tokens
    
    # Tenta encontrar container local em execução
    # Filtra por nome que contenha 'openclaw' e esteja rodando
    local container_id=$(docker ps --filter "name=openclaw_openclaw" --filter "status=running" --format "{{.ID}}" | head -n 1)
    
    if [ -n "$container_id" ]; then
        log_info "Container encontrado: $container_id"
        
        echo ""
        echo -e "${BRANCO}Comandos internos disponíveis no OpenClaw:${RESET}"
        echo -e "  - ${VERDE}openclaw onboard --install-daemon${RESET} : Executar o processo de integração"
        echo -e "  - ${VERDE}openclaw doctor${RESET}                   : Verificação rápida do sistema"
        echo -e "  - ${VERDE}openclaw status${RESET} + ${VERDE}health${RESET}      : Verificar integridade do gateway"
        echo -e "  - ${VERDE}openclaw channels login --channel whatsapp${RESET} : Gera QRCode do WhatsApp"
        echo -e "  - ${VERDE}openclaw gateway restart${RESET}          : Reinicia o gateway (útil após conectar)"
        echo -e "  - ${VERDE}/usr/local/bin/scan_skills.sh${RESET}     : Escaneia e instala novas skills"
        echo -e "  - ${VERDE}openclaw --help${RESET}                   : Ajuda geral do CLI"
        echo -e "  - ${VERDE}exit${RESET}                              : Sair do terminal"
        echo ""
        echo -e "${VERDE}Acessando container como usuário 'openclaw'...${RESET}"
        
        # Tenta bash, se falhar tenta sh. Força usuário openclaw para garantir permissões corretas
        docker exec -it -u openclaw "$container_id" /bin/bash || docker exec -it -u openclaw "$container_id" /bin/sh
    else
        log_error "Nenhum container do OpenClaw encontrado em execução neste nó."
        echo -e "${AMARELO}Se estiver usando Swarm em múltiplos nós, o container pode estar rodando em outro servidor.${RESET}"
        echo -e "${AMARELO}Tente: docker service ps openclaw_openclaw${RESET}"
    fi
}

# --- Limpeza ---

cleanup_vps() {
    log_info "Iniciando processo de remoção do OpenClaw..."
    echo ""
    echo -e "${VERMELHO}!!! ATENÇÃO !!!${RESET}"
    echo -e "Esta ação irá remover:"
    echo -e "  - A Stack 'openclaw' do Swarm"
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
    if docker stack ls >/dev/null 2>&1; then
        if docker stack ls | grep -q "openclaw"; then
            log_info "Removendo stack 'openclaw' do Swarm..."
            docker stack rm openclaw
            # Aguarda um pouco para garantir que os containers terminem
            log_info "Aguardando encerramento dos serviços (10s)..."
            sleep 10
        fi
    fi

    # 2. Remover Volumes (Forçar limpeza)
    log_info "Removendo volumes persistentes..."
    docker volume rm openclaw_config openclaw_workspace openclaw_home 2>/dev/null || true

    # 3. Remover Dados Persistentes e Credenciais
    log_info "Removendo dados persistentes (/root/openclaw) e credenciais..."
    rm -rf /root/openclaw
    rm -rf /root/dados_vps
    
    # 4. Remover Diretório
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Removendo diretório de instalação: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi

    # --- VERIFICAÇÃO FINAL ---
    log_info "Verificando se a limpeza foi completa..."
    local errors=0

    # Verifica Serviços
    if docker service ls --filter "name=openclaw" --format "{{.ID}}" | grep -q .; then
        log_warn "Ainda existem serviços 'openclaw' detectados."
        errors=$((errors+1))
    fi

    # Verifica Volumes
    if docker volume ls --filter "name=openclaw" --format "{{.Name}}" | grep -q .; then
        log_warn "Ainda existem volumes 'openclaw' detectados."
        errors=$((errors+1))
    fi

    # Verifica Diretórios
    if [ -d "$INSTALL_DIR" ] || [ -d "/root/openclaw" ]; then
        log_warn "Alguns diretórios não foram removidos."
        errors=$((errors+1))
    fi

    if [ $errors -eq 0 ]; then
        log_success "Limpeza verificada com SUCESSO! Tudo foi removido."
        log_info "Fechando o menu para limpar cache e estado..."
        sleep 2
        exit 0
    else
        log_error "A limpeza terminou com $errors pendências. Verifique manualmente."
    fi
}

uninstall_docker() {
    log_info "Iniciando desinstalação COMPLETA do Docker..."
    echo ""
    echo -e "${VERMELHO}!!! CUIDADO !!!${RESET}"
    echo -e "Esta ação irá remover:"
    echo -e "  - Docker Engine, CLI, Containerd, Docker Compose"
    echo -e "  - TODOS os containers, imagens, volumes e redes"
    echo -e "  - Diretórios /var/lib/docker e /var/lib/containerd"
    echo -e "  - Dados do OpenClaw (/root/openclaw e /root/dados_vps)"
    echo ""
    echo -en "${BRANCO}Tem certeza absoluta? [sim/N]: ${RESET}"
    read -r CONFIRM_DOCKER

    if [ "$CONFIRM_DOCKER" != "sim" ]; then
        log_info "Operação cancelada."
        return
    fi

    log_info "Parando serviços Docker..."
    systemctl stop docker.service docker.socket containerd.service >/dev/null 2>&1

    log_info "Removendo pacotes..."
    apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-compose-v2 docker-ce-rootless-extras >/dev/null 2>&1
    apt-get autoremove -y >/dev/null 2>&1

    log_info "Removendo diretórios de dados..."
    rm -rf /var/lib/docker
    rm -rf /var/lib/containerd
    rm -rf /etc/docker
    rm -rf /root/openclaw
    rm -rf /root/dados_vps
    
    # Remover arquivos de definição de stack Swarm
    rm -f /root/traefik.yml
    rm -f /root/portainer.yml
    
    # Remover instalação do OpenClaw também, já que sem docker não funciona
    if [ -d "$INSTALL_DIR" ]; then
         rm -rf "$INSTALL_DIR"
    fi

    # --- VERIFICAÇÃO FINAL ---
    log_info "Verificando desinstalação..."
    local errors=0

    if command -v docker &> /dev/null; then
        log_warn "O comando 'docker' ainda está disponível."
        errors=$((errors+1))
    fi

    if [ -d "/var/lib/docker" ]; then
        log_warn "O diretório /var/lib/docker ainda existe."
        errors=$((errors+1))
    fi

    if [ $errors -eq 0 ]; then
        log_success "Docker e OpenClaw foram removidos completamente."
        log_info "Fechando o menu para limpar cache e estado..."
        sleep 2
        exit 0
    else
        log_error "A desinstalação pode ter deixado resíduos. Verifique manualmente."
    fi
}


# --- Setup Sandbox ---
# Usa a imagem oficial de sandbox necessária para execução isolada de tools
setup_sandbox() {
    log_info "Configurando ambiente de Sandbox..."
    
    local sandbox_remote="watink/openclaw-sandbox:bookworm-slim"
    local sandbox_local="openclaw-sandbox:bookworm-slim"

    log_info "Verificando imagem oficial de sandbox: $sandbox_remote"
    
    if ! docker image inspect "$sandbox_remote" >/dev/null 2>&1; then
        log_info "Baixando imagem oficial de sandbox..."
        if ! docker pull "$sandbox_remote"; then
            log_error "Falha ao baixar imagem oficial de sandbox."
            return 1
        fi
    fi

    # Garante a tag local para compatibilidade com o resto do script/aplicação
    if ! docker image inspect "$sandbox_local" >/dev/null 2>&1; then
        log_info "Criando alias para imagem de sandbox..."
        docker tag "$sandbox_remote" "$sandbox_local"
    fi

    log_success "Ambiente de Sandbox configurado."
}

populate_swarm_volumes() {
    log_info "Verificando e populando volumes do Swarm..."
    # Configura pasta root/openclaw (Base para o Named Volume Bind)
    mkdir -p /root/openclaw/workspace/skills
    if [ -d "skills" ]; then
        log_info "Copiando skills iniciais para /root/openclaw/workspace/skills..."
        cp -rn skills/* /root/openclaw/workspace/skills/ 2>/dev/null || true
        chown -R 1000:1000 /root/openclaw
    fi
}

# --- Wizard Oficial ---


run_wizard() {
    log_info "Preparando para executar o Wizard de Configuração..."
    
    # Valida imagem
    if [ -z "$(docker images -q watink/openclaw:latest 2> /dev/null)" ]; then
        log_info "Imagem não encontrada. Baixando/Construindo..."
        docker pull watink/openclaw:latest || build_image
    fi
    
    log_info "Modo Swarm detectado (Volumes Nomeados)."

    log_info "Executando 'openclaw onboard'..."
    echo -e "${AMARELO}Siga as instruções na tela.${RESET}"
    echo -e "${AMARELO}NOTA: Se o processo exibir 'Onboarding complete' mas não sair automaticamente,${RESET}"
    echo -e "${AMARELO}pressione Ctrl+C para finalizar e continuar o setup.${RESET}"
    echo -e "${AMARELO}O assistente pode demorar alguns instantes para iniciar. Por favor, aguarde...${RESET}"
    echo ""
    
    local exit_code=0
    
    # Executa Wizard usando o named volume se ele já existir ou bind direto
    # Nota: Em modo interativo temporário, bind direto é mais simples e garante persistência em /root/openclaw
    docker run --rm -it \
        -v /root/openclaw:/home/openclaw/.openclaw \
        watink/openclaw:latest openclaw onboard
    exit_code=$?
    
    # Validação de sucesso
    local config_valid=0
    # Verifica no host (já que /root/openclaw reflete .openclaw)
    if grep -q "\"token\":" "/root/openclaw/openclaw.json" 2>/dev/null; then
         config_valid=1
    fi
    
    if [ $exit_code -eq 0 ] || [ $config_valid -eq 1 ]; then
        if [ $exit_code -ne 0 ]; then
             echo ""
             log_warn "O Wizard foi interrompido, mas uma configuração válida foi detectada."
             log_info "Prosseguindo com a pós-instalação..."
        else
             log_success "Wizard concluído com sucesso."
        fi
        

        # Ler novo token gerado pelo Wizard
        # Ler novo token gerado pelo Wizard
        local new_token=""
        if command -v jq &>/dev/null; then
            new_token=$(jq -r '.gateway.auth.token // empty' /root/openclaw/openclaw.json 2>/dev/null)
        else
            new_token=$(docker run --rm -v /root/openclaw:/data alpine \
                 sh -c "apk add --no-cache jq >/dev/null 2>&1; jq -r '.gateway.auth.token // empty' /data/openclaw.json 2>/dev/null")
        fi

        echo -e "${VERDE}Reiniciando gateway para aplicar alterações...${RESET}"
        
        # Swarm
        if docker service ps openclaw_openclaw >/dev/null 2>&1; then
             log_info "Modo Swarm detectado. Atualizando Stack no Portainer com novo token..."
             
             # Tentar recuperar configurações originais
             local domain=""
             if [ -f "/root/dados_vps/openclaw.txt" ]; then
                 # Extrai domínio da URL
                 domain=$(grep "URL: " /root/dados_vps/openclaw.txt | awk '{print $2}' | sed 's|http://||' | sed 's|https://||' | cut -d/ -f1)
             fi
             [ -z "$domain" ] && domain="openclaw.app.localhost"
             
             # Tentar recuperar domínio do Canvas
             local canvas_domain=""
             if [ -f "/root/dados_vps/openclaw.txt" ]; then
                 canvas_domain=$(grep "CANVAS URL: " /root/dados_vps/openclaw.txt | awk '{print $2}' | sed 's|http://||' | sed 's|https://||' | cut -d/ -f1)
             fi
             # Fallback: Se não encontrou, sugere baseado no domínio principal
             if [ -z "$canvas_domain" ]; then
                  if [[ "$domain" == openclaw.* ]]; then
                      canvas_domain="${domain/openclaw./canvas.}"
                  else
                      canvas_domain="canvas.$domain"
                  fi
             fi
             
             # Recuperar Rede Traefik
             local network_name=$(detect_swarm_traefik)
             
             # Se detecção falhar, tenta ler do arquivo salvo na instalação
             if [ -z "$network_name" ] && [ -f "/root/dados_vps/openclaw.txt" ]; then
                 network_name=$(grep "NETWORK: " /root/dados_vps/openclaw.txt | awk '{print $2}')
             fi
             
             # Último recurso (fallback padrão)
             [ -z "$network_name" ] && network_name="public_net"
             
             # Recuperar/Gerar Auth Hash
             local auth_hash=""
             local auth_user=$(grep "USER: " /root/dados_vps/openclaw.txt | awk '{print $2}')
             local auth_pass=$(grep "PASS: " /root/dados_vps/openclaw.txt | awk '{print $2}')
             
             if [ -n "$auth_user" ] && [ -n "$auth_pass" ]; then
                  log_info "Regerando hash de autenticação..."
                  auth_hash=$(docker run --rm --entrypoint htpasswd httpd:alpine -nb "$auth_user" "$auth_pass" 2>/dev/null)
                  if [ -z "$auth_hash" ] && command -v python3 &>/dev/null; then
                       local pass_hash=$(python3 -c "import crypt; print(crypt.crypt('$auth_pass', crypt.mksalt(crypt.METHOD_MD5)))" 2>/dev/null)
                       [ -n "$pass_hash" ] && auth_hash="$auth_user:$pass_hash"
                  fi
             fi
             
             # Regerar arquivo de configuração Swarm com o NOVO TOKEN e atualizar Stack
             if [ -n "$new_token" ]; then
                 generate_swarm_config "$network_name" "$domain" "$auth_hash" "$new_token" "$canvas_domain"
                 deploy_stack_via_api "openclaw" "/root/openclaw.yaml"
             else
                 log_warn "Novo token não encontrado. Forçando apenas restart do serviço..."
                 docker service update --force openclaw_openclaw
             fi
        fi
        
        echo -e "${VERDE}Sincronizando informações de conexão (Token)...${RESET}"
        setup_security_config "" ""
    else
        log_error "Wizard cancelado ou falhou."
    fi
}

# --- Utilitários de Canal e Gateway ---




generate_whatsapp_qrcode() {
    log_info "Iniciando geração de QR Code do WhatsApp..."
    sync_tokens
    
    # Swarm Mode
    local container_id=$(docker ps --filter "name=openclaw_openclaw" --filter "status=running" --format "{{.ID}}" | head -n 1)
    
    if [ -n "$container_id" ]; then
         log_info "Executando comando no container do Swarm..."
         docker exec -it -u openclaw "$container_id" openclaw channels login --channel whatsapp
    else
         log_error "Container do serviço OpenClaw não encontrado neste nó."
         echo -e "${AMARELO}Se estiver em um cluster multi-node, execute no nó onde a tarefa está rodando.${RESET}"
    fi
}


restart_gateway() {
    log_info "Reiniciando Gateway (Swarm Service)..."
    if docker service ps openclaw_openclaw >/dev/null 2>&1; then
         log_info "Forçando atualização do serviço (Rolling Restart)..."
         docker service update --force openclaw_openclaw
         log_success "Serviço atualizado."
    else
         log_error "Serviço openclaw_openclaw não encontrado no Swarm."
    fi
}

sync_tokens() {
    local config_file="/root/openclaw/openclaw.json"
    if [ -f "$config_file" ]; then
         local auth_token=$(jq -r '.gateway.auth.token // empty' "$config_file" 2>/dev/null)
         local remote_token=$(jq -r '.gateway.remote.token // empty' "$config_file" 2>/dev/null)
         
         if [ -n "$auth_token" ] && [ "$auth_token" != "$remote_token" ]; then
             log_info "Sincronizando token do Gateway para CLI (Remote Token)..."
             
             # Create temp file to store new config
             local tmp_conf=$(mktemp)
             if jq --arg token "$auth_token" '.gateway.remote.token = $token' "$config_file" > "$tmp_conf"; then
                 mv "$tmp_conf" "$config_file"
                 
                 # Fix permissions (994:994 is openclaw user in container)
                 chown 994:994 "$config_file"
                 chmod 700 "$config_file"
                 
                 log_success "Tokens sincronizados."
                 restart_gateway
             else
                 log_error "Falha ao atualizar token no openclaw.json"
                 rm -f "$tmp_conf"
             fi
         fi
    fi
}

show_openclaw_access() {
    header
    echo -e "${AZUL}=== Informações de Acesso ao OpenClaw ===${RESET}"
    
    local config_file="/root/openclaw/openclaw.json"
    if [ ! -f "$config_file" ] && [ -f "/root/openclaw/config/openclaw.json" ]; then
        config_file="/root/openclaw/config/openclaw.json"
    fi

    if [ ! -f "$config_file" ]; then
        log_error "Arquivo openclaw.json não encontrado. Certifique-se de que o deploy e onboarding foram concluídos."
        echo "Caminho esperado: /root/openclaw/openclaw.json"
        return
    fi
    
    local token=$(jq -r '.gateway.auth.token // empty' "$config_file" 2>/dev/null)
    local domain=$(grep "URL: " /root/dados_vps/openclaw.txt | awk '{print $2}' | sed 's|http://||;s|https://||')
    
    if [ -z "$domain" ]; then
        # Tenta pegar do openclaw.yaml se não estiver no txt
        domain=$(grep "Host(\`" /root/openclaw.yaml | head -n 1 | sed 's/.*Host(`\(.*\)`).*/\1/')
    fi

    if [ -n "$token" ]; then
        echo -e "${BRANCO}Domínio: ${VERDE}https://$domain ${RESET}"
        echo -e "${BRANCO}Token:   ${VERDE}$token ${RESET}"
        echo ""
        echo -e "${BRANCO}URL de Acesso Direto:${RESET}"
        echo -e "${AZUL}https://$domain/?token=$token ${RESET}"
        
        # Salvar para o usuário ver depois
        echo "TOKEN_ACESSO: $token" >> /root/dados_vps/openclaw.txt
        sort -u -o /root/dados_vps/openclaw.txt /root/dados_vps/openclaw.txt
    else
        log_warn "Token não encontrado no openclaw.json."
    fi
}

approve_device() {
    log_info "Gerenciamento de Dispositivos (Device Pairing)..."
    
    # Encontrar container localmente (necessário para docker exec)
    local container_id=$(docker ps --filter "name=openclaw_openclaw" --filter "status=running" --format "{{.ID}}" | head -n 1)

    if [ -n "$container_id" ]; then
        log_info "Container encontrado: $container_id"
        
        # Sincroniza tokens antes de listar dispositivos
        sync_tokens

        log_info "Listando dispositivos..."
        echo ""
        echo -e "${AMARELO}--- Lista de Dispositivos (Pareados e Pendentes) ---${RESET}"
        # Executa como usuário openclaw para ler a config correta na home do usuário
        docker exec -u openclaw "$container_id" openclaw devices list
        echo -e "${AMARELO}----------------------------------------------------${RESET}"
        echo -e "${BRANCO}Nota: Apenas dispositivos na seção 'Pending' precisam de aprovação.${RESET}"
        echo ""
        
        echo -e "${AZUL}Selecione o tipo de aprovação:${RESET}"
        echo -e "1) Aprovar dispositivo por ID (da lista acima)"
        echo -e "2) Aprovar pareamento por código (ex: WhatsApp/Telegram)"
        echo -e "0) Voltar"
        echo -en "${AMARELO}Opção: ${RESET}"
        read -r APPROVE_OPT
        
        if [ "$APPROVE_OPT" == "1" ]; then
            echo -en "${BRANCO}Digite o ID da requisição para aprovar (ou ENTER para sair): ${RESET}"
            read -r REQ_ID
            
            if [ -n "$REQ_ID" ]; then
                log_info "Tentando aprovar dispositivo $REQ_ID..."
                docker exec -u openclaw "$container_id" openclaw devices approve "$REQ_ID"
                
                if [ $? -eq 0 ]; then
                    log_success "Dispositivo aprovado com sucesso!"
                else
                    log_error "Falha ao aprovar dispositivo. Verifique o ID e tente novamente."
                fi
            else
                log_info "Operação cancelada."
            fi
        elif [ "$APPROVE_OPT" == "2" ]; then
            echo -en "${BRANCO}Digite o código de pareamento (ex: NRWEFA4K): ${RESET}"
            read -r PAIR_CODE
            
            if [ -n "$PAIR_CODE" ]; then
                echo -en "${BRANCO}Canal (padrão: whatsapp) [whatsapp/telegram/...]: ${RESET}"
                read -r CHANNEL
                [ -z "$CHANNEL" ] && CHANNEL="whatsapp"
                
                log_info "Tentando aprovar código '$PAIR_CODE' no canal '$CHANNEL'..."
                docker exec -u openclaw "$container_id" openclaw pairing approve "$CHANNEL" "$PAIR_CODE"
                
                if [ $? -eq 0 ]; then
                    log_success "Pareamento aprovado com sucesso!"
                else
                    log_error "Falha ao aprovar pareamento. Verifique o código e o canal."
                fi
            else
                log_info "Operação cancelada."
            fi
        else
            return
        fi
    else
        log_error "Container OpenClaw não encontrado neste nó."
        echo -e "${AMARELO}Se estiver em cluster Swarm, execute este comando no nó onde o container 'openclaw' está rodando.${RESET}"
    fi
}

# --- Gerenciamento de Skills ---

manage_skills() {
    while true; do
        header
        echo -e "${BRANCO}Gerenciamento de Skills (Capacidades):${RESET}"
        echo ""
        echo -e "Diretório de Skills: ${VERDE}$INSTALL_DIR/skills${RESET}"
        echo ""
        echo -e "${BRANCO}Skills Instaladas:${RESET}"
        
        # Listar skills locais
        if [ -d "$INSTALL_DIR/skills" ]; then
            # Lista apenas diretórios
            ls -F "$INSTALL_DIR/skills" | grep '/$' | sed 's/\///' | sed 's/^/  - /'
        else
            echo -e "  ${AMARELO}(Nenhuma skill encontrada)${RESET}"
        fi
        
        echo ""
        echo -e "${VERDE}1${BRANCO} - Instalar Nova Skill (Git URL)${RESET}"
        echo -e "${VERDE}2${BRANCO} - Atualizar Skills Oficiais (Git Pull)${RESET}"
        echo -e "${VERDE}3${BRANCO} - Forçar Scan/Instalação de Dependências${RESET}"
        echo -e "${VERDE}0${BRANCO} - Voltar${RESET}"
        echo ""
        echo -en "${AMARELO}Opção: ${RESET}"
        read -r OPCAO_SKILL
        
        case $OPCAO_SKILL in
            1)
                echo ""
                echo -e "${BRANCO}Digite a URL do repositório Git da Skill:${RESET}"
                read -r SKILL_URL
                if [ -n "$SKILL_URL" ]; then
                    if [ -f "$INSTALL_DIR/add_skill.sh" ]; then
                        cd "$INSTALL_DIR" || return
                        ./add_skill.sh "$SKILL_URL"
                        restart_gateway
                    else
                        log_error "Script add_skill.sh não encontrado em $INSTALL_DIR."
                    fi
                fi
                read -p "Pressione ENTER para continuar..."
                ;;
            2)
                log_info "Atualizando repositório oficial..."
                if [ -d "$INSTALL_DIR" ]; then
                    cd "$INSTALL_DIR" || return
                    git pull
                    log_success "Repositório atualizado. Novas skills oficiais (se houver) foram baixadas."
                    restart_gateway
                else
                    log_error "Diretório de instalação não encontrado."
                fi
                read -p "Pressione ENTER para continuar..."
                ;;
            3)
                log_info "Executando Scan de Skills dentro do container..."
                local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
                if [ -n "$container_id" ]; then
                    docker exec "$container_id" /usr/local/bin/scan_skills.sh
                    log_success "Scan concluído."
                else
                    log_error "Container OpenClaw não encontrado."
                fi
                read -p "Pressione ENTER para continuar..."
                ;;
            0)
                return
                ;;
            *)
                echo "Opção inválida."
                sleep 1
                ;;
        esac
    done
}

# --- Diagnóstico e Status ---

run_doctor() {
    log_info "Executando 'openclaw doctor'..."
    sync_tokens
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    if [ -n "$container_id" ]; then
         echo -e "${VERDE}>>> Executando diagnóstico...${RESET}"
         docker exec -it -u openclaw "$container_id" openclaw doctor
    else
         log_error "Container não encontrado."
    fi
}

run_status() {
    log_info "Verificando status do gateway..."
    sync_tokens
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    if [ -n "$container_id" ]; then
         echo -e "${AZUL}>>> Status:${RESET}"
         docker exec -it -u openclaw "$container_id" openclaw status
         echo ""
         echo -e "${AZUL}>>> Health:${RESET}"
         docker exec -it -u openclaw "$container_id" openclaw health
    else
         log_error "Container não encontrado."
    fi
}

run_dashboard() {
    log_info "Iniciando Dashboard..."
    sync_tokens
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    if [ -n "$container_id" ]; then
         docker exec -it -u openclaw "$container_id" openclaw dashboard
    else
         log_error "Container não encontrado."
    fi
}

configure_gateway_mode() {
    header
    echo -e "${AZUL}=== Configurar Modo de Operação (Gateway Mode) ===${RESET}"
    echo ""
    echo -e "${BRANCO}O OpenClaw pode operar em dois modos:${RESET}"
    echo -e "  1. ${VERDE}Local${RESET}  : Processamento local de mensagens (Padrão para Standalone)."
    echo -e "  2. ${VERDE}Remote${RESET} : Atua como ponte para outro servidor (Ex: Cloud/SaaS)."
    echo ""
    
    # Tenta pegar container ID
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    if [ -z "$container_id" ]; then
        container_id=$(docker ps --filter "name=openclaw_openclaw" --format "{{.ID}}" | head -n 1)
    fi

    if [ -n "$container_id" ]; then
        echo -e "Modo atual: $(docker exec -u openclaw "$container_id" openclaw config get gateway.mode 2>/dev/null || echo "Desconhecido")"
    else
        echo -e "Modo atual: ${AMARELO}Indisponível (Container offline)${RESET}"
    fi
    echo ""
    
    echo -en "${BRANCO}Escolha o modo [1-Local / 2-Remote]: ${RESET}"
    read -r MODE_OPT

    local MODE=""
    case $MODE_OPT in
        1) MODE="local" ;;
        2) MODE="remote" ;;
        *) 
           log_error "Opção inválida."
           return 
           ;;
    esac

    log_info "Configurando gateway.mode para: $MODE"
    
    if [ -n "$container_id" ]; then
        docker exec -u openclaw "$container_id" openclaw config set gateway.mode "$MODE"
        
        if [ $? -eq 0 ]; then
            log_success "Modo configurado com sucesso para '$MODE'."
            
            restart_gateway
        else
            log_error "Falha ao configurar modo."
        fi
    else
        log_error "Container OpenClaw não encontrado. Certifique-se que o sistema está rodando."
    fi
}


check_wizard_status() {
    if [ ! -f "/root/openclaw/openclaw.json" ] && [ ! -f "/root/openclaw/config/openclaw.json" ]; then
        echo ""
        log_error "Configuração não encontrada!"
        echo -e "${AMARELO}Esta funcionalidade requer que o OpenClaw esteja configurado.${RESET}"
        echo -e "${AMARELO}Por favor, execute o 'Wizard de Configuração (Opção 4)' primeiro.${RESET}"
        echo ""
        return 1
    fi
    return 0
}

reset_portainer_password() {
    header
    echo -e "${AZUL}=== Resetar Senha do Portainer ===${RESET}"
    echo ""
    echo -e "${AMARELO}Esta operação irá parar temporariamente o Portainer para resetar a senha do admin.${RESET}"
    echo -en "${BRANCO}Deseja continuar? [y/N]: ${RESET}"
    read -r CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Operação cancelada."
        return
    fi
    
    log_info "Iniciando processo de reset..."
    
    # Detectar Modo Swarm ou Standalone
    local is_swarm=false
    if docker service ls >/dev/null 2>&1 && docker service ls | grep -q "portainer"; then
        is_swarm=true
    fi
    
    if [ "$is_swarm" = true ]; then
        # --- MODO SWARM ---
        log_info "Modo Swarm detectado."
        
        # 1. Detectar nome do serviço
        local service_name=$(docker service ls --format '{{.Name}}' | grep "portainer" | head -n 1)
        if [ -z "$service_name" ]; then
            log_error "Serviço Portainer não encontrado no Swarm."
            return
        fi
        log_info "Serviço alvo: $service_name"
        
        # 2. Detectar Volume de Dados
        log_info "Inspecionando volume de dados..."
        local volume_name=$(docker service inspect "$service_name" --format '{{ range .Spec.TaskTemplate.ContainerSpec.Mounts }}{{ if eq .Target "/data" }}{{ .Source }}{{ end }}{{ end }}')
        
        if [ -z "$volume_name" ]; then
            log_warn "Não foi possível detectar o volume automaticamente. Tentando 'portainer_data'..."
            volume_name="portainer_data"
        fi
        log_info "Volume detectado: $volume_name"
        
        # 3. Escalar para 0
        log_info "Parando serviço (Scale 0)..."
        docker service scale "$service_name=0" >/dev/null
        
        log_info "Aguardando parada total (10s)..."
        sleep 10
        
        # 4. Rodar Helper
        log_info "Executando helper de reset..."
        local output=$(docker run --rm -v "$volume_name":/data portainer/helper-reset-password 2>&1)
        local new_pass=$(echo "$output" | grep "Password:" | awk '{print $2}')
        local full_output="$output"
        
        # 5. Restaurar Serviço
        log_info "Reiniciando serviço (Scale 1)..."
        docker service scale "$service_name=1" >/dev/null
        
        # Resultado
        if [ -n "$new_pass" ]; then
             echo ""
             echo -e "${VERDE}Senha resetada com SUCESSO!${RESET}"
             echo -e "${BRANCO}Nova Senha: ${VERDE}$new_pass${RESET}"
             echo ""
             echo -e "${AMARELO}Copie a senha acima.${RESET}"
             
             # Atualizar arquivo local
             if [ -f "/root/dados_vps/dados_portainer.txt" ]; then
                  sed -i "s/Pass: .*/Pass: $new_pass/" /root/dados_vps/dados_portainer.txt
                  log_success "Arquivo dados_portainer.txt atualizado."
             fi
        else
             log_error "Falha ao obter nova senha. Output:"
             echo "$full_output"
        fi
        
    else
        # --- MODO STANDALONE ---
        log_info "Modo Standalone detectado."
        
        # 1. Detectar Container
        local container_id=$(docker ps -a --filter "ancestor=portainer/portainer-ce:latest" --format "{{.ID}}" | head -n 1)
        if [ -z "$container_id" ]; then
             container_id=$(docker ps -a --filter "name=portainer" --format "{{.ID}}" | head -n 1)
        fi
        
        if [ -z "$container_id" ]; then
            log_error "Container Portainer não encontrado."
            return
        fi
        log_info "Container alvo: $container_id"
        
        # 2. Parar Container
        log_info "Parando container..."
        docker stop "$container_id"
        
        # 3. Detectar Volume (Inspecionar mounts)
        local volume_name=$(docker inspect "$container_id" --format '{{ range .Mounts }}{{ if eq .Destination "/data" }}{{ .Name }}{{ end }}{{ end }}')
        if [ -z "$volume_name" ]; then
             # Tenta Source se for bind mount
             volume_name=$(docker inspect "$container_id" --format '{{ range .Mounts }}{{ if eq .Destination "/data" }}{{ .Source }}{{ end }}{{ end }}')
        fi
        
        if [ -z "$volume_name" ]; then
             log_warn "Volume não detectado. Usando 'portainer_data'..."
             volume_name="portainer_data"
        fi
        
        # 4. Rodar Helper
        log_info "Executando helper..."
        local output=$(docker run --rm -v "$volume_name":/data portainer/helper-reset-password 2>&1)
        local new_pass=$(echo "$output" | grep "Password:" | awk '{print $2}')
        
        # 5. Iniciar Container
        log_info "Iniciando container..."
        docker start "$container_id"
        
        # Resultado
        if [ -n "$new_pass" ]; then
             echo ""
             echo -e "${VERDE}Senha resetada com SUCESSO!${RESET}"
             echo -e "${BRANCO}Nova Senha: ${VERDE}$new_pass${RESET}"
             
             if [ -f "/root/dados_vps/dados_portainer.txt" ]; then
                  sed -i "s/Pass: .*/Pass: $new_pass/" /root/dados_vps/dados_portainer.txt
                  log_success "Arquivo dados_portainer.txt atualizado."
             fi
        else
             log_error "Falha ao resetar. Output:"
             echo "$output"
        fi
    fi
}

update_openclaw_internal() {
    header
    echo -e "${AZUL}=== Atualizar OpenClaw (Via Container) ===${RESET}"
    echo ""
    echo -e "${AMARELO}Esta operação irá executar comandos de atualização DENTRO do container do OpenClaw.${RESET}"
    echo -e "${BRANCO}Isso é útil para atualizações rápidas de código (git pull) sem recriar o serviço.${RESET}"
    echo ""

    # Tenta encontrar container no Swarm (no nó local)
    local container_id=$(docker ps --filter "name=openclaw_openclaw" --filter "status=running" --format "{{.ID}}" | head -n 1)

    if [ -z "$container_id" ]; then
        log_error "Nenhum container do OpenClaw encontrado em execução neste nó. Execute isso no nó onde a tarefa está rodando."
        log_info "Certifique-se que a aplicação está rodando."
        return
    fi

    log_info "Container detectado: $container_id"
    echo ""
    echo -e "${BRANCO}Comando a ser executado:${RESET}"
    echo -e "${VERDE}git pull && npm install && npm run build && pm2 reload all${RESET}"
    echo ""
    echo -en "${BRANCO}Confirmar atualização? [y/N]: ${RESET}"
    read -r CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "Cancelado."
        return
    fi

    log_info "Executando atualização..."
    
    # Executa o comando
    if docker exec -it "$container_id" bash -c "git pull && npm install && npm run build && pm2 reload all"; then
        log_success "Atualização concluída com sucesso!"
    else
        log_error "Falha na atualização. Verifique os logs acima."
        echo -e "${AMARELO}Dica: O container pode não ter git/npm ou não ter acesso à internet.${RESET}"
    fi
    
    read -p "Pressione ENTER para continuar..."
}

# --- Ferramentas ---

menu_tools() {
    while true; do
        header
        echo -e "${AZUL}=== Ferramentas e Diagnóstico ===${RESET}"
        echo ""
        echo -e "${BRANCO}Selecione uma ferramenta:${RESET}"
        echo ""
        echo -e "${VERDE} 1${BRANCO} - Ver Logs de Serviço (OpenClaw, Portainer, Traefik)"
        echo -e "${VERDE} 2${BRANCO} - Resetar Senha Admin Portainer (Swarm/Standalone)"
        echo -e "${VERDE} 3${BRANCO} - Restart Forçado de Serviço"
        echo -e "${VERDE} 4${BRANCO} - Desinstalar Tudo (Nuke)"
        echo -e "${VERDE} 0${BRANCO} - Voltar ao Menu Principal"
        echo ""
        echo -en "${AMARELO}Opção: ${RESET}"
        read -r OPCAO_TOOLS

        case $OPCAO_TOOLS in
            1)
                tool_view_logs
                ;;
            2)
                check_root
                check_deps
                reset_portainer_password
                read -p "Pressione ENTER para continuar..."
                ;;
            3)
                tool_force_restart
                ;;
            4)
                check_root
                cleanup_vps
                read -p "Pressione ENTER para continuar..."
                ;;
            0)
                return
                ;;
            *)
                echo "Opção inválida."
                sleep 1
                ;;
        esac
    done
}

tool_view_logs() {
    echo ""
    echo -e "${AZUL}=== Visualizar Logs (Swarm) ===${RESET}"
    echo -e "1) OpenClaw"
    echo -e "2) Portainer"
    echo -e "3) Traefik"
    echo -en "${AMARELO}Escolha o serviço: ${RESET}"
    read -r LOG_OPT

    local service_swarm=""
    
    case $LOG_OPT in
        1) service_swarm="openclaw_openclaw";;
        2) service_swarm="portainer_portainer";; 
        3) service_swarm="openclaw_traefik";;
        *) echo "Opção inválida."; return;;
    esac

    # Detectar Swarm
    if docker service ls >/dev/null 2>&1; then
        # Refinar nome do serviço se necessário (ex: pode ser apenas 'portainer' se não for stack)
        if ! docker service ls --format '{{.Name}}' | grep -q "^$service_swarm$"; then
             # Tenta achar parcial
             local found_svc=$(docker service ls --format '{{.Name}}' | grep "$service_swarm" | head -n 1)
             if [ -n "$found_svc" ]; then 
                service_swarm="$found_svc" 
             else
                # Tenta fallback comum (ex: traefik ao invés de openclaw_traefik)
                local simple_name=$(echo "$service_swarm" | cut -d_ -f2)
                found_svc=$(docker service ls --format '{{.Name}}' | grep "$simple_name" | head -n 1)
                if [ -n "$found_svc" ]; then service_swarm="$found_svc"; fi
             fi
        fi
        
        log_info "Exibindo logs do serviço Swarm: $service_swarm"
        docker service logs -f --tail 100 "$service_swarm"
    else
        log_error "Swarm não detectado."
    fi
    read -p "Pressione ENTER para continuar..."
}

tool_force_restart() {
    echo ""
    echo -e "${AZUL}=== Restart Forçado (Swarm Service Update) ===${RESET}"
    echo -e "1) OpenClaw"
    echo -e "2) Portainer"
    echo -e "3) Traefik"
    echo -en "${AMARELO}Escolha o serviço: ${RESET}"
    read -r RST_OPT

    local service_swarm=""
    
    case $RST_OPT in
        1) service_swarm="openclaw_openclaw";;
        2) service_swarm="portainer_portainer";; 
        3) service_swarm="openclaw_traefik";;
        *) echo "Opção inválida."; return;;
    esac

    # Detectar Swarm
    if docker service ls >/dev/null 2>&1; then
        # Refinar nome do serviço
        if ! docker service ls --format '{{.Name}}' | grep -q "^$service_swarm$"; then
             local found_svc=$(docker service ls --format '{{.Name}}' | grep "$service_swarm" | head -n 1)
             if [ -n "$found_svc" ]; then 
                service_swarm="$found_svc" 
             else
                # Tenta fallback comum
                local simple_name=$(echo "$service_swarm" | cut -d_ -f2)
                found_svc=$(docker service ls --format '{{.Name}}' | grep "$simple_name" | head -n 1)
                if [ -n "$found_svc" ]; then service_swarm="$found_svc"; fi
             fi
        fi

        log_info "Forçando update do serviço Swarm: $service_swarm"
        docker service update --force "$service_swarm"
    else
        log_error "Swarm não detectado."
    fi
    read -p "Pressione ENTER para continuar..."
}

# --- Menu Principal ---

menu() {
    while true; do
        header
        echo -e "${BRANCO}Selecione uma opção:${RESET}"
        echo ""

        # Layout 2 colunas organizado
        printf "${AZUL}%-60s${AZUL}%-45s${RESET}\n" "--- Instalação & Configuração ---" "--- Operações Diárias ---"
        printf "${VERDE}%2s${BRANCO} - %-55s ${VERDE}%2s${BRANCO} - %s${RESET}\n" "1" "Setup Infraestrutura (Swarm)"     "5" "Gerenciar Skills (Plugins)"
        printf "${VERDE}%2s${BRANCO} - %-55s ${VERDE}%2s${BRANCO} - %s${RESET}\n" "2" "Deploy OpenClaw (Aplicação)"      "6" "Gerenciar Dispositivos (Pairing)"
        printf "${VERDE}%2s${BRANCO} - %-55s ${VERDE}%2s${BRANCO} - %s${RESET}\n" "3" "Wizard de Configuração (Onboard)" "7" "Gerar QR Code WhatsApp"
        printf "${VERDE}%2s${BRANCO} - %-55s ${VERDE}%2s${BRANCO} - %s${RESET}\n" "4" "Configurar Modo (Local/Remoto)"   "8" "Reiniciar Gateway"
        printf "%-60s ${VERDE}%2s${BRANCO} - %s${RESET}\n" "" "9" "Atualizar OpenClaw (Interno)"

        echo ""
        printf "${AZUL}%-60s${AZUL}%-45s${RESET}\n" "--- Diagnóstico & Acesso ---" "--- Manutenção & Sistema ---"
        printf "${VERDE}%2s${BRANCO} - %-55s ${VERDE}%2s${BRANCO} - %s${RESET}\n" "10" "Verificar Saúde (Doctor)"        "15" "Terminal do Container"
        printf "${VERDE}%2s${BRANCO} - %-55s ${VERDE}%2s${BRANCO} - %s${RESET}\n" "11" "Status do Gateway"               "16" "Resetar Senha do Portainer"
        printf "${VERDE}%2s${BRANCO} - %-55s ${VERMELHO}%2s${BRANCO} - %s${RESET}\n" "12" "Dashboard CLI"                   "17" "Limpar VPS (Remover OpenClaw)"
        printf "${VERDE}%2s${BRANCO} - %-55s ${VERMELHO}%2s${BRANCO} - %s${RESET}\n" "13" "Ver Logs do Sistema"             "18" "Desinstalar Docker (Remover TUDO)"
        printf "${VERDE}%2s${BRANCO} - %-55s ${VERDE}%2s${BRANCO} - %s${RESET}\n" "14" "Exibir Dados de Conexão"         "0" "Sair"

        echo ""
        echo -en "${AMARELO}Opção: ${RESET}"
        read -r OPCAO

        case $OPCAO in
            1)
                header
                echo -e "${AZUL}=== Setup Infraestrutura (Swarm) ===${RESET}"
                install_infrastructure
                read -p "Pressione ENTER para continuar..."
                ;;
            2)
                install_docker
                setup_sandbox
                setup_openclaw
                read -p "Pressione ENTER para continuar..."
                ;;
            3)
                run_wizard
                read -p "Pressione ENTER para continuar..."
                ;;
            4)
                check_wizard_status || { read -p "Pressione ENTER para continuar..."; continue; }
                configure_gateway_mode
                read -p "Pressione ENTER para continuar..."
                ;;
            5)
                check_wizard_status || { read -p "Pressione ENTER para continuar..."; continue; }
                manage_skills
                ;;
            6)
                check_wizard_status || { read -p "Pressione ENTER para continuar..."; continue; }
                approve_device
                read -p "Pressione ENTER para continuar..."
                ;;
            7)
                check_wizard_status || { read -p "Pressione ENTER para continuar..."; continue; }
                generate_whatsapp_qrcode
                read -p "Pressione ENTER para continuar..."
                ;;
            8)
                check_root
                restart_gateway
                read -p "Pressione ENTER para continuar..."
                ;;
            9)
                check_root
                check_wizard_status || { read -p "Pressione ENTER para continuar..."; continue; }
                update_openclaw_internal
                ;;
            10)
                run_doctor
                read -p "Pressione ENTER para continuar..."
                ;;
            11)
                run_status
                read -p "Pressione ENTER para continuar..."
                ;;
            12)
                run_dashboard
                read -p "Pressione ENTER para continuar..."
                ;;
            13)
                tool_view_logs
                ;;
            14)
                show_openclaw_access
                read -p "Pressione ENTER para continuar..."
                ;;
            15)
                enter_shell
                read -p "Pressione ENTER para continuar..."
                ;;
            16)
                reset_portainer_password
                read -p "Pressione ENTER para continuar..."
                ;;
            17)
                check_root
                cleanup_vps
                read -p "Pressione ENTER para continuar..."
                ;;
            18)
                check_root
                uninstall_docker
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
check_root
setup_hostname
check_deps
echo ""
echo -e "${VERDE}Configuração inicial concluída. Carregando menu...${RESET}"
sleep 2
menu