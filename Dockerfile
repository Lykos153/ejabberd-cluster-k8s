# ARG EJABBERD_VERSION
FROM ghcr.io/processone/ejabberd:21.12

ENV EJABBERD_HOSTS=localhost \
    EJABBERD_ERLANG_NODE="ejabberd@$(hostname -f)"

USER root

RUN apk add --no-cache curl jq gettext

COPY entrypoint.sh ready-probe.sh /
COPY --from=vaporio/k8s-elector:1.2.0 elector /usr/local/bin/elector

# Setup runtime environment
USER ejabberd
WORKDIR $HOME

ENTRYPOINT exec /entrypoint.sh
