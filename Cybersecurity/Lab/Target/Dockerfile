FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_MIRROR=http://mirrors.aliyun.com/ubuntu

RUN sed -i \
        -e "s|http://archive.ubuntu.com/ubuntu/|${UBUNTU_MIRROR%/}/|g" \
        -e "s|http://security.ubuntu.com/ubuntu/|${UBUNTU_MIRROR%/}/|g" \
        -e 's/^Components:.*/Components: main/' \
        /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get \
        -o Acquire::Retries=5 \
        -o Acquire::http::Timeout=120 \
        update \
    && apt-get install -y --no-install-recommends \
        apache2 \
        curl \
        iproute2 \
        iputils-ping \
    && rm -rf /var/lib/apt/lists/*

RUN echo "Ubuntu target is running" > /var/www/html/index.html

EXPOSE 80

CMD ["apachectl", "-D", "FOREGROUND"]
