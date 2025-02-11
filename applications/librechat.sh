#!/usr/bin/bash

# References:
# https://github.com/danny-avila/LibreChat/blob/main/docker-compose.yml
# https://www.librechat.ai/docs/local/docker
# https://github.com/themattman/mongodb-raspberrypi-docker
# https://github.com/gjpin/mongodb-raspberrypi-docker
# https://github.com/danny-avila/LibreChat/blob/main/.env.example
# https://www.librechat.ai/docs/configuration/dotenv

# Create Docker network
docker network create librechat

# Create directories
mkdir -p ${DATA_PATH}/librechat/docker
mkdir -p ${DATA_PATH}/librechat/configs
mkdir -p ${DATA_PATH}/librechat/volumes/librechat/{logs,images}
mkdir -p ${DATA_PATH}/librechat/volumes/{mongodb,pgvector,meilisearch}

# Fix permissions
sudo chown -R 1000:1000 ${DATA_PATH}/librechat/configs
sudo chown -R 1000:1000 ${DATA_PATH}/librechat/volumes

################################################
##### Docker Compose
################################################

tee ${DATA_PATH}/librechat/docker/docker-compose.yml << EOF
services:
  librechat:
    image: ghcr.io/danny-avila/librechat-dev:15c55d226e1e19abcda140335f30b5cbf9c299e6
    pull_policy: always
    container_name: librechat
    restart: always
    user: "${UID}:${GID}"
    networks:
      - librechat
    env_file:
      - config.env
    volumes:
      - ${DATA_PATH}/librechat/volumes/librechat/images:/app/client/public/images
      - ${DATA_PATH}/librechat/volumes/librechat/logs:/app/api/logs
      - ${DATA_PATH}/librechat/configs/librechat.yaml:/app/librechat.yaml
    depends_on:
      - librechat-mongodb
      - librechat-rag

  librechat-mongodb:
    container_name: librechat-mongodb
    image: ghcr.io/gjpin/mongodb-raspberrypi-docker:7.0.14
    restart: always
    user: "${UID}:${GID}"
    volumes:
      - ${DATA_PATH}/librechat/volumes/mongodb:/data/db
    command: mongod --noauth
    networks:
      - librechat

  librechat-meilisearch:
    container_name: librechat-meilisearch
    image: docker.io/getmeili/meilisearch:v1.12.8
    env_file:
      - config.env
    user: "${UID}:${GID}"
    volumes:
      - ${DATA_PATH}/librechat/volumes/meilisearch:/meili_data
    restart: always
    networks:
      - librechat

  librechat-pgvector:
    container_name: librechat-pgvector
    image: docker.io/pgvector/pgvector:0.8.0-pg17
    env_file:
      - config.env
    volumes:
      - ${DATA_PATH}/librechat/volumes/pgvector:/var/lib/postgresql/data
    restart: always
    networks:
      - librechat

  librechat-rag:
    container_name: librechat-rag
    image: ghcr.io/danny-avila/librechat-rag-api-dev-lite:9e4bb52e15d97856e3b69653c88d2cf1bb34324f
    pull_policy: always
    restart: always
    networks:
      - librechat
    env_file:
      - config.env
    depends_on:
      - librechat-pgvector

networks:
  librechat:
    external: true
EOF

################################################
##### Environment variables
################################################

tee ${DATA_PATH}/librechat/docker/config.env << EOF
# Server
HOST=0.0.0.0
PORT=3080
MONGO_URI=mongodb://librechat-mongodb:27017/LibreChat
DOMAIN_CLIENT=${LIBRECHAT_DOMAIN_CLIENT}
DOMAIN_SERVER=${LIBRECHAT_DOMAIN_SERVER}
NO_INDEX=true
DEBUG_LOGGING=true
DEBUG_CONSOLE=false
CONSOLE_JSON=false

# RAG
RAG_PORT=8000
RAG_API_URL=http://librechat-rag:8000
DB_HOST=librechat-pgvector
DB_PORT=5432
RAG_OPENAI_API_KEY=${LIBRECHAT_RAG_OPENAI_API_KEY}
EMBEDDINGS_PROVIDER=openai
EMBEDDINGS_MODEL=text-embedding-3-small

