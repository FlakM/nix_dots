{ pkgs, lib, config, ... }:
let
  # the issue is that mailboxes is stricter now, so fake entries have to be injected using named-mailboxes.
  list-mailboxes = pkgs.writeScriptBin "list-mailboxes" ''
    find ${config.accounts.email.maildirBasePath}/$1 -type d -name cur | sort | sed -e 's:/cur/*$::' -e 's/ /\\ /g' | uniq | tr '\n' ' '
  '';
  list-empty-mailboxes = pkgs.writeScriptBin "list-empty-mailboxes" ''
    find ${config.accounts.email.maildirBasePath}/$1 -type d -exec bash -c 'd1=("$1"/cur/); d2=("$1"/*/); [[ ! -e "$d1" && -e "$d2" ]]' _ {} \; -printf "%p "
  '';
  cat-cred = pkgs.writeScriptBin "cat-cred" ''
    ${../../mutt_oauth2.py} /tmp/maciej.flak@modivo.com
  '';
  autodiscoverMailboxes = path: "mailboxes `${list-mailboxes}/bin/list-mailboxes ${path}`";
  colorscheme = (import ./neomutt_colorscheme.nix).colorscheme;
  smokeOutBugs = true;
in
{
  home.packages = [
    list-mailboxes
    list-empty-mailboxes
    cat-cred
  ];

  programs.neomutt = {
    enable = true;
    package = pkgs.enableDebugging ((pkgs.neomutt.override {
      enableLua = true;
      enableZstd = true;
      enableMixmaster = true;
    }).overrideAttrs (old: {
      # Undefined behavior + address sanitizer.
      configureFlags = old.configureFlags ++ lib.optional smokeOutBugs "--asan --ubsan";
    }));
    sidebar.width = 40;
    sidebar.enable = true;
    sidebar.shortPath = true;
    sidebar.format = "%D%> %?N?%N/?%S";
    vimKeys = true;
    sort = "reverse-date";
    extraConfig = ''
      bind index,pager K sidebar-prev       
      bind index,pager J sidebar-next       
      bind index,pager \CO sidebar-open       # Ctrl-Shift-O - Open Highlighted Mailbox
      bind index,pager B sidebar-toggle-visible
      bind pager ,g group-reply

      # Move message(s) to Spam by pressing "S"
      macro index S "<tag-prefix><enter-command>unset resolve<enter><tag-prefix><clear-flag>N<tag-prefix><enter-command>set resolve<enter><tag-prefix><save-message>=spam<enter>" "file as Spam"
      macro pager S "<save-message>=spam<enter>" "file as Spam"
      # Return to Inbox by pressing "."
      macro index . "<change-folder>=INBOX<enter>" "INBOX"


      set sidebar_delim_chars="/"             # Delete everything up to the last / character
      set sidebar_folder_indent               # Indent folders whose names we've shortened
      set sidebar_indent_string="  "          # Indent with two spaces
      set mail_check_stats=yes
      set sidebar_component_depth="1"
      set sidebar_sort_method = "path"
      set sidebar_new_mail_only = no
      set sidebar_non_empty_mailbox_only = no

      set header_cache_backend='lmdb'
      set header_cache='~/mail/hcache'
      set header_cache_compress_method = "zstd"
      set header_cache_compress_level = 10

      alternative_order text/plain text/html
      set mailcap_path = ~/.config/mailcap

      set mime_forward = no
      set forward_attachments = yes
      macro pager \cb "<pipe-message> ${pkgs.urlscan}/bin/urlscan<Enter>" "call urlscan to extract URLs out of a message"
      macro index,pager O "<shell-escape>mbsync -a<enter>" "run mbsync to sync all emails"
      macro attach 'V' "<pipe-entry>iconv -c --to-code=UTF8 > ~/.cache/mutt/mail.html<enter><shell-escape>$BROWSER ~/.cache/mutt/mail.html<enter>"

      auto_view text/html image/*

      ${colorscheme}
    '';
  };

  programs = {
    mbsync.enable = true;
    msmtp.enable = true;
  };

  services.imapnotify.enable = true;

  accounts.email = {
    maildirBasePath = "mail";
    accounts = {
      "me@flakm.com" = {
        realName = "Maciek Flak";
        neomutt = {
          enable = true;
          extraConfig = ''
            ${autodiscoverMailboxes "me@flakm.com"}
            named-mailboxes ENS-Inbox +Inbox
            folder-hook . "set sort=reverse-date ; set sort_aux=date"
          '';
        };
        primary = true;
        address = "me@flakm.com";
        flavor = "fastmail.com";
        signature = {
          showSignature = "append";
          text = ''
            Regards,
            Maciek Flak
          '';
        };
        imap = {
          host = "imap.fastmail.com";
          tls.enable = true;
        };
        smtp = {
          host = "smtp.fastmail.com";
          port = 587;
          tls.enable = true;
          tls.useStartTls = true;
        };

        mbsync = {
          enable = true;
          create = "both";
        };
        msmtp.enable = true;

        passwordCommand = "gpg --decrypt /var/secrets/me@fastmail_pass";
      };

    };
  };



}
