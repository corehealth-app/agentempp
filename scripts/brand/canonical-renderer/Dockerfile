FROM node@sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436

ENV BODYFLOW_BRAND_BASE_IMAGE=node@sha256:d649c27dae7ba0137b3cef5dd75baa422c08dc3d9e3fc0c23dfb172dc3cc6436
ENV VIPS_CONCURRENCY=1

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    fontconfig=2.14.1-4 \
    fontconfig-config=2.14.1-4 \
    fonts-liberation2=2.1.5-1 \
    libbrotli1=1.0.9-2+b6 \
    libexpat1=2.5.0-1+deb12u2 \
    libfontconfig1=2.14.1-4 \
    libfreetype6=2.12.1+dfsg-5+deb12u4 \
    libpng16-16=1.6.39-2+deb12u5 \
    libxml2=2.9.14+dfsg-1.3~deb12u6 \
    libxml2-utils=2.9.14+dfsg-1.3~deb12u6 \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/bodyflow-brand-renderer
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts=false --no-audit --no-fund \
  && test "$(node -p "require('sharp/package.json').version")" = "0.34.5" \
  && printf '%s  %s\n' \
    '8d91388f1d3604b3b8ae0e3ee2d140e50cd6122f9214514f4aca772540a4076d' \
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf' \
    'ba0e0dc3f7aca5b0afbc31e800531ee43be3aa79ae35b2ef1f6470a9547765c4' \
    '/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf' \
  | sha256sum --check --strict
