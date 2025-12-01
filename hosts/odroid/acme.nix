{ self, config, lib, pkgs, ... }:

{
  security.acme = {
    acceptTerms = true;
    defaults.email = "me@flakm.com";
    defaults.reloadServices = [ "nginx" ];

    certs."house.flakm.com" = {
      domain = "house.flakm.com";
      extraDomainNames = [ "*.house.flakm.com" ];
      dnsProvider = "cloudflare";
      dnsPropagationCheck = true;
      credentialsFile = /var/secrets/cloudflare.ini;
    };
  };

  users.users.nginx.extraGroups = [ "acme" ];
}
