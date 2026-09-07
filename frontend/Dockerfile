FROM docker.io/nginxinc/nginx-unprivileged:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 8080
CMD ["nginx","-g","daemon off;"]
