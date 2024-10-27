# Stage 1: Build the frontend using Node.js
FROM node:16 as builder

WORKDIR /build
COPY web/package.json ./
RUN npm install
COPY ./web ./
COPY ./VERSION ./
RUN DISABLE_ESLINT_PLUGIN='true' VITE_REACT_APP_VERSION=$(cat VERSION) npm run build

# Stage 2: Build the Go backend
FROM golang AS builder2

ENV GO111MODULE=on \
    CGO_ENABLED=1 \
    GOOS=linux

WORKDIR /build
ADD go.mod go.sum ./
RUN go mod download
COPY . ./
COPY --from=builder /build/dist ./web/dist
RUN go build -ldflags "-s -w -X 'one-api/common.Version=$(cat VERSION)' -extldflags '-static'" -o one-api

# Stage 3: Create a minimal runtime image with Alpine
FROM alpine

# Install required dependencies
RUN apk update \
    && apk upgrade \
    && apk add --no-cache ca-certificates tzdata curl \
    && update-ca-certificates 2>/dev/null || true

# Copy the built Go binary
COPY --from=builder2 /build/one-api /

# Install cloudflared
RUN curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared

# Expose application and cloudflared ports
EXPOSE 3000 8080

# Set working directory for data
WORKDIR /data

# Copy the cloudflared configuration or set it up
# If you have a specific config file, you can copy it over. Otherwise, we assume you're using the key directly.
# COPY ./cloudflared-config.yml /etc/cloudflared/config.yml

# Set up the tunnel with the provided key (replace with your actual key)
ENV TUNNEL_KEY=eyJhIjoiNGYwN2QxOTUwMjcwZDEwMTRiYjY5NjQ2MmE5MGY3OTEiLCJ0IjoiZWI2OWNiYmQtMjc4OS00MWY5LWE2ZGYtMWIyN2MyMjM4YTNjIiwicyI6IlltVXlabUl5WWpBdE9UbGtOQzAwWmpkakxUZzFNakV0WlRZMk5EQXdNV0kyTUdRNSJ9

# Start both the app and cloudflared tunnel
CMD cloudflared tunnel --no-autoupdate run --token $TUNNEL_KEY & /one-api
