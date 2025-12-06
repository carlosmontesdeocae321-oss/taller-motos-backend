# Dockerfile for the Express backend
# Uses node:18-alpine for small image size
FROM node:18-alpine

# Create app directory
WORKDIR /usr/src/app

# Install build dependencies for any native modules if needed
RUN apk add --no-cache python3 make g++

# Copy package manifests and install dependencies
COPY package.json package-lock.json* ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Ensure folders for uploads and invoices exist
RUN mkdir -p uploads/services invoices || true

# Expose port (backend default 3000)`
EXPOSE 3000

# Default environment variables (override at runtime)
ENV NODE_ENV=production
ENV PORT=3000

CMD ["node", "index.js"]
