ARG CONSUL_VERSION=latest
FROM hashicorp/consul:${CONSUL_VERSION}
RUN apk add --no-cache bash ca-certificates
ADD rootfs /
RUN chmod +x /docker-bootstrap.sh
VOLUME [ "/consul/certs" ]
ENTRYPOINT [ "/docker-bootstrap.sh" ]
CMD ["agent", "-dev", "-client", "0.0.0.0"]
