# 🦞 OpenClaw Docker - Ambiente de Produção

Este repositório contém a configuração completa para rodar o **OpenClaw** em containers Docker, otimizado com Ubuntu 24.04 LTS, Node.js 22 e suporte total a automação de navegadores (Playwright).

## 🚀 Funcionalidades

- **Base Robusta**: Ubuntu 24.04 LTS + Node.js 22.
- **Navegadores Pré-instalados**: Chromium, Firefox e WebKit (via Playwright) prontos para uso.
- **Gerenciamento de Processos**: Utiliza **PM2** para manter o agente sempre online.
- **Suporte a Cluster**: Detecção automática de **Docker Swarm** e integração nativa com **Traefik** (Load Balancer).
- **Gestão de Skills**:
  - Injeção segura de skills via diretório local.
  - **Auto-Reload Diário**: O sistema verifica novas skills automaticamente todo dia às 03:00 AM.
  - Instalação automática de dependências (`npm install`) para novas skills.
- **Segurança**: Executa como usuário não-root (`openclaw`).

---

## 🛠️ Instalação e Uso

### Pré-requisitos
- Um servidor VPS (Ubuntu/Debian recomendado), preferencialmente "limpo".
- Acesso root (ou sudo sem senha).
- **Não é necessário instalar nada antes:** O script instalará automaticamente Docker, Docker Compose, Git, Swarm, Traefik, Portainer e todas as dependências.

### ☁️ Instalação em VPS (Produção)

Para facilitar o deploy em servidores VPS (Ubuntu/Debian), criamos o **SetupOpenclaw**, um script automatizado que configura todo o ambiente utilizando Docker Swarm (opcional) e integra-se nativamente com o Traefik.

✨ **O que o SetupOpenclaw faz:**

*   Instala dependências (Docker, Docker Compose, Git).
*   Configura o ambiente (Standalone ou Cluster/Swarm).
*   Gera e implanta a Stack completa do OpenClaw.
*   Integração automática com **Traefik** (se detectado) para Proxy Reverso e SSL.

🚀 **Como usar:**

Acesse seu servidor via SSH como `root` e execute o comando abaixo:

```bash
rm -rf SetupOpenclaw.sh && curl -sSL https://raw.githubusercontent.com/alltomatos/openclaw-docker/main/SetupOpenclaw.sh -o SetupOpenclaw.sh && chmod +x SetupOpenclaw.sh && ./SetupOpenclaw.sh
```

![Setup OpenClaw Menu](./imagem/setup1.5.0.png)

O menu interativo facilita o gerenciamento do ambiente:
1.  **Instalar/Atualizar**: Realiza o deploy completo (Standalone ou Swarm).
2.  **Apenas Instalar Docker**: Prepara o servidor se ele estiver "zerado".
3.  **Ver Logs**: Atalho para visualizar o que está acontecendo.
4.  **Acessar Terminal**: Entra no container para manutenção avançada.
5.  **Gerenciar Skills**: Menu dedicado para adicionar e escanear plugins/skills.
6.  **Rodar Setup Wizard**: Executa o assistente oficial de configuração (Onboarding).
7.  **Gerar QR Code WhatsApp**: Atalho rápido para conectar seu WhatsApp.
8.  **Reiniciar Gateway**: Reinicia o serviço de gateway (útil após conectar canais).
9.  **Limpar VPS**: Remove completamente o OpenClaw (cuidado!).
10. **Instalação Completa (Zero to Hero)**: Opção recomendada para servidores novos. Instala e configura automaticamente:
    - Docker & Docker Swarm.
    - **Traefik** (Proxy Reverso com SSL automático).
    - **Portainer** (Interface de Gestão) já com **usuário admin criado**.
    - **OpenClaw** integrado ao cluster.
11. **Aprovar Dispositivo**: Interface interativa para listar e aprovar novos dispositivos (pairing) sem precisar decorar comandos.

Siga as instruções do menu interativo. O script detectará automaticamente se é necessário instalar a infraestrutura e guiará você passo-a-passo.

### 🌟 Destaque: Instalação Completa (Opção 10)
Esta opção transforma um VPS vazio em um ambiente de produção completo em minutos.
- **Automação Total**: Diferente de outros setups, este script já cria o **usuário Admin do Portainer** para você, evitando que a interface fique exposta para registro público.
- **Credenciais Seguras**: Ao final, todas as senhas, tokens e URLs gerados são salvos em um arquivo protegido:
  ```bash
  /root/dados_vps/openclaw.txt
  ```
  *(Apenas o usuário root pode ler este arquivo)*.

