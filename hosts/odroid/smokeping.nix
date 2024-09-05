{ pkgs, config, inputs, ... }: {

  services.smokeping = {
    enable = true;
    #secretFile = "/var/lib/smokeping/smokeping_secrets";

    config = "
*** General ***
owner    = Your Name
contact  = your-email@example.com
mailhost = localhost
imgcache = /var/lib/smokeping/cache
imgurl   = cache
datadir  = /var/lib/smokeping/data
piddir   = /var/lib/smokeping/var
cgiurl   = http://your-domain.com/cgi-bin/smokeping.cgi

*** Alerts ***
to = sysadmin@example.com

+bigloss
type = loss
pattern = >25%,*12*,>25%

*** Database ***
step = 300
pings = 5

*** Presentation ***
template = /usr/share/smokeping/etc/basepage.html

+ charts
menu = Charts
title = My SmokePing Charts

*** Probes ***
+ Curl
binary = /run/current-system/sw/bin/curl
forks = 5
offset = 50%
timeout = 15
pings = 5

+++ Variables
urlformat = https://seomatic.dev.modivo.io/api/v1/seo?url=%s

*** Targets ***
+ Modivo
menu = Modivo API Check
title = Modivo API SEO Check

++ SEO
menu = SEO API
title = Check SEO for Modivo
probe = Curl

+++ MelissaBaleriny
menu = Melissa Baleriny
title = Melissa Baleriny URL Test
url = https://modivo-local.pl/p/melissa-baleriny-jean-jason-wu-vii-ad-32288-foioletowy
";
  };



  services.nginx = {
    enable = true;
    virtualHosts = {
      "smokeping.house.flakm.com" = {
        useACMEHost = "house.flakm.com";
        forceSSL = true;
        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:8888";
            recommendedProxySettings = true;
            #extraConfig = ''
            #  proxy_set_header Host $http_host; # try $host instead if this doesn't work
            #  proxy_set_header X-Forwarded-Proto $scheme;
            #  proxy_pass http://127.0.0.1:3030; # replace port
            #  proxy_redirect http://127.0.0.1:3030 https://recipes.domain.tld; # replace port and domain
            #'';
          };
        };
      };
    };
  };

}
