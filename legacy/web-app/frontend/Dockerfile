# LOCAL ONLY — In AWS this SPA is deployed to S3 contoso-web-frontend-s3 and served via CloudFront. The nginx /api/ proxy here stands in for CloudFront /api/* behavior (coupling C1).
# Multi-stage: build the Vue SPA with Node, serve the static bundle with nginx.
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx:alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html
RUN chown -R nginx:nginx /usr/share/nginx/html
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost/ || exit 1
EXPOSE 80
