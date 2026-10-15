{ pkgs, ... }:
let
  aristonBridgenet = pkgs.fetchFromGitHub {
    owner = "wrongisthenewright";
    repo = "ebusd-configuration-ariston-bridgenet";
    rev = "v2.7";
    hash = "sha256-fy+vlUe8SpcFHO2aC6bo9A9pUdH4k3i+vwl8UHKZKaw=";
  };
  aristonReadOnly = pkgs.runCommand "ariston-bridgenet-readonly" { } ''
    mkdir -p $out
    cp ${aristonBridgenet}/*.csv $out/
    cp ${./ariston-clas-x-readonly.csv} $out/clas-x.csv
    chmod u+w $out/*.csv
    sed -i '/^w,/d; /^[bgr],ignored,/d' $out/ariston.csv
    sed -E -i '/^([^,]*,){7}[[:xdigit:]]{11,},/d' $out/ariston.csv
    sed -i '/^r,boiler,\(boiler_pressure\|pressure_monitoring_device\|flame_power_kw\|pump_current_modulation\),/d; /^b,boiler,ext_temp,/d' $out/ariston.csv
    sed -i 's/^# r,boiler,LWT_temp,/r1,boiler,LWT_temp,/' $out/ariston.csv
    sed -i '/^r,boiler,\(flame_active\|EWT_temp\|boiler_current_modulation\|boiler_status\),/s/^r,/r1,/' $out/ariston.csv
    # Publish poll/update values to MQTT: ebusd does not publish CSV messages
    # without an integration file. Based on the upstream HA integration file so
    # ebusd publishes ebusd/<circuit>/<name> for seen read/update messages.
    sed 's/^filter-direction = .*/filter-direction = r|u/' \
      ${aristonBridgenet}/mqtt-hassio.cfg > $out/mqtt-ebusd.cfg
    sed -i '/^#filter-non-name =/a filter-non-name = candidate|^register_' $out/mqtt-ebusd.cfg
    # Publish values but suppress HA MQTT discovery (entities are declared by hand
    # in heating-monitoring.nix); blank discovery topics are not published.
    sed -i '$a definition-topic =\ndef_global-topic =\ndef_global_running-topic =\ndef_global_signal-topic =\ndef_global_scan-topic =\ndef_global_updatecheck-topic =' $out/mqtt-ebusd.cfg
  '';
in
{
  services.ebusd = {
    enable = true;
    device = "ens:192.168.0.244:9999";
    port = 8890;
    configpath = "${aristonReadOnly}";
    scanconfig = "off";
    extraArguments = [
      "--localhost"
      "--mqtthost=127.0.0.1"
      "--mqttport=1883"
      "--mqttjson"
      "--mqttint=${aristonReadOnly}/mqtt-ebusd.cfg"
      "--mqtttopic=ebusd"
      "--pollinterval=5"
    ];
  };
  systemd.services.ebusd = {
    after = [ "network-online.target" "mosquitto.service" ];
    wants = [ "network-online.target" "mosquitto.service" ];
  };
  systemd.services.ebusd-counters = {
    description = "Read Ariston lifetime counters";
    after = [ "ebusd.service" ];
    requires = [ "ebusd.service" ];
    serviceConfig.Type = "oneshot";
    path = [ pkgs.ebusd ];
    script = ''
      for name in hours_burner_on_CH hours_burner_on_DHW ignition_cycles hours_pump_on diverter_cycles; do
        ebusctl -p 8890 read -m 0 -c boiler "$name"
      done
    '';
  };
  systemd.timers.ebusd-counters = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "30s";
      OnUnitActiveSec = "15min";
    };
  };
  environment.systemPackages = [ pkgs.ebusd ];
}