### ☁️ Modos de Instalação

> **Nota:** Se o script detectar um cluster Swarm com Traefik, ele oferecerá a opção de configurar o OpenClaw como um serviço replicado e acessível via domínio (ex: `openclaw.app.localhost`).

### 🔐 Segurança (Opcional)

Se você estiver rodando em **Swarm com Traefik**, pode proteger o acesso ao OpenClaw com uma senha (Token).
Edite o arquivo `docker-compose.swarm.yml` e descomente as linhas de **Basic Auth**.

Para gerar o hash da senha:
```bash
# Instale o utilitário (se não tiver)
sudo apt install apache2-utils

# Gere o hash (substitua 'seu_token' pela senha desejada)
htpasswd -nb admin seu_token
# Saída: admin:$apr1$.......
```
Copie a saída e cole na label `traefik.http.middlewares.openclaw-auth.basicauth.users` no arquivo `docker-compose.swarm.yml`.

### Opção 2: Instalação Manual
1. Iniciar o Agente:
```bash
docker compose up -d
```

### 2. Configuração Inicial (Onboarding)
Se for a primeira vez, você precisará configurar suas chaves de API (LLM) e canais.
O sistema já inicia com uma **política de segurança padrão** (Sandboxing: All, Tool Policy: Safe).

Você pode configurar suas chaves de três formas:

**Opção A: Via Setup Wizard (Recomendado)**
Selecione a **opção 6** no menu do `SetupOpenclaw.sh`. Isso iniciará o assistente interativo oficial dentro do container.

**Opção B: Via CLI dedicado**
```bash
# Para configuração inicial ou ajustes (mantém defaults seguros)
docker compose run --rm openclaw-cli configure
```

**Opção C: Via Terminal Manual**
Selecione a **opção 4** no menu para acessar o terminal e rode `openclaw configure`.

### 🛡️ Política de Segurança e Sandboxing
Por padrão, este instalador configura o OpenClaw em modo **Secure by Default**:
- **Sandboxing:** Ativado para **TODAS** as sessões (`agents.defaults.sandbox.mode: "all"`).
- **Workspace:** Permissão de escrita (`rw`) para que as tools possam trabalhar.
- **Modo Elevado:** Habilitado para administradores (`tools.elevated.enabled: true`).

Se precisar ajustar, edite o arquivo `openclaw.json` gerado em `/root/openclaw/config/openclaw.json` (ou `./data/config` localmente).

### 🔑 Autenticação Avançada (Headless/Automação)
Para instalações automatizadas onde você não pode rodar o onboarding interativo, você pode pré-definir um token mestre via variável de ambiente. Isso está em conformidade com o **Protocolo Gateway**, permitindo que clientes (CLI/UI) se conectem imediatamente se possuírem o token.

No `docker-compose.yml` (ou via `.env`), defina:
```bash
OPENCLAW_GATEWAY_TOKEN=seu-token-super-seguro-aqui
```
Com isso, qualquer cliente que apresentar este token no handshake WebSocket será autenticado como Admin/Operator.

### 📱 Canais e Configuração (Channels)

Além do WhatsApp, o OpenClaw suporta diversos outros canais como Telegram, Discord, Slack, etc.

#### 1. Conectar WhatsApp (QR Code)
A forma mais fácil é usar o menu do instalador:
1.  Execute `./SetupOpenclaw.sh`
2.  Escolha a **Opção 7 - Gerar QR Code WhatsApp**.
3.  📱 **Ação:** Tenha seu celular pronto em **Aparelhos Conectados > Conectar um aparelho**, pois o código expira rápido.

Alternativamente, via terminal:
```bash
openclaw channels login --channel whatsapp
```
*Dica: Use `openclaw channels login --channel whatsapp --account trabalho` para configurar múltiplas contas.*

#### 2. Conectar Telegram
Para o Telegram, você precisa de um Bot Token (fale com o @BotFather).

```bash
# Adicionar token via CLI
openclaw channels add --channel telegram --token SEU_TOKEN_AQUI

# Configurar permissões de grupo
# (Recomendado configurar no arquivo openclaw.json para maior controle)
```

#### 3. Configuração Avançada (openclaw.json)
O arquivo de configuração principal fica em `/home/openclaw/.openclaw/openclaw.json` (dentro do volume `openclaw_config`).

