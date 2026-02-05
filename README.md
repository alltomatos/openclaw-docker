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
- Docker & Docker Compose instalados.
- Linux/WSL2 (Recomendado).

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
curl -sL https://raw.githubusercontent.com/alltomatos/openclaw-docker/main/SetupOpenclaw.sh -o SetupOpenclaw.sh && chmod +x SetupOpenclaw.sh && ./SetupOpenclaw.sh
```

![Setup OpenClaw Menu](./imagem/setup.png)

O menu interativo facilita o gerenciamento do ambiente:
1.  **Instalar/Atualizar**: Realiza o deploy completo (Standalone ou Swarm).
2.  **Apenas Instalar Docker**: Prepara o servidor se ele estiver "zerado".
3.  **Ver Logs**: Atalho para visualizar o que está acontecendo.
4.  **Acessar Terminal**: Entra no container para manutenção avançada.
5.  **Limpar VPS**: Remove tudo (útil para testes ou reset).

Siga as instruções do menu interativo. O script detectará automaticamente se é necessário instalar a infraestrutura e guiará você passo-a-passo. Você poderá escolher entre o modo **Cluster (Swarm + Traefik)** ou **Standalone (Docker Puro)**.

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
Você pode fazer isso de duas formas:

**Opção A: Via comando direto (Host)**
```bash
docker compose exec openclaw openclaw onboard
```

**Opção B: Via Terminal Interativo**
Selecione a **opção 4** no menu do `SetupOpenclaw.sh` ou entre manualmente no container. Ao entrar, você verá uma lista de comandos úteis:

![OpenClaw Container Terminal](./imagem/container.png)

> **Nota:** O terminal de manutenção abre como `root` para permitir instalações e ajustes, mas a aplicação OpenClaw roda em background como usuário seguro `openclaw` (via `gosu` no entrypoint).

### 📱 Canais e Configuração (Channels)

Além do WhatsApp, o OpenClaw suporta diversos outros canais como Telegram, Discord, Slack, etc.

#### 1. Conectar WhatsApp (QR Code)
Para conectar o WhatsApp, você precisa gerar o QR Code diretamente no terminal do container.

1.  Acesse o terminal do container (Menu opção 4 ou `docker compose exec ...`).
2.  Execute o comando:
    ```bash
    openclaw channels login --channel whatsapp
    ```
    *Dica: Use `openclaw channels login --channel whatsapp --account trabalho` para configurar múltiplas contas.*
3.  📱 **Ação:** Tenha seu celular pronto em **Aparelhos Conectados > Conectar um aparelho**, pois o código expira rápido.

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

Se você executar `openclaw security audit --deep` e encontrar alertas como `gateway.loopback_no_auth` ou `gateway.trusted_proxies_missing`, adicione a configuração de Gateway ao seu `openclaw.json`.

Isso é essencial se você expõe o OpenClaw através de um proxy reverso (como Traefik) ou quer proteger a API local.

```json
{
  "gateway": {
    "auth": {
      "type": "token",
      "token": "gere-um-token-seguro-aqui"
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
Se o bot não responder imediatamente após a conexão, reinicie o gateway para carregar a nova sessão:
```bash
openclaw gateway restart
```

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
    *   **Opção A (Automática)**: O sistema roda um scan diário às **03:00 AM**. Ele detecta novas pastas, instala as dependências (Node/Python) e recarrega o agente.
    *   **Opção B (Manual/Imediata)**: Force a detecção e instalação agora mesmo sem reiniciar o container:
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

| Volume | Caminho no Container | Descrição |
|--------|----------------------|-----------|
| `openclaw_config` | `/home/openclaw/.openclaw` | Armazena configurações, chaves de API e sessões. |
| `openclaw_workspace` | `/home/openclaw/workspace` | Arquivos gerados pelo agente durante o uso. |
| `./skills` (Bind Mount) | `/home/openclaw/workspace/skills` | Sincronização direta das suas skills locais. |

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
