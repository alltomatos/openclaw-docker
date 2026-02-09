# 🦞 OpenClaw Docker - Ambiente de Produção

Este repositório contém a configuração completa para rodar o **OpenClaw** em containers Docker, otimizado com Ubuntu 24.04 LTS, Node.js 22 e suporte total a automação de navegadores (Playwright).

## 🚀 Funcionalidades

- **Base Robusta**: Ubuntu 24.04 LTS + Node.js 22.
- **Navegadores Pré-instalados**: Chromium, Firefox e WebKit (via Playwright) prontos para uso.
- **Gerenciamento de Processos**: Utiliza **PM2** para manter o agente sempre online.
- **Suporte a Cluster (Nativo)**: Instalação automatizada de **Docker Swarm**, **Traefik** (Load Balancer) e **Portainer** (Gestão).
- **Instalação Dinâmica**: O script gera as configurações (`openclaw.yaml`, `traefik.yml`) em tempo de execução, garantindo flexibilidade e segurança.
- **Gestão de Skills**:
  - Injeção segura de skills via diretório local.
  - **Auto-Reload Diário**: O sistema verifica novas skills automaticamente todo dia às 03:00 AM.
  - Instalação automática de dependências (`npm install`) para novas skills.
- **Segurança**: Executa como usuário não-root (`openclaw`) com patch de compatibilidade para Docker API 1.24.

---

## 🛠️ Instalação e Uso

### Pré-requisitos
- Um servidor VPS (Ubuntu/Debian recomendado), preferencialmente "limpo".
- Acesso root (ou sudo sem senha).
- **Não é necessário instalar nada antes:** O script instalará automaticamente Docker, Docker Compose, Git, Swarm, Traefik, Portainer e todas as dependências.

### ☁️ Instalação em VPS (Produção)

Para facilitar o deploy em servidores VPS (Ubuntu/Debian), criamos o **SetupOpenclaw**, um script automatizado que configura todo o ambiente utilizando Docker Swarm e integra-se nativamente com o Traefik.

✨ **O que o SetupOpenclaw faz:**

*   Instala dependências (Docker, Docker Compose, Git, jq, etc.).
*   Inicia e configura o **Docker Swarm**.
*   Gera e implanta a Stack completa do OpenClaw (dinamicamente).
*   Integração automática com **Traefik** (Proxy Reverso e SSL) e **Portainer** (Gestão).
*   Configura resolução de DNS local (`/etc/hosts`) para facilitar o acesso interno.

🚀 **Como usar:**

Acesse seu servidor via SSH como `root` e execute o comando abaixo:

```bash
rm -rf SetupOpenclaw.sh && curl -sSL https://raw.githubusercontent.com/alltomatos/openclaw-docker/main/SetupOpenclaw.sh -o SetupOpenclaw.sh && chmod +x SetupOpenclaw.sh && ./SetupOpenclaw.sh
```

![Setup OpenClaw Menu](./imagem/setup2.9.5.png)

O menu interativo (v2.9.7+) facilita o gerenciamento do ambiente:

**Configuração & Operação**
1.  **Setup Infraestrutura (Swarm)**: Opção recomendada ("Zero to Hero"). Instala Docker, Swarm, Traefik e Portainer.
2.  **Deploy OpenClaw (Aplicação)**: Gera a configuração e faz o deploy do OpenClaw no cluster.
3.  **Wizard de Configuração (Onboard)**: Executa o assistente oficial de configuração (Onboarding).
4.  **Configurar Modo (Local/Remoto)**: Ajusta o modo de operação do Gateway.
5.  **Acessar Terminal / CLI**: Menu avançado com acesso direto a ferramentas internas (`openclaw doctor`, `dashboard`, etc).

**Ferramentas & Diagnóstico**
6.  **Ver Logs do Sistema**: Visualize logs do OpenClaw, Portainer ou Traefik diretamente no menu.
7.  **Exibir Dados de Conexão**: Mostra URLs e Tokens de acesso.
8.  **Resetar Senha do Portainer**: Utilitário para recuperar acesso administrativo.

**Limpeza**
9.  **Remover OpenClaw**: Remove a stack e dados da aplicação.
10. **Desinstalar Docker**: Remove completamente o Docker e todos os dados (limpeza total).

### 🌟 Destaque: Instalação Completa (Opção 1)
Esta opção transforma um VPS vazio em um ambiente de produção completo em minutos.
- **Docker Swarm**: Inicia automaticamente o cluster Swarm.
- **Automação Total**: Instala **Traefik** (Proxy Reverso com SSL) e **Portainer** (Interface de Gestão).
- **Gestão Facilitada**: Já cria o **usuário Admin do Portainer** para você.
- **Credenciais Seguras**: Ao final, todas as senhas, tokens e URLs gerados são salvos em um arquivo protegido:
  ```bash
  /root/dados_vps/openclaw.txt
  ```
  *(Apenas o usuário root pode ler este arquivo)*.

### 🔐 Segurança (Opcional)

Se você configurar autenticação durante o setup, o script irá gerar automaticamente os middlewares do Traefik necessários no arquivo `openclaw.yaml`.

### 2. Configuração Inicial (Onboarding)
Se for a primeira vez, você precisará configurar suas chaves de API (LLM) e canais.
O sistema já inicia com uma **política de segurança padrão** (Sandboxing: All, Tool Policy: Safe).

Você pode configurar suas chaves de três formas:

**Opção A: Via Setup Wizard (Recomendado)**
Selecione a **opção 3** no menu do `SetupOpenclaw.sh`. Isso iniciará o assistente interativo oficial dentro do container.

**Opção B: Via CLI dedicado**
```bash
# Para configuração inicial ou ajustes (mantém defaults seguros)
docker exec -it $(docker ps -q -f name=openclaw) openclaw configure
```

### 🛡️ Política de Segurança e Sandboxing
Por padrão, este instalador configura o OpenClaw em modo **Secure by Default**:
- **Sandboxing:** Ativado para **TODAS** as sessões (`agents.defaults.sandbox.mode: "all"`).
- **Workspace:** Permissão de escrita (`rw`) para que as tools possam trabalhar.
- **Modo Elevado:** Habilitado para administradores (`tools.elevated.enabled: true`).

Se precisar ajustar, edite o arquivo `openclaw.json` gerado em `/root/openclaw/config/openclaw.json` (ou use o Wizard).

### 🔑 Autenticação Avançada (Headless/Automação)
Para instalações automatizadas, o token de gateway é configurado via variável de ambiente `OPENCLAW_GATEWAY_TOKEN` no `openclaw.yaml` gerado.

### 📱 Canais e Configuração (Channels)

Além do WhatsApp, o OpenClaw suporta diversos outros canais como Telegram, Discord, Slack, etc.

#### 1. Conectar WhatsApp (QR Code)
A forma mais fácil é usar o menu do instalador:
1.  Execute `./SetupOpenclaw.sh`
2.  Escolha a **Opção 7 - Gerar QR Code WhatsApp**.
3.  📱 **Ação:** Tenha seu celular pronto em **Aparelhos Conectados > Conectar um aparelho**, pois o código expira rápido.

#### 2. Conectar Telegram
Para o Telegram, você precisa de um Bot Token (fale com o @BotFather).

```bash
# Adicionar token via CLI (dentro do container ou via Wizard)
openclaw channels add --channel telegram --token SEU_TOKEN_AQUI
```

#### 3. Configuração Avançada (openclaw.json)
O arquivo de configuração principal fica em `/home/openclaw/.openclaw/openclaw.json` (dentro do volume montado em `/root/openclaw`).

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
 ...
```
