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

# Variáveis Globais de Armazenamento
STORAGE_MODE="host" # host | volume
VOLUME_NAME="openclaw_data"

# --- Helpers de Armazenamento ---

# Verifica se um arquivo de configuração existe
# $1: Caminho relativo dentro do config (ex: openclaw.json)
check_config_exists() {
    local file="$1"
    if [ "$STORAGE_MODE" = "volume" ]; then
        docker run --rm -v "$VOLUME_NAME:/data" alpine test -f "/data/$file"
        return $?
    else
        test -f "/root/openclaw/.openclaw/$file"
        return $?
    fi
}

# Lê conteúdo de um arquivo de configuração
# $1: Caminho relativo dentro do config
cat_config() {
    local file="$1"
    if [ "$STORAGE_MODE" = "volume" ]; then
        docker run --rm -v "$VOLUME_NAME:/data" alpine cat "/data/$file" 2>/dev/null
    else
        cat "/root/openclaw/.openclaw/$file" 2>/dev/null
    fi
}

# Escreve conteúdo em um arquivo de configuração (lê do stdin)
# $1: Caminho relativo dentro do config
write_config() {
    local file="$1"
    if [ "$STORAGE_MODE" = "volume" ]; then
        # Usa sh -c para redirecionamento dentro do container
        docker run --rm -i -v "$VOLUME_NAME:/data" alpine sh -c "cat > /data/$file && chown 1000:1000 /data/$file"
    else
        local full_path="/root/openclaw/.openclaw/$file"
        mkdir -p "$(dirname "$full_path")"
        cat > "$full_path"
        chown 1000:1000 "$full_path"
    fi
}

# Garante que o volume exista (se modo volume)
ensure_volume_exists() {
    if [ "$STORAGE_MODE" = "volume" ]; then
        if ! docker volume ls -q | grep -q "^${VOLUME_NAME}$"; then
            log_info "Criando volume Docker: $VOLUME_NAME"
            docker volume create "$VOLUME_NAME"
        fi
    fi
}

# --- Funções Visuais e Logs ---

header() {
    clear
    echo -e "${AZUL}## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##${RESET}"
    echo -e "${AZUL}##                                         SETUP OPENCLAW                                      ##${RESET}"
    echo -e "${AZUL}## // ## // ## // ## // ## // ## // ## // ## //## // ## // ## // ## // ## // ## // ## // ## // ##${RESET}"
    echo ""
    echo -e "                           ${BRANCO}Versão do Instalador: ${VERDE}v1.7.0${RESET}                "
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
    log_info "Atualizando repositórios e sistema..."
    apt-get update -qq >/dev/null 2>&1
    # Upgrade silencioso para garantir patches de segurança, como no SetupOrion
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq >/dev/null 2>&1 || log_info "Upgrade de sistema pulado ou finalizado com avisos."

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
    echo -e "${AZUL}=== Configuração Inicial ===${RESET}"
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
    log_info "Instalando Portainer Standalone..."
    
    echo -en "${BRANCO}Usuário Admin do Portainer (ex: admin): ${RESET}"
    read -r PORTAINER_USER
    [ -z "$PORTAINER_USER" ] && PORTAINER_USER="admin"
    
    echo -en "${BRANCO}Senha do Portainer (min 12 chars): ${RESET}"
    read -r PORTAINER_PASS

    docker run -d -p 9000:9000 -p 9443:9443 --name portainer \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest
        
    if [ $? -eq 0 ]; then
        log_success "Container do Portainer iniciado."
        local ip_addr=$(hostname -I | awk '{print $1}')
        echo -e "${AMARELO}Aguardando inicialização do Portainer em https://$ip_addr:9443 ...${RESET}"
        
        # Aguarda Portainer responder
        sleep 10
        local MAX_RETRIES=10
        local READY=false
        for i in $(seq 1 $MAX_RETRIES); do
             if curl -k -s -I "https://localhost:9443" >/dev/null 2>&1; then
                 READY=true
                 break
             fi
             sleep 5
        done
        
        if [ "$READY" = true ]; then
             log_info "Configurando usuário admin do Portainer..."
             # Cria Admin
             local RESPONSE=$(curl -k -s -X POST "https://localhost:9443/api/users/admin/init" \
                -H "Content-Type: application/json" \
                -d "{\"Username\": \"$PORTAINER_USER\", \"Password\": \"$PORTAINER_PASS\"}")
             
             if echo "$RESPONSE" | grep -q "\"Username\":\"$PORTAINER_USER\"" || echo "$RESPONSE" | grep -q "Users already exists"; then
                  log_success "Admin Portainer configurado."
                  
                  # Gera Token
                  local TOKEN=$(curl -k -s -X POST "https://localhost:9443/api/auth" \
                    -H "Content-Type: application/json" \
                    -d "{\"username\":\"$PORTAINER_USER\",\"password\":\"$PORTAINER_PASS\"}" | jq -r .jwt)
                  
                  # Salva credenciais
                  echo "Portainer URL: https://$ip_addr:9443" > /root/dados_vps/dados_portainer.txt
                  echo "User: $PORTAINER_USER" >> /root/dados_vps/dados_portainer.txt
                  echo "Pass: $PORTAINER_PASS" >> /root/dados_vps/dados_portainer.txt
                  echo "Token: $TOKEN" >> /root/dados_vps/dados_portainer.txt
                  log_success "Credenciais salvas em /root/dados_vps/dados_portainer.txt"
             else
                  log_error "Falha ao criar admin: $RESPONSE"
             fi
        else
             log_warn "Portainer demorou para responder. Configure o admin manualmente."
        fi
        
    else
        log_error "Falha ao instalar Portainer."
    fi
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
    if [ "$STORAGE_MODE" = "volume" ]; then
        log_info "Configurando volume de persistência Docker: $VOLUME_NAME..."
        ensure_volume_exists
        # Configura permissões e estrutura básica dentro do volume
        # mkdir -p garante que a estrutura exista
        docker run --rm -v "$VOLUME_NAME:/data" alpine sh -c "mkdir -p /data/workspace/skills && chown -R 1000:1000 /data"
        log_success "Volume $VOLUME_NAME pronto e configurado."
    else
        log_info "Configurando diretórios de persistência em /root/openclaw..."
        
        # Cria diretórios no host
        mkdir -p /root/openclaw/.openclaw/workspace/skills
        
        # Ajusta permissões para o usuário do container (UID 1000)
        # Isso evita erros de EACCES/Permission Denied
        chown -R 1000:1000 /root/openclaw
        
        log_success "Diretórios de persistência prontos."
    fi
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
        log_info "Configurando autenticação para o usuário: $(echo $auth_hash | cut -d: -f1)"
        middleware_config="
        - \"traefik.http.middlewares.openclaw-auth.basicauth.users=$auth_hash\"
        - \"traefik.http.routers.openclaw.middlewares=openclaw-auth\""
    fi

    # Configuração COMPLETA para Swarm (evita dependência do docker-compose.yml e erro de 'profiles')
    cat > docker-compose.swarm.yml <<EOF
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
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-$gateway_token}
      # Configurações Adicionais (OpenClaw Best Practices)
      - TZ=America/Sao_Paulo
      - NODE_ENV=production
    # Permite iniciar sem config para rodar o onboard depois
    command: ["openclaw", "gateway", "--allow-unconfigured"]
    healthcheck:
      test: ["CMD", "node", "dist/index.js", "health", "--json"]
      interval: 30s
      timeout: 10s
      retries: 3
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
        - "traefik.http.routers.openclaw.entrypoints=web"
        - "traefik.http.routers.openclaw.entrypoints=websecure"
        - "traefik.http.routers.openclaw.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.openclaw.loadbalancer.server.port=18789"
        # Canvas Host (Porta 18793)
        - "traefik.http.routers.openclaw-canvas.rule=Host(\`$canvas_domain\`)"
        - "traefik.http.routers.openclaw-canvas.entrypoints=web"
        - "traefik.http.routers.openclaw-canvas.entrypoints=websecure"
        - "traefik.http.routers.openclaw-canvas.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.openclaw-canvas.loadbalancer.server.port=18793"
    volumes:
      # Persistência via Volumes Nomeados (Padrão Swarm-Native)
      - openclaw_config:/home/openclaw/.openclaw
      - openclaw_workspace:/home/openclaw/workspace
      - openclaw_home:/home/openclaw
      # Socket do Docker para Sandboxing
      - /var/run/docker.sock:/var/run/docker.sock
