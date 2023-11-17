{ pkgs, ... }: {

  users.users.backup = {
    isNormalUser = true;
    home = "/home/backup";
    description = "Backup User";
  };

  # one time setup of zfs permissions
  # sudo zfs allow backup compression,mountpoint,create,mount,receive tank/backup
  users.users.backup.openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCQYN15z7XxnM+br9zdrBs1dzk/Vvh9LwP8d/DwiNUssyMfF4y8wJhiBNK/OYcfl1iZnl5wDdO539ogiy+xWse4zxTaE5i5roUD/jCFs9OTEzxlZgDnDzv6MBnWnErDo9Pn5XoNQvmBiB6m45hWa8mGtSgVGQ+hdJGnviF6nmOPDsnR+X9nJIFvOJGB6CArUPElKmUBRmoJdJRBqWio/+J+QuWT2dBwE/g41+8eppJpLK9CLd9wKC4TlFCIXminGUUP4uQWei86NJQPjD0vUqO/xSxc9P6hPC6qQp9t6y/LjplA3tKXISKIGgvR4mv76AAAjchMccdBEeFL9Rk/pCOCwGr8Hg4PJTuuigVk+4gWgZ9U2QZH2ZRWRWd9JwzB5AN45eVtk8gQhqMBlkMHodilum2gx5Eqs4A8TA9rBmBFkXWALZCE6ywaiX+Z43mo6LW5z48JzwQUQhEC1aUAuDcYnWUnBefI+xSaZD8owEVtgUlr96XnABeGPkeWXoC2HQM= root@amd-pc" ];

  environment.systemPackages = with pkgs; [
    lzop
    mbuffer
  ];

}
