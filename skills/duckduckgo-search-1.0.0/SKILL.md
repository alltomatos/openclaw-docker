---
name: duckduckgo-search
description: Realiza pesquisas na web usando o DuckDuckGo para recuperar informações em tempo real da internet. Use quando o usuário precisar pesquisar eventos atuais, documentação, tutoriais ou qualquer informação que exija recursos de pesquisa na web.
allowed-tools: Bash(duckduckgo-search:*), Bash(python:*), Bash(pip:*), Bash(uv:*)
---

# Skill de Pesquisa Web DuckDuckGo

Esta skill implementa funcionalidade de pesquisa na web através do mecanismo de busca DuckDuckGo, ajudando a obter informações em tempo real.

## Funcionalidades

- 🔍 Pesquisa baseada no DuckDuckGo com foco em privacidade
- 📰 Suporte a pesquisa de notícias
- 🖼️ Suporte a pesquisa de imagens
- 📹 Suporte a pesquisa de vídeos
- 🌐 Sem necessidade de API Key, uso gratuito
- 🔒 Proteção de privacidade, sem rastreamento de usuário

## Instalação

```bash
# Instalação via uv (recomendado)
uv pip install duckduckgo-search

# Ou instalação via pip
pip install duckduckgo-search
```

## Início Rápido

### Modo Linha de Comando

```bash
# Pesquisa de texto básica
python -c "
from duckduckgo_search import DDGS

with DDGS() as ddgs:
    results = list(ddgs.text('Python tutorial', max_results=5))
    for r in results:
        print(f\"Título: {r['title']}\")
        print(f\"Link: {r['href']}\")
        print(f\"Resumo: {r['body']}\")
        print('---')
"
```

## Tipos de Pesquisa

### 1. Pesquisa de Texto (Text Search)

A forma mais comum de pesquisa, retornando resultados de páginas web:

```bash
python -c "
from duckduckgo_search import DDGS

query = 'sua consulta de pesquisa'

with DDGS() as ddgs:
    results = list(ddgs.text(
        query,
        region='cn-zh',      # Configuração de região: cn-zh(China), us-en(EUA), wt-wt(Global)
        safesearch='moderate', # Pesquisa segura: on, moderate, off
        timelimit='m',       # Intervalo de tempo: d(dia), w(semana), m(mês), y(ano), None(sem limite)
        max_results=10       # Número máximo de resultados
    ))
    
    for i, r in enumerate(results, 1):
        print(f\"{i}. {r['title']}\")
        print(f\"   URL: {r['href']}\")
        print(f\"   Resumo: {r['body'][:100]}...\")
        print()
"
```

### 2. Pesquisa de Notícias (News Search)

Pesquisa por notícias recentes:

```bash
python -c "
from duckduckgo_search import DDGS

with DDGS() as ddgs:
    results = list(ddgs.news(
        'AI technology',
        region='wt-wt',
        safesearch='moderate',
        timelimit='d',       # d=últimas 24 horas, w=última semana, m=último mês
        max_results=10
    ))
    
    for r in results:
        print(f\"📰 {r['title']}\")
        print(f\"   Fonte: {r['source']}\")
        print(f\"   Data: {r['date']}\")
        print(f\"   Link: {r['url']}\")
        print()
"
```

### 3. Pesquisa de Imagem (Image Search)

Pesquisa por recursos de imagem:

```bash
python -c "
from duckduckgo_search import DDGS

with DDGS() as ddgs:
    results = list(ddgs.images(
        'cute cats',
        region='wt-wt',
        safesearch='moderate',
        size='Medium',       # Small, Medium, Large, Wallpaper
        type_image='photo',  # photo, clipart, gif, transparent, line
        layout='Square',     # Square, Tall, Wide
        max_results=10
    ))
    
    for r in results:
        print(f\"🖼️ {r['title']}\")
        print(f\"   Imagem: {r['image']}\")
        print(f\"   Miniatura: {r['thumbnail']}\")
        print(f\"   Fonte: {r['source']}\")
        print()
"
```

### 4. Pesquisa de Vídeo (Video Search)

Pesquisa por conteúdo de vídeo:

