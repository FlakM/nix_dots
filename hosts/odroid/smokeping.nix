{ pkgs, config, inputs, ... }:
let
  binary = pkgs.writeShellApplication {
    name = "smokeping-curl";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      if [ "$1" = "--help" ]; then
        exec curl --help all
        exit 0
      fi
    
      echo "params $*" >> /var/lib/smokeping/data/smokeping.log
      exec curl "$@"
    '';
  };
in
{




  # write binary to 

  services.smokeping = {
    enable = true;
    webService = true;
    host = "smokeping.house.flakm.com";

    probeConfig = ''
      + Curl
      binary = ${binary}/bin/smokeping-curl
      step = 60
      pings = 5
      offset = random
      timeout = 5
      urlformat = https://%host%/
    '';

    targetConfig = ''
      probe = Curl
      menu = Top
      title = Seomatic API Test

      + SEOGetRequestDev
      menu = SEO API Test
      title = SEOmatic API Test for URL

      host = seomatic.dev.modivo.io
      urlformat = https://%host%/api/v1/seo?url=https://fake.com
    '';
  };


}
