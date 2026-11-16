# Runtime image for the Tichu authority server. The binary is compiled in CI
# (it needs the Flutter SDK's Dart for package resolution), see
# .github/workflows/deploy-authority.yml.
FROM debian:stable-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY authority /app/authority
COPY tichu_q_v3.safetensors /app/assets/bots/tichu_q_v3.safetensors
ENV TICHU_SUPABASE_AUTHORITY_HOST=0.0.0.0 \
    PORT=8080
EXPOSE 8080
CMD ["/app/authority"]
