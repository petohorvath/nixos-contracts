{ fixtures, ... }:
let
  inherit (fixtures) examples;
in
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

  testGrafanaExampleDeliversItsSecretsToItsStaticUnit = {
    expr = examples.grafana.result;
    expected = {
      security = {
        admin_password = "$__file{/run/credentials/grafana.service/grafana_admin-password}";
        secret_key = "$__file{/run/credentials/grafana.service/grafana_secret-key}";
      };
      loadCredential = [
        "grafana_secret-key:/run/agenix/grafana_secret-key"
        "grafana_admin-password:/run/agenix/grafana_admin-password"
      ];
      installed = {
        grafana_admin-password = {
          owner = "root";
          group = "root";
          mode = "0440";
        };
        grafana_secret-key = {
          owner = "root";
          group = "root";
          mode = "0440";
        };
      };
      failures = [ ];
    };
  };

  testSharedTokenExampleCopiesEveryTelegrafTokenOnTheStore = {
    expr = examples.shared-token.result;
    expected = {
      copies = {
        influxdb_metrics_secrets_telegraf_token = {
          owner = "influxdb2";
          group = "influxdb2";
          mode = "0400";
          rekeyFile = "metrics/telegraf_token.age";
          generator = null;
        };
        influxdb_store_secrets_telegraf_token = {
          owner = "influxdb2";
          group = "influxdb2";
          mode = "0400";
          rekeyFile = "store/telegraf_token.age";
          generator = null;
        };
      };
      original = "metrics/telegraf_token.age";
      auths = {
        metrics_secrets_telegraf_token = "/run/agenix/influxdb_metrics_secrets_telegraf_token";
        store_secrets_telegraf_token = "/run/agenix/influxdb_store_secrets_telegraf_token";
      };
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
}
