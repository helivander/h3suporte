FROM node:24-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
RUN mkdir -p /app/dados && chown node:node /app/dados
USER node
ENV PORTA=21114 BANCO=/app/dados/h3suporte.db
EXPOSE 21114
VOLUME ["/app/dados"]
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:21114/saude || exit 1
CMD ["node", "src/main.js"]