$middleware_config

volumes:
  openclaw_config:
  openclaw_workspace:
  openclaw_home:

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

    # Tenta ler do host primeiro (mais robusto para Swarm)
    local config_content=""
    local host_config="/root/openclaw/.openclaw/openclaw.json"
    
    if [ -f "$host_config" ]; then
        config_content=$(cat "$host_config")
    fi
    
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
        echo "================================================================" > /root/dados_vps/openclaw.txt
        echo " DATA DE INSTALAÇÃO: $(date)" >> /root/dados_vps/openclaw.txt
        echo "================================================================" >> /root/dados_vps/openclaw.txt
        echo " TOKEN DE ACESSO (GATEWAY):" >> /root/dados_vps/openclaw.txt
        echo " $auth_token" >> /root/dados_vps/openclaw.txt
        echo "----------------------------------------------------------------" >> /root/dados_vps/openclaw.txt
        echo " LINK DIRETO DO DASHBOARD:" >> /root/dados_vps/openclaw.txt
        echo " $BASE_URL/?token=$auth_token" >> /root/dados_vps/openclaw.txt
        echo "================================================================" >> /root/dados_vps/openclaw.txt
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
    
    # Detecta modo (Swarm ou Standalone)
    local is_swarm=false
    if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
        is_swarm=true
    fi
    
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
    
    # Se não temos domínio, tenta localhost para standalone
    if [ -z "$p_domain" ] && [ "$is_swarm" = false ]; then
        p_domain="localhost:9443"
    fi
    
    # Se ainda não temos domínio, falha
    if [ -z "$p_domain" ]; then
        log_info "Domínio do Portainer não identificado. Usando deploy via CLI."
        if [ "$is_swarm" = true ]; then
            docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
        else
            docker compose -f "$compose_file" up -d
        fi
        return
    fi
    
    local portainer_url="https://$p_domain"
    
    # Se não temos token, tenta gerar
    if [ -z "$token" ] && [ -n "$p_user" ] && [ -n "$p_pass" ]; then
         log_info "Gerando token temporário para deploy via API..."
         token=$(curl -k -s --resolve "$p_domain:443:127.0.0.1" -X POST "$portainer_url/api/auth" \
            -H "Content-Type: application/json" \
            -d "{\"username\":\"$p_user\",\"password\":\"$p_pass\"}" | jq -r .jwt)
    fi

    if [ -z "$token" ] || [ "$token" == "null" ]; then
        log_warn "Não foi possível autenticar na API do Portainer. Usando deploy via CLI."
        if [ "$is_swarm" = true ]; then
            docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
        else
            docker compose -f "$compose_file" up -d
        fi
        return
    fi

    # Obter Endpoint ID (assume local/primary como o primeiro endpoint)
    local endpoint_id=$(curl -k -s -H "Authorization: Bearer $token" --resolve "$p_domain:443:127.0.0.1" "$portainer_url/api/endpoints" | jq -r '.[0].Id')
    
    if [ -z "$endpoint_id" ] || [ "$endpoint_id" == "null" ]; then
         log_warn "Falha ao obter Endpoint ID. Usando deploy via CLI."
         if [ "$is_swarm" = true ]; then
             docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
         else
             docker compose -f "$compose_file" up -d
         fi
         return
    fi
    
    # Arquivos temporários para capturar saída
    local response_output=$(mktemp)
    local error_output=$(mktemp)
    local file_content=$(cat "$compose_file")
    
    log_info "Tentando deploy via Portainer API (Stack: $stack_name, Endpoint: $endpoint_id, Mode: $(if $is_swarm; then echo Swarm; else echo Standalone; fi))..."

    # Verificar se a stack já existe
    local stack_id=$(curl -k -s -H "Authorization: Bearer $token" --resolve "$p_domain:443:127.0.0.1" "$portainer_url/api/stacks" | jq -r --arg name "$stack_name" '.[] | select(.Name == $name) | .Id')

    if [ -n "$stack_id" ] && [ "$stack_id" != "null" ]; then
         log_info "Stack '$stack_name' encontrada (ID: $stack_id). Atualizando via API..."
         
         # Preparar payload JSON seguro usando jq
         local payload=$(jq -n --arg content "$file_content" --argjson prune true '{StackFileContent: $content, Prune: $prune}')
         
         # Se Standalone, payload é diferente (EnvVars, etc) - mas para update simples pode ser similar
         # Na API v2, update de standalone stack usa PUT /stacks/{id}?endpointId={id}
         
         local http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X PUT \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            --resolve "$p_domain:443:127.0.0.1" \
            -d "$payload" \
            "$portainer_url/api/stacks/$stack_id?endpointId=$endpoint_id" 2> "$error_output")
            
         if [ "$http_code" -eq 200 ]; then
            log_success "Stack '$stack_name' atualizada com SUCESSO via Portainer API!"
         else
            log_error "Erro ao atualizar stack via API (HTTP $http_code)."
            log_error "Resposta: $(cat $response_output)"
            log_info "Tentando fallback via CLI..."
            if [ "$is_swarm" = true ]; then
                docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
            else
                docker compose -f "$compose_file" up -d
            fi
         fi
    else
        # API Request para CRIAR stack
        local http_code=0
        
        if [ "$is_swarm" = true ]; then
            # SWARM DEPLOY
            # Obter Swarm ID
            local swarm_id=$(curl -k -s -H "Authorization: Bearer $token" --resolve "$p_domain:443:127.0.0.1" "$portainer_url/api/endpoints/$endpoint_id/docker/swarm" | jq -r .ID)
            
            http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
            -H "Authorization: Bearer $token" \
            --resolve "$p_domain:443:127.0.0.1" \
            -F "Name=$stack_name" \
            -F "file=@$(pwd)/$compose_file" \
            -F "SwarmID=$swarm_id" \
            -F "endpointId=$endpoint_id" \
            "$portainer_url/api/stacks/create/swarm/file" 2> "$error_output")
        else
            # STANDALONE DEPLOY (Docker Compose)
            # API: POST /api/stacks/create/standalone/file
            # Form-Data: Name, file, endpointId, Env (json string)
            
            # Preparar variáveis de ambiente para injetar (Standlone precisa explícito)
            # OPENCLAW_CONFIG_PATH, TZ, NODE_ENV
            local env_json="[
                {\"name\": \"OPENCLAW_CONFIG_PATH\", \"value\": \"/root/openclaw/.openclaw\"},
                {\"name\": \"TZ\", \"value\": \"America/Sao_Paulo\"},
                {\"name\": \"NODE_ENV\", \"value\": \"production\"}
            ]"
            
            http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
            -H "Authorization: Bearer $token" \
            --resolve "$p_domain:443:127.0.0.1" \
            -F "Name=$stack_name" \
            -F "file=@$(pwd)/$compose_file" \
            -F "endpointId=$endpoint_id" \
            -F "Env=$env_json" \
            "$portainer_url/api/stacks/create/standalone/file" 2> "$error_output")
        fi
        
        if [ "$http_code" -eq 200 ]; then
            log_success "Deploy da stack '$stack_name' realizado com SUCESSO via Portainer API!"
            log_info "A stack agora deve aparecer como 'Total Control' no Portainer."
        elif [ "$http_code" -eq 409 ]; then
            log_warn "Stack '$stack_name' já existe no Portainer (Conflito detectado tardiamente). Atualizando via CLI..."
            if [ "$is_swarm" = true ]; then
                docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
            else
                docker compose -f "$compose_file" up -d
            fi
        else
            log_error "Erro no deploy via API (HTTP $http_code)."
            log_error "Resposta: $(cat $response_output)"
            log_error "Detalhes: $(cat $error_output)"
            log_info "Tentando fallback via CLI..."
            if [ "$is_swarm" = true ]; then
                docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
            else
                docker compose -f "$compose_file" up -d
            fi
        fi
    fi
    
    rm -f "$response_output" "$error_output"
}

