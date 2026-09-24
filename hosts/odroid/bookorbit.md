# BookOrbit on odroid

BookOrbit runs at `https://bookorbit.house.flakm.com`; Prowlarr runs at `https://prowlarr.house.flakm.com`. Both use the existing `house.flakm.com` wildcard certificate. BookOrbit's application data and PostgreSQL 18 database live in `/var/lib/bookorbit`; its request staging area lives on the media pool at `/var/media/bookorbit-dock`.

## First login

1. Sign in as `flakm`. Get the generated administrator password on odroid with `sudo cat /var/lib/bookorbit/secrets/admin_password`, then change it in BookOrbit.
2. **Ebooks** (`/var/media/books/ebooks`) and **Audiobooks** (`/var/media/audiobookshelf`) are already created as libraries and set as the default request destinations. The Book Dock is separate from both libraries. Leave automatic file renaming and metadata writing off on the Audiobookshelf-managed directory.

## Connect searches and downloads

1. BookOrbit is connected to Prowlarr at `http://127.0.0.1:9696`, with automatic indexer sync enabled. The NZBgeek Books indexer uses the `nzb_api_key` SOPS credential and searches ebooks (7020) and audiobooks (3030); Readarr uses the same credential. If that key rotates, update both indexers and sync BookOrbit again. Prowlarr can also sync indexers to Readarr if desired.
2. BookOrbit's SABnzbd download client is connected and tested at `http://127.0.0.1:8080` with its own `bookorbit` category. Its completed downloads are mounted read-only at `/var/lib/sabnzbd/Downloads/complete` and mapped to the same path in BookOrbit. BookOrbit's v3.0 release supports SABnzbd, even though the public requests guide still lists only NZBGet for Usenet.
3. To use torrent sources too, add Deluge at `http://127.0.0.1:8112` with its Web UI password, enable Deluge's Label plugin, and map its `/var/media/...` completed path to itself.
4. Grant other users **Request books**; grant **Download books directly** to users who should choose releases without approval. Automatic downloading is off by default.

BookOrbit's credentials and bootstrap token are generated once on the host and kept under `/var/lib/bookorbit/secrets`. Keep that directory with the PostgreSQL and app data when backing up or moving the instance. Hardlinks work only when the completed download and Book Dock share a filesystem; the existing SABnzbd download directory and `/var/media/audiobookshelf` are separate ZFS datasets, so imports may require a copy.