Exemplo de configuração segura para produção:

```json
{
  "channels": {
    "whatsapp": {
      "dmPolicy": "allowlist",
      "allowFrom": ["+5511999999999"], // Lista de permissão (DMs)
      "groups": {
        "*": { "requireMention": true } // Em grupos, só responde se mencionado
      }
    },
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing", // Exige pareamento para novas conversas
      "groups": {
        "*": { "requireMention": true }
      }
    }
  },
  "messages": {
    "groupChat": {
      "mentionPatterns": ["@openclaw", "bot"] // Gatilhos de menção
    }
  }
}
```

> **Dica de Mentor:** Sempre configure o `allowFrom` e `requireMention` em ambientes de produção para evitar que seu bot responda a mensagens indesejadas ou consuma tokens excessivos de LLM em grupos movimentados.

### 🛡️ Segurança e Auditoria

O **script de instalação (`SetupOpenclaw.sh`) configura a segurança automaticamente** para você. Ele gera um token único e configura os proxies confiáveis.

No final da instalação, você verá:
```text
================================================================
 TOKEN DE ACESSO GERADO (GATEWAY):
 a1b2c3d4... (seu token único)
================================================================
Guarde este token. Uma cópia foi salva em: /root/dados_vps/openclaw.txt
```

Caso precise configurar manualmente (ex: rotação de chaves), edite o `openclaw.json`:

```json
{
  "gateway": {
    "auth": {
      "type": "token",
      "token": "SEU_TOKEN_GERADO_AQUI"
    },
    "trustedProxies": [
      "10.0.0.0/8",     // Rede interna do Docker (Swarm/Compose)
      "172.16.0.0/12",
      "192.168.0.0/16",
      "127.0.0.1"
    ]
  },
  // ... outras configurações (channels, messages)
}
```

**Troubleshooting:**
Se o bot não responder imediatamente após a conexão, reinicie o gateway para carregar a nova sessão. Use a **Opção 8** do menu ou execute:
```bash
openclaw gateway restart
```

### 📱 Acesso ao Dashboard (Control UI) e Segurança

O Dashboard (Control UI) é acessível via navegador na porta `18789`.

**1. Pairing (Aprovação de Dispositivo)**
Por segurança, o OpenClaw exige que novos dispositivos (navegadores) sejam aprovados manualmente se não estiverem rodando na mesma máquina (localhost).
Se você vir a mensagem **"Disconnected (1008): Pairing Required"** ou similar:

**Opção A: Via Menu (Recomendado)**
1. Rode `./SetupOpenclaw.sh` no servidor.
2. Escolha a **Opção 11 - Aprovar Dispositivo**.
3. Selecione o ID correspondente ao seu navegador na lista.

**Opção B: Via Terminal Manual**
1.  Acesse o terminal da VPS (ou use a **Opção 4** do menu).
2.  Liste os pedidos pendentes:
    ```bash
    openclaw devices list
    ```
3.  Aprove o ID do seu navegador:
    ```bash
    openclaw devices approve <ID_DO_DEVICE>
    ```

**2. Limitações HTTP (WebCrypto)**
Se você acessar via IP direto (ex: `http://1.2.3.4:18789`), algumas funcionalidades do navegador (WebCrypto) podem ser bloqueadas por falta de HTTPS/SSL.
*   **Recomendado:** Usar Swarm + Traefik (configurado automaticamente pelo setup) para ter HTTPS.
*   **Alternativa:** Fazer um Túnel SSH para acessar como localhost:
    ```bash
    ssh -L 18789:127.0.0.1:18789 root@seu-ip-vps
    ```
    E acessar em seu computador: `http://localhost:18789`.

---

## 🧠 Gerenciamento de Skills

Este ambiente possui um sistema avançado e automatizado para gerenciamento de capacidades (Skills), permitindo estender o OpenClaw com novas funcionalidades.

### Skills Suportadas
O sistema de **Auto-Reload** detecta e instala dependências automaticamente para:
- **Node.js**: Projetos com `package.json` (instala via `npm install`).
- **Python**: Projetos com `requirements.txt` (instala via `pip install --user`).

### Skills Pré-instaladas
- **DuckDuckGo Search**: Permite que o agente realize pesquisas na web anônimas (texto, imagens, notícias) sem necessidade de API Key. Documentação completa em `./skills/duckduckgo-search-1.0.0/SKILL.md`.

### Como adicionar uma nova Skill

