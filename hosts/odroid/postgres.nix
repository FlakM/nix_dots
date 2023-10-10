{ pkgs, config, inputs, ... }: {

services.postgresql = {
  enable = true;
  ensureDatabases = [ "tandoor" "nextcloud" ];
 
  identMap = ''
    # ArbitraryMapName systemUser DBUser
       superuser_map      root      postgres
       superuser_map      postgres  postgres
       # Let other names login as themselves
       superuser_map      /^(.*)$   \1
       superuser_map      flakm     tandoor
       superuser_map      flakm     nextcloud
  '';
};
  
}