```bash
python -c "
from duckduckgo_search import DDGS

with DDGS() as ddgs:
    results = list(ddgs.videos(
        'Python programming',
        region='wt-wt',
        safesearch='moderate',
        timelimit='w',       # d, w, m
        resolution='high',   # high, standard
        duration='medium',   # short, medium, long
        max_results=10
    ))
    
    for r in results:
        print(f\"📹 {r['title']}\")
        print(f\"   Duração: {r.get('duration', 'N/A')}\")
        print(f\"   Fonte: {r['publisher']}\")
        print(f\"   Link: {r['content']}\")
        print()
"
```

### 5. Respostas Instantâneas (Instant Answers)

Obtém respostas instantâneas do DuckDuckGo:

```bash
python -c "
from duckduckgo_search import DDGS

with DDGS() as ddgs:
    results = ddgs.answers('what is python programming language')
    
    for r in results:
        print(f\"📚 {r['text']}\")
        print(f\"   Fonte: {r.get('url', 'DuckDuckGo')}\")
"
```

### 6. Sugestões de Pesquisa (Suggestions)

Obtém sugestões de pesquisa:

```bash
python -c "
from duckduckgo_search import DDGS

with DDGS() as ddgs:
    suggestions = list(ddgs.suggestions('python'))
    
    print('🔍 Sugestões de pesquisa:')
    for s in suggestions:
        print(f\"   - {s['phrase']}\")
"
```

### 7. Pesquisa de Mapas (Maps Search)

Pesquisa por informações de localização:

```bash
python -c "
from duckduckgo_search import DDGS

with DDGS() as ddgs:
    results = list(ddgs.maps(
        'coffee shop',
        place='Beijing, China',
        max_results=10
    ))
    
    for r in results:
        print(f\"📍 {r['title']}\")
        print(f\"   Endereço: {r['address']}\")
        print(f\"   Telefone: {r.get('phone', 'N/A')}\")
        print(f\"   Coordenadas: {r['latitude']}, {r['longitude']}\")
        print()
"
```

## Scripts Úteis

### Função de Pesquisa Genérica

Criando um script de pesquisa reutilizável:

```bash
python -c "
from duckduckgo_search import DDGS
import json

def web_search(query, search_type='text', max_results=5, region='wt-wt', timelimit=None):
    '''
    Executa pesquisa no DuckDuckGo
    
    Parâmetros:
        query: Palavra-chave de pesquisa
        search_type: Tipo de pesquisa (text, news, images, videos)
        max_results: Número máximo de resultados
        region: Região (cn-zh, us-en, wt-wt)
        timelimit: Limite de tempo (d, w, m, y)
    '''
    with DDGS() as ddgs:
        if search_type == 'text':
            results = list(ddgs.text(query, region=region, timelimit=timelimit, max_results=max_results))
        elif search_type == 'news':
            results = list(ddgs.news(query, region=region, timelimit=timelimit, max_results=max_results))
        elif search_type == 'images':
            results = list(ddgs.images(query, region=region, max_results=max_results))
        elif search_type == 'videos':
            results = list(ddgs.videos(query, region=region, timelimit=timelimit, max_results=max_results))
        else:
            results = []
    
    return results

# Exemplo de uso
query = 'Python 3.12 new features'
results = web_search(query, search_type='text', max_results=5)

print(f'🔍 Pesquisa: {query}')
print(f'📊 Encontrados {len(results)} resultados')
print()

for i, r in enumerate(results, 1):
    print(f\"{i}. {r['title']}\")
    print(f\"   {r['href']}\")
    print(f\"   {r['body'][:150]}...\")
    print()
"
```

### Pesquisar e Salvar Resultados

```bash
python -c "
from duckduckgo_search import DDGS
import json
from datetime import datetime

query = 'latest tech news'
output_file = f'search_results_{datetime.now().strftime(\"%Y%m%d_%H%M%S\")}.json'

with DDGS() as ddgs:
    results = list(ddgs.text(query, max_results=10))

# Salvar em arquivo JSON
with open(output_file, 'w', encoding='utf-8') as f:
    json.dump({
        'query': query,
        'timestamp': datetime.now().isoformat(),
        'results': results
    }, f, ensure_ascii=False, indent=2)

print(f'✅ Resultados da pesquisa salvos em: {output_file}')
print(f'📊 Total de {len(results)} resultados')
"
```

### Pesquisa em Lote com Múltiplas Palavras-chave

