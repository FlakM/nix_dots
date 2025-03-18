{ pkgs, lib, config, ... }:
let
  # the issue is that mailboxes is stricter now, so fake entries have to be injected using named-mailboxes.
  list-mailboxes = pkgs.writeScriptBin "list-mailboxes" ''
    find ${config.accounts.email.maildirBasePath}/$1 -type d -name cur | sort | sed -e 's:/cur/*$::' -e 's/ /\\ /g' | uniq | tr '\n' ' '
  '';
  list-empty-mailboxes = pkgs.writeScriptBin "list-empty-mailboxes" ''
    find ${config.accounts.email.maildirBasePath}/$1 -type d -exec bash -c 'd1=("$1"/cur/); d2=("$1"/*/); [[ ! -e "$d1" && -e "$d2" ]]' _ {} \; -printf "%p "
  '';

  pick-mailbox = pkgs.writeScriptBin "pick-mailbox" ''
    fzf_command='fzf --height ~100%'
    fd_command="fd . ${config.home.homeDirectory}/mail/ --type d --max-depth 1"
    
    folder="$($fd_command | $fzf_command)"
    
    # Get the basename; this will be used to locate the account config.
    basefolder=$(basename "$folder")
    
    # Construct the push command: unmailboxes, then source the config, then sync and change folder.
    echo "push '<enter-command>unmailboxes *<enter><enter-command>source ~/.config/neomutt/$basefolder<enter><sync-mailbox><change-folder>$folder/Inbox<enter>'"
  '';

  autodiscoverMailboxes = path: "mailboxes `${list-mailboxes}/bin/list-mailboxes ${path}`";
  colorscheme = (import ./neomutt_colorscheme.nix).colorscheme;
in
{
  home.packages = [
    list-mailboxes
    list-empty-mailboxes
  ];

  imports = [
    ./mailcap.nix
  ];

  # inspired by 
  # https://github.com/RaitoBezarius/nixos-home/blob/master/emails/neomutt.nix
  programs.neomutt = {
    enable = true;
    sidebar.width = 40;
    sidebar.enable = true;
    sidebar.shortPath = true;
    sidebar.format = "%D%> %?N?%N/?%S";
    vimKeys = true;
    sort = "reverse-date";

    extraConfig = ''
      bind index,pager K sidebar-prev       
      bind index,pager J sidebar-next       
      bind index,pager B sidebar-toggle-visible
      bind index,pager \CO sidebar-open       # Ctrl-Shift-O - Open Highlighted Mailbox

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

      macro index <F1> ":source ${pick-mailbox}/bin/pick-mailbox|<enter>" "Pick a mailbox"
      
      ${colorscheme}
    '';
  };

  programs = {
    mbsync.enable = true;
    msmtp.enable = true;
  };

  services.imapnotify.enable = true;




}
