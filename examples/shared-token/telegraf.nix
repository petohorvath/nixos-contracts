# A service module for a telegraf node: it generates the token it writes
# metrics with. Another node's influxdb copies the token by reference.
{ contractsLib, ... }:
{
  contracts.services.telegraf = contractsLib.mkDefaultContract {
    enable = true;
    identity.static.user = "telegraf";
    secrets.token.value.generated = "alnum";
  };
}