# --- Instalação Completa (Swarm + Portainer + Traefik) ---

install_full_stack_swarm() {
    log_info "Iniciando Setup Completo (Docker Swarm + Portainer + Traefik + OpenClaw)..."
    
    # 0. Verificar conflitos / Limpeza prévia
    if docker info >/dev/null 2>&1 && docker stack ls >/dev/null 2>&1; then
        if docker stack ls | grep -qE "openclaw|traefik|portainer"; then
            echo ""
            echo -e "${AMARELO}Detectamos stacks existentes (openclaw, traefik ou portainer).${RESET}"
            echo -e "${VERMELHO}Para uma 'Instalação Completa', é recomendado limpar o ambiente anterior.${RESET}"
            echo -en "${BRANCO}Deseja remover as stacks antigas antes de continuar? [y/N]: ${RESET}"
            read -r CLEAN_INSTALL
            
            if [[ "$CLEAN_INSTALL" =~ ^[Yy]$ ]]; then
                log_info "Realizando limpeza de stacks..."
                docker stack rm openclaw traefik portainer 2>/dev/null
                log_info "Aguardando remoção dos serviços (20s)..."
                sleep 20
                
                # Opcional: Remover volumes se o usuário quiser reset total
                echo -en "${VERMELHO}Deseja apagar também os DADOS/VOLUMES antigos? (Irreversível) [y/N]: ${RESET}"
                read -r WIPE_DATA
                if [[ "$WIPE_DATA" =~ ^[Yy]$ ]]; then
                     docker volume rm openclaw_config openclaw_workspace openclaw_home volume_swarm_certificates portainer_data 2>/dev/null || true
                     rm -rf /root/openclaw
                     log_success "Dados antigos removidos."
                else
                     log_info "Volumes de dados foram mantidos."
                fi
            else
                log_info "Continuando sem limpeza (pode haver conflitos)..."
            fi
        fi
    fi

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
    
    # Garantir diretório temporário para arquivos de configuração
    local TEMP_SETUP_DIR="/tmp/openclaw_setup_$(date +%s)"
    mkdir -p "$TEMP_SETUP_DIR"
    local CURRENT_DIR=$(pwd)
    cd "$TEMP_SETUP_DIR" || exit

    # 5. Deploy Traefik
    log_info "Preparando Traefik em $TEMP_SETUP_DIR..."
    cat > traefik.yaml <<EOF
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
    docker stack deploy --prune --resolve-image always -c traefik.yaml traefik
    wait_stack "traefik"
    
    # 6. Deploy Portainer
    log_info "Preparando Portainer..."
    cat > portainer.yaml <<EOF
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
    docker stack deploy --prune --resolve-image always -c portainer.yaml portainer
    
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
    
    # Limpeza do diretório temporário
    cd "$CURRENT_DIR" || true
    rm -rf "$TEMP_SETUP_DIR"
}

# --- Instalação do OpenClaw (Smart Deploy) ---

