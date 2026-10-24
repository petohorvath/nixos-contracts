{ examples }:
{
  testInfluxdbExampleWiresTheDaemonAndBackends = {
    expr = examples.influxdb.result;
    expected = {
      bindAddress = "127.0.0.1:8086";
      initialSetup = {
        passwordFile = "/run/agenix/influxdb-admin-password";
        tokenFile = "/run/agenix/influxdb-admin-token";
      };
      preserved = [
        {
          directory = "/var/lib/influxdb2";
          user = "influxdb2";
          group = "influxdb2";
          mode = "0700";
        }
      ];
      secrets = {
        influxdb-admin-password = {
          owner = "root";
          group = "influxdb2";
          mode = "0440";
          rekeyFile = "influxdb-admin-password.age";
          generator = "alnum";
        };
        influxdb-admin-token = {
          owner = "root";
          group = "influxdb2";
          mode = "0440";
          rekeyFile = "influxdb-admin-token.age";
          generator = null;
        };
      };
      failures = [ ];
    };
  };

  testAlloyExampleDeliversItsSecretAsACredential = {
    expr = examples.alloy.result;
    expected = {
      listenFlags = [ "--server.http.listen-addr=127.0.0.1:12345" ];
      passwordFile = "/run/credentials/alloy.service/alloy-loki-main-password";
      loadCredential = [ "alloy-loki-main-password:/run/agenix/alloy-loki-main-password" ];
      installed = {
        owner = "root";
        group = "root";
        mode = "0440";
        path = "/run/agenix/alloy-loki-main-password";
        generator = "alnum";
      };
      failures = [ ];
    };
  };

  testSharedTokenExampleCopiesAnotherNodesSecret = {
    expr = examples.sharedToken.result;
    expected = {
      copy = {
        owner = "root";
        group = "influxdb2";
        mode = "0440";
        rekeyFile = "metrics/telegraf-token.age";
        generator = null;
      };
      original = "metrics/telegraf-token.age";
      storesOwn = "store/telegraf-token.age";
      auths.telegraf-metrics = "/run/agenix/influxdb-writer-telegraf-metrics";
      failures = {
        metrics = [ ];
        store = [ ];
      };
    };
  };

  testExporterExampleHoldsTheHelpersBindOnItsOwnContract = {
    expr = examples.exporter.result;
    expected = {
      binds = {
        chrony-ntp = [ "0.0.0.0:123" ];
        chrony-exporter-metrics = [ "127.0.0.1:9123" ];
      };
      identities = {
        chrony.static = {
          user = "chrony";
          group = null;
        };
        chrony-exporter.static = {
          user = "chrony";
          group = null;
        };
      };
      exporterListen = "127.0.0.1:9123";
      failures = [ ];
    };
  };

  testCustomKindExampleFoldsAndClashes = {
    expr = examples.customKind.result;
    expected = {
      claimSet = {
        grafana-main = {
          database = "grafana";
          owner = "grafana";
        };
        vaultwarden-main = {
          database = "vaultwarden";
          owner = "vaultwarden";
        };
        vaultwarden-attachments = {
          database = "vaultwarden_attachments";
          owner = "vaultwarden";
        };
      };
      validFailures = [ ];
      clashingFailures = [
        "nixos-contracts: databases claims `grafana-main` and `vaultwarden-attachments` clash: both own `grafana`."
      ];
    };
  };
}