1.  **Clone a skill** para a pasta `./skills` na raiz deste projeto.
    Use o script facilitador para fazer isso de forma segura e organizada:
    ```bash
    ./add_skill.sh https://github.com/usuario/repo-da-skill
    ```

2.  **Ativação**:
    *   **Opção A (Automática)**: O sistema roda um scan diário às **03:00 AM**. Além disso, o **script de instalação executa uma varredura inicial** logo após o deploy.
    *   **Opção B (Manual/Imediata)**: Force a detecção e instalação agora mesmo sem reiniciar o container. Use a **Opção 5** do menu ou execute:
        ```bash
        docker compose exec openclaw /usr/local/bin/scan_skills.sh
        ```
    *   **Opção C (Reinício Total)**:
        ```bash
        docker compose restart openclaw
        ```

### Estrutura de Diretórios
O diretório `./skills` do seu host é mapeado diretamente para dentro do container, facilitando o desenvolvimento.

```text
.
├── skills/                  # Suas skills locais (Git Repos)
│   ├── duckduckgo-search/   # Skill Python (com requirements.txt)
│   ├── outra-skill-node/    # Skill Node.js (com package.json)
│   └── ...
├── docker-compose.yml       # Orquestração
└── ...
```

---

## 🐳 Desenvolvimento e Manutenção

### Construir a Imagem Localmente
Se você fez alterações no Dockerfile e quer testar localmente:
```bash
docker build -t watink/openclaw:latest .
```

---

## 📂 Volumes e Persistência

### 1. Portas
- **18789 (Gateway):** Porta principal para API e WebSockets (Control UI, CLI, Nodes).
- **18793 (Canvas Host):** Porta para o Live Canvas (interface HTML/A2UI editável pelo agente).

### 2. Volumes
Para garantir que seus dados estejam seguros e acessíveis, o instalador configura automaticamente a persistência no host:

| Volume | Caminho no Container | Caminho no Host (Produção/Setup) | Caminho Local (Dev/Manual) |
|--------|----------------------|----------------------------------|----------------------------|
| `openclaw_config` | `/home/openclaw/.openclaw` | `/root/openclaw/.openclaw` | `./data/config` |
| `./skills` (Bind) | `/home/openclaw/.openclaw/workspace/skills` | `/opt/openclaw/skills` | `./skills` |

> **Nota:** O OpenClaw armazena o workspace dentro de `.openclaw/workspace`. Por isso, apenas o volume de configuração é necessário.

> **Nota:** O script `SetupOpenclaw.sh` configura permissões automáticas (`chown 1000:1000`) para que o usuário do container possa escrever nestes diretórios sem erros.

---

## 🔍 Troubleshooting

**Verificar logs do agente:**
```bash
docker compose logs -f openclaw
```

**Verificar status do PM2 (Gerenciador de Processos):**
```bash
docker compose exec openclaw pm2 status
```

**Verificar logs de instalação de skills:**
```bash
docker compose exec openclaw cat /home/openclaw/workspace/skill_scan.log
```

### 🛡️ Segurança (OpSec)
Este instalador implementa as seguintes práticas recomendadas:
1.  **Usuário não-root:** O container roda como usuário `openclaw` (UID 1000) para minimizar a superfície de ataque.
2.  **Trusted Proxies:** Configura automaticamente `gateway.trustedProxies` para permitir conexões de redes locais (10.0.0.0/8, 172.16.0.0/12, etc) e Docker.
3.  **Token de Autenticação:** Gera um token seguro (`gateway.auth.token`) no primeiro setup, bloqueando acessos não autorizados.
4.  **mDNS Desativado:** `OPENCLAW_DISABLE_BONJOUR=1` evita anúncios na rede local, ideal para VPS/Cloud.
5.  **Sandboxing (Docker-in-Docker):** Suporte nativo para execução segura de tools em containers isolados. O setup cria automaticamente a imagem `openclaw-sandbox:bookworm-slim` e mapeia o socket do Docker.

### 🏗️ Arquitetura
- **Gateway Único:** Um único Gateway gerencia todas as conexões (WhatsApp, Telegram, etc).
- **Protocolo WebSocket:** Toda comunicação (CLI, UI, Nodes) ocorre via WS na porta 18789.
- **Canvas Host:** A porta 18793 serve interfaces visuais geradas pelos agentes (A2UI).
- **Isolamento de Skills:** Skills rodam no mesmo container mas com dependências gerenciadas em volumes persistentes.

## 🤝 Contribuindo
