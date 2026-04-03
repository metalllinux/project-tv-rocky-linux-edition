FROM docker.io/chinachu/mirakurun:latest

# Build recpt1 with px4_drv chardev support
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential autoconf automake pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Clone px4_drv for the ptx_ioctl.h header
RUN git clone --depth 1 https://github.com/tsukumijima/px4_drv.git /tmp/px4_drv

# Clone and build recpt1 (stz2012 fork with px4_drv support)
RUN git clone --depth 1 https://github.com/stz2012/recpt1.git /tmp/recpt1 \
    && cd /tmp/recpt1/recpt1 \
    && sed -i 's|char\* tuner_name = NULL;|const char* tuner_name = NULL;|g' pt1_dev.h 2>/dev/null || true \
    && ./autogen.sh \
    && ./configure --enable-b25 \
        CPPFLAGS="-I/tmp/px4_drv/include" \
    && make -j$(nproc) \
    && make install \
    && cd / \
    && rm -rf /tmp/recpt1 /tmp/px4_drv

# Verify recpt1 is installed
RUN recpt1 --version
