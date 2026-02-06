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
    echo -e "                           ${BRANCO}Versão do Instalador: ${VERDE}v1.5.0${RESET}                "
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

# --- Verificações ---

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Este script precisa ser executado como root (sudo)."
        exit 1
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

prepare_persistence() {
    log_info "Configurando diretórios de persistência em /root/openclaw..."
    
    # Cria diretórios no host
    mkdir -p /root/openclaw/.openclaw/workspace
    
    # Ajusta permissões para o usuário do container (UID 1000)
    # Isso evita erros de EACCES/Permission Denied
    chown -R 1000:1000 /root/openclaw
    
    log_success "Diretórios de persistência prontos."
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
    deploy:
      mode: replicated
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.openclaw.rule=Host(\`$domain\`)"
        - "traefik.http.routers.openclaw.entrypoints=web"
        - "traefik.http.routers.openclaw.entrypoints=websecure"
        - "traefik.http.routers.openclaw.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.openclaw.loadbalancer.server.port=18789"
        # Canvas Host (Porta 18793) - Requer subdomínio ou path separado se exposto via Traefik
    environment:
      - OPENCLAW_DISABLE_BONJOUR=1
      # Token de Gateway para automação (opcional, pode ser injetado via secret futuramente)
      - OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN:-}
    volumes:
      # Mapeamento direto para persistência no host
      - /root/openclaw/.openclaw:/home/openclaw/.openclaw
      # Mapeamento de Skills
      - ./skills:/home/openclaw/.openclaw/workspace/skills
      # Socket do Docker para Sandboxing
      - /var/run/docker.sock:/var/run/docker.sock
$middleware_config

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
}

setup_security_config() {
    log_info "Verificando e aplicando configurações de segurança..."
    
    # Aguarda o container subir (tentativa simples)
    sleep 5
    
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    
    if [ -z "$container_id" ]; then
        log_error "Container não encontrado. Configuração automática de segurança ignorada."
        return
    fi

    # Tenta copiar config atual (se existir)
    # Se falhar (arquivo não existe), cria um JSON vazio
    docker cp "$container_id":/home/openclaw/.openclaw/openclaw.json ./current_config.json 2>/dev/null || echo "{}" > ./current_config.json

    # Fix self-healing: Remove invalid key 'gateway.auth.type' if present (bug fix)
    local CONFIG_CHANGED=false
    if jq -e '.gateway.auth.type' ./current_config.json >/dev/null 2>&1; then
        log_info "Corrigindo configuração antiga (removendo gateway.auth.type inválido)..."
        jq 'del(.gateway.auth.type)' ./current_config.json > ./fixed_config.json && mv ./fixed_config.json ./current_config.json
        CONFIG_CHANGED=true
    fi

    # Verificar se já tem gateway.auth.token configurado
    local HAS_TOKEN=$(jq -r '.gateway.auth.token // empty' ./current_config.json 2>/dev/null)
    
    if [ -n "$HAS_TOKEN" ]; then
        if [ "$CONFIG_CHANGED" = true ]; then
            log_info "Aplicando correções na configuração existente..."
            docker cp ./current_config.json "$container_id":/home/openclaw/.openclaw/openclaw.json
            docker exec -u root "$container_id" chown openclaw:openclaw /home/openclaw/.openclaw/openclaw.json
            log_info "Reiniciando container para aplicar correções..."
            docker restart "$container_id"
            log_success "Configuração corrigida com sucesso."
        else
            log_info "Configuração de segurança já existente e correta."
        fi
        rm -f ./current_config.json
        return
    fi

    log_info "Gerando Token de Segurança e configurando Trusted Proxies..."

    # Gerar Token
    local NEW_TOKEN=""
    if command -v openssl &> /dev/null; then
        NEW_TOKEN=$(openssl rand -hex 32)
    else
        NEW_TOKEN=$(date +%s%N | sha256sum | head -c 64)
    fi

    # Merge/Criação com jq
    # Adiciona auth token e trusted proxies (essencial para evitar erros de loopback_no_auth)
    jq --arg token "$NEW_TOKEN" '
        .gateway.auth.token = $token |
        .gateway.trustedProxies = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "127.0.0.1"]
    ' ./current_config.json > ./new_config.json
    
    # Copiar de volta para o container
    docker cp ./new_config.json "$container_id":/home/openclaw/.openclaw/openclaw.json
    
    # Ajustar permissões (Root executa chown)
    docker exec -u root "$container_id" chown openclaw:openclaw /home/openclaw/.openclaw/openclaw.json
    docker exec -u root "$container_id" chmod 600 /home/openclaw/.openclaw/openclaw.json
    
    # Reiniciar para aplicar
    log_info "Reiniciando container para carregar novas configurações..."
    docker restart "$container_id"
    
    # Salvar token em arquivo seguro
    mkdir -p /root/dados_vps
    
    # Detectar IP Externo para facilitar o acesso
    local PUBLIC_IP="LOCALHOST"
    if command -v curl &> /dev/null; then
        PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me || echo "LOCALHOST")
    fi
    
    echo "================================================================" > /root/dados_vps/openclaw.txt
    echo " DATA DE INSTALAÇÃO: $(date)" >> /root/dados_vps/openclaw.txt
    echo "================================================================" >> /root/dados_vps/openclaw.txt
    echo " TOKEN DE ACESSO (GATEWAY):" >> /root/dados_vps/openclaw.txt
    echo " $NEW_TOKEN" >> /root/dados_vps/openclaw.txt
    echo "----------------------------------------------------------------" >> /root/dados_vps/openclaw.txt
    echo " LINK DIRETO DO DASHBOARD:" >> /root/dados_vps/openclaw.txt
    echo " http://$PUBLIC_IP:18789/?token=$NEW_TOKEN" >> /root/dados_vps/openclaw.txt
    echo "----------------------------------------------------------------" >> /root/dados_vps/openclaw.txt
    echo " NOTA IMPORTANTE (PRIMEIRO ACESSO):" >> /root/dados_vps/openclaw.txt
    echo " Ao acessar por IP externo, o sistema pode pedir aprovação (Pairing)." >> /root/dados_vps/openclaw.txt
    echo " Se vir 'Pairing Required', rode no terminal:" >> /root/dados_vps/openclaw.txt
    echo "   openclaw devices list      (para ver o ID)" >> /root/dados_vps/openclaw.txt
    echo "   openclaw devices approve <ID> (para liberar)" >> /root/dados_vps/openclaw.txt
    echo "================================================================" >> /root/dados_vps/openclaw.txt
    chmod 600 /root/dados_vps/openclaw.txt

    log_success "Segurança configurada com sucesso!"
    echo ""
    echo -e "${AZUL}================================================================${RESET}"
    echo -e "${VERDE} TOKEN DE ACESSO GERADO (GATEWAY):${RESET}"
    echo -e "${BRANCO} $NEW_TOKEN ${RESET}"
    echo -e "${AZUL}================================================================${RESET}"
    echo -e "Guarde este token. Uma cópia foi salva em: ${VERDE}/root/dados_vps/openclaw.txt${RESET}"
    echo ""
    
    rm -f ./current_config.json ./new_config.json
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
    local stack_name="$1"
    local max_retries=30
    local count=0
    
    log_info "Aguardando serviços da stack '$stack_name'..."
    
    while [ $count -lt $max_retries ]; do
        # Verifica se todos os serviços da stack têm réplicas rodando
        local services_total=$(docker stack services "$stack_name" --format "{{.Replicas}}" | wc -l)
        local services_running=$(docker stack services "$stack_name" --format "{{.Replicas}}" | grep -v "0/0" | grep -v "0/" | wc -l)
        
        if [ "$services_total" -gt 0 ] && [ "$services_total" -eq "$services_running" ]; then
            log_success "Stack '$stack_name' está operacional."
            return 0
        fi
        
        echo -n "."
        sleep 5
        count=$((count + 1))
    done
    
    log_error "Timeout aguardando stack '$stack_name'."
    return 1
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
        docker swarm init >/dev/null 2>&1 || log_error "Falha ao iniciar Swarm (talvez precise de --advertise-addr?)"
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
    image: traefik:v3.4.0
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
      - "--log.level=INFO"
      - "--accesslog=true"
    volumes:
      - volume_swarm_certificates:/etc/traefik/letsencrypt
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
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.traefik-dashboard.rule=Host(\`traefik.localhost\`)"
        - "traefik.http.routers.traefik-dashboard.service=api@internal"
        - "traefik.http.routers.traefik-dashboard.entrypoints=websecure"
        - "traefik.http.routers.traefik-dashboard.tls.certresolver=letsencryptresolver"

volumes:
  volume_swarm_certificates:
    external: true

networks:
  $NETWORK_NAME:
    external: true
EOF

    log_info "Implantando Traefik..."
    docker stack deploy -c traefik.yaml traefik
    wait_stack "traefik"
    
    # 6. Deploy Portainer
    log_info "Preparando Portainer..."
    cat > portainer.yaml <<EOF
version: "3.7"
services:
  agent:
    image: portainer/agent:lts
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
    image: portainer/portainer-ce:lts
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

volumes:
  portainer_data:
    external: true

networks:
  $NETWORK_NAME:
    external: true
EOF

    log_info "Implantando Portainer..."
    docker stack deploy -c portainer.yaml portainer
    
    log_info "Aguardando Portainer iniciar para criar admin..."
    wait_stack "portainer"
    sleep 10 # Margem de segurança extra
    
    # 7. Criar Admin Portainer
    log_info "Configurando usuário admin do Portainer..."
    local MAX_RETRIES=20
    local CONTA_CRIADA=false
    
    for i in $(seq 1 $MAX_RETRIES); do
        RESPONSE=$(curl -k -s -X POST "https://$PORTAINER_DOMAIN/api/users/admin/init" \
            -H "Content-Type: application/json" \
            -d "{\"Username\": \"$PORTAINER_USER\", \"Password\": \"$PORTAINER_PASS\"}")
        
        if echo "$RESPONSE" | grep -q "\"Username\":\"$PORTAINER_USER\""; then
            log_success "Admin Portainer criado com sucesso!"
            CONTA_CRIADA=true
            break
        else
            log_info "Tentativa $i/$MAX_RETRIES de criar admin falhou. Retentando em 10s..."
            sleep 10
        fi
    done
    
    local TOKEN=""
    if [ "$CONTA_CRIADA" = true ]; then
        # Gerar Token JWT
        TOKEN=$(curl -k -s -X POST "https://$PORTAINER_DOMAIN/api/auth" \
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
    else
        log_error "Não foi possível criar o admin do Portainer automaticamente."
        echo "Crie manualmente acessando: https://$PORTAINER_DOMAIN"
    fi
    
    # 8. Deploy OpenClaw
    echo ""
    echo -e "${AZUL}=== Instalação do OpenClaw ===${RESET}"
    
    # Usar a função setup_openclaw mas forçando o modo swarm
    # Como setup_openclaw é interativo, vamos chamar a lógica de deploy direto aqui
    # ou podemos chamar setup_openclaw e o usuário escolhe Swarm (que já vai ser detectado!)
    
    log_info "Continuando para instalação do OpenClaw..."
    
    # Limpeza do diretório temporário
    cd "$CURRENT_DIR" || true
    rm -rf "$TEMP_SETUP_DIR"

    setup_openclaw
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
    
    # Preparar persistência (diretórios no host)
    prepare_persistence

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
                    
                    # Salvar credenciais Swarm
                    mkdir -p /root/dados_vps
                    echo "" >> /root/dados_vps/openclaw.txt
                    echo " ACESSO WEB (SWARM):" >> /root/dados_vps/openclaw.txt
                    echo " URL: http://$DOMAIN" >> /root/dados_vps/openclaw.txt
                    echo " USER: $AUTH_USER" >> /root/dados_vps/openclaw.txt
                    echo " PASS: $AUTH_PASS" >> /root/dados_vps/openclaw.txt
                    chmod 600 /root/dados_vps/openclaw.txt
                else
                    log_error "Não foi possível gerar o hash (requer internet para baixar httpd:alpine ou python3 local)."
                    echo -e "${AMARELO}A instalação continuará sem autenticação.${RESET}"
                fi
            fi

            generate_swarm_config "$TRAEFIK_NET" "$DOMAIN" "$AUTH_HASH"
            
            log_info "Baixando imagem oficial..."
            if ! docker pull watink/openclaw:latest; then
                log_error "Falha ao baixar imagem watink/openclaw:latest."
                echo -e "${AMARELO}Tentando construir localmente como fallback...${RESET}"
                build_image
            fi
            
            log_info "Realizando deploy da Stack..."
            # Usa APENAS o arquivo Swarm gerado (que agora é completo), evitando conflitos com 'profiles' do docker-compose.yml
            docker stack deploy -c docker-compose.swarm.yml openclaw
            
            if [ $? -eq 0 ]; then
                log_success "OpenClaw implantado no Swarm!"
                setup_security_config
                sync_official_skills
                install_initial_skills
                echo -e "Acesse em: ${VERDE}http://$DOMAIN${RESET}"
            else
                log_error "Falha no deploy Swarm."
            fi
            return
        fi
    fi

    # Modo Standalone (Padrão)
    log_info "Baixando imagem oficial e iniciando containers (Standalone)..."
    
    # Define variáveis para o docker-compose.yml usar paths do host
    export OPENCLAW_CONFIG_PATH="/root/openclaw/.openclaw"
    
    docker compose pull
    docker compose up -d
    
    if [ $? -eq 0 ]; then
        log_success "OpenClaw iniciado com sucesso!"
        setup_security_config
        sync_official_skills
        install_initial_skills
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
    # Filtra por nome que contenha 'openclaw' (ex: openclaw-openclaw-gateway-1 ou openclaw_openclaw.1.xxx)
    local container_id=$(docker ps --filter "name=openclaw" --format "{{.ID}}" | head -n 1)
    
    if [ -n "$container_id" ]; then
        log_info "Container encontrado: $container_id"
        
        echo ""
        echo -e "${BRANCO}Comandos internos disponíveis no OpenClaw:${RESET}"
        echo -e "  - ${VERDE}openclaw onboard --install-daemon${RESET} : Instala o daemon do sistema"
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

    # Pergunta explícita sobre os dados persistentes no Host
    echo ""
    echo -e "${VERMELHO}Deseja apagar também os dados persistentes em /root/openclaw?${RESET}"
    echo -e "${AMARELO}(Isso excluirá TODAS as configurações, chaves e bancos de dados locais)${RESET}"
    echo -en "${BRANCO}[y/N]: ${RESET}"
    read -r DELETE_DATA

    if [[ "$DELETE_DATA" =~ ^[Yy]$ ]]; then
        log_info "Removendo dados persistentes (/root/openclaw)..."
        rm -rf /root/openclaw
        log_success "Dados persistentes removidos."
    else
        log_info "Dados persistentes mantidos em /root/openclaw."
    fi

    # 4. Remover Diretório
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Removendo diretório de instalação: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi

    log_success "Limpeza concluída! O OpenClaw foi removido deste servidor."
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
    
    # Garante que os diretórios de persistência existem e têm permissão correta
    prepare_persistence

    log_info "Executando 'openclaw onboard' via container temporário..."
    echo -e "${AMARELO}Siga as instruções na tela. Pressione Ctrl+C para cancelar.${RESET}"
    echo -e "${AMARELO}O assistente pode demorar alguns instantes para iniciar. Por favor, aguarde...${RESET}"
    echo ""
    
    # Executa o serviço CLI definido no docker-compose.yml
    docker compose run --rm openclaw-cli onboard
    
    if [ $? -eq 0 ]; then
        log_success "Wizard concluído com sucesso."
        echo -e "${VERDE}Reiniciando gateway para aplicar alterações...${RESET}"
        docker compose restart openclaw-gateway
    else
        log_error "Wizard cancelado ou falhou."
    fi
}

# --- Utilitários de Canal e Gateway ---

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

# --- Menu Principal ---

menu() {
    while true; do
        header
        echo -e "${BRANCO}Selecione uma opção:${RESET}"
        echo ""
        echo -e "${AZUL}--- Instalação ---${RESET}"
        echo -e "${VERDE}1${BRANCO} - Instalação Completa (Swarm + Portainer + Traefik + OpenClaw)${RESET}"
        echo -e "${VERDE}2${BRANCO} - Instalar OpenClaw (Standalone ou Cluster Existente)${RESET}"
        echo -e "${VERDE}3${BRANCO} - Apenas Instalar Docker${RESET}"
        echo ""
        echo -e "${AZUL}--- Configuração & Gerenciamento ---${RESET}"
        echo -e "${VERDE}4${BRANCO} - Setup Wizard (Onboard Oficial)${RESET}"
        echo -e "${VERDE}5${BRANCO} - Gerenciar Skills (Plugins)${RESET}"
        echo -e "${VERDE}6${BRANCO} - Gerenciar Dispositivos (Aprovar Pairing)${RESET}"
        echo -e "${VERDE}7${BRANCO} - Gerar QR Code WhatsApp${RESET}"
        echo ""
        echo -e "${AZUL}--- Utilitários ---${RESET}"
        echo -e "${VERDE}8${BRANCO} - Ver Logs do OpenClaw${RESET}"
        echo -e "${VERDE}9${BRANCO} - Acessar Terminal do Container${RESET}"
        echo -e "${VERDE}10${BRANCO} - Reiniciar Gateway${RESET}"
        echo ""
        echo -e "${AZUL}--- Sistema ---${RESET}"
        echo -e "${VERMELHO}11${BRANCO} - Limpar VPS (Desinstalar OpenClaw)${RESET}"
        echo -e "${VERDE}0${BRANCO} - Sair${RESET}"
        echo ""
        echo -en "${AMARELO}Opção: ${RESET}"
        read -r OPCAO

        case $OPCAO in
            1)
                check_root
                check_deps
                ensure_docker_permission
                install_full_stack_swarm
                read -p "Pressione ENTER para continuar..."
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
                approve_device
                read -p "Pressione ENTER para continuar..."
                ;;
            7)
                check_root
                generate_whatsapp_qrcode
                read -p "Pressione ENTER para continuar..."
                ;;
            8)
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
            9)
                enter_shell
                read -p "Pressione ENTER para continuar..."
                ;;
            10)
                check_root
                restart_gateway
                read -p "Pressione ENTER para continuar..."
                ;;
            11)
                check_root
                cleanup_vps
                read -p "Pressione ENTER para continuar..."
                ;;
            12)
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
menu
