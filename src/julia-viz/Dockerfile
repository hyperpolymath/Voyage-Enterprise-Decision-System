FROM julia:1.10-bookworm

WORKDIR /app

# Install system dependencies for graphics
RUN apt-get update && apt-get install -y \
    libgl1-mesa-glx \
    libxrandr2 \
    libxinerama1 \
    libxcursor1 \
    libxi6 \
    libxext6 \
    libcairo2-dev \
    libpango1.0-dev \
    libjpeg-dev \
    libpng-dev \
    libgif-dev \
    fontconfig \
    && rm -rf /var/lib/apt/lists/*

# Copy project files
COPY Project.toml .
COPY src/ src/

# Install Julia packages
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# Expose Genie web server port
EXPOSE 8080

# Run the visualization server
CMD ["julia", "--project=.", "-e", "using VEDSViz; app = VEDSApp(); start_server(app)"]
