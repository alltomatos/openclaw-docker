# 🦞 OpenClaw Docker - Ambiente de Produção

Este repositório contém a configuração completa para rodar o **OpenClaw** em containers Docker, otimizado com Ubuntu 24.04 LTS, Node.js 22 e suporte total a automação de navegadores (Playwright).

## 🚀 Funcionalidades

- **Base Robusta**: Ubuntu 24.04 LTS + Node.js 22.
- **Navegadores Pré-instalados**: Chromium, Firefox e WebKit (via Playwright) prontos para uso.
- **Gerenciamento de Processos**: Utiliza **PM2** para manter o agente sempre online.
- **Gestão de Skills**:
  - Injeção segura de skills via diretório local.
  - **Auto-Reload Diário**: O sistema verifica novas skills automaticamente todo dia às 03:00 AM.
  - Instalação automática de dependências (`npm install`) para novas skills.
- **Segurança**: Executa como usuário não-root (`openclaw`).

---

## 🛠️ Instalação e Uso

### Pré-requisitos
- Docker & Docker Compose instalados.

### 1. Iniciar o Agente
```bash
docker compose up -d
```

### 2. Configuração Inicial (Onboarding)
Se for a primeira vez, você precisará configurar suas chaves de API (LLM) e canais:
```bash
docker compose exec openclaw openclaw onboard
```

---

## 🧠 Gerenciamento de Skills

Este ambiente possui um sistema avançado para gerenciamento de capacidades (Skills).

### Como adicionar uma nova Skill

1.  **Clone a skill** para a pasta `./skills` na raiz deste projeto.
    Use o script facilitador para fazer isso de forma segura:
    ```bash
    ./add_skill.sh https://github.com/usuario/repo-da-skill
    ```

2.  **Ativação**:
    *   **Opção A (Automática)**: Aguarde até às 03:00 AM. O sistema detectará a nova pasta, instalará as dependências e reiniciará o agente.
    *   **Opção B (Manual/Imediata)**: Force a detecção agora mesmo:
        ```bash
        docker compose exec openclaw /usr/local/bin/scan_skills.sh
        ```
    *   **Opção C (Reinício)**: Reinicie o container:
        ```bash
        docker compose restart openclaw
        ```

### Estrutura de Diretórios

O diretório `./skills` do seu host é mapeado diretamente para dentro do container.
```text
.
├── skills/                  # Suas skills locais (Git Repos)
│   ├── skill-google-search/
│   └── skill-pdf-reader/
├── docker-compose.yml       # Orquestração
├── Dockerfile               # Definição da Imagem
└── ...
```

---

## 🐳 Desenvolvimento e Manutenção

### Construir a Imagem Localmente
Se você fez alterações no Dockerfile:
```bash
docker build -t openclaw:latest .
```

### Publicar no Docker Hub
Para enviar uma nova versão para o registro público (requer login):
```bash
./push_to_hub.sh seu-usuario-dockerhub
# Exemplo: ./push_to_hub.sh watink
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
