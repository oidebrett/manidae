#!/bin/sh
# NLWeb component setup: copy template config if present
set -e
if [ -f "/host-setup/templates/nlweb_config/config_nlweb.yaml" ]; then
  mkdir -p /host-setup/config/nlweb
  cp -r "/host-setup/templates/nlweb_config/" "/host-setup/config/nlweb/"
fi