# Endpoints
DEBUG_PLUGINS=true
OPENAI_API_KEY=${LIBRECHAT_OPENAI_API_KEY}
GROQ_API_KEY=${LIBRECHAT_GROQ_API_KEY}
MISTRAL_API_KEY=${LIBRECHAT_MISTRAL_API_KEY}
DEEPSEEK_API_KEY=${LIBRECHAT_DEEPSEEK_API_KEY}

# Credentials
CREDS_KEY=${LIBRECHAT_CREDS_KEY}
CREDS_IV=${LIBRECHAT_CREDS_IV}

# Meilisearch
SEARCH=true
MEILI_NO_ANALYTICS=true
MEILI_HOST=http://librechat-meilisearch:7700
MEILI_MASTER_KEY=${LIBRECHAT_MEILI_MASTER_KEY}

# User system
OPENAI_MODERATION=false
BAN_VIOLATIONS=false
LIMIT_MESSAGE_IP=true
LIMIT_MESSAGE_USER=false
CHECK_BALANCE=false
ALLOW_EMAIL_LOGIN=true
ALLOW_REGISTRATION=true
ALLOW_SOCIAL_LOGIN=false
ALLOW_SOCIAL_REGISTRATION=false
ALLOW_PASSWORD_RESET=false
ALLOW_ACCOUNT_DELETION=true
ALLOW_UNVERIFIED_EMAIL_LOGIN=true
ALLOW_SHARED_LINKS=false
ALLOW_SHARED_LINKS_PUBLIC=false
JWT_SECRET=${LIBRECHAT_JWT_SECRET}
JWT_REFRESH_SECRET=${LIBRECHAT_JWT_REFRESH_SECRET}

# UI
APP_TITLE=LibreChat
HELP_AND_FAQ_URL=https://librechat.ai

# pgvector (postgres)
POSTGRES_PASSWORD=${LIBRECHAT_POSTGRES_PASSWORD}
POSTGRES_USER=librechat
POSTGRES_DB=librechat
EOF

################################################
##### Config
################################################

tee ${DATA_PATH}/librechat/configs/librechat.yaml << EOF
version: 1.2.1
 
cache: true
 
interface:
  privacyPolicy:
    externalUrl: 'https://librechat.ai/privacy-policy'
    openNewTab: true
 
  termsOfService:
    externalUrl: 'https://librechat.ai/tos'
    openNewTab: true

  endpointsMenu: true
  modelSelect: true
  parameters: true
  sidePanel: true
  presets: true
  prompts: true
  bookmarks: true
  multiConvo: true
  agents: true
 
registration:
  socialLogins: []
 
endpoints:
  custom:
 
    # groq
    - name: "groq"
      apiKey: "${LIBRECHAT_GROQ_API_KEY}"
      baseURL: "https://api.groq.com/openai/v1/"
      models:
        default: [
          "deepseek-r1-distill-llama-70b",
          "deepseek-r1-distill-qwen-32b",
          "llama-3.3-70b-versatile",
          "qwen-2.5-32b",
          "mixtral-8x7b-32768"
        ]
        fetch: false
      titleConvo: true
      titleModel: "deepseek-r1-distill-llama-70b"
      modelDisplayLabel: "Deepseek R1 Distill Lama"
 
    # Mistral AI API
    - name: "Mistral"
      apiKey: "${LIBRECHAT_MISTRAL_API_KEY}"
      baseURL: "https://api.mistral.ai/v1"
      models:
        default: [
          "codestral-latest",
          "mistral-large-latest",
          "pixtral-large-latest"
        ]
        fetch: true
      titleConvo: true
      titleModel: "mistral-large-latest"
      modelDisplayLabel: "Mistral Large"

    # Deepseek
    - name: "Deepseek"
      apiKey: "${LIBRECHAT_DEEPSEEK_API_KEY}"
      baseURL: "https://api.deepseek.com/v1"
      models:
        default: [
          "deepseek-chat", 
          "deepseek-coder", 
          "deepseek-reasoner"
        ]
        fetch: false
      titleConvo: true
      titleModel: "deepseek-chat"
      modelDisplayLabel: "Deepseek Chat"
EOF