setup_openclaw() {
    log_info "Iniciando Smart Deploy do OpenClaw..."
    
    # --- Passo A: Validação de Pré-requisitos (Smart Check) ---
    log_info "Verificando pré-requisitos de infraestrutura..."
    local error_found=false
    
    # 1. Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker não encontrado."
        error_found=true
    fi
    
    # 2. Persistência Central (/root/dados_vps)
    # No modo Standalone pode não ter dados_vps populado com portainer, mas deve existir se foi rodado o menu 1
    # Mas se o usuário rodou menu 1 standalone, deve ter criado.
    # Vamos ser flexíveis: se não existir, criamos, mas avisamos.
    if [ ! -d "/root/dados_vps" ]; then
         log_warn "Diretório /root/dados_vps não encontrado."
         # Não é erro fatal para standalone, mas é suspeito.
    fi
    
    # 3. Portainer (Verifica se algum container portainer está rodando)
    if ! docker ps --format '{{.Names}}' | grep -q "portainer"; then
         # Verifica se é service (Swarm)
         if ! docker service ls --format '{{.Name}}' | grep -q "portainer"; then
             log_error "Portainer não detectado (Container ou Serviço)."
             error_found=true
         fi
    fi
    
    if [ "$error_found" = true ]; then
        echo ""
        echo -e "${VERMELHO}⚠️  Erro: Infraestrutura não detectada ou incompleta.${RESET}"
        echo -e "${BRANCO}Por favor, execute a ${VERDE}Opção 1 (Instalação & Setup)${BRANCO} primeiro.${RESET}"
        return
    fi
    
    log_success "Infraestrutura validada."
    
    # --- Passo B: Detecção de Modo ---
    local DEPLOY_MODE="standalone"
    if [ "$(docker info --format '{{.Swarm.LocalNodeState}}')" == "active" ]; then
        DEPLOY_MODE="swarm"
        log_info "Modo detectado: SWARM"
    else
        log_info "Modo detectado: STANDALONE"
    fi
    
    # Preparar repositório
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Atualizando repositório em $INSTALL_DIR..."
        cd "$INSTALL_DIR" || exit
        git pull
    else
        log_info "Clonando repositório em $INSTALL_DIR..."
        git clone "$REPO_URL" "$INSTALL_DIR"
        cd "$INSTALL_DIR" || exit
    fi
    
    # Configurar permissões básicas
    chmod +x *.sh
    mkdir -p skills
    chmod 777 skills
    prepare_persistence
    # Ajuste de permissões
    chown -R 1000:1000 /root/openclaw

    # Copiar skills iniciais
    if [ -d "skills" ]; then
        mkdir -p /root/openclaw/.openclaw/workspace/skills
        cp -rn skills/* /root/openclaw/.openclaw/workspace/skills/ 2>/dev/null || true
        chown -R 1000:1000 /root/openclaw/.openclaw/workspace/skills
    fi

    # --- Passo C: Deploy ---
    
    if [ "$DEPLOY_MODE" == "swarm" ]; then
        # === DEPLOY SWARM ===
        
        # Recuperar Rede Traefik
        local TRAEFIK_NET=$(detect_swarm_traefik)
        if [ -z "$TRAEFIK_NET" ]; then
            log_error "Swarm ativo, mas Traefik não detectado. Execute a Opção 1 (Swarm) novamente."
            return
        fi
        
        echo -en "${BRANCO}Digite o domínio para o OpenClaw (ex: openclaw.app.localhost): ${RESET}"
        read -r DOMAIN
        [ -z "$DOMAIN" ] && DOMAIN="openclaw.app.localhost"
        
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
                echo "" >> /root/dados_vps/openclaw.txt
                echo " ACESSO WEB (SWARM):" >> /root/dados_vps/openclaw.txt
                echo " URL: http://$DOMAIN" >> /root/dados_vps/openclaw.txt
                echo " CANVAS URL: http://$CANVAS_DOMAIN" >> /root/dados_vps/openclaw.txt
                echo " USER: $AUTH_USER" >> /root/dados_vps/openclaw.txt
                echo " PASS: $AUTH_PASS" >> /root/dados_vps/openclaw.txt
                echo " NETWORK: $TRAEFIK_NET" >> /root/dados_vps/openclaw.txt
                chmod 600 /root/dados_vps/openclaw.txt
            fi
        fi
        
        # Token será gerado pelo Wizard, passamos vazio por enquanto
        generate_swarm_config "$TRAEFIK_NET" "$DOMAIN" "$AUTH_HASH" "" "$CANVAS_DOMAIN"
        
        log_info "Baixando imagem oficial..."
        docker pull watink/openclaw:latest || build_image
        
        log_info "Realizando deploy da Stack via Portainer API..."
        deploy_stack_via_api "openclaw" "docker-compose.swarm.yml"
        
        # --- Sincronia e Health Check ---
        log_info "Aguardando serviço estabilizar (Health Check)..."
        if check_service_health "openclaw_openclaw" 1 300; then
             log_success "Serviço OpenClaw está online e saudável!"
             populate_swarm_volumes
             sync_official_skills
             install_initial_skills
             
             echo ""
             echo -en "${BRANCO}Deseja iniciar o Wizard de Configuração (Onboard) agora? [Y/n]: ${RESET}"
             read -r RUN_WIZARD
             
             if [[ "$RUN_WIZARD" =~ ^[Yy]$ || -z "$RUN_WIZARD" ]]; then
                 setup_sandbox
                 run_wizard
             else
                 log_info "Wizard pulado. Você pode executá-lo manualmente depois pela Opção 4."
             fi
        else
             log_error "Falha ao iniciar o serviço OpenClaw. Abortando Wizard."
        fi
        
    else
        # === DEPLOY STANDALONE ===
        log_info "Iniciando deploy Standalone (Docker Compose via Portainer API)..."
        
        # Configurações de ambiente
        unset OPENCLAW_GATEWAY_TOKEN
        export OPENCLAW_CONFIG_PATH="/root/openclaw/.openclaw"
        export TZ="America/Sao_Paulo"
        export NODE_ENV="production"
        
        # Tenta deploy via API primeiro para ter controle total no Portainer
        # A função deploy_stack_via_api detecta se é Swarm ou Standalone baseado no contexto?
        # Precisamos adaptar deploy_stack_via_api para suportar Standalone (endpoint 1)
        
        # Gera o docker-compose.yml final com as variáveis substituídas se necessário,
        # mas como deploy_stack_via_api usa o arquivo, e o arquivo usa env vars do host no compose up,
        # para API do Portainer precisamos que o arquivo seja "autocontido" ou use env vars da stack.
        # O docker-compose.yml atual depende de variáveis de ambiente do shell (ex: ${OPENCLAW_CONFIG_PATH}).
        # O Portainer Standalone API (Stacks) permite definir EnvVars no payload.
        
        # Como fallback/simplicidade, vamos tentar usar o deploy_stack_via_api
        # mas precisamos garantir que ele saiba lidar com Standalone.
        # Vamos modificar deploy_stack_via_api para detectar o modo.
        
        deploy_stack_via_api "openclaw" "docker-compose.yml"
        
        # Se o deploy via API falhar, ele faz fallback para CLI (docker stack deploy),
        # mas docker stack deploy não funciona em Standalone.
        # O fallback do deploy_stack_via_api precisa ser "docker compose up -d" se for standalone.
        
        # Para garantir, vamos verificar se o serviço subiu
        log_info "Aguardando containers ficarem saudáveis..."
        
        # FIX: check_service_health usa 'docker service ls' que só funciona em Swarm.
        # Em Standalone, usamos 'docker compose ps' ou 'docker inspect'.
        # Removemos a chamada de check_service_health para standalone.
        
        local max_retries=30
        local count=0
        local healthy=false
        
        while [ $count -lt $max_retries ]; do
            # Verifica se o container existe e está Up
            if docker compose ps | grep "openclaw-gateway" | grep -q "Up"; then
                healthy=true
                break
            fi
            sleep 2
            count=$((count+1))
            echo -n "."
        done
        echo ""
        
        if [ "$healthy" = true ]; then
            log_success "OpenClaw iniciado com sucesso!"
            sync_official_skills
            install_initial_skills
            
            echo ""
            echo -en "${BRANCO}Deseja iniciar o Wizard de Configuração (Onboard) agora? [Y/n]: ${RESET}"
            read -r RUN_WIZARD_SA
            
            if [[ "$RUN_WIZARD_SA" =~ ^[Yy]$ || -z "$RUN_WIZARD_SA" ]]; then
                setup_sandbox
                run_wizard
            else
                log_info "Wizard pulado. Você pode executá-lo manualmente depois pela Opção 4."
            fi
        else
            log_error "Falha ao iniciar containers Standalone."
            docker compose logs --tail 20
        fi
    fi
}

# --- Acesso ao Shell ---

enter_shell() {
    log_info "Tentando acessar o shell do container OpenClaw..."
    
    # Tenta encontrar container local (funciona para Standalone e Swarm se estiver no node atual)
    # Filtra por nome que contenha 'openclaw' (ex: openclaw-openclaw-gateway-1 ou openclaw_openclaw.1.xxx)
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    
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
    if docker stack ls >/dev/null 2>&1; then
        if docker stack ls | grep -q "openclaw"; then
            log_info "Removendo stack 'openclaw' do Swarm..."
            docker stack rm openclaw
            # Aguarda um pouco para garantir que os containers terminem
            log_info "Aguardando encerramento dos serviços (10s)..."
            sleep 10
        fi
    fi

    # 2. Remover Containers Standalone (se existirem)
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR" || return
        if docker compose ls >/dev/null 2>&1; then
            if docker compose ls | grep -q "openclaw"; then
                 log_info "Parando e removendo containers Standalone..."
                 docker compose down -v --remove-orphans
            fi
        fi
    fi

    # 3. Remover Volumes (Forçar limpeza)
    log_info "Removendo volumes persistentes..."
    docker volume rm openclaw_config openclaw_workspace openclaw_home 2>/dev/null || true

    # 4. Remover Dados Persistentes e Credenciais
    log_info "Removendo dados persistentes (/root/openclaw) e credenciais..."
    rm -rf /root/openclaw
    rm -rf /root/dados_vps
    
    # 5. Remover Diretório
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Removendo diretório de instalação: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi

    # --- VERIFICAÇÃO FINAL ---
    log_info "Verificando se a limpeza foi completa..."
    local errors=0

    # Verifica Containers
    if docker ps -a --filter "name=openclaw" --format "{{.ID}}" | grep -q .; then
        log_warn "Ainda existem containers 'openclaw' detectados."
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
# Constrói a imagem base de sandbox necessária para execução isolada de tools
setup_sandbox() {
    log_info "Configurando ambiente de Sandbox (Docker-in-Docker)..."
    
    # Verifica se a imagem base de sandbox já existe
    if docker image inspect openclaw-sandbox:bookworm-slim >/dev/null 2>&1; then
        log_info "Imagem de sandbox 'openclaw-sandbox:bookworm-slim' já existe."
    else
        log_info "Construindo imagem base de sandbox (openclaw-sandbox:bookworm-slim)..."
        # Cria um Dockerfile temporário para a sandbox se necessário, 
        # ou usa o script oficial se estivesse disponível.
        # Como fallback, vamos criar uma imagem mínima baseada em debian:bookworm-slim
        
        TEMP_DIR=$(mktemp -d)
        cat <<EOF > "$TEMP_DIR/Dockerfile"
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    curl \
    git \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash sandbox
USER sandbox
WORKDIR /home/sandbox
EOF
        
        if docker build -t openclaw-sandbox:bookworm-slim "$TEMP_DIR"; then
            log_success "Imagem de sandbox construída com sucesso."
        else
            log_error "Falha ao construir imagem de sandbox."
        fi
        rm -rf "$TEMP_DIR"
    fi
}

populate_swarm_volumes() {
    log_info "Verificando e populando volumes do Swarm..."
    # Copia skills iniciais se existirem localmente e estivermos em Swarm (volumes nomeados)
    if [ -d "skills" ] && docker volume ls -q | grep -q "^openclaw_workspace$"; then
        log_info "Copiando skills iniciais para volume openclaw_workspace..."
         # Usa um container temporário para copiar
         docker run --rm \
            -v openclaw_workspace:/target \
            -v "$(pwd)/skills":/source \
            alpine sh -c "mkdir -p /target/skills && cp -rn /source/* /target/skills/ && chown -R 1000:1000 /target"
         log_success "Skills copiadas para o volume Swarm."
    fi
}

# --- Wizard Oficial ---

run_wizard() {
    log_info "Iniciando Wizard de Configuração Oficial (Onboard)..."
    
    if [ ! -d "$INSTALL_DIR" ]; then
        log_error "Diretório de instalação não encontrado ($INSTALL_DIR). Instale o OpenClaw primeiro."
        return
    fi
    
    cd "$INSTALL_DIR" || return
    
    # Verifica se a imagem existe
    if ! docker image inspect watink/openclaw:latest >/dev/null 2>&1; then
        log_info "Imagem não encontrada. Baixando/Construindo..."
        docker compose pull || build_image
    fi
    
    # Detecta modo Swarm (Volumes nomeados)
    local is_swarm=0
    if docker volume ls -q | grep -q "^openclaw_config$"; then
        is_swarm=1
        log_info "Modo Swarm detectado (Volumes Nomeados)."
    else
        # Modo Standalone: Garante que os diretórios de persistência existem
        export OPENCLAW_CONFIG_PATH="/root/openclaw/.openclaw"
        prepare_persistence
    fi

    log_info "Executando 'openclaw onboard'..."
    echo -e "${AMARELO}Siga as instruções na tela.${RESET}"
    echo -e "${AMARELO}NOTA: Se o processo exibir 'Onboarding complete' mas não sair automaticamente,${RESET}"
    echo -e "${AMARELO}pressione Ctrl+C para finalizar e continuar o setup.${RESET}"
    echo -e "${AMARELO}O assistente pode demorar alguns instantes para iniciar. Por favor, aguarde...${RESET}"
    echo ""
    
    local exit_code=0
    
    if [ $is_swarm -eq 1 ]; then
        # Executa Wizard usando volumes nomeados diretamente
        # Usa -it para interatividade
        docker run --rm -it \
            -v openclaw_config:/home/openclaw/.openclaw \
            -v openclaw_workspace:/home/openclaw/workspace \
            -v openclaw_home:/home/openclaw \
            watink/openclaw:latest openclaw onboard
        exit_code=$?
    else
        # Executa o serviço CLI definido no docker-compose.yml (Standalone)
        docker compose run --rm openclaw-cli onboard
        exit_code=$?
    fi
    
    # Validação de sucesso
    local config_valid=0
    if [ $is_swarm -eq 1 ]; then
        # Verifica no volume
        if docker run --rm -v openclaw_config:/data alpine grep -q "\"token\":" "/data/openclaw.json" 2>/dev/null; then
             config_valid=1
        fi
    else
        # Verifica no host
        if [ -f "/root/openclaw/.openclaw/openclaw.json" ]; then
             if grep -q "\"token\":" "/root/openclaw/.openclaw/openclaw.json"; then
                 config_valid=1
             fi
        fi
    fi
    
    if [ $exit_code -eq 0 ] || [ $config_valid -eq 1 ]; then
        if [ $exit_code -ne 0 ]; then
             echo ""
             log_warn "O Wizard foi interrompido, mas uma configuração válida foi detectada."
             log_info "Prosseguindo com a pós-instalação..."
        else
             log_success "Wizard concluído com sucesso."
        fi
        
        # --- FIX: Forçar Bind LAN no openclaw.json ---
        log_info "Forçando bind='lan' no openclaw.json..."
        
        if [ $is_swarm -eq 1 ]; then
             # Ajuste via container temporário (Swarm/Volume)
             docker run --rm -v openclaw_config:/data watink/openclaw:latest \
                 sh -c "if [ -f /home/openclaw/.openclaw/openclaw.json ]; then \
                        apk add --no-cache jq >/dev/null 2>&1 || true; \
                        if command -v jq >/dev/null; then \
                            jq '.gateway.bind = \"lan\"' /home/openclaw/.openclaw/openclaw.json > /tmp/tmp.json && \
                            mv /tmp/tmp.json /home/openclaw/.openclaw/openclaw.json && \
                            chown 1000:1000 /home/openclaw/.openclaw/openclaw.json; \
                        fi; \
                        fi"
             log_success "Configuração de bind atualizada (Volume Mode)."
        else
             # Ajuste via host (Standalone)
             if [ -f "/root/openclaw/.openclaw/openclaw.json" ]; then
                 local tmp_json=$(mktemp)
                 if command -v jq &> /dev/null; then
                     jq '.gateway.bind = "lan"' "/root/openclaw/.openclaw/openclaw.json" > "$tmp_json"
                     if [ -s "$tmp_json" ]; then
                         mv "$tmp_json" "/root/openclaw/.openclaw/openclaw.json"
                         chown 1000:1000 "/root/openclaw/.openclaw/openclaw.json"
                         log_success "Configuração de bind atualizada para LAN."
                     fi
                 else
                     log_warn "jq não encontrado. Não foi possível ajustar o bind."
                 fi
                 rm -f "$tmp_json"
             fi
        fi

        # Ler novo token gerado pelo Wizard
        local new_token=""
        if [ $is_swarm -eq 1 ]; then
             new_token=$(docker run --rm -v openclaw_config:/data watink/openclaw:latest \
                 sh -c "apk add --no-cache jq >/dev/null 2>&1 || true; jq -r '.gateway.auth.token // empty' /home/openclaw/.openclaw/openclaw.json 2>/dev/null")
        else
             if [ -f "/root/openclaw/.openclaw/openclaw.json" ]; then
                  new_token=$(jq -r '.gateway.auth.token // empty' "/root/openclaw/.openclaw/openclaw.json")
             fi
        fi

        echo -e "${VERDE}Reiniciando gateway para aplicar alterações...${RESET}"
        
        # Standalone
        if [ -f "docker-compose.yml" ] && [ $is_swarm -eq 0 ]; then
             if [ -n "$new_token" ]; then
                 export OPENCLAW_GATEWAY_TOKEN="$new_token"
             fi
             docker compose restart openclaw-gateway
        fi
        
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
                 deploy_stack_via_api "openclaw" "docker-compose.swarm.yml"
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

force_bind_lan() {
    log_info "Forçando bind='lan' no openclaw.json (Correção para Acesso Externo)..."
    
    if [ ! -f "/root/openclaw/.openclaw/openclaw.json" ]; then
        log_error "Arquivo de configuração não encontrado em /root/openclaw/.openclaw/openclaw.json"
        return
    fi
    
    local tmp_json=$(mktemp)
    # Verifica se jq está disponível
    if command -v jq &> /dev/null; then
        jq '.gateway.bind = "lan"' "/root/openclaw/.openclaw/openclaw.json" > "$tmp_json"
        if [ -s "$tmp_json" ]; then
            mv "$tmp_json" "/root/openclaw/.openclaw/openclaw.json"
            chown 1000:1000 "/root/openclaw/.openclaw/openclaw.json"
            log_success "Configuração de bind atualizada para LAN."
            
            # Pergunta se deseja reiniciar
            echo -en "${BRANCO}Deseja reiniciar o Gateway agora para aplicar? [Y/n]: ${RESET}"
            read -r RESTART_NOW
            if [[ "$RESTART_NOW" =~ ^[Yy]$ || -z "$RESTART_NOW" ]]; then
                restart_gateway
            fi
        else
            log_warn "Falha ao atualizar openclaw.json (saída vazia)."
        fi
    else
        log_error "jq não encontrado. Instale jq para usar esta função."
    fi
    rm -f "$tmp_json"
}

generate_whatsapp_qrcode() {
    log_info "Iniciando geração de QR Code do WhatsApp..."
    
    if [ ! -d "$INSTALL_DIR" ]; then
        log_error "Diretório de instalação não encontrado ($INSTALL_DIR)."
        return
    fi
    
    cd "$INSTALL_DIR" || return

    # Verifica se estamos em Swarm ou Standalone
    if docker service ps openclaw_openclaw >/dev/null 2>&1; then
        # Swarm Mode
        local container_id=$(docker ps --filter "name=openclaw_openclaw" --format "{{.ID}}" | head -n 1)
        if [ -n "$container_id" ]; then
             log_info "Executando comando no container do Swarm..."
             docker exec -it "$container_id" openclaw channels login --channel whatsapp
        else
             log_error "Container do serviço OpenClaw não encontrado neste nó (pode estar em outro nó do cluster)."
        fi
    else
        # Standalone Mode
        log_info "Executando via container CLI..."
        # Usa o serviço CLI definido no compose para garantir o ambiente correto
        docker compose run --rm openclaw-cli channels login --channel whatsapp
    fi
}

restart_gateway() {
    log_info "Reiniciando Gateway OpenClaw..."
     
    # Mesma lógica do menu 4 (enter_shell) para encontrar o container
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    
    if [ -n "$container_id" ]; then
        log_info "Container encontrado: $container_id"
        log_info "Executando 'openclaw gateway restart'..."
        docker exec "$container_id" openclaw gateway restart
        log_success "Comando enviado com sucesso."
    else
        # Fallback para Swarm se não achar container local (ex: rodando em outro nó)
        if docker service ps openclaw_openclaw >/dev/null 2>&1; then
             log_info "Container não encontrado localmente, mas serviço Swarm detectado."
             log_info "Forçando atualização do serviço (Rolling Restart)..."
             docker service update --force openclaw_openclaw
             log_success "Serviço atualizado."
        else
             log_error "Nenhum container do OpenClaw encontrado em execução neste nó."
             echo -e "${AMARELO}Se estiver usando Swarm em múltiplos nós, o container pode estar em outro servidor.${RESET}"
        fi
    fi
}

approve_device() {
    log_info "Gerenciamento de Dispositivos (Device Pairing)..."
    
    # Encontrar container (Lógica unificada de busca)
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    
    # Se não achou por nome simples, tenta padrão Swarm no nó local
    if [ -z "$container_id" ]; then
        container_id=$(docker ps --filter "name=openclaw_openclaw" --format "{{.ID}}" | head -n 1)
    fi

    if [ -n "$container_id" ]; then
        log_info "Container encontrado: $container_id"
        
        # FIX: Ensure CLI has the token (sync auth.token to remote.token)
        local config_file="/root/openclaw/.openclaw/openclaw.json"
        if [ -f "$config_file" ]; then
             local auth_token=$(jq -r '.gateway.auth.token // empty' "$config_file" 2>/dev/null)
             local remote_token=$(jq -r '.gateway.remote.token // empty' "$config_file" 2>/dev/null)
             
             if [ -n "$auth_token" ] && [ "$auth_token" != "$remote_token" ]; then
                 log_info "Sincronizando token do cliente CLI para permitir comandos locais..."
                 local tmp_conf=$(mktemp)
                 jq --arg token "$auth_token" '.gateway.remote.token = $token' "$config_file" > "$tmp_conf" && mv "$tmp_conf" "$config_file"
             fi
        fi

        log_info "Listando requisições de pareamento pendentes..."
        echo ""
        echo -e "${AMARELO}--- Requisições Pendentes ---${RESET}"
        docker exec "$container_id" openclaw devices list
        echo -e "${AMARELO}-----------------------------${RESET}"
        echo ""
        
        echo -en "${BRANCO}Digite o ID da requisição para aprovar (ou ENTER para sair): ${RESET}"
        read -r REQ_ID
        
        if [ -n "$REQ_ID" ]; then
            log_info "Tentando aprovar dispositivo $REQ_ID..."
            docker exec "$container_id" openclaw devices approve "$REQ_ID"
            
            if [ $? -eq 0 ]; then
                log_success "Dispositivo aprovado com sucesso!"
            else
                log_error "Falha ao aprovar dispositivo. Verifique o ID e tente novamente."
            fi
        else
            log_info "Operação cancelada."
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
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    if [ -n "$container_id" ]; then
         echo -e "${VERDE}>>> Executando diagnóstico...${RESET}"
         docker exec -it "$container_id" openclaw doctor
    else
         log_error "Container não encontrado."
    fi
}

run_status() {
    log_info "Verificando status do gateway..."
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    if [ -n "$container_id" ]; then
         echo -e "${AZUL}>>> Status:${RESET}"
         docker exec -it "$container_id" openclaw status
         echo ""
         echo -e "${AZUL}>>> Health:${RESET}"
         docker exec -it "$container_id" openclaw health
    else
         log_error "Container não encontrado."
    fi
}

run_dashboard() {
    log_info "Iniciando Dashboard..."
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    if [ -n "$container_id" ]; then
         docker exec -it "$container_id" openclaw dashboard
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
        echo -e "Modo atual: $(docker exec "$container_id" openclaw config get gateway.mode 2>/dev/null || echo "Desconhecido")"
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
        docker exec "$container_id" openclaw config set gateway.mode "$MODE"
        
        if [ $? -eq 0 ]; then
            log_success "Modo configurado com sucesso para '$MODE'."
            
            echo -en "${BRANCO}Deseja reiniciar o Gateway agora para aplicar? [Y/n]: ${RESET}"
            read -r RESTART_NOW
            if [[ "$RESTART_NOW" =~ ^[Yy]$ || -z "$RESTART_NOW" ]]; then
                restart_gateway
            fi
        else
            log_error "Falha ao configurar modo."
        fi
    else
        log_error "Container OpenClaw não encontrado. Certifique-se que o sistema está rodando."
    fi
}

push_to_hub_menu() {
    header
    echo -e "${AZUL}=== Enviar Imagem para DockerHub ===${RESET}"
    echo ""
    echo -e "${BRANCO}Esta opção irá reconstruir a imagem e enviá-la para o DockerHub.${RESET}"
    echo -e "${BRANCO}Certifique-se de estar logado no Docker (${VERDE}docker login${RESET})${BRANCO}.${RESET}"
    echo ""
    echo -en "${BRANCO}Digite seu usuário do DockerHub (ex: watink): ${RESET}"
    read -r DOCKER_USER
    
    if [ -z "$DOCKER_USER" ]; then
        log_error "Usuário não informado."
        return
    fi
    
    echo ""
    log_info "Iniciando processo de push para usuário: $DOCKER_USER"
    
    if [ -f "$INSTALL_DIR/push_to_hub.sh" ]; then
        cd "$INSTALL_DIR" || return
        # Garante permissão de execução
        chmod +x push_to_hub.sh
        ./push_to_hub.sh "$DOCKER_USER"
    else
        log_error "Script push_to_hub.sh não encontrado em $INSTALL_DIR"
    fi
}

# --- Menu Principal ---

menu() {
    while true; do
        header
        echo -e "${BRANCO}Selecione uma opção:${RESET}"
        echo ""
        echo -e "${AZUL}--- Instalação & Setup ---${RESET}"
        echo -e "${VERDE}1${BRANCO} - Setup Infraestrutura (Swarm/Standalone)${RESET}"
        echo -e "${VERDE}2${BRANCO} - Deploy OpenClaw (Aplicação)${RESET}"
        echo -e "${VERDE}3${BRANCO} - Apenas Instalar Docker${RESET}"
        echo ""
        echo -e "${AZUL}--- Configuração & Gestão ---${RESET}"
        echo -e "${VERDE}4${BRANCO} - Wizard de Configuração (Onboard)${RESET}"
        echo -e "${VERDE}5${BRANCO} - Gerenciar Skills (Plugins)${RESET}"
        echo -e "${VERDE}6${BRANCO} - Gerenciar Dispositivos (Pairing)${RESET}"
        echo -e "${VERDE}7${BRANCO} - Gerar QR Code WhatsApp${RESET}"
        echo -e "${VERDE}8${BRANCO} - Configurar Modo (Local/Remoto)${RESET}"
        echo -e "${VERDE}9${BRANCO} - Configurar Bind para LAN (Acesso Externo)${RESET}"
        echo -e "${VERDE}20${BRANCO} - Alterar Hostname${RESET}"
        echo ""
        echo -e "${AZUL}--- Diagnóstico & Logs ---${RESET}"
        echo -e "${VERDE}10${BRANCO} - Verificar Saúde (Doctor)${RESET}"
        echo -e "${VERDE}11${BRANCO} - Status do Gateway${RESET}"
        echo -e "${VERDE}12${BRANCO} - Dashboard CLI${RESET}"
        echo -e "${VERDE}13${BRANCO} - Ver Logs do OpenClaw${RESET}"
        echo ""
        echo -e "${AZUL}--- Ferramentas & Acesso ---${RESET}"
        echo -e "${VERDE}14${BRANCO} - Terminal do Container${RESET}"
        echo -e "${VERDE}15${BRANCO} - Reiniciar Gateway${RESET}"
        echo -e "${VERDE}16${BRANCO} - Exibir Dados de Conexão (Token)${RESET}"
        echo ""
        echo -e "${AZUL}--- Desenvolvimento ---${RESET}"
        echo -e "${VERDE}17${BRANCO} - Enviar Imagem para DockerHub (Build & Push)${RESET}"
        echo ""
        echo -e "${AZUL}--- Sistema (Danger Zone) ---${RESET}"
        echo -e "${VERMELHO}18${BRANCO} - Limpar VPS (Remover OpenClaw)${RESET}"
        echo -e "${VERMELHO}19${BRANCO} - Desinstalar Docker (Remover TUDO)${RESET}"
        echo -e "${VERDE}0${BRANCO} - Sair${RESET}"
        echo ""
        echo -en "${AMARELO}Opção: ${RESET}"
        read -r OPCAO

        case $OPCAO in
            1)
                check_root
                check_deps
                ensure_docker_permission
                
                header
                echo -e "${AZUL}=== Setup Infraestrutura ===${RESET}"
                echo -e "${BRANCO}Qual tipo de ambiente deseja preparar?${RESET}"
                echo -e "${VERDE}1${BRANCO} - Standalone (Docker + Portainer Local)${RESET}"
                echo -e "${VERDE}2${BRANCO} - Swarm (Cluster + Traefik + Portainer)${RESET}"
                echo -e "${VERDE}0${BRANCO} - Voltar${RESET}"
                echo ""
                echo -en "${AMARELO}Opção: ${RESET}"
                read -r ENV_OPT
                
                if [ "$ENV_OPT" == "1" ]; then
                     install_docker
                     install_portainer_standalone
                     read -p "Pressione ENTER para continuar..."
                elif [ "$ENV_OPT" == "2" ]; then
                     install_full_stack_swarm
                     read -p "Pressione ENTER para continuar..."
                elif [ "$ENV_OPT" == "0" ]; then
                     # Apenas retorna ao loop principal
                     :
                else
                     log_error "Opção inválida."
                     read -p "Pressione ENTER para continuar..."
                fi
                ;;
            2)
                check_root
                check_deps
                ensure_docker_permission
                install_docker
                setup_sandbox
                setup_openclaw
                read -p "Pressione ENTER para continuar..."
                ;;
            3)
                check_root
                check_deps
                install_docker
                read -p "Pressione ENTER para continuar..."
                ;;
            4)
                check_root
                run_wizard
                read -p "Pressione ENTER para continuar..."
                ;;
            5)
                manage_skills
                ;;
            6)
                check_root
                check_deps # Garante que jq está instalado
                approve_device
                read -p "Pressione ENTER para continuar..."
                ;;
            7)
                check_root
                generate_whatsapp_qrcode
                read -p "Pressione ENTER para continuar..."
                ;;
            8)
                check_root
                check_deps
                configure_gateway_mode
                read -p "Pressione ENTER para continuar..."
                ;;
            9)
                check_root
                check_deps
                force_bind_lan
                read -p "Pressione ENTER para continuar..."
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
                log_info "Buscando logs do OpenClaw..."
                
                # Tenta logs de Swarm Service primeiro
                if docker service ps openclaw_openclaw >/dev/null 2>&1; then
                    log_info "Detectado modo Swarm. Exibindo logs do serviço..."
                    docker service logs -f --tail 100 openclaw_openclaw
                # Se não, tenta logs de Container local (Standalone ou Node específico)
                elif [ -d "$INSTALL_DIR" ]; then
                     cd "$INSTALL_DIR" || exit
                     if docker compose ps | grep -q "openclaw"; then
                        docker compose logs -f --tail 100
                     else
                        # Fallback genérico: busca container por nome
                        local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
                        if [ -n "$container_id" ]; then
                             docker logs -f --tail 100 "$container_id"
                        else
                             log_error "Nenhum container ou serviço OpenClaw encontrado rodando."
                        fi
                     fi
                else
                    log_error "OpenClaw não parece estar instalado em $INSTALL_DIR e nenhum serviço Swarm foi detectado."
                fi
                read -p "Pressione ENTER para continuar..."
                ;;
            14)
                enter_shell
                read -p "Pressione ENTER para continuar..."
                ;;
            15)
                check_root
                restart_gateway
                read -p "Pressione ENTER para continuar..."
                ;;
            16)
                check_root
                echo -e "${AZUL}Sincronizando e exibindo informações de conexão...${RESET}"
                setup_security_config "" ""
                read -p "Pressione ENTER para continuar..."
                ;;
            17)
                check_root
                push_to_hub_menu
                read -p "Pressione ENTER para continuar..."
                ;;
            18)
                check_root
                cleanup_vps
                read -p "Pressione ENTER para continuar..."
                ;;
            19)
                check_root
                uninstall_docker
                read -p "Pressione ENTER para continuar..."
                ;;
            20)
                check_root
                setup_hostname "force"
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
echo ""
echo -e "${VERDE}Configuração inicial concluída. Carregando menu...${RESET}"
sleep 2
menu
