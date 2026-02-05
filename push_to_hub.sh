#!/bin/bash
set -e

# Verifica se o nome de usuário foi fornecido
if [ -z "$1" ]; then
    echo "Erro: Nome de usuário do Docker Hub não fornecido."
    echo "Uso: ./push_to_hub.sh <seu-usuario-dockerhub>"
    echo "Exemplo: ./push_to_hub.sh meuusuario"
    exit 1
fi

DOCKER_USER=$1
IMAGE_NAME="openclaw"
VERSION=$(date +%Y.%m.%d) # Tag baseada na data (ex: 2024.02.05)

echo "========================================================"
echo "🐳 Preparando para enviar $DOCKER_USER/$IMAGE_NAME para o Docker Hub"
echo "========================================================"

# Removemos a verificação estrita de 'docker system info' pois pode falhar em alguns ambientes
# Vamos deixar o próprio comando 'docker push' falhar se não houver autenticação.

# 1. Tagueia a imagem 'latest' local para o repositório remoto
echo "🏷️  Tagueando imagens..."
# Verifica se a imagem local existe antes de taguear
if ! docker image inspect $IMAGE_NAME:latest > /dev/null 2>&1; then
    echo "⚠️ Imagem local $IMAGE_NAME:latest não encontrada. Tentando construir..."
    docker build -t $IMAGE_NAME:latest .
fi

docker tag $IMAGE_NAME:latest $DOCKER_USER/$IMAGE_NAME:latest
docker tag $IMAGE_NAME:latest $DOCKER_USER/$IMAGE_NAME:$VERSION

# 2. Faz o push
echo "🚀 Enviando tag 'latest'..."
if docker push $DOCKER_USER/$IMAGE_NAME:latest; then
    echo "✅ Tag 'latest' enviada com sucesso."
else
    echo "❌ Falha ao enviar. Verifique se você está logado com 'docker login'."
    exit 1
fi

echo "🚀 Enviando tag '$VERSION'..."
if docker push $DOCKER_USER/$IMAGE_NAME:$VERSION; then
    echo "✅ Tag '$VERSION' enviada com sucesso."
else
    echo "❌ Falha ao enviar tag versionada."
    exit 1
fi

echo "========================================================"
echo "✅ Sucesso! Imagem disponível em:"
echo "   https://hub.docker.com/r/$DOCKER_USER/$IMAGE_NAME"
echo "========================================================"
