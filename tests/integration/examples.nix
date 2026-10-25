{ examples }:
{
  testInfluxdbExampleWiresTheDaemonAndBackends = {
    expr = examples.influxdb.result;
    expected = {
      bindAddress = "127.0.0.1:8086";
      initialSetup = {
        passwordFile = "/run/agenix/influxdb_admin-password";
        tokenFile = "/run/agenix/influxdb_admin-token";
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
        influxdb_admin-password = {
          owner = "root";
          group = "influxdb2";
          mode = "0440";
          rekeyFile = "influxdb_admin-password.age";
          generator = "alnum";
        };
        influxdb_admin-token = {
          owner = "root";
          group = "influxdb2";
          mode = "0440";
          rekeyFile = "influxdb_admin-token.age";
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
      passwordFile = "/run/credentials/alloy.service/alloy_loki-main-password";
      loadCredential = [ "alloy_loki-main-password:/run/agenix/alloy_loki-main-password" ];
      installed = {
        owner = "root";
        group = "root";
        mode = "0440";
        path = "/run/agenix/alloy_loki-main-password";
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
        rekeyFile = "metrics/telegraf_token.age";
        generator = null;
      };
      original = "metrics/telegraf_token.age";
      storesOwn = "store/telegraf_token.age";
      auths.telegraf-metrics = "/run/agenix/influxdb_writer-telegraf-metrics";
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
        chrony.ntp = [ "0.0.0.0:123" ];
        chrony-exporter.metrics = [ "127.0.0.1:9123" ];
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
        grafana.main = {
          database = "grafana";
          owner = "grafana";
        };
        vaultwarden = {
          main = {
            database = "vaultwarden";
            owner = "vaultwarden";
          };
          attachments = {
            database = "vaultwarden_attachments";
            owner = "vaultwarden";
          };
        };
      };
      validFailures = [ ];
      clashingFailures = [
        "nixos-contracts: databases claims `grafana.main` and `vaultwarden.attachments` clash: both own `grafana`."
      ];
    };
  };
}