```bash
python -c "
from duckduckgo_search import DDGS
import time

queries = [
    'Python best practices 2024',
    'React vs Vue 2024',
    'AI development tools'
]

all_results = {}

with DDGS() as ddgs:
    for query in queries:
        print(f'🔍 Pesquisando: {query}')
        results = list(ddgs.text(query, max_results=3))
        all_results[query] = results
        print(f'   Encontrados {len(results)} resultados')
        time.sleep(1)  # Evitar requisições muito rápidas

print()
print('=' * 50)
print('📊 Resumo da Pesquisa')
print('=' * 50)

for query, results in all_results.items():
    print(f'\n🔎 {query}:')
    for i, r in enumerate(results, 1):
        print(f\"   {i}. {r['title'][:60]}...\")
"
```

## Explicação dos Parâmetros

### Códigos de Região (region)

| Código | Região |
|------|------|
| `cn-zh` | China |
| `us-en` | Estados Unidos |
| `uk-en` | Reino Unido |
| `jp-jp` | Japão |
| `kr-kr` | Coreia do Sul |
| `wt-wt` | Global (Sem restrição de região) |

### Limite de Tempo (timelimit)

| Valor | Significado |
|----|------|
| `d` | Últimas 24 horas |
| `w` | Última semana |
| `m` | Último mês |
| `y` | Último ano |
| `None` | Sem limite |

### Pesquisa Segura (safesearch)

| Valor | Significado |
|----|------|
| `on` | Filtragem estrita |
| `moderate` | Filtragem moderada (padrão) |
| `off` | Filtragem desligada |

## Tratamento de Erros

```bash
python -c "
from duckduckgo_search import DDGS
from duckduckgo_search.exceptions import DuckDuckGoSearchException

try:
    with DDGS() as ddgs:
        results = list(ddgs.text('test query', max_results=5))
        print(f'✅ Pesquisa bem-sucedida, encontrados {len(results)} resultados')
except DuckDuckGoSearchException as e:
    print(f'❌ Erro na pesquisa: {e}')
except Exception as e:
    print(f'❌ Erro desconhecido: {e}')
"
```

## Uso de Proxy

Se precisar usar um proxy:

```bash
python -c "
from duckduckgo_search import DDGS

# Configurar proxy
proxy = 'http://127.0.0.1:7890'  # Substitua pelo seu endereço de proxy

with DDGS(proxy=proxy) as ddgs:
    results = list(ddgs.text('test query', max_results=5))
    print(f'Pesquisa via proxy bem-sucedida, encontrados {len(results)} resultados')
"
```

## Perguntas Frequentes

**Falha na instalação?**
```bash
# Certifique-se de que o pip está na versão mais recente
pip install --upgrade pip
pip install duckduckgo-search

# Ou use uv
uv pip install duckduckgo-search
```

**Pesquisa sem resultados?**
```bash
# Verifique a conexão de rede
# Tente usar um proxy
# Reduza a complexidade das palavras-chave de pesquisa
# Verifique se a configuração de região está correta
```

**Requisições limitadas?**
```bash
# Adicione atraso entre múltiplas pesquisas
import time
time.sleep(1)  # Aguarde 1 segundo

# Reduza o número de resultados por requisição única
max_results=5  # Em vez de 50
```

## Integração com Outras Ferramentas

### Combinar com browser-use para obter conteúdo detalhado

```bash
# 1. Primeiro pesquise com DuckDuckGo
python -c "
from duckduckgo_search import DDGS

with DDGS() as ddgs:
    results = list(ddgs.text('Python async tutorial', max_results=1))
    if results:
        url = results[0]['href']
        print(f'URL: {url}')
"

# 2. Use browser-use para abrir e obter conteúdo detalhado
browser-use open <url_from_search>
browser-use state
```

## Observações Importantes

⚠️ **Sugestões de Uso**:

1. **Respeite os limites de frequência**: Evite um grande número de requisições em um curto período
2. **Defina o número de resultados razoavelmente**: Não solicite muitos resultados de uma vez
3. **Adicione atraso apropriado**: Ao pesquisar em lote, adicione `time.sleep()` entre as requisições
4. **Trate exceções**: Sempre adicione código de tratamento de erros
5. **Respeite os direitos autorais**: Os resultados da pesquisa são apenas para referência, preste atenção aos direitos autorais do conteúdo
