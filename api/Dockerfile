FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY server.mjs ./
RUN mkdir -p /app/uploads/profile && chown -R node:node /app/uploads
USER node
EXPOSE 3000
CMD ["npm","start"]
