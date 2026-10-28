# A service module for a telegraf node: it generates the token it writes
# metrics with. The fleet carries the token's `ref` to the influxdb that
# stores them.
{ contractsLib, ... }:
{
  contracts.services.telegraf = contractsLib.mkDefaultContract {
    enable = true;
    identity.static.user = "telegraf";
    secrets.token.value.generated.generator = "alnum";
  };
}
