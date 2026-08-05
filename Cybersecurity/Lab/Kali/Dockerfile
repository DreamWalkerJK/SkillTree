FROM docker.io/kalilinux/kali-rolling

ARG DEBIAN_FRONTEND=noninteractive

# Use HTTP only to bootstrap the CA bundle, then use HTTPS mirrors.
ARG KALI_BOOTSTRAP_MIRROR=http://mirror.nju.edu.cn/kali/
ARG KALI_MIRROR=https://mirror.nju.edu.cn/kali/
ARG KALI_FALLBACK_MIRROR=https://mirrors.ustc.edu.cn/kali/
ARG KALI_SECOND_FALLBACK_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/kali/
ARG KALI_TERTIARY_MIRROR=https://mirrors.aliyun.com/kali/
ARG APT_RETRIES=5
ARG APT_TIMEOUT=120
ARG APT_INSTALL_ROUNDS=2

RUN --mount=type=cache,id=lab-kali-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=lab-kali-apt-archives,target=/var/cache/apt/archives,sharing=locked \
    set -eux; \
    printf '%s\n' \
        'Types: deb' \
        "URIs: ${KALI_BOOTSTRAP_MIRROR%/}/" \
        'Suites: kali-rolling' \
        'Components: main' \
        'Signed-By: /usr/share/keyrings/kali-archive-keyring.gpg' \
        > /etc/apt/sources.list.d/kali.sources; \
    apt-get \
        -o Acquire::Retries="${APT_RETRIES}" \
        -o Acquire::http::Timeout="${APT_TIMEOUT}" \
        -o APT::Update::Error-Mode=any \
        update; \
    apt-get \
        -o Acquire::Retries="${APT_RETRIES}" \
        -o Acquire::http::Timeout="${APT_TIMEOUT}" \
        install -y --no-install-recommends ca-certificates

COPY --chmod=0755 apt-install-retry /usr/local/sbin/apt-install-retry

# 建议把需要的工具写进 Dockerfile，不要每次进入容器后再手工安装，否则重新构建或创建容器后容易丢失。
# Keep successful groups as independent image layers. A transient failure in
# Burp Suite or Metasploit no longer invalidates all previously installed tools.
RUN --mount=type=cache,id=lab-kali-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=lab-kali-apt-archives,target=/var/cache/apt/archives,sharing=locked \
    apt-install-retry \
        nmap \
        masscan \
        sqlmap \
        nikto \
        john \
        hydra \
        iproute2 \
        iputils-ping \
        dnsutils \
        netcat-openbsd \
        git \
        curl \
        wget \
        vim

RUN --mount=type=cache,id=lab-kali-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=lab-kali-apt-archives,target=/var/cache/apt/archives,sharing=locked \
    apt-install-retry burpsuite

RUN --mount=type=cache,id=lab-kali-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,id=lab-kali-apt-archives,target=/var/cache/apt/archives,sharing=locked \
    apt-install-retry metasploit-framework

RUN rm -f /usr/local/sbin/apt-install-retry

WORKDIR /root/kali-test

CMD ["sleep", "infinity"]
