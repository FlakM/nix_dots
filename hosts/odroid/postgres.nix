{ pkgs, config, inputs, lib, ... }: {

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_14;
    ensureDatabases = [ "tandoor" "nextcloud" "users" ];

    identMap = ''
      # ArbitraryMapName systemUser DBUser
         superuser_map      root      postgres
         superuser_map      postgres  postgres
         superuser_map      flakm     tandoor
         superuser_map      flakm     nextcloud
         superuser_map      nextcloud     nextcloud
         superuser_map      flakm     zabbix
    '';

    #  let every DB user have access to it without a password through a "local" Unix socket "/var/lib/postgresql
    authentication = pkgs.lib.mkOverride 10 ''
      #type database  DBuser  auth-method
      local all       all     trust
    '';


    initialScript = pkgs.writeText "backend-initScript" ''
      CREATE ROLE tandoor WITH LOGIN;
      GRANT ALL PRIVILEGES ON DATABASE tandoor TO tandoor;

      CREATE ROLE nextcloud WITH LOGIN;
      GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;


      CREATE ROLE zabbix WITH LOGIN;
      GRANT ALL PRIVILEGES ON DATABASE zabbix TO zabbix;
    '';
  };

}
