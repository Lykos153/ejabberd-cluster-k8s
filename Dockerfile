# ARG EJABBERD_VERSION
FROM ejabberd/ecs:21.12

ENV EJABBERD_HOSTS=localhost \
    EJABBERD_ERLANG_NODE="ejabberd@$(hostname -f)"

USER root

RUN apk add --no-cache curl jq gettext

COPY entrypoint.sh ready-probe.sh /


# Setup runtime environment
USER ejabberd
WORKDIR $HOME

ENTRYPOINT exec /entrypoint.sh
