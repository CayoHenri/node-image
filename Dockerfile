# ============================================================
# STAGE 1 - BUILD
# Responsável por instalar as dependências da aplicação. npm e demais ferramentas ficam disponíveis nesta etapa.
# ============================================================

# Usa a imagem oficial do Node baseada em Alpine."AS build" dá um nome para esta etapa do build.
FROM node:alpine AS build

# Define um argumento que pode ser informado durante o docker build.
# Exemplo:docker build --build-arg NODE_ENV_ARG=production -t node-image:good .
ARG NODE_ENV_ARG=production

# Transforma o argumento recebido em uma variável de ambiente.
ENV NODE_ENV=$NODE_ENV_ARG

# Define o diretório de trabalho dentro do container.
WORKDIR /app

# Copia primeiro apenas os arquivos responsáveis pelas dependências. Isso melhora o aproveitamento do cache de camadas do Docker.
COPY package*.json ./

# Instala somente as dependências necessárias em produção. npm ci utiliza exatamente as versões definidas no package-lock.json.
# Depois limpa o cache do npm para evitar arquivos desnecessários.
RUN npm ci --omit=dev \
    && npm cache clean --force

# Copia o restante do código-fonte da aplicação.
COPY . .


# ============================================================
# STAGE 2 - RUNTIME
# Imagem final utilizada para executar a aplicação.
# Não precisamos utilizar npm durante a execução.
# ============================================================

FROM node:alpine AS production

# Define o ambiente como produção.
ENV NODE_ENV=production

# Define o diretório da aplicação.
WORKDIR /app

# Copia da etapa "build" somente a aplicação já preparada.
COPY --from=build /app /app

# ------------------------------------------------------------
# SEGURANÇA
# ------------------------------------------------------------

# Remove o npm e o npx da imagem final.
#
# A aplicação será executada diretamente com: node src/app.js
#
# Portanto, npm não é necessário em runtime.
#
# Isso também reduz a superfície de ataque da imagem e remove
# dependências vulneráveis que podem existir dentro do próprio npm,
# como brace-expansion, minimatch, glob, tar etc.
RUN rm -rf /usr/local/lib/node_modules/npm \
    && rm -f /usr/local/bin/npm \
    && rm -f /usr/local/bin/npx

# ------------------------------------------------------------
# USUÁRIO
# ------------------------------------------------------------

# Cria um grupo chamado "caio".
# -S cria um grupo de sistema.
#
# Depois cria o usuário "caio":
# -S -> usuário de sistema
# -G -> adiciona ao grupo caio
# -D -> não define senha
RUN addgroup -S caio \
    && adduser -S caio -G caio -D \
    && chown -R caio:caio /app

# A partir daqui, o container não executará como root.
# Isso reduz o impacto caso a aplicação seja comprometida.
USER caio

# Documenta que a aplicação utiliza a porta 3000.
EXPOSE 3000

# ------------------------------------------------------------
# HEALTHCHECK
# ------------------------------------------------------------

# Verifica se a aplicação continua respondendo.
#
# Utilizamos Node em vez de curl porque a imagem node:alpine
# normalmente não possui curl instalado.
#
# --interval=30s -> executa a cada 30 segundos
# --timeout=3s   -> considera falha se demorar mais de 3 segundos
# --start-period -> aguarda antes de considerar falhas na inicialização
# --retries=3    -> após 3 falhas o container fica "unhealthy"
#
HEALTHCHECK \
    --interval=30s \
    --timeout=3s \
    --start-period=10s \
    --retries=3 \
    CMD node -e "fetch('http://localhost:3000/').then(r => { if (!r.ok) process.exit(1) }).catch(() => process.exit(1))"

# ------------------------------------------------------------
# INICIALIZAÇÃO
# ------------------------------------------------------------

# Executa diretamente o Node, sem depender de npm.
CMD ["node", "src/app.js"]