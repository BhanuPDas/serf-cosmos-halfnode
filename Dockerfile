# Stage 1: Build the Go application
FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
# This builds the Go binary and places it in /app/go-p2p-service inside this stage
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/go-p2p-service .

# Stage 2: Create the final image with Python and the Go app
FROM python:3.11-slim-bookworm
WORKDIR /app

# Copy Python webapp requirements and install them
COPY webapp/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the Python webapp code
COPY webapp/ ./webapp

# Copy the compiled Go service from the builder stage
COPY --from=builder /app/go-p2p-service .

# Copy the startup script and make it executable
COPY start.sh .
RUN chmod +x start.sh

# --- NEW LINES ---
# Install the official Serf CLI tool for debugging and checking members
RUN apt-get update && apt-get install -y unzip wget && \
    wget https://releases.hashicorp.com/serf/0.11.1/serf_0.11.1_linux_amd64.zip -O serf.zip && \
    unzip serf.zip && \
    mv serf /usr/local/bin/serf && \
    rm serf.zip
# --- END OF NEW LINES ---

EXPOSE 5000
CMD ["./start.sh"]
