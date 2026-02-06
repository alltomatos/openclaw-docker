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
    echo -e "                           ${BRANCO}Versão do Instalador: ${VERDE}v1.5.1${RESET}                "
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
      # Bind LAN (necessário para Traefik alcançar o container)
      - OPENCLAW_GATEWAY_BIND=lan
      # Token de Gateway para automação
      - OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-$gateway_token}
    # Permite iniciar sem config para rodar o onboard depois
    command: ["openclaw", "gateway", "--allow-unconfigured"]
    volumes:
      # Mapeamento direto para persistência no host
      - /root/openclaw/.openclaw:/home/openclaw/.openclaw
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
    
    # Se não temos domínio, não dá pra usar API
    if [ -z "$p_domain" ]; then
        log_info "Domínio do Portainer não identificado. Usando deploy via CLI."
        docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
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
        docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
        return
    fi

    # Obter Endpoint ID (assume local/primary como o primeiro endpoint)
    local endpoint_id=$(curl -k -s -H "Authorization: Bearer $token" --resolve "$p_domain:443:127.0.0.1" "$portainer_url/api/endpoints" | jq -r '.[0].Id')
    
    if [ -z "$endpoint_id" ] || [ "$endpoint_id" == "null" ]; then
         log_warn "Falha ao obter Endpoint ID. Usando deploy via CLI."
         docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
         return
    fi
    
    # Obter Swarm ID
    local swarm_id=$(curl -k -s -H "Authorization: Bearer $token" --resolve "$p_domain:443:127.0.0.1" "$portainer_url/api/endpoints/$endpoint_id/docker/swarm" | jq -r .ID)

    log_info "Tentando deploy via Portainer API (Stack: $stack_name, Endpoint: $endpoint_id)..."
    
    # Arquivos temporários para capturar saída
    local response_output=$(mktemp)
    local error_output=$(mktemp)
    
    # Verificar se a stack já existe
    local stack_id=$(curl -k -s -H "Authorization: Bearer $token" --resolve "$p_domain:443:127.0.0.1" "$portainer_url/api/stacks" | jq -r --arg name "$stack_name" '.[] | select(.Name == $name) | .Id')

    if [ -n "$stack_id" ] && [ "$stack_id" != "null" ]; then
         log_info "Stack '$stack_name' encontrada (ID: $stack_id). Atualizando via API..."
         
         # Preparar payload JSON seguro usando jq
         local file_content=$(cat "$compose_file")
         local payload=$(jq -n --arg content "$file_content" --argjson prune true '{StackFileContent: $content, Prune: $prune}')
         
         # API Request para ATUALIZAR stack
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
            docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
         fi
    else
        # API Request para CRIAR stack
        local http_code=$(curl -s -o "$response_output" -w "%{http_code}" -k -X POST \
        -H "Authorization: Bearer $token" \
        --resolve "$p_domain:443:127.0.0.1" \
        -F "Name=$stack_name" \
        -F "file=@$(pwd)/$compose_file" \
        -F "SwarmID=$swarm_id" \
        -F "endpointId=$endpoint_id" \
        "$portainer_url/api/stacks/create/swarm/file" 2> "$error_output")
        
        if [ "$http_code" -eq 200 ]; then
            log_success "Deploy da stack '$stack_name' realizado com SUCESSO via Portainer API!"
            log_info "A stack agora deve aparecer como 'Total Control' no Portainer."
        elif [ "$http_code" -eq 409 ]; then
            log_warn "Stack '$stack_name' já existe no Portainer (Conflito detectado tardiamente). Atualizando via CLI..."
            docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
        else
            log_error "Erro no deploy via API (HTTP $http_code)."
            log_error "Resposta: $(cat $response_output)"
            log_error "Detalhes: $(cat $error_output)"
            log_info "Tentando fallback via CLI..."
            docker stack deploy --prune --resolve-image always -c "$compose_file" "$stack_name"
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
    
    # FIX: Corrigir permissões de propriedade para o usuário openclaw (UID 1000)
    # Isso resolve erros como "EACCES: permission denied, watch '/home/openclaw/.openclaw'"
    log_info "Ajustando permissões de propriedade (chown 1000:1000) em /root/openclaw..."
    chown -R 1000:1000 /root/openclaw
    
    # Copiar skills iniciais para a persistência (evita montar volume nested/circular)
    if [ -d "skills" ]; then
        log_info "Copiando skills iniciais para o workspace..."
        mkdir -p /root/openclaw/.openclaw/workspace/skills
        cp -rn skills/* /root/openclaw/.openclaw/workspace/skills/ 2>/dev/null || true
        # Garante permissões corretas
        chown -R 1000:1000 /root/openclaw/.openclaw/workspace/skills
    fi

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
            # Token não será gerado aqui, deixaremos o Wizard (onboard) criar.
            local GEN_TOKEN=""
            # if command -v openssl &> /dev/null; then
            #    GEN_TOKEN=$(openssl rand -hex 16)
            # else
            #    GEN_TOKEN=$(date +%s%N | sha256sum | base64 | head -c 32)
            # fi

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
            
            # Salvar Token para referência (Swarm)
            mkdir -p /root/dados_vps
            if [ ! -f /root/dados_vps/openclaw.txt ]; then
                 echo "================================================================" > /root/dados_vps/openclaw.txt
                 echo " DATA DE INSTALAÇÃO: $(date)" >> /root/dados_vps/openclaw.txt
                 echo "================================================================" >> /root/dados_vps/openclaw.txt
            fi
            
            # Não salvamos o GEN_TOKEN como token final pois o Wizard irá sobrescrever
            chmod 600 /root/dados_vps/openclaw.txt

            # Passamos token vazio para iniciar sem configuração e permitir onboard
            generate_swarm_config "$TRAEFIK_NET" "$DOMAIN" "$AUTH_HASH" ""
            
            log_info "Baixando imagem oficial..."
            if ! docker pull watink/openclaw:latest; then
                log_error "Falha ao baixar imagem watink/openclaw:latest."
                echo -e "${AMARELO}Tentando construir localmente como fallback...${RESET}"
                build_image
            fi
            
            log_info "Realizando deploy da Stack..."
            # Usa APENAS o arquivo Swarm gerado (que agora é completo), evitando conflitos com 'profiles' do docker-compose.yml
            deploy_stack_via_api "openclaw" "docker-compose.swarm.yml"
            
            if [ $? -eq 0 ]; then
                log_success "OpenClaw implantado no Swarm!"
                sync_official_skills
                install_initial_skills
                
                echo ""
                echo -e "${AMARELO}IMPORTANTE: Instalação da Stack concluída.${RESET}"
                echo -e "${BRANCO}Iniciando agora o Wizard de Configuração Oficial (Obrigatório)...${RESET}"
                echo ""
                sleep 2
                
                setup_sandbox
                run_wizard
            else
                log_error "Falha no deploy Swarm."
            fi
            return
        fi
    fi

    # Modo Standalone (Padrão)
    log_info "Baixando imagem oficial e iniciando containers (Standalone)..."
    
    # Não geramos token temporário, deixamos o Wizard criar.
    GEN_TOKEN=""
    # if [ -z "$GEN_TOKEN" ]; then
    #    if command -v openssl &> /dev/null; then
    #        GEN_TOKEN=$(openssl rand -hex 16)
    #    else
    #        GEN_TOKEN=$(date +%s%N | sha256sum | base64 | head -c 32)
    #    fi
    # fi

    # Define variáveis para o docker-compose.yml usar paths do host
    # export OPENCLAW_GATEWAY_TOKEN="$GEN_TOKEN"
    unset OPENCLAW_GATEWAY_TOKEN
    export OPENCLAW_CONFIG_PATH="/root/openclaw/.openclaw"
    
    docker compose pull
    docker compose up -d
    
    if [ $? -eq 0 ]; then
        log_success "OpenClaw iniciado com sucesso!"
        sync_official_skills
        install_initial_skills
        echo ""
        echo -e "${AMARELO}IMPORTANTE: Containers iniciados.${RESET}"
        echo -e "${BRANCO}Iniciando agora o Wizard de Configuração Oficial (Obrigatório)...${RESET}"
        echo ""
        sleep 2
        
        setup_sandbox
        run_wizard
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

    # 4. Remover Dados Persistentes e Credenciais
    log_info "Removendo dados persistentes (/root/openclaw) e credenciais..."
    rm -rf /root/openclaw
    rm -rf /root/dados_vps
    
    # 5. Remover Diretório
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Removendo diretório de instalação: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi

    log_success "Limpeza concluída! O OpenClaw foi removido deste servidor."
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

    log_success "Docker desinstalado completamente."
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
    
    # GARANTE que o volume correto seja usado pelo docker-compose
    export OPENCLAW_CONFIG_PATH="/root/openclaw/.openclaw"
    
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
        
        # Ler novo token gerado pelo Wizard
        local new_token=""
        if [ -f "/root/openclaw/.openclaw/openclaw.json" ]; then
             new_token=$(jq -r '.gateway.auth.token // empty' "/root/openclaw/.openclaw/openclaw.json")
        fi

        echo -e "${VERDE}Reiniciando gateway para aplicar alterações...${RESET}"
        
        # Standalone
        if [ -f "docker-compose.yml" ]; then
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
             
             # Recuperar Rede Traefik
             local network_name=$(detect_swarm_traefik)
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
                 generate_swarm_config "$network_name" "$domain" "$auth_hash" "$new_token"
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
        echo -e "${VERDE}8${BRANCO} - Verificar Saúde do Sistema (Doctor)${RESET}"
        echo -e "${VERDE}9${BRANCO} - Verificar Status do Gateway${RESET}"
        echo -e "${VERDE}16${BRANCO} - Abrir Dashboard CLI${RESET}"
        echo ""
        echo -e "${AZUL}--- Utilitários ---${RESET}"
        echo -e "${VERDE}10${BRANCO} - Ver Logs do OpenClaw${RESET}"
        echo -e "${VERDE}11${BRANCO} - Acessar Terminal do Container${RESET}"
        echo -e "${VERDE}12${BRANCO} - Reiniciar Gateway${RESET}"
        echo -e "${VERDE}15${BRANCO} - Exibir Dados de Conexão (Token/URL)${RESET}"
        echo ""
        echo -e "${AZUL}--- Sistema ---${RESET}"
        echo -e "${VERMELHO}13${BRANCO} - Limpar VPS (Desinstalar OpenClaw)${RESET}"
        echo -e "${VERMELHO}14${BRANCO} - Desinstalar Docker (Remove TUDO)${RESET}"
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
                run_doctor
                read -p "Pressione ENTER para continuar..."
                ;;
            9)
                run_status
                read -p "Pressione ENTER para continuar..."
                ;;
            10)
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
            11)
                enter_shell
                read -p "Pressione ENTER para continuar..."
                ;;
            12)
                check_root
                restart_gateway
                read -p "Pressione ENTER para continuar..."
                ;;
            15)
                check_root
                echo -e "${AZUL}Sincronizando e exibindo informações de conexão...${RESET}"
                setup_security_config "" ""
                read -p "Pressione ENTER para continuar..."
                ;;
            16)
                run_dashboard
                read -p "Pressione ENTER para continuar..."
                ;;
            13)
                check_root
                cleanup_vps
                read -p "Pressione ENTER para continuar..."
                ;;
            14)
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
