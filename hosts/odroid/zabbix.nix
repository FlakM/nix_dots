{ config, pkgs, lib, ... }:
{

  # ——————————————————————————————————————————————
  # Zabbix Server (psql backend)
  # ——————————————————————————————————————————————
  services.zabbixServer = {
    enable = true;
    database = {
      type = "pgsql";
      socket = "/run/postgresql";
      host = "/run/postgresql";
      createLocally = true;
    };
  };


  #services.postgresql.ensureUsers = [
  #  {
  #    name = "zabbix";
  #    ensureDBOwnership = true;
  #  }
  #];

  services.zabbixWeb = {
    enable = true;
    frontend = "nginx";
    nginx = {
      virtualHost = {
        serverName = "zabbix.house.flakm.com";
        useACMEHost = "house.flakm.com";
        forceSSL = true;

      };
    };
  };



  services.zabbixAgent = {
    enable = true;
    openFirewall = true; # opens TCP 10050
    server = "127.0.0.1";
  };

}
