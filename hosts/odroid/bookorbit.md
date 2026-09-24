# BookOrbit on odroid

BookOrbit runs at `https://bookorbit.house.flakm.com`; Prowlarr runs at `https://prowlarr.house.flakm.com`. Both use the existing `house.flakm.com` wildcard certificate. BookOrbit's application data and PostgreSQL 18 database live in `/var/lib/bookorbit`; its request staging area lives on the media pool at `/var/media/bookorbit-dock`.

## First login

1. After switching the odroid configuration, get the one-time setup token with `sudo cat /var/lib/bookorbit/secrets/setup_bootstrap_token` on odroid. Create the BookOrbit administrator at the BookOrbit URL.
2. In **Settings > Libraries**, create an **Ebooks** library with folder `/var/media/books/ebooks` and an **Audiobooks** library with folder `/var/media/audiobookshelf`. Use **Folder as Book** for audiobooks. If Audiobookshelf also manages metadata in that directory, leave BookOrbit's automatic file renaming and metadata writing off.
3. Under **Settings > Server > Requests**, set Ebooks and Audiobooks as the default destinations for their respective media. The Book Dock is separate from both libraries.

## Connect searches and downloads

1. Add book and audiobook indexers to Prowlarr, then copy its API key from **Settings > General**. In BookOrbit **Settings > Server > Requests > Sources**, connect Prowlarr at `http://127.0.0.1:9696` using that key and allow private addresses. Enable the relevant indexers for ebooks and audiobooks. Prowlarr can also sync those indexers to Readarr if desired; Readarr does not itself supply BookOrbit with indexer feeds.
2. In **Download clients**, add the existing SABnzbd at `http://127.0.0.1:8080` using its API key, and/or Deluge at `http://127.0.0.1:8112` using its Web UI password. Set a BookOrbit-specific category/label. Deluge requires its Label plugin enabled. BookOrbit's v3.0 release supports SABnzbd, even though the public requests guide still lists only NZBGet for Usenet.
3. Map the download client's completed-download path to the same path on the BookOrbit host (the container sees `/var/media` at the same path). If the client reports a different path, map that prefix to its corresponding `/var/media/...` path. Test both the connection and the path mapping before enabling requests.
4. Grant users **Request books**; grant **Download books directly** to users who should choose releases without approval. Automatic downloading is optional and defaults to off.

BookOrbit's credentials and bootstrap token are generated once on the host and kept under `/var/lib/bookorbit/secrets`. Keep that directory with the PostgreSQL and app data when backing up or moving the instance. Hardlinks work only when the completed download and Book Dock share a filesystem; the existing `/var/media/audiobookshelf` is a separate ZFS dataset, so filing audiobooks there may require a copy.
