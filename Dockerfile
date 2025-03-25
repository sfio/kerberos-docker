FROM alpine:3.20.6

RUN apk add --no-cache -u krb5-server tini krb5 netcat-openbsd

COPY configure.sh /var/lib/krb5kdc/

ENTRYPOINT ["/sbin/tini", "--", "/var/lib/krb5kdc/configure.sh"]
