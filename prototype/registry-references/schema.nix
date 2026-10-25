# PROTOTYPE, throwaway. The shared schema a fleet would own: structure
# (who runs what, which proxy fronts it, which stores exist) plus the
# contract references senders contribute in place of `sendTo`.
{ contractsLib }:
{ lib, ... }:
let
  inherit (lib) mkOption types;
  secretRef = contractsLib.types.referenceTo "secrets";

  vhost = types.submodule {
    options = {
      proxy = mkOption { type = types.str; };
      domain = mkOption { type = types.str; };
      maxBodySize = mkOption {
        type = types.str;
        default = "1m";
      };
      websockets = mkOption {
        type = types.bool;
        default = false;
      };
      readTimeout = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      basicAuth = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  export = types.submodule {
    options = {
      # The bind as a contract reference; the proxy resolves its port.
      bind = mkOption { type = contractsLib.types.referenceTo "binds"; };
      vhost = mkOption {
        type = types.nullOr vhost;
        default = null;
      };
    };
  };

  instance = types.submodule {
    options = {
      node = mkOption { type = types.str; };
      exports = mkOption {
        type = types.attrsOf export;
        default = { };
      };
      # Basic-auth clients, by the client claim's name; lazy, so reading
      # one client forces no other node.
      clients = mkOption {
        type = types.lazyAttrsOf secretRef;
        default = { };
      };
    };
  };

  # Keyed by store name, so a writer contributes without reading the
  # combined data to find which instance holds the store.
  store = types.submodule {
    options = {
      node = mkOption { type = types.str; };
      organization = mkOption { type = types.str; };
      bucket = mkOption { type = types.str; };
      writers = mkOption {
        type = types.lazyAttrsOf secretRef;
        default = { };
      };
      readers = mkOption {
        type = types.lazyAttrsOf secretRef;
        default = { };
      };
    };
  };
in
{
  options = {
    nodes = mkOption {
      type = types.attrsOf (types.submodule { options.address = mkOption { type = types.str; }; });
      default = { };
    };
    services = mkOption {
      type = types.attrsOf (types.attrsOf instance);
      default = { };
    };
    stores = mkOption {
      type = types.attrsOf store;
      default = { };
    };
  };
}